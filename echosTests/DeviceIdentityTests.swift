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
import XCTest
@testable import echos

final class DeviceIdentityTests: XCTestCase {

    // MARK: - Подпись

    func test_signature_verifiesAgainstOwnPublicKey() throws {
        let identity = DeviceIdentity()
        let challenge = Data("случайная строка от сервера".utf8)

        let signature = try identity.signature(for: challenge)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKey)

        XCTAssertTrue(publicKey.isValidSignature(signature, for: challenge))
    }

    func test_signature_doesNotFitAnotherChallenge() throws {
        let identity = DeviceIdentity()

        let signature = try identity.signature(for: Data("первый вызов".utf8))
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKey)

        XCTAssertFalse(publicKey.isValidSignature(signature, for: Data("второй вызов".utf8)),
                       "Подпись должна годиться ровно для одного подключения")
    }

    func test_signature_doesNotFitAnotherKey() throws {
        let bob = DeviceIdentity()
        let carol = DeviceIdentity()
        let challenge = Data("вызов".utf8)

        let signature = try carol.signature(for: challenge)
        let bobsKey = try Curve25519.Signing.PublicKey(rawRepresentation: bob.publicKey)

        XCTAssertFalse(bobsKey.isValidSignature(signature, for: challenge),
                       "Чужой подписью под своим именем подтвердиться нельзя")
    }

    // MARK: - Отпечаток

    func test_fingerprint_isStableAndShort() {
        let identity = DeviceIdentity()

        XCTAssertEqual(identity.fingerprint, identity.fingerprint)
        XCTAssertEqual(identity.fingerprint.count, 16)
    }

    func test_fingerprint_differsBetweenDevices() {
        XCTAssertNotEqual(DeviceIdentity().fingerprint, DeviceIdentity().fingerprint)
    }

    // MARK: - Конверт hello

    func test_helloEnvelope_carriesKeyAndUsableSignature() throws {
        let identity = DeviceIdentity()
        let challenge = Data("вызов сервера".utf8)

        let envelope = try RelayEnvelope.hello(from: "Alice",
                                               answering: challenge,
                                               as: identity)

        XCTAssertEqual(envelope.kind, .hello)
        XCTAssertEqual(envelope.sender, "Alice")

        let payload = try XCTUnwrap(envelope.payload)
        let proof = try JSONDecoder().decode(HelloPayload.self, from: payload)

        XCTAssertEqual(proof.publicKey, identity.publicKey)

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: proof.publicKey)
        XCTAssertTrue(publicKey.isValidSignature(proof.signature, for: challenge))
    }

    func test_helloEnvelope_survivesTheWire() throws {
        let identity = DeviceIdentity()
        let challenge = Data("вызов сервера".utf8)

        let original = try RelayEnvelope.hello(from: "Alice",
                                               answering: challenge,
                                               as: identity)
        let restored = try RelayEnvelope.decode(from: try original.encoded())

        let payload = try XCTUnwrap(restored.payload)
        let proof = try JSONDecoder().decode(HelloPayload.self, from: payload)

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: proof.publicKey)
        XCTAssertTrue(publicKey.isValidSignature(proof.signature, for: challenge))
    }

    // MARK: - Вызов

    func test_challengeEnvelope_decodesToRawNonce() throws {
        // Так конверт приходит от релея: nonce лежит в payload как есть.
        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let json = ["kind": "challenge", "sender": "", "payload": nonce.base64EncodedString()]
        let data = try JSONSerialization.data(withJSONObject: json)

        let envelope = try RelayEnvelope.decode(from: data)

        XCTAssertEqual(envelope.kind, .challenge)
        XCTAssertEqual(try envelope.decodeChallenge(), nonce)
    }
}
