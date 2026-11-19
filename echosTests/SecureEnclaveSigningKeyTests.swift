//
//  SecureEnclaveSigningKeyTests.swift
//  echosTests
//
//  Политика доступа и порядок операций для Secure Enclave ключа.
//  Настоящий чип в юнит-тесте не требуется: хранилище подменяется
//  обычным P-256 ключом в памяти, а биометрия — заглушкой LAContext.
//

import Foundation
import LocalAuthentication
import Security
import Testing
@testable import echos

@MainActor
final class SecureEnclaveSigningKeyTests {

    // MARK: - Политика доступа

    @Test func accessPolicy_requiresPrivateKeyUsageAndCurrentBiometry() {
        let policy = SecureEnclaveAccessPolicy.faceIDRequired
        let flags = policy.accessControlFlags

        #expect(flags.contains(.privateKeyUsage))
        #expect(flags.contains(.biometryCurrentSet))
        #expect(!flags.contains(.userPresence), "Для этого ключа код-пароль не должен заменять Face ID")
    }

    // MARK: - Жизненный цикл ключа

    @Test func publicKey_createsKeyOnlyOnce() throws {
        let store = FakeSecureEnclaveKeyStore()
        let service = SecureEnclaveSigningService(store: store,
                                                  gate: FakeAuthenticationGate())

        let first = try service.publicKey()
        let second = try service.publicKey()

        #expect(first == second)
        #expect(store.createdAccounts == [SecureEnclaveSigningService.defaultAccount])
    }

    @Test func reset_removesExistingKey() throws {
        let store = FakeSecureEnclaveKeyStore()
        let service = SecureEnclaveSigningService(store: store,
                                                  gate: FakeAuthenticationGate())

        _ = try service.ensureKey()
        try service.reset()

        #expect(try !store.hasKey(account: SecureEnclaveSigningService.defaultAccount))

        let recreated = try service.publicKey()
        #expect(store.createdAccounts.count == 2)
        #expect(!recreated.isEmpty)
    }

    // MARK: - Доступ только после Face ID

    @Test func sign_asksBiometryThenSignsWithSameAuthenticatedContext() async throws {
        let store = FakeSecureEnclaveKeyStore()
        let gate = FakeAuthenticationGate()
        let service = SecureEnclaveSigningService(store: store, gate: gate)
        let data = Data("подписать".utf8)

        _ = try service.ensureKey()
        let signature = try await service.sign(data, reason: "Подтвердить действие")

        #expect(gate.requestedReasons == ["Подтвердить действие"])
        #expect(store.keyLookupContexts == [ObjectIdentifier(gate.context)])
        #expect(store.signedData == [data])

        let publicKey = try #require(SecKeyCreateWithData(
            try service.publicKey() as CFData,
            [
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256
            ] as CFDictionary,
            nil
        ))
        #expect(SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            signature as CFData,
            nil
        ))
    }

    @Test func sign_withoutKey_failsBeforeBiometry() async {
        let store = FakeSecureEnclaveKeyStore()
        let gate = FakeAuthenticationGate()
        let service = SecureEnclaveSigningService(store: store, gate: gate)

        do {
            _ = try await service.sign(Data("test".utf8), reason: "Подтвердить действие")
            Issue.record("подпись без ключа должна падать")
        }
        catch let error as SecureEnclaveKeyError {
            #expect(error == .keyNotFound(SecureEnclaveSigningService.defaultAccount))
        }
        catch {
            Issue.record("не та ошибка: \(error)")
        }

        #expect(gate.requestedReasons.isEmpty)
        #expect(store.signedData.isEmpty)
    }

    @Test func sign_whenBiometryFails_doesNotTouchPrivateKey() async {
        let store = FakeSecureEnclaveKeyStore()
        let gate = FakeAuthenticationGate()
        let service = SecureEnclaveSigningService(store: store, gate: gate)

        _ = try? service.ensureKey()
        gate.failure = .authenticationFailed("отменено пользователем")

        do {
            _ = try await service.sign(Data("test".utf8), reason: "Подтвердить действие")
            Issue.record("без успешного Face ID подписи быть не должно")
        }
        catch let error as SecureEnclaveKeyError {
            #expect(error == .authenticationFailed("отменено пользователем"))
        }
        catch {
            Issue.record("не та ошибка: \(error)")
        }

        #expect(store.signedData.isEmpty)
    }
}

// MARK: - Test doubles

@MainActor
private final class FakeSecureEnclaveKeyStore: SecureEnclaveKeyStore {

    private(set) var keys: [String: SecKey] = [:]
    private(set) var createdAccounts: [String] = []
    private(set) var keyLookupContexts: [ObjectIdentifier] = []
    private(set) var signedData: [Data] = []

    func hasKey(account: String) throws -> Bool {
        keys[account] != nil
    }

    func key(account: String, context: LAContext) throws -> SecKey? {
        keyLookupContexts.append(ObjectIdentifier(context))
        return keys[account]
    }

    func createKey(account: String,
                   policy: SecureEnclaveAccessPolicy) throws -> SecKey {
        createdAccounts.append(account)

        let attributes = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256
        ] as CFDictionary
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes, &error) else {
            Issue.record("не удалось создать тестовый P-256 ключ: \(String(describing: error))")
            throw SecureEnclaveKeyError.keyGenerationFailed("test key")
        }
        keys[account] = key
        return key
    }

    func publicKey(account: String) throws -> Data? {
        guard let privateKey = keys[account],
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        return SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
    }

    func delete(account: String) throws {
        keys.removeValue(forKey: account)
    }

    func sign(_ data: Data,
              with key: SecKey,
              algorithm: SecKeyAlgorithm) throws -> Data {
        signedData.append(data)

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            algorithm,
            data as CFData,
            &error
        ) else {
            throw SecureEnclaveKeyError.signingFailed(
                error.map { String(describing: $0.takeUnretainedValue()) } ?? "unknown"
            )
        }
        return signature as Data
    }
}

@MainActor
private final class FakeAuthenticationGate: SecureEnclaveAuthenticationGate {

    private(set) var requestedReasons: [String] = []
    var failure: SecureEnclaveKeyError?
    let context = LAContext()

    func authenticatedContext(reason: String) async throws -> LAContext {
        requestedReasons.append(reason)
        if let failure {
            throw failure
        }
        context.localizedReason = reason
        return context
    }
}
