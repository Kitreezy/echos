//
//  KeyBundleTests.swift
//  echosTests
//
//  Привязка ключа соглашения к личности: проверенной становится только
//  связка, где подпись сходится с подписывающим ключом.
//

import CryptoKit
import XCTest
@testable import echos

final class KeyBundleTests: XCTestCase {

    private func bundle(of identity: DeviceIdentity) throws -> KeyBundle {
        try identity.keyBundle(session: try SessionKey(signedBy: identity))
    }

    func test_ownBundle_verifies() throws {
        let bob = DeviceIdentity()
        let peer = try XCTUnwrap(try bundle(of: bob).verified())

        XCTAssertEqual(peer.fingerprint, bob.fingerprint)
        XCTAssertEqual(peer.agreementKey, bob.agreementKey)
    }

    func test_agreementKey_differsFromSigningKey() {
        let bob = DeviceIdentity()
        XCTAssertNotEqual(bob.agreementKey, bob.publicKey,
                          "Ключ соглашения — отдельный ключ, а не подписывающий в другой роли")
    }

    func test_swappedAgreementKey_failsVerification() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let honest = try bundle(of: bob)

        let swapped = KeyBundle(publicKey: honest.publicKey,
                                agreementKey: mallory.agreementKey,
                                agreementProof: honest.agreementProof,
                                sessionKey: honest.sessionKey,
                                sessionProof: honest.sessionProof)

        XCTAssertNil(swapped.verified())
    }

    func test_proofByAnotherIdentity_failsVerification() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let malloryBundle = try bundle(of: mallory)

        let hijacked = KeyBundle(publicKey: bob.publicKey,
                                 agreementKey: malloryBundle.agreementKey,
                                 agreementProof: malloryBundle.agreementProof,
                                 sessionKey: malloryBundle.sessionKey,
                                 sessionProof: malloryBundle.sessionProof)

        XCTAssertNil(hijacked.verified())
    }

    func test_garbageKeys_failVerification() {
        let junk = KeyBundle(publicKey: Data("не ключ".utf8),
                             agreementKey: Data("и это не ключ".utf8),
                             agreementProof: Data(repeating: 0, count: 64),
                             sessionKey: Data("и это".utf8),
                             sessionProof: Data(repeating: 0, count: 64))

        XCTAssertNil(junk.verified())
    }

    func test_signingKeyValidButAgreementKeyGarbage_failsVerification() throws {
        let bob = DeviceIdentity()
        let junkKey = Data("не ключ соглашения".utf8)

        let session = try SessionKey(signedBy: bob)
        let bundle = KeyBundle(publicKey: bob.publicKey,
                               agreementKey: junkKey,
                               agreementProof: try bob.signature(for: KeyBundle.bindingMessage(for: junkKey)),
                               sessionKey: session.publicKey,
                               sessionProof: session.proof)

        XCTAssertNil(bundle.verified(), "Подпись честная, но ключ не разбирается")
    }

    // MARK: - Сессионный ключ

    func test_sessionKey_isCarriedAndVerified() throws {
        let bob = DeviceIdentity()
        let session = try SessionKey(signedBy: bob)
        let peer = try XCTUnwrap(try bob.keyBundle(session: session).verified())

        XCTAssertEqual(peer.sessionKey, session.publicKey)
    }

    func test_sessionKeyProvenByAnotherIdentity_failsVerification() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let honest = try bundle(of: bob)
        let mallorySession = try SessionKey(signedBy: mallory)

        let hijacked = KeyBundle(publicKey: honest.publicKey,
                                 agreementKey: honest.agreementKey,
                                 agreementProof: honest.agreementProof,
                                 sessionKey: mallorySession.publicKey,
                                 sessionProof: mallorySession.proof)

        XCTAssertNil(hijacked.verified())
    }

    /// Статический и сессионный ключ — оба X25519 по 32 байта, и подпись
    /// под одним не должна годиться под другой: префиксы разные.
    func test_agreementProof_doesNotProveASessionKey() throws {
        let bob = DeviceIdentity()
        let honest = try bundle(of: bob)

        let confused = KeyBundle(publicKey: honest.publicKey,
                                 agreementKey: honest.agreementKey,
                                 agreementProof: honest.agreementProof,
                                 sessionKey: honest.agreementKey,
                                 sessionProof: honest.agreementProof)

        XCTAssertNil(confused.verified())
        XCTAssertNotEqual(SessionKey.bindingMessage(for: honest.agreementKey),
                          KeyBundle.bindingMessage(for: honest.agreementKey))
    }

    func test_bundleWithoutSessionKey_doesNotDecode() throws {
        // Так выглядит связка от сборки с только статическим ключом.
        let json = #"{"publicKey":"AA==","agreementKey":"AA==","agreementProof":"AA=="}"#
        XCTAssertThrowsError(try JSONDecoder().decode(KeyBundle.self, from: Data(json.utf8)))
    }

    func test_bindingMessage_isNotABareKey() {
        let key = Data(repeating: 7, count: 32)
        XCTAssertNotEqual(KeyBundle.bindingMessage(for: key), key)
        XCTAssertGreaterThan(KeyBundle.bindingMessage(for: key).count, 32,
                             "Иначе подпись под вызовом сошла бы за подпись под ключом")
    }

    func test_bundle_survivesTheWire() throws {
        let bob = DeviceIdentity()
        let bundle = try bundle(of: bob)

        let restored = try JSONDecoder().decode(KeyBundle.self, from: try JSONEncoder().encode(bundle))

        XCTAssertEqual(restored, bundle)
        XCTAssertNotNil(restored.verified())
    }

    // MARK: - Участник релея

    func test_participant_withMatchingKeys_hasIdentity() throws {
        let bob = DeviceIdentity()
        let participant = RelayParticipant(id: bob.fingerprint, name: "Bob", keys: try bundle(of: bob))

        XCTAssertEqual(participant.verifiedIdentity?.fingerprint, bob.fingerprint)
    }

    func test_participant_withoutKeys_hasNoIdentity() {
        let participant = RelayParticipant(id: "0123456789abcdef", name: "Старая сборка")
        XCTAssertNil(participant.verifiedIdentity)
    }

    /// Релей поставил рядом с адресом Боба ключи Мэллори. Отпечаток ключей
    /// с адресом не совпадает — и этого достаточно, чтобы отказать.
    func test_participant_withSomeoneElsesKeys_hasNoIdentity() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let participant = RelayParticipant(id: bob.fingerprint, name: "Bob", keys: try bundle(of: mallory))

        XCTAssertNil(participant.verifiedIdentity)
    }

    /// Присутствие от старого релея, без ключей, разбирается — участник
    /// просто остаётся без личности.
    func test_participant_fromOldRelay_decodes() throws {
        let json = #"[{"id":"0123456789abcdef","name":"Bob"}]"#
        let participants = try JSONDecoder().decode([RelayParticipant].self, from: Data(json.utf8))

        XCTAssertEqual(participants.count, 1)
        XCTAssertNil(participants[0].verifiedIdentity)
    }

    /// Участник со статическим ключом, но без сессионного — сборка между
    /// двумя шагами. Ключ переписки с ней вывести нельзя.
    func test_participant_withoutSessionKey_hasNoIdentity() throws {
        let bob = DeviceIdentity()
        let honest = try bundle(of: bob)
        let json = """
        [{"id":"\(bob.fingerprint)","name":"Bob",
          "publicKey":"\(honest.publicKey.base64EncodedString())",
          "agreementKey":"\(honest.agreementKey.base64EncodedString())",
          "agreementProof":"\(honest.agreementProof.base64EncodedString())"}]
        """
        let participants = try JSONDecoder().decode([RelayParticipant].self, from: Data(json.utf8))

        XCTAssertNil(participants[0].verifiedIdentity)
    }
}
