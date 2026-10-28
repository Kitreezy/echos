//
//  KeyBundleTests.swift
//  echosTests
//
//  Привязка ключа соглашения к личности: проверенной становится только
//  связка, где подпись сходится с подписывающим ключом.
//

import CryptoKit
import Foundation
import Testing
@testable import echos

@Suite(.tags(.crypto))
struct KeyBundleTests {

    private func bundle(of identity: DeviceIdentity) throws -> KeyBundle {
        try identity.keyBundle(session: try SessionKey(signedBy: identity))
    }

    @Test func ownBundle_verifies() throws {
        let bob = DeviceIdentity()
        let peer = try #require(try bundle(of: bob).verified())

        #expect(peer.fingerprint == bob.fingerprint)
        #expect(peer.agreementKey == bob.agreementKey)
    }

    @Test func agreementKey_differsFromSigningKey() {
        let bob = DeviceIdentity()
        #expect(bob.agreementKey != bob.publicKey, "Ключ соглашения — отдельный ключ, а не подписывающий в другой роли")
    }

    @Test func swappedAgreementKey_failsVerification() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let honest = try bundle(of: bob)

        let swapped = KeyBundle(publicKey: honest.publicKey,
                                agreementKey: mallory.agreementKey,
                                agreementProof: honest.agreementProof,
                                sessionKey: honest.sessionKey,
                                sessionProof: honest.sessionProof)

        #expect(swapped.verified() == nil)
    }

    @Test func proofByAnotherIdentity_failsVerification() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let malloryBundle = try bundle(of: mallory)

        let hijacked = KeyBundle(publicKey: bob.publicKey,
                                 agreementKey: malloryBundle.agreementKey,
                                 agreementProof: malloryBundle.agreementProof,
                                 sessionKey: malloryBundle.sessionKey,
                                 sessionProof: malloryBundle.sessionProof)

        #expect(hijacked.verified() == nil)
    }

    @Test func garbageKeys_failVerification() {
        let junk = KeyBundle(publicKey: Data("не ключ".utf8),
                             agreementKey: Data("и это не ключ".utf8),
                             agreementProof: Data(repeating: 0, count: 64),
                             sessionKey: Data("и это".utf8),
                             sessionProof: Data(repeating: 0, count: 64))

        #expect(junk.verified() == nil)
    }

    @Test func signingKeyValidButAgreementKeyGarbage_failsVerification() throws {
        let bob = DeviceIdentity()
        let junkKey = Data("не ключ соглашения".utf8)

        let session = try SessionKey(signedBy: bob)
        let bundle = KeyBundle(publicKey: bob.publicKey,
                               agreementKey: junkKey,
                               agreementProof: try bob.signature(for: KeyBundle.bindingMessage(for: junkKey)),
                               sessionKey: session.publicKey,
                               sessionProof: session.proof)

        #expect(bundle.verified() == nil, "Подпись честная, но ключ не разбирается")
    }

    // MARK: - Сессионный ключ

    @Test func sessionKey_isCarriedAndVerified() throws {
        let bob = DeviceIdentity()
        let session = try SessionKey(signedBy: bob)
        let peer = try #require(try bob.keyBundle(session: session).verified())

        #expect(peer.sessionKey == session.publicKey)
    }

    @Test func sessionKeyProvenByAnotherIdentity_failsVerification() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let honest = try bundle(of: bob)
        let mallorySession = try SessionKey(signedBy: mallory)

        let hijacked = KeyBundle(publicKey: honest.publicKey,
                                 agreementKey: honest.agreementKey,
                                 agreementProof: honest.agreementProof,
                                 sessionKey: mallorySession.publicKey,
                                 sessionProof: mallorySession.proof)

        #expect(hijacked.verified() == nil)
    }

    /// Статический и сессионный ключ — оба X25519 по 32 байта, и подпись
    /// под одним не должна годиться под другой: префиксы разные.
    @Test func agreementProof_doesNotProveASessionKey() throws {
        let bob = DeviceIdentity()
        let honest = try bundle(of: bob)

        let confused = KeyBundle(publicKey: honest.publicKey,
                                 agreementKey: honest.agreementKey,
                                 agreementProof: honest.agreementProof,
                                 sessionKey: honest.agreementKey,
                                 sessionProof: honest.agreementProof)

        #expect(confused.verified() == nil)
        #expect(SessionKey.bindingMessage(for: honest.agreementKey) != KeyBundle.bindingMessage(for: honest.agreementKey))
    }

    @Test func bundleWithoutSessionKey_doesNotDecode() throws {
        // Так выглядит связка от сборки с только статическим ключом.
        let json = #"{"publicKey":"AA==","agreementKey":"AA==","agreementProof":"AA=="}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(KeyBundle.self, from: Data(json.utf8)) }
    }

    @Test func bindingMessage_isNotABareKey() {
        let key = Data(repeating: 7, count: 32)
        #expect(KeyBundle.bindingMessage(for: key) != key)
        #expect(KeyBundle.bindingMessage(for: key).count > 32, "Иначе подпись под вызовом сошла бы за подпись под ключом")
    }

    @Test func bundle_survivesTheWire() throws {
        let bob = DeviceIdentity()
        let bundle = try bundle(of: bob)

        let restored = try JSONDecoder().decode(KeyBundle.self, from: try JSONEncoder().encode(bundle))

        #expect(restored == bundle)
        #expect(restored.verified() != nil)
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
