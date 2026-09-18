//
//  AppAttestTests.swift
//  echosTests
//
//  App Attest со стороны клиента. Само доказательство выдаёт Apple, и
//  проверить его здесь нечем; проверяется, что клиент просит его за тот
//  ключ и под тот вызов, что нужно, и что в hello оно доезжает целиком —
//  а без него hello выглядит ровно как раньше.
//

import XCTest
@testable import echos

final class AppAttestTests: XCTestCase {

    private let identity = DeviceIdentity()
    private let challenge = Data("relay challenge".utf8)

    private func helloJSON(attestation: AttestationProof?) throws -> [String: Any] {
        let envelope = try RelayEnvelope.hello(from: "Alice",
                                               answering: challenge,
                                               as: identity,
                                               session: try SessionKey(signedBy: identity),
                                               attestation: attestation)
        let payload = try XCTUnwrap(envelope.payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    }

    // MARK: - hello

    func test_helloWithoutAttestation_looksLikeBefore() throws {
        let json = try helloJSON(attestation: nil)

        for key in ["attestKeyId", "attestation", "attestChallenge", "assertion"] {
            XCTAssertNil(json[key], "\(key) не должен появляться, когда ручаться нечем: старый релей его не ждёт")
        }
    }

    func test_helloWithAttestation_carriesAllFourFields() throws {
        let proof = FakeAttestation().proof
        let json = try helloJSON(attestation: proof)

        XCTAssertEqual(json["attestKeyId"] as? String, proof.keyID.base64EncodedString())
        XCTAssertEqual(json["attestation"] as? String, proof.attestation.base64EncodedString())
        XCTAssertEqual(json["attestChallenge"] as? String, proof.challenge.base64EncodedString())
        XCTAssertEqual(json["assertion"] as? String, proof.assertion.base64EncodedString())
    }

    func test_helloWithAttestation_stillSignsTheChallenge() throws {
        // Ручательство устройства дополняет подпись личности, а не заменяет.
        let json = try helloJSON(attestation: FakeAttestation().proof)

        XCTAssertNotNil(json["signature"])
        XCTAssertEqual(json["publicKey"] as? String, identity.publicKey.base64EncodedString())
    }

    // MARK: - Что подписывается

    func test_assertionClientData_bindsChallengeToIdentityKey() {
        let data = assertionClientData(challenge: Data([1, 2]), publicKey: Data([3, 4, 5]))

        XCTAssertEqual(data, Data([1, 2, 3, 4, 5]),
                       "Порядок и склейка обязаны совпадать с AssertionClientData на релее")
    }

    func test_noAttestation_yieldsNothing() async throws {
        let proof = try await NoAttestation().proof(answering: challenge, for: identity.publicKey)

        XCTAssertNil(proof)
    }

    // MARK: - Присутствие

    func test_participant_readsAttestedFlag() throws {
        let json = #"[{"id":"a1","name":"Alice","attested":true},{"id":"b2","name":"Bob"}]"#
        let participants = try JSONDecoder().decode([RelayParticipant].self, from: Data(json.utf8))

        XCTAssertEqual(participants[0].attested, true)
        XCTAssertNil(participants[1].attested, "Старый релей поля не шлёт — это не false, а неизвестно")
    }
}
