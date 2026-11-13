//
//  RelayCryptoIntegrationTests.swift
//  echosTests
//
//  Стыковка криптопакета с сетевыми конвертами приложения: личность из
//  EchosCrypto должна проходить через hello и presence релея без изменений.
//

import CryptoKit
import EchosCrypto
import Foundation
import Testing
@testable import echos

@Suite(.tags(.crypto))
struct RelayCryptoIntegrationTests {

    private func bundle(of identity: DeviceIdentity) throws -> KeyBundle {
        try identity.keyBundle(session: try SessionKey(signedBy: identity))
    }

    // MARK: - hello

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

    // MARK: - Участник релея

    @Test func participant_withMatchingKeys_hasIdentity() throws {
        let bob = DeviceIdentity()
        let participant = RelayParticipant(id: bob.fingerprint, name: "Bob", keys: try bundle(of: bob))

        #expect(participant.verifiedIdentity?.fingerprint == bob.fingerprint)
    }

    @Test func participant_withoutKeys_hasNoIdentity() {
        let participant = RelayParticipant(id: "0123456789abcdef", name: "Старая сборка")
        #expect(participant.verifiedIdentity == nil)
    }

    /// Релей поставил рядом с адресом Боба ключи Мэллори. Отпечаток ключей
    /// с адресом не совпадает — и этого достаточно, чтобы отказать.
    @Test func participant_withSomeoneElsesKeys_hasNoIdentity() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let participant = RelayParticipant(id: bob.fingerprint, name: "Bob", keys: try bundle(of: mallory))

        #expect(participant.verifiedIdentity == nil)
    }

    /// Присутствие от старого релея, без ключей, разбирается — участник
    /// просто остаётся без личности.
    @Test func participant_fromOldRelay_decodes() throws {
        let json = #"[{"id":"0123456789abcdef","name":"Bob"}]"#
        let participants = try JSONDecoder().decode([RelayParticipant].self, from: Data(json.utf8))

        #expect(participants.count == 1)
        #expect(participants[0].verifiedIdentity == nil)
    }

    /// Участник со статическим ключом, но без сессионного — сборка между
    /// двумя шагами. Ключ переписки с ней вывести нельзя.
    @Test func participant_withoutSessionKey_hasNoIdentity() throws {
        let bob = DeviceIdentity()
        let honest = try bundle(of: bob)
        let json = """
        [{"id":"\(bob.fingerprint)","name":"Bob",
          "publicKey":"\(honest.publicKey.base64EncodedString())",
          "agreementKey":"\(honest.agreementKey.base64EncodedString())",
          "agreementProof":"\(honest.agreementProof.base64EncodedString())"}]
        """
        let participants = try JSONDecoder().decode([RelayParticipant].self, from: Data(json.utf8))

        #expect(participants[0].verifiedIdentity == nil)
    }
}
