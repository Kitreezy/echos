//
//  ConversationCipherTests.swift
//  echosTests
//
//  Шифр переписки: обе стороны выводят один ключ, чужой не открывает,
//  подмена и перестановка конверта не проходят.
//

import CryptoKit
import XCTest
@testable import echos

final class ConversationCipherTests: XCTestCase {

    private let alice = DeviceIdentity()
    private let bob = DeviceIdentity()
    private let mallory = DeviceIdentity()

    private func peer(_ identity: DeviceIdentity) throws -> PeerIdentity {
        try XCTUnwrap(try identity.keyBundle().verified())
    }

    private func payload(_ text: String) -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: true), senderName: "Alice")
    }

    // MARK: - Честная пара

    func test_bothSides_deriveTheSameKey() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))
        let bobSide = try ConversationCipher(identity: bob, peer: peer(alice))

        let sealed = try aliceSide.seal(payload("привет"), from: alice.fingerprint, to: bob.fingerprint)
        let opened = try bobSide.open(sealed, as: MessagePayload.self,
                                      from: alice.fingerprint, to: bob.fingerprint)

        XCTAssertEqual(opened.text, "привет")
    }

    func test_sealedText_isNotVisibleOnTheWire() throws {
        let cipher = try ConversationCipher(identity: alice, peer: peer(bob))
        let sealed = try cipher.seal(payload("секрет"), from: alice.fingerprint, to: bob.fingerprint)

        let wire = try JSONEncoder().encode(sealed)
        XCTAssertFalse(String(decoding: wire, as: UTF8.self).contains("секрет"))
        XCTAssertNil(sealed.box.range(of: Data("секрет".utf8)))
    }

    func test_sameMessageTwice_looksDifferentOnTheWire() throws {
        let cipher = try ConversationCipher(identity: alice, peer: peer(bob))
        let message = payload("одно и то же")

        let first = try cipher.seal(message, from: alice.fingerprint, to: bob.fingerprint)
        let second = try cipher.seal(message, from: alice.fingerprint, to: bob.fingerprint)

        XCTAssertNotEqual(first, second, "nonce должен быть свежим на каждое сообщение")
    }

    /// Порядок адресов не важен: Боб, считающий ключ с Алисой, и Алиса,
    /// считающая ключ с Бобом, должны сойтись, хотя отпечатки у них
    /// в разном порядке.
    func test_keyDerivation_isSymmetric() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))
        let bobSide = try ConversationCipher(identity: bob, peer: peer(alice))

        let fromBob = try bobSide.seal(payload("ответ"), from: bob.fingerprint, to: alice.fingerprint)
        let opened = try aliceSide.open(fromBob, as: MessagePayload.self,
                                        from: bob.fingerprint, to: alice.fingerprint)

        XCTAssertEqual(opened.text, "ответ")
    }

    // MARK: - Чужие

    func test_thirdParty_cannotOpen() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))
        let malloryWithBob = try ConversationCipher(identity: mallory, peer: peer(bob))
        let malloryWithAlice = try ConversationCipher(identity: mallory, peer: peer(alice))

        let sealed = try aliceSide.seal(payload("не для тебя"), from: alice.fingerprint, to: bob.fingerprint)

        XCTAssertThrowsError(try malloryWithBob.open(sealed, as: MessagePayload.self,
                                                     from: alice.fingerprint, to: bob.fingerprint))
        XCTAssertThrowsError(try malloryWithAlice.open(sealed, as: MessagePayload.self,
                                                       from: alice.fingerprint, to: bob.fingerprint))
    }

    func test_tamperedBox_doesNotOpen() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))
        let bobSide = try ConversationCipher(identity: bob, peer: peer(alice))

        let sealed = try aliceSide.seal(payload("целое"), from: alice.fingerprint, to: bob.fingerprint)
        var box = sealed.box
        box[box.count / 2] ^= 0xFF
        let tampered = SealedPayload(version: sealed.version, box: box)

        XCTAssertThrowsError(try bobSide.open(tampered, as: MessagePayload.self,
                                              from: alice.fingerprint, to: bob.fingerprint))
    }

    func test_truncatedBox_doesNotOpen() throws {
        let bobSide = try ConversationCipher(identity: bob, peer: peer(alice))
        let garbage = SealedPayload(version: 1, box: Data([1, 2, 3]))

        XCTAssertThrowsError(try bobSide.open(garbage, as: MessagePayload.self,
                                              from: alice.fingerprint, to: bob.fingerprint))
    }

    // MARK: - Направление

    /// Релей знает адреса и мог бы отправить конверт Алисы обратно ей же,
    /// выдав за ответ Боба. Направление входит в проверяемые данные.
    func test_reflectedEnvelope_doesNotOpen() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))

        let sealed = try aliceSide.seal(payload("моё"), from: alice.fingerprint, to: bob.fingerprint)

        XCTAssertThrowsError(try aliceSide.open(sealed, as: MessagePayload.self,
                                                from: bob.fingerprint, to: alice.fingerprint))
    }

    func test_envelopeWithWrongSender_doesNotOpen() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))
        let bobSide = try ConversationCipher(identity: bob, peer: peer(alice))

        let sealed = try aliceSide.seal(payload("от Алисы"), from: alice.fingerprint, to: bob.fingerprint)

        XCTAssertThrowsError(try bobSide.open(sealed, as: MessagePayload.self,
                                              from: mallory.fingerprint, to: bob.fingerprint))
    }

    // MARK: - Версия

    func test_unknownVersion_isRefusedBeforeDecrypting() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))
        let bobSide = try ConversationCipher(identity: bob, peer: peer(alice))

        let sealed = try aliceSide.seal(payload("будущее"), from: alice.fingerprint, to: bob.fingerprint)
        let fromTheFuture = SealedPayload(version: 2, box: sealed.box)

        XCTAssertThrowsError(try bobSide.open(fromTheFuture, as: MessagePayload.self,
                                              from: alice.fingerprint, to: bob.fingerprint)) { error in
            XCTAssertEqual(error as? ConversationCipherError, .unsupportedVersion(2))
        }
    }

    func test_sealedPayload_survivesTheWire() throws {
        let aliceSide = try ConversationCipher(identity: alice, peer: peer(bob))
        let bobSide = try ConversationCipher(identity: bob, peer: peer(alice))

        let sealed = try aliceSide.seal(payload("по проводу"), from: alice.fingerprint, to: bob.fingerprint)
        let restored = try JSONDecoder().decode(SealedPayload.self, from: try JSONEncoder().encode(sealed))

        let opened = try bobSide.open(restored, as: MessagePayload.self,
                                      from: alice.fingerprint, to: bob.fingerprint)
        XCTAssertEqual(opened.text, "по проводу")
    }

    // MARK: - Совместимость с Go

    /// Конверт, запечатанный тестовым собеседником из echos-relay
    /// (`cmd/peer`). Ключи там выводятся из имени, поэтому Боба можно
    /// собрать здесь заново и открыть его же ключом. Вектор печатает
    /// `go test ./cmd/peer -run TestVectorForSwift -v`.
    func test_opensBoxSealedByGoPeer() throws {
        func key(_ base64: String) -> Data { Data(base64Encoded: base64)! }

        let aliceSigning = try Curve25519.Signing.PrivateKey(rawRepresentation: key("4wLc4Q9R4163xYud2r7dDmE5PkoUUcNhyj0b+PvSsvs="))
        let aliceAgreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: key("9hZllO32unMi/JkzwEjIGSNp730ynbACHJrnf8elECc="))
        let bobSigning = try Curve25519.Signing.PrivateKey(rawRepresentation: key("OhHEgFXO8S+Ks1pHE4IzZ3I36Gt77PmLjP538NhIBXE="))
        let bobAgreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: key("2Ucn6lN44VJgZEJAKkkVw1r/A+Pa4oJHVJDUYt2ZqHw="))

        let goAlice = DeviceIdentity(privateKey: aliceSigning, agreementKey: aliceAgreement)
        let goBob = DeviceIdentity(privateKey: bobSigning, agreementKey: bobAgreement)

        XCTAssertEqual(goAlice.fingerprint, "c2d6d68fabefff2d", "Отпечаток считается одинаково")
        XCTAssertEqual(goBob.fingerprint, "09d58fd4509b6b70")

        let bobSide = try ConversationCipher(identity: goBob, peer: peer(goAlice))
        let sealed = SealedPayload(version: 1, box: key("OtacJ1+4Xh8A7CsPFYLBrmd4CWf8mt8VbSwU8quuK8MUzXAnxPspO/xY14lw3rPHMLpMp9sdevTkFwh5gU0fCGVU797UReSeKEkWj6g/TjcSfMJtIwpg2vfTjE1crrB4Yz430TxpG4asP3a1lRsZseSiae6C6Z0CI2+CzaZYHYfKIBE8poamdlE7Pj6sXKw="))

        let opened = try bobSide.open(sealed, as: MessagePayload.self,
                                      from: goAlice.fingerprint, to: goBob.fingerprint)

        XCTAssertEqual(opened.text, "из Go в Swift")
        XCTAssertEqual(opened.senderName, "Alice")
        XCTAssertEqual(opened.id, "00000000-0000-0000-0000-000000000001")
    }
}
