//
//  SecureEnclaveSigningKey.swift
//  echos
//
//  Ключ P-256 внутри Secure Enclave: закрытая часть не покидает чип,
//  извлечь её из Keychain нельзя, и каждая подпись требует свежей
//  биометрической проверки.
//
//  Это отдельный ключ от личности устройства. Личность и рукопожатие релея
//  построены на Curve25519/Ed25519 и совместимости с сервером, а Secure
//  Enclave умеет только P-256/ECDSA. Менять существующий адрес ради нового
//  хранилища нельзя — поэтому здесь появляется второй, более строго
//  защищённый ключ для операций, где человек должен подтвердить себя лично.
//

import Foundation
import LocalAuthentication
import Security

/// Что именно требуется от устройства, прежде чем трогать закрытый ключ.
struct SecureEnclaveAccessPolicy: Equatable, Sendable {

    enum Protection: String, Equatable, Sendable {
        /// Ключ живёт только на этом устройстве и только в разблокированном
        /// состоянии. В резервную копию он в любом случае не попадает —
        /// за это отвечает Secure Enclave, а не атрибут Keychain.
        case whenUnlockedThisDeviceOnly
    }

    let protection: Protection

    /// Строго биометрия текущего набора: Face ID отменили или перенастроили —
    /// доступ к старому ключу закрывается. Без fallback на код-пароль: это
    /// осознанное ограничение для ключей, которые должны означать «это именно
    /// человек, а не кто-то, знающий код».
    let requiresCurrentBiometry: Bool

    static let faceIDRequired = SecureEnclaveAccessPolicy(
        protection: .whenUnlockedThisDeviceOnly,
        requiresCurrentBiometry: true
    )

    var accessControlFlags: SecAccessControlCreateFlags {
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if requiresCurrentBiometry {
            flags.insert(.biometryCurrentSet)
        }
        return flags
    }

    func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        let accessibility = switch protection {
        case .whenUnlockedThisDeviceOnly:
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        guard let control = SecAccessControlCreateWithFlags(
            nil,
            accessibility,
            accessControlFlags,
            &error
        ) else {
            let reason = error.map { String(describing: $0.takeUnretainedValue()) } ?? "unknown"
            throw SecureEnclaveKeyError.accessControlFailed(reason)
        }
        return control
    }
}

enum SecureEnclaveKeyError: Error, Equatable, LocalizedError {
    case keyNotFound(String)
    case accessControlFailed(String)
    case keyGenerationFailed(String)
    case authenticationUnavailable(String)
    case authenticationFailed(String)
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .keyNotFound(let account):
            return String(localized: "Secure Enclave ключ '\(account)' не найден")
        case .accessControlFailed(let reason):
            return String(localized: "Не удалось создать политику доступа ключа: \(reason)")
        case .keyGenerationFailed(let reason):
            return String(localized: "Не удалось создать Secure Enclave ключ: \(reason)")
        case .authenticationUnavailable(let reason):
            return String(localized: "Face ID сейчас недоступен: \(reason)")
        case .authenticationFailed(let reason):
            return String(localized: "Face ID не подтверждён: \(reason)")
        case .signingFailed(let reason):
            return String(localized: "Подпись Secure Enclave не получилась: \(reason)")
        }
    }
}

/// Хранилище закрытых ключей. Реализация ходит в Security, тесты подменяют
/// объект, не трогая чип и не показывая системный UI.
@MainActor
protocol SecureEnclaveKeyStore: AnyObject {
    /// Проверка существования без подписи. Нужна, чтобы не просить Face ID
    /// за ключ, которого ещё нет.
    func hasKey(account: String) throws -> Bool

    /// Ссылка на закрытый ключ после успешной биометрии. Контекст уходит в
    /// запрос Keychain, чтобы операция использовала именно эту проверку.
    func key(account: String, context: LAContext) throws -> SecKey?

    func createKey(account: String, policy: SecureEnclaveAccessPolicy) throws -> SecKey
    func publicKey(account: String) throws -> Data?
    func delete(account: String) throws
    func sign(_ data: Data,
              with key: SecKey,
              algorithm: SecKeyAlgorithm) throws -> Data
}

/// Реальный ключ создаётся в Secure Enclave. `SecKeyCreateRandomKey` с
/// `kSecAttrTokenIDSecureEnclave` возвращает только ссылку: байтов закрытого
/// ключа у приложения нет и получить их нельзя.
@MainActor
final class SecureEnclaveKeychainStore: SecureEnclaveKeyStore {

    func hasKey(account: String) throws -> Bool {
        try copyKey(account: account, context: nil) != nil
    }

    func key(account: String, context: LAContext) throws -> SecKey? {
        try copyKey(account: account, context: context)
    }

    func createKey(account: String, policy: SecureEnclaveAccessPolicy) throws -> SecKey {
        let access = try policy.makeAccessControl()
        let privateKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrAccessControl as String: access
        ]
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrLabel as String: Self.label(account),
            kSecPrivateKeyAttrs as String: privateKeyAttributes
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let reason = error.map { String(describing: $0.takeUnretainedValue()) } ?? "unknown"
            throw SecureEnclaveKeyError.keyGenerationFailed(reason)
        }
        return key
    }

    func publicKey(account: String) throws -> Data? {
        guard let privateKey = try copyKey(account: account, context: nil),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        return SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveKeyError.keyGenerationFailed(Self.securityDescription(status))
        }
    }

    func sign(_ data: Data,
              with key: SecKey,
              algorithm: SecKeyAlgorithm) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            algorithm,
            data as CFData,
            &error
        ) else {
            let reason = error.map { String(describing: $0.takeUnretainedValue()) } ?? "unknown"
            throw SecureEnclaveKeyError.signingFailed(reason)
        }
        return signature as Data
    }

    // MARK: - Private

    private func copyKey(account: String, context: LAContext?) throws -> SecKey? {
        var query = query(account: account)
        query[kSecReturnRef as String] = true
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            // Security вернул объект ключа именно из-за kSecReturnRef.
            // swiftlint:disable:next force_cast
            return result as! SecKey
        case errSecItemNotFound:
            return nil
        default:
            throw SecureEnclaveKeyError.keyGenerationFailed(Self.securityDescription(status))
        }
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrLabel as String: Self.label(account)
        ]
    }

    private static func label(_ account: String) -> String {
        "com.echos.secure-enclave.\(account)"
    }

    private static func securityDescription(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { String($0) } ?? "OSStatus \(status)"
    }
}

/// Проверка «это человек» перед доступом к закрытому ключу. Возвращает тот
/// же `LAContext`, которым потом запрашивается ссылка на ключ: подпись
/// получает уже разрешённый ключ, не показывая второй системный запрос.
@MainActor
protocol SecureEnclaveAuthenticationGate: AnyObject {
    func authenticatedContext(reason: String) async throws -> LAContext
}

@MainActor
final class LocalAuthenticationGate: SecureEnclaveAuthenticationGate {

    /// Строго биометрия. `.deviceOwnerAuthentication` дал бы fallback на
    /// код-пароль, а для этого ключа код-пароль — не доказательство присутствия
    /// владельца.
    private let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics

    func authenticatedContext(reason: String) async throws -> LAContext {
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(policy, error: &availabilityError) else {
            throw SecureEnclaveKeyError.authenticationUnavailable(
                availabilityError?.localizedDescription ?? "unknown"
            )
        }

        do {
            try await context.evaluatePolicy(policy, localizedReason: reason)
            return context
        }
        catch {
            throw SecureEnclaveKeyError.authenticationFailed(error.localizedDescription)
        }
    }
}

/// Подпись одним строго защищённым ключом. Сервис не кэширует подпись и не
/// прячет биометрию: каждый вызов — новый Face ID и новый проход через чип.
@MainActor
final class SecureEnclaveSigningService {

    static let shared = SecureEnclaveSigningService()
    static let defaultAccount = "owner-confirmation"

    private let store: any SecureEnclaveKeyStore
    private let gate: any SecureEnclaveAuthenticationGate

    init(store: any SecureEnclaveKeyStore = SecureEnclaveKeychainStore(),
         gate: any SecureEnclaveAuthenticationGate = LocalAuthenticationGate()) {
        self.store = store
        self.gate = gate
    }

    /// Открытый ключ можно показывать без биометрии. Если закрытого ключа ещё
    /// нет, он создаётся в Secure Enclave и в будущем живёт там постоянно.
    @discardableResult
    func ensureKey(account: String = defaultAccount,
                   policy: SecureEnclaveAccessPolicy = .faceIDRequired) throws -> Data {
        if let publicKey = try store.publicKey(account: account) {
            return publicKey
        }

        let key = try store.createKey(account: account, policy: policy)
        guard let publicKey = SecKeyCopyPublicKey(key),
              let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw SecureEnclaveKeyError.keyGenerationFailed("public key is missing")
        }
        return data
    }

    func publicKey(account: String = defaultAccount) throws -> Data {
        try ensureKey(account: account)
    }

    func sign(_ data: Data,
              account: String = defaultAccount,
              reason: String) async throws -> Data {
        guard try store.hasKey(account: account) else {
            throw SecureEnclaveKeyError.keyNotFound(account)
        }

        // Сначала доказываем, что перед устройством владелец. Только потом
        // запрашиваем ссылку на закрытый ключ с этим LAContext.
        let context = try await gate.authenticatedContext(reason: reason)
        guard let key = try store.key(account: account, context: context) else {
            throw SecureEnclaveKeyError.keyNotFound(account)
        }

        return try store.sign(
            data,
            with: key,
            algorithm: .ecdsaSignatureMessageX962SHA256
        )
    }

    func reset(account: String = defaultAccount) throws {
        try store.delete(account: account)
    }
}
