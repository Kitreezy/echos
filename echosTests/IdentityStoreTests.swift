//
//  IdentityStoreTests.swift
//  echosTests
//
//  Что делает хранилище личности, когда Keychain ведёт себя не по учебнику.
//  Цена ошибки в обе стороны: лишний новый ключ — это смена адреса и потеря
//  переписок, а отказ работать из-за мусора — приложение, которое не
//  запускается никогда.
//

import CryptoKit
import Foundation
import Testing
@testable import echos

@Suite(.tags(.crypto))
struct IdentityStoreTests {

    // MARK: - Первый запуск

    @Test func emptyKeychain_createsBothKeysAndWritesThem() throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let identity = try store.identity()

        #expect(keychain[IdentityStore.signingAccount]?.count == 32)
        #expect(keychain[IdentityStore.agreementAccount]?.count == 32)
        #expect(keychain.writes == 2)
        #expect(identity.publicKey.count == 32)
    }

    @Test func secondCall_comesFromCache() throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let first = try store.identity()
        let readsAfterFirst = keychain.reads
        let second = try store.identity()

        #expect(first.fingerprint == second.fingerprint)
        #expect(keychain.reads == readsAfterFirst, "Кэш есть, чтобы в Keychain не ходить")
    }

    // MARK: - Уже есть

    @Test func existingKeys_areLoadedNotReplaced() throws {
        let signing = Curve25519.Signing.PrivateKey()
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let keychain = FakeSecretStore([
            IdentityStore.signingAccount: signing.rawRepresentation,
            IdentityStore.agreementAccount: agreement.rawRepresentation
        ])

        let identity = try IdentityStore(store: keychain).identity()

        #expect(identity.publicKey == signing.publicKey.rawRepresentation)
        #expect(identity.agreementKey == agreement.publicKey.rawRepresentation)
        #expect(keychain.writes == 0, "Есть ключ — нечего писать")
    }

    @Test func onlySigningKey_keepsAddressAndAddsAgreement() throws {
        // Обновление с версии без шифрования: подписывающий ключ уже есть,
        // и адрес из-за появления второго меняться не должен.
        let signing = Curve25519.Signing.PrivateKey()
        let keychain = FakeSecretStore([IdentityStore.signingAccount: signing.rawRepresentation])

        let identity = try IdentityStore(store: keychain).identity()

        #expect(identity.fingerprint == DeviceIdentity.fingerprint(of: signing.publicKey.rawRepresentation))
        #expect(keychain[IdentityStore.agreementAccount]?.count == 32)
        #expect(keychain.writes == 1)
    }

    // MARK: - Заперто

    @Test func lockedDevice_throwsAndCreatesNothing() {
        let signing = Curve25519.Signing.PrivateKey()
        let keychain = FakeSecretStore([IdentityStore.signingAccount: signing.rawRepresentation])
        keychain.readFailure = .locked

        #expect(throws: SecretStoreError.locked) { try IdentityStore(store: keychain).identity() }
        #expect(keychain.writes == 0, "Ключ на месте, просто не достать: новый сейчас — это смена адреса")
    }

    @Test func afterUnlock_sameIdentityComesBack() throws {
        let signing = Curve25519.Signing.PrivateKey()
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let keychain = FakeSecretStore([
            IdentityStore.signingAccount: signing.rawRepresentation,
            IdentityStore.agreementAccount: agreement.rawRepresentation
        ])
        let store = IdentityStore(store: keychain)

        keychain.readFailure = .locked
        #expect(throws: (any Error).self) { try store.identity() }

        keychain.readFailure = nil
        let identity = try store.identity()

        #expect(identity.publicKey == signing.publicKey.rawRepresentation, "Неудача не кэшируется, а после разблокировки ключ тот же")
    }

    @Test func failedWrite_isNotCachedAsIdentity() throws {
        let keychain = FakeSecretStore()
        keychain.writeFailure = .failed(-25293)
        let store = IdentityStore(store: keychain)

        #expect(throws: (any Error).self) { try store.identity() }

        keychain.writeFailure = nil
        let identity = try store.identity()

        #expect(identity.publicKey.count == 32)
        #expect(keychain.writes == 3, "Первая запись упала, вторая и третья прошли")
    }

    // MARK: - Мусор

    @Test func corruptedSigningKey_isReplaced() throws {
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let keychain = FakeSecretStore([
            IdentityStore.signingAccount: Data("не ключ".utf8),
            IdentityStore.agreementAccount: agreement.rawRepresentation
        ])

        let identity = try IdentityStore(store: keychain).identity()

        #expect(keychain[IdentityStore.signingAccount]?.count == 32, "Мусор перезаписан настоящим ключом")
        #expect(identity.agreementKey == agreement.publicKey.rawRepresentation, "Целый ключ соглашения не тронут")
        #expect(keychain.writes == 1)
    }

    @Test func corruptedKey_wrongLength_isReplaced() throws {
        let keychain = FakeSecretStore([IdentityStore.signingAccount: Data(repeating: 0xAB, count: 31)])

        #expect(throws: Never.self) { try IdentityStore(store: keychain).identity() }
        #expect(keychain[IdentityStore.signingAccount]?.count == 32)
    }

    // MARK: - Сброс

    @Test func reset_forgetsIdentityAndNextOneIsNew() throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let before = try store.identity()
        try store.reset()
        let after = try store.identity()

        #expect(before.fingerprint != after.fingerprint)
        #expect(keychain[IdentityStore.signingAccount]?.count == 32, "Новый ключ записан на место старого")
    }

    // MARK: - Параллельно

    @Test func concurrentFirstAccess_createsOneIdentity() async throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let fingerprints = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<16 {
                group.addTask { try? store.identity().fingerprint }
            }
            return await group.reduce(into: Set<String?>()) { $0.insert($1) }
        }

        #expect(fingerprints.count == 1, "Гонка на первом обращении не должна плодить личности")
        #expect(keychain.writes == 2)
    }
}
