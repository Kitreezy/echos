//
//  SecretRotationTests.swift
//  echosTests
//
//  Unit: ротация секретов — перезапись без смены ключа, починка мусора
//  и пустоты, уважение к запертому Keychain.
//

import CryptoKit
import Foundation
import Testing
@testable import echos

struct SecretRotationTests {

    private func makeKeys() -> (signing: Data, agreement: Data) {
        (Curve25519.Signing.PrivateKey().rawRepresentation,
         Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
    }

    @Test func existingSecrets_areRewritten_unchanged() throws {
        let (signing, agreement) = makeKeys()
        let store = FakeSecretStore([
            IdentityStore.signingAccount: signing,
            IdentityStore.agreementAccount: agreement
        ])
        let rotation = SecretRotation(store: store)

        let result = try rotation.rotate()

        #expect(result.rotated == 2)
        #expect(result.healed == 0)
        #expect(!result.skippedLocked)
        // Ключ — прежний: ротация тасует обёртку, адрес не смещается.
        #expect(store[IdentityStore.signingAccount] == signing)
        #expect(store[IdentityStore.agreementAccount] == agreement)
    }

    @Test func garbageBytes_areHealedIntoValidKey() throws {
        let store = FakeSecretStore([
            IdentityStore.signingAccount: Data("не ключ".utf8)
        ])
        let rotation = SecretRotation(store: store)

        let result = try rotation.rotate()

        #expect(result.healed == 2, "Мусор и отсутствие записи — оба лечатся")
        let healed = try #require(store[IdentityStore.signingAccount])
        // Вылеченная запись — настоящий ключ, а не повтор мусора.
        let parsed = try? Curve25519.Signing.PrivateKey(rawRepresentation: healed)
        #expect(parsed != nil)
    }

    @Test func rotation_isIdempotent() throws {
        let (signing, agreement) = makeKeys()
        let store = FakeSecretStore([
            IdentityStore.signingAccount: signing,
            IdentityStore.agreementAccount: agreement
        ])
        let rotation = SecretRotation(store: store)

        _ = try rotation.rotate()
        let afterFirst = (store[IdentityStore.signingAccount],
                          store[IdentityStore.agreementAccount])
        let second = try rotation.rotate()

        #expect(second.rotated == 2)
        #expect(second.healed == 0)
        #expect(afterFirst.0 == store[IdentityStore.signingAccount])
        #expect(afterFirst.1 == store[IdentityStore.agreementAccount])
    }

    @Test func lockedKeychain_skipsWithoutDamage() throws {
        let (signing, agreement) = makeKeys()
        let store = FakeSecretStore([
            IdentityStore.signingAccount: signing,
            IdentityStore.agreementAccount: agreement
        ])
        store.readFailure = .locked
        let rotation = SecretRotation(store: store)

        let result = try rotation.rotate()

        #expect(result.skippedLocked)
        #expect(result.rotated == 0)
        #expect(store.writes == 0, "Запертому Keychain не пишем вовсе")
        // Записи не тронуты: запертый Keychain — не повод пересоздавать ключи.
        #expect(store[IdentityStore.signingAccount] == signing)
        #expect(store[IdentityStore.agreementAccount] == agreement)
    }
}
