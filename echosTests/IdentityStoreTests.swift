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
import XCTest
@testable import echos

final class IdentityStoreTests: XCTestCase {

    // MARK: - Первый запуск

    func test_emptyKeychain_createsBothKeysAndWritesThem() throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let identity = try store.identity()

        XCTAssertEqual(keychain[IdentityStore.signingAccount]?.count, 32)
        XCTAssertEqual(keychain[IdentityStore.agreementAccount]?.count, 32)
        XCTAssertEqual(keychain.writes, 2)
        XCTAssertEqual(identity.publicKey.count, 32)
    }

    func test_secondCall_comesFromCache() throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let first = try store.identity()
        let readsAfterFirst = keychain.reads
        let second = try store.identity()

        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(keychain.reads, readsAfterFirst, "Кэш есть, чтобы в Keychain не ходить")
    }

    // MARK: - Уже есть

    func test_existingKeys_areLoadedNotReplaced() throws {
        let signing = Curve25519.Signing.PrivateKey()
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let keychain = FakeSecretStore([
            IdentityStore.signingAccount: signing.rawRepresentation,
            IdentityStore.agreementAccount: agreement.rawRepresentation
        ])

        let identity = try IdentityStore(store: keychain).identity()

        XCTAssertEqual(identity.publicKey, signing.publicKey.rawRepresentation)
        XCTAssertEqual(identity.agreementKey, agreement.publicKey.rawRepresentation)
        XCTAssertEqual(keychain.writes, 0, "Есть ключ — нечего писать")
    }

    func test_onlySigningKey_keepsAddressAndAddsAgreement() throws {
        // Обновление с версии без шифрования: подписывающий ключ уже есть,
        // и адрес из-за появления второго меняться не должен.
        let signing = Curve25519.Signing.PrivateKey()
        let keychain = FakeSecretStore([IdentityStore.signingAccount: signing.rawRepresentation])

        let identity = try IdentityStore(store: keychain).identity()

        XCTAssertEqual(identity.fingerprint, DeviceIdentity.fingerprint(of: signing.publicKey.rawRepresentation))
        XCTAssertEqual(keychain[IdentityStore.agreementAccount]?.count, 32)
        XCTAssertEqual(keychain.writes, 1)
    }

    // MARK: - Заперто

    func test_lockedDevice_throwsAndCreatesNothing() {
        let signing = Curve25519.Signing.PrivateKey()
        let keychain = FakeSecretStore([IdentityStore.signingAccount: signing.rawRepresentation])
        keychain.readFailure = .locked

        XCTAssertThrowsError(try IdentityStore(store: keychain).identity()) { error in
            XCTAssertEqual(error as? SecretStoreError, .locked)
        }
        XCTAssertEqual(keychain.writes, 0,
                       "Ключ на месте, просто не достать: новый сейчас — это смена адреса")
    }

    func test_afterUnlock_sameIdentityComesBack() throws {
        let signing = Curve25519.Signing.PrivateKey()
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let keychain = FakeSecretStore([
            IdentityStore.signingAccount: signing.rawRepresentation,
            IdentityStore.agreementAccount: agreement.rawRepresentation
        ])
        let store = IdentityStore(store: keychain)

        keychain.readFailure = .locked
        XCTAssertThrowsError(try store.identity())

        keychain.readFailure = nil
        let identity = try store.identity()

        XCTAssertEqual(identity.publicKey, signing.publicKey.rawRepresentation,
                       "Неудача не кэшируется, а после разблокировки ключ тот же")
    }

    func test_failedWrite_isNotCachedAsIdentity() throws {
        let keychain = FakeSecretStore()
        keychain.writeFailure = .failed(-25293)
        let store = IdentityStore(store: keychain)

        XCTAssertThrowsError(try store.identity())

        keychain.writeFailure = nil
        let identity = try store.identity()

        XCTAssertEqual(identity.publicKey.count, 32)
        XCTAssertEqual(keychain.writes, 3, "Первая запись упала, вторая и третья прошли")
    }

    // MARK: - Мусор

    func test_corruptedSigningKey_isReplaced() throws {
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let keychain = FakeSecretStore([
            IdentityStore.signingAccount: Data("не ключ".utf8),
            IdentityStore.agreementAccount: agreement.rawRepresentation
        ])

        let identity = try IdentityStore(store: keychain).identity()

        XCTAssertEqual(keychain[IdentityStore.signingAccount]?.count, 32, "Мусор перезаписан настоящим ключом")
        XCTAssertEqual(identity.agreementKey, agreement.publicKey.rawRepresentation,
                       "Целый ключ соглашения не тронут")
        XCTAssertEqual(keychain.writes, 1)
    }

    func test_corruptedKey_wrongLength_isReplaced() throws {
        let keychain = FakeSecretStore([IdentityStore.signingAccount: Data(repeating: 0xAB, count: 31)])

        XCTAssertNoThrow(try IdentityStore(store: keychain).identity())
        XCTAssertEqual(keychain[IdentityStore.signingAccount]?.count, 32)
    }

    // MARK: - Сброс

    func test_reset_forgetsIdentityAndNextOneIsNew() throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let before = try store.identity()
        try store.reset()
        let after = try store.identity()

        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
        XCTAssertEqual(keychain[IdentityStore.signingAccount]?.count, 32, "Новый ключ записан на место старого")
    }

    // MARK: - Параллельно

    func test_concurrentFirstAccess_createsOneIdentity() async throws {
        let keychain = FakeSecretStore()
        let store = IdentityStore(store: keychain)

        let fingerprints = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<16 {
                group.addTask { try? store.identity().fingerprint }
            }
            return await group.reduce(into: Set<String?>()) { $0.insert($1) }
        }

        XCTAssertEqual(fingerprints.count, 1, "Гонка на первом обращении не должна плодить личности")
        XCTAssertEqual(keychain.writes, 2)
    }
}
