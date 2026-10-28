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
@testable import echos

@Suite(.tags(.crypto))
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

    // MARK: - Конверт hello

    @Test func helloEnvelope_carriesKeyAndUsableSignature() throws {
        let identity = DeviceIdentity()
        let challenge = Data("вызов сервера".utf8)

        let envelope = try RelayEnvelope.hello(from: "Alice",
                                               answering: challenge,
                                               as: identity,
                                               session: try SessionKey(signedBy: identity))

        #expect(envelope.kind == .hello)
        #expect(envelope.sender == "Alice")

        let payload = try #require(envelope.payload)
        let proof = try JSONDecoder().decode(HelloPayload.self, from: payload)

        #expect(proof.publicKey == identity.publicKey)

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: proof.publicKey)
        #expect(publicKey.isValidSignature(proof.signature, for: challenge))
    }

    @Test func helloEnvelope_survivesTheWire() throws {
        let identity = DeviceIdentity()
        let challenge = Data("вызов сервера".utf8)

        let original = try RelayEnvelope.hello(from: "Alice",
                                               answering: challenge,
                                               as: identity,
                                               session: try SessionKey(signedBy: identity))
        let restored = try RelayEnvelope.decode(from: try original.encoded())

        let payload = try #require(restored.payload)
        let proof = try JSONDecoder().decode(HelloPayload.self, from: payload)

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: proof.publicKey)
        #expect(publicKey.isValidSignature(proof.signature, for: challenge))
    }

    // MARK: - Вызов

    @Test func challengeEnvelope_decodesToRawNonce() throws {
        // Так конверт приходит от релея: nonce лежит в payload как есть.
        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let json = ["kind": "challenge", "sender": "", "payload": nonce.base64EncodedString()]
        let data = try JSONSerialization.data(withJSONObject: json)

        let envelope = try RelayEnvelope.decode(from: data)

        #expect(envelope.kind == .challenge)
        #expect(try envelope.decodeChallenge() == nonce)
    }
}
