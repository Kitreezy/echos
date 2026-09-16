//
//  ConversationCipherTests.swift
//  echosTests
//
//  Шифр переписки: обе стороны выводят один ключ, чужой не открывает,
//  подмена и перестановка конверта не проходят, а прошлая сессия закрыта
//  даже для тех, у кого есть долгие ключи.
//

import CryptoKit
import XCTest
@testable import echos

final class ConversationCipherTests: XCTestCase {

    private let alice = DeviceIdentity()
    private let bob = DeviceIdentity()
    private let mallory = DeviceIdentity()

    /// Одна сессия между двумя: у каждого свой сессионный ключ и свой
    /// шифр, выведенный из ключей другого.
    private struct Session {
        let aliceSide: ConversationCipher
        let bobSide: ConversationCipher
    }

    private func session(_ a: DeviceIdentity, _ b: DeviceIdentity) throws -> Session {
        let aSession = try SessionKey(signedBy: a)
        let bSession = try SessionKey(signedBy: b)
        let aAsPeer = try XCTUnwrap(try a.keyBundle(session: aSession).verified())
        let bAsPeer = try XCTUnwrap(try b.keyBundle(session: bSession).verified())

        return Session(aliceSide: try ConversationCipher(identity: a, session: aSession, peer: bAsPeer),
                       bobSide: try ConversationCipher(identity: b, session: bSession, peer: aAsPeer))
    }

    private func payload(_ text: String) -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: true), senderName: "Alice")
    }

    private func sealed(_ text: String, by cipher: ConversationCipher) throws -> SealedPayload {
        try cipher.seal(payload(text), kind: .message, from: alice.fingerprint, to: bob.fingerprint)
    }

    private func open(_ sealed: SealedPayload, with cipher: ConversationCipher) throws -> MessagePayload {
        try cipher.open(sealed, as: MessagePayload.self, kind: .message, from: alice.fingerprint, to: bob.fingerprint)
    }

    // MARK: - Честная пара

    func test_bothSides_deriveTheSameKey() throws {
        let s = try session(alice, bob)

        let opened = try open(try sealed("привет", by: s.aliceSide), with: s.bobSide)

        XCTAssertEqual(opened.text, "привет")
    }

    func test_sealedText_isNotVisibleOnTheWire() throws {
        let s = try session(alice, bob)
        let box = try sealed("секрет", by: s.aliceSide)

        let wire = try JSONEncoder().encode(box)
        XCTAssertFalse(String(decoding: wire, as: UTF8.self).contains("секрет"))
        XCTAssertNil(box.box.range(of: Data("секрет".utf8)))
    }

    func test_sameMessageTwice_looksDifferentOnTheWire() throws {
        let s = try session(alice, bob)

        XCTAssertNotEqual(try sealed("одно и то же", by: s.aliceSide),
                          try sealed("одно и то же", by: s.aliceSide),
                          "nonce должен быть свежим на каждое сообщение")
    }

    /// Порядок адресов не важен: Боб, считающий ключ с Алисой, и Алиса,
    /// считающая ключ с Бобом, должны сойтись, хотя отпечатки у них
    /// в разном порядке.
    func test_keyDerivation_isSymmetric() throws {
        let s = try session(alice, bob)

        let fromBob = try s.bobSide.seal(payload("ответ"), kind: .message, from: bob.fingerprint, to: alice.fingerprint)
        let opened = try s.aliceSide.open(fromBob, as: MessagePayload.self, kind: .message,
                                          from: bob.fingerprint, to: alice.fingerprint)

        XCTAssertEqual(opened.text, "ответ")
    }

    // MARK: - Сессии

    /// Ради этого всё и затевалось: новая сессия — новый ключ, и записанное
    /// в прошлой не открыть ключом нынешней.
    func test_newSession_cannotOpenThePreviousOne() throws {
        let first = try session(alice, bob)
        let second = try session(alice, bob)

        let recorded = try sealed("из прошлой сессии", by: first.aliceSide)

        XCTAssertThrowsError(try open(recorded, with: second.bobSide))
        XCTAssertEqual(try open(recorded, with: first.bobSide).text, "из прошлой сессии",
                       "А своим ключом — открывается")
    }

    /// Утечка долгих ключей. У противника — оба закрытых ключа обеих сторон,
    /// и только сессионных нет: они забыты вместе с сессией. Единственный
    /// шифр, который он может вывести, — с какими-то другими сессионными
    /// ключами, и записанное им не открывается.
    func test_leakedLongTermKeys_doNotOpenAPastSession() throws {
        let past = try session(alice, bob)
        let recorded = try sealed("что было", by: past.aliceSide)

        // Противник знает alice и bob целиком, но сессионные ключи прошлой
        // сессии ему взять неоткуда: заводит свои.
        let attacker = try session(alice, bob)

        XCTAssertThrowsError(try open(recorded, with: attacker.bobSide))
        XCTAssertThrowsError(try open(recorded, with: attacker.aliceSide))
    }

    /// Посредник с утёкшим подписывающим ключом Алисы, но без её ключа
    /// соглашения. Сессионные ключи он подпишет сам, и подписи сойдутся —
    /// но без статического секрета ключ переписки не выведется.
    func test_staticKey_isPartOfTheDerivation() throws {
        let aliceSigning = Curve25519.Signing.PrivateKey()
        let realAlice = DeviceIdentity(privateKey: aliceSigning,
                                       agreementKey: Curve25519.KeyAgreement.PrivateKey())
        let impostor = DeviceIdentity(privateKey: aliceSigning,
                                      agreementKey: Curve25519.KeyAgreement.PrivateKey())

        // Один и тот же сессионный ключ у обеих «Алис»: важно показать, что
        // одного его недостаточно.
        let sessionPrivate = Curve25519.KeyAgreement.PrivateKey()
        let realSession = try SessionKey(privateKey: sessionPrivate, signedBy: realAlice)
        let impostorSession = try SessionKey(privateKey: sessionPrivate, signedBy: impostor)

        let bobSession = try SessionKey(signedBy: bob)
        let bobAsPeer = try XCTUnwrap(try bob.keyBundle(session: bobSession).verified())
        let realAliceAsPeer = try XCTUnwrap(try realAlice.keyBundle(session: realSession).verified())

        let honestBob = try ConversationCipher(identity: bob, session: bobSession, peer: realAliceAsPeer)
        let impostorSide = try ConversationCipher(identity: impostor, session: impostorSession, peer: bobAsPeer)

        let forged = try impostorSide.seal(payload("я Алиса"), kind: .message, from: realAlice.fingerprint, to: bob.fingerprint)
        XCTAssertThrowsError(try honestBob.open(forged, as: MessagePayload.self, kind: .message,
                                                from: realAlice.fingerprint, to: bob.fingerprint))
    }

    // MARK: - Чужие

    func test_thirdParty_cannotOpen() throws {
        let s = try session(alice, bob)
        let malloryWithBob = try session(mallory, bob)
        let malloryWithAlice = try session(mallory, alice)

        let box = try sealed("не для тебя", by: s.aliceSide)

        XCTAssertThrowsError(try open(box, with: malloryWithBob.bobSide))
        XCTAssertThrowsError(try open(box, with: malloryWithAlice.bobSide))
    }

    func test_tamperedBox_doesNotOpen() throws {
        let s = try session(alice, bob)

        let box = try sealed("целое", by: s.aliceSide)
        var bytes = box.box
        bytes[bytes.count / 2] ^= 0xFF

        XCTAssertThrowsError(try open(SealedPayload(version: box.version, box: bytes), with: s.bobSide))
    }

    func test_truncatedBox_doesNotOpen() throws {
        let s = try session(alice, bob)
        let garbage = SealedPayload(version: SealedPayload.currentVersion, box: Data([1, 2, 3]))

        XCTAssertThrowsError(try open(garbage, with: s.bobSide))
    }

    // MARK: - Направление

    /// Релей знает адреса и мог бы отправить конверт Алисы обратно ей же,
    /// выдав за ответ Боба. Направление входит в проверяемые данные.
    func test_reflectedEnvelope_doesNotOpen() throws {
        let s = try session(alice, bob)
        let box = try sealed("моё", by: s.aliceSide)

        XCTAssertThrowsError(try s.aliceSide.open(box, as: MessagePayload.self, kind: .message,
                                                  from: bob.fingerprint, to: alice.fingerprint))
    }

    func test_envelopeWithWrongSender_doesNotOpen() throws {
        let s = try session(alice, bob)
        let box = try sealed("от Алисы", by: s.aliceSide)

        XCTAssertThrowsError(try s.bobSide.open(box, as: MessagePayload.self, kind: .message,
                                                from: mallory.fingerprint, to: bob.fingerprint))
    }

    // MARK: - Род содержимого

    /// Росчерк, выданный за сообщение: тот же ключ, то же направление, но
    /// род входит в проверяемые данные — не откроется.
    func test_strokeSealedAsStroke_doesNotOpenAsMessage() throws {
        let s = try session(alice, bob)
        let stroke = Stroke(author: alice.fingerprint, points: [])

        let box = try s.aliceSide.seal(stroke, kind: .stroke, from: alice.fingerprint, to: bob.fingerprint)

        XCTAssertThrowsError(try s.bobSide.open(box, as: MessagePayload.self, kind: .message,
                                                from: alice.fingerprint, to: bob.fingerprint))
        XCTAssertThrowsError(try s.bobSide.open(box, as: Stroke.self, kind: .wall,
                                                from: alice.fingerprint, to: bob.fingerprint))
        XCTAssertNoThrow(try s.bobSide.open(box, as: Stroke.self, kind: .stroke,
                                            from: alice.fingerprint, to: bob.fingerprint))
    }

    func test_wholeWall_sealsAndOpens() throws {
        let s = try session(alice, bob)
        let wall = [Stroke(author: bob.fingerprint, points: []),
                    Stroke(author: alice.fingerprint, points: [])]

        let box = try s.aliceSide.seal(wall, kind: .wall, from: alice.fingerprint, to: bob.fingerprint)
        let opened = try s.bobSide.open(box, as: [Stroke].self, kind: .wall,
                                        from: alice.fingerprint, to: bob.fingerprint)

        XCTAssertEqual(opened.map(\.author), wall.map(\.author))
    }

    // MARK: - Версия

    func test_unknownVersion_isRefusedBeforeDecrypting() throws {
        let s = try session(alice, bob)
        let box = try sealed("будущее", by: s.aliceSide)
        let fromTheFuture = SealedPayload(version: 99, box: box.box)

        XCTAssertThrowsError(try open(fromTheFuture, with: s.bobSide)) { error in
            XCTAssertEqual(error as? ConversationCipherError, .unsupportedVersion(99))
        }
    }

    /// Первая версия — без сессионного ключа. Сборка с ней в список и так
    /// не попадает, а её конверт не должен открываться и случайно.
    func test_firstVersion_isRefused() throws {
        let s = try session(alice, bob)
        let box = try sealed("старое", by: s.aliceSide)

        XCTAssertThrowsError(try open(SealedPayload(version: 1, box: box.box), with: s.bobSide)) { error in
            XCTAssertEqual(error as? ConversationCipherError, .unsupportedVersion(1))
        }
    }

    func test_sealedPayload_survivesTheWire() throws {
        let s = try session(alice, bob)
        let box = try sealed("по проводу", by: s.aliceSide)
        let restored = try JSONDecoder().decode(SealedPayload.self, from: try JSONEncoder().encode(box))

        XCTAssertEqual(try open(restored, with: s.bobSide).text, "по проводу")
    }

    // MARK: - Совместимость с Go

    /// Конверт, запечатанный тестовым собеседником из echos-relay
    /// (`cmd/peer`). Ключи там выводятся из имени, поэтому Боба и его
    /// сессию можно собрать здесь заново. Вектор печатает
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

        let aliceSession = try SessionKey(privateKey: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: key("CCvXtlHdrUL5AgHL6MfphlDzXilFLXVUlj7Mr0VtKQI=")),
                                          signedBy: goAlice)
        let bobSession = try SessionKey(privateKey: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: key("0/Gfgacwu7QanSP2PJJtL6b7Ey6YPzY2XGQSCVOrhIU=")),
                                        signedBy: goBob)
        let aliceAsPeer = try XCTUnwrap(try goAlice.keyBundle(session: aliceSession).verified())

        let bobSide = try ConversationCipher(identity: goBob, session: bobSession, peer: aliceAsPeer)
        let sealed = SealedPayload(version: 2, box: key("GSjvIvQZMEdbFklrA3GRewU8IgjrS1qzQILeuzn2NgNi8BYSlG6HFOVymfzyXzdWCzrL/6TrJn8B7DomEnKYhAwJpQWzt9ocO49i9sPnZJlGjxGM0GkjhKrF+6G5Hua98r+vaKk2gGuwbCvQh+0U7ERnQQi8EUnq2otoDZHO/dO/HYau+4EH9icDHjbZdgg="))

        let opened = try bobSide.open(sealed, as: MessagePayload.self, kind: .message,
                                      from: goAlice.fingerprint, to: goBob.fingerprint)

        XCTAssertEqual(opened.text, "из Go в Swift")
        XCTAssertEqual(opened.senderName, "Alice")
        XCTAssertEqual(opened.id, "00000000-0000-0000-0000-000000000001")
    }
}
