//
//  KeyBundleTests.swift
//  echosTests
//
//  Привязка ключа соглашения к личности: проверенной становится только
//  связка, где подпись сходится с подписывающим ключом.
//

import XCTest
@testable import echos

final class KeyBundleTests: XCTestCase {

    func test_ownBundle_verifies() throws {
        let bob = DeviceIdentity()
        let peer = try XCTUnwrap(try bob.keyBundle().verified())

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
        let honest = try bob.keyBundle()

        let swapped = KeyBundle(publicKey: honest.publicKey,
                                agreementKey: mallory.agreementKey,
                                agreementProof: honest.agreementProof)

        XCTAssertNil(swapped.verified())
    }

    func test_proofByAnotherIdentity_failsVerification() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let malloryBundle = try mallory.keyBundle()

        let hijacked = KeyBundle(publicKey: bob.publicKey,
                                 agreementKey: malloryBundle.agreementKey,
                                 agreementProof: malloryBundle.agreementProof)

        XCTAssertNil(hijacked.verified())
    }

    func test_garbageKeys_failVerification() {
        let junk = KeyBundle(publicKey: Data("не ключ".utf8),
                             agreementKey: Data("и это не ключ".utf8),
                             agreementProof: Data(repeating: 0, count: 64))

        XCTAssertNil(junk.verified())
    }

    func test_signingKeyValidButAgreementKeyGarbage_failsVerification() throws {
        let bob = DeviceIdentity()
        let junkKey = Data("не ключ соглашения".utf8)

        let bundle = KeyBundle(publicKey: bob.publicKey,
                               agreementKey: junkKey,
                               agreementProof: try bob.signature(for: KeyBundle.bindingMessage(for: junkKey)))

        XCTAssertNil(bundle.verified(), "Подпись честная, но ключ не разбирается")
    }

    func test_bindingMessage_isNotABareKey() {
        let key = Data(repeating: 7, count: 32)
        XCTAssertNotEqual(KeyBundle.bindingMessage(for: key), key)
        XCTAssertGreaterThan(KeyBundle.bindingMessage(for: key).count, 32,
                             "Иначе подпись под вызовом сошла бы за подпись под ключом")
    }

    func test_bundle_survivesTheWire() throws {
        let bob = DeviceIdentity()
        let bundle = try bob.keyBundle()

        let restored = try JSONDecoder().decode(KeyBundle.self, from: try JSONEncoder().encode(bundle))

        XCTAssertEqual(restored, bundle)
        XCTAssertNotNil(restored.verified())
    }

    // MARK: - Участник релея

    func test_participant_withMatchingKeys_hasIdentity() throws {
        let bob = DeviceIdentity()
        let participant = RelayParticipant(id: bob.fingerprint, name: "Bob", keys: try bob.keyBundle())

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
        let participant = RelayParticipant(id: bob.fingerprint, name: "Bob", keys: try mallory.keyBundle())

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
}
