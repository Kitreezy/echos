//
//  DeviceIdentityTests.swift
//  echosTests
//
//  Личность устройства и рукопожатие с релеем.
//
//  Keychain здесь не участвует: тесты работают с одноразовым ключом, а
//  хранение проверяется на устройстве — подменить Keychain в юнит-тесте
//  всё равно нечем.
//

import CryptoKit
import Foundation
import Testing
@testable import EchosCrypto

struct DeviceIdentityTests {

    // MARK: - Подпись

    @Test func signature_verifiesAgainstOwnPublicKey() throws {
        let identity = DeviceIdentity()
        let challenge = Data("случайная строка от сервера".utf8)

        let signature = try identity.signature(for: challenge)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKey)

        #expect(publicKey.isValidSignature(signature, for: challenge))
    }

    @Test func signature_doesNotFitAnotherChallenge() throws {
        let identity = DeviceIdentity()

        let signature = try identity.signature(for: Data("первый вызов".utf8))
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKey)

        #expect(!(publicKey.isValidSignature(signature, for: Data("второй вызов".utf8))), "Подпись должна годиться ровно для одного подключения")
    }

    @Test func signature_doesNotFitAnotherKey() throws {
        let bob = DeviceIdentity()
        let carol = DeviceIdentity()
        let challenge = Data("вызов".utf8)

        let signature = try carol.signature(for: challenge)
        let bobsKey = try Curve25519.Signing.PublicKey(rawRepresentation: bob.publicKey)

        #expect(!(bobsKey.isValidSignature(signature, for: challenge)), "Чужой подписью под своим именем подтвердиться нельзя")
    }

    // MARK: - Отпечаток

    @Test func fingerprint_isStableAndShort() {
        let identity = DeviceIdentity()

        #expect(identity.fingerprint == identity.fingerprint)
        #expect(identity.fingerprint.count == 16)
    }

    @Test func fingerprint_differsBetweenDevices() {
        #expect(DeviceIdentity().fingerprint != DeviceIdentity().fingerprint)
    }
}
