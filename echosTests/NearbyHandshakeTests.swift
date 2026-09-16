//
//  NearbyHandshakeTests.swift
//  echosTests
//
//  Подтверждение личности у тех, кто рядом.
//

import CryptoKit
import XCTest
@testable import echos

final class NearbyHandshakeTests: XCTestCase {

    private let nonce = Data("случайная строка от нас".utf8)

    /// Честный ответ Боба на наш вызов, с его сессионным ключом.
    private func answer(as identity: DeviceIdentity, to nonce: Data? = nil) throws -> (HelloPayload, SessionKey) {
        let session = try SessionKey(signedBy: identity)
        return (try NearbyHandshake.answer(to: nonce ?? self.nonce, as: identity, session: session), session)
    }

    // MARK: - Честный собеседник

    func test_signedAnswer_givesTheAddress() throws {
        let bob = DeviceIdentity()
        let (hello, session) = try answer(as: bob)

        let peer = NearbyHandshake.verify(hello: hello,
                                          nonce: nonce,
                                          advertised: bob.publicKey)

        XCTAssertEqual(peer?.fingerprint, bob.fingerprint)
        XCTAssertEqual(peer?.agreementKey, bob.agreementKey,
                       "Вместе с адресом приходит ключ, которым его шифровать")
        XCTAssertEqual(peer?.sessionKey, session.publicKey,
                       "И сессионный — для этой сессии")
    }

    /// Подключились к нам первыми — объявления мы не видели, сверять не с чем.
    /// Подписи при этом достаточно: ключ и есть личность.
    func test_withoutAdvertisedKey_signatureIsEnough() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob)

        XCTAssertEqual(NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil)?.fingerprint,
                       bob.fingerprint)
    }

    // MARK: - Самозванцы

    func test_answerToAnotherChallenge_isRejected() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob, to: Data("чужой вызов".utf8))

        XCTAssertNil(NearbyHandshake.verify(hello: hello,
                                            nonce: nonce,
                                            advertised: bob.publicKey))
    }

    /// Самое важное: в объявлении один ключ, в ответе другой. Так выглядела бы
    /// попытка показаться в списке одним человеком, а в переписке оказаться
    /// другим.
    func test_keyDifferentFromTheAdvertisedOne_isRejected() throws {
        let bob = DeviceIdentity()
        let carol = DeviceIdentity()
        let (hello, _) = try answer(as: carol)

        XCTAssertNil(NearbyHandshake.verify(hello: hello,
                                            nonce: nonce,
                                            advertised: bob.publicKey))
    }

    func test_forgedSignature_isRejected() throws {
        let bob = DeviceIdentity()
        let (honest, _) = try answer(as: bob)

        let forged = HelloPayload(publicKey: bob.publicKey,
                                  signature: Data(repeating: 0, count: 64),
                                  agreementKey: honest.agreementKey,
                                  agreementProof: honest.agreementProof,
                                  sessionKey: honest.sessionKey,
                                  sessionProof: honest.sessionProof)

        XCTAssertNil(NearbyHandshake.verify(hello: forged,
                                            nonce: nonce,
                                            advertised: bob.publicKey))
    }

    func test_garbageInsteadOfKey_isRejected() throws {
        let hello = HelloPayload(publicKey: Data("не ключ".utf8),
                                 signature: Data(repeating: 0, count: 64),
                                 agreementKey: Data("тоже не ключ".utf8),
                                 agreementProof: Data(repeating: 0, count: 64),
                                 sessionKey: Data("и это".utf8),
                                 sessionProof: Data(repeating: 0, count: 64))

        XCTAssertNil(NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil))
    }

    // MARK: - Ключ соглашения

    /// Подпись под вызовом честная, а ключ соглашения подменён. Именно так
    /// выглядел бы посредник, который хочет читать переписку.
    func test_swappedAgreementKey_isRejected() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let (honest, _) = try answer(as: bob)

        let swapped = honest.replacing(agreementKey: mallory.agreementKey)

        XCTAssertNil(NearbyHandshake.verify(hello: swapped, nonce: nonce, advertised: bob.publicKey))
    }

    /// Ключ соглашения чужой и подпись под ним чужая — но подпись под
    /// вызовом всё ещё от Боба. Привязка должна быть к его ключу.
    func test_agreementKeyProvenByAnotherIdentity_isRejected() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let (honest, _) = try answer(as: bob)
        let malloryBundle = try mallory.keyBundle(session: try SessionKey(signedBy: mallory))

        let hijacked = honest.replacing(agreementKey: malloryBundle.agreementKey,
                                        agreementProof: malloryBundle.agreementProof)

        XCTAssertNil(NearbyHandshake.verify(hello: hijacked, nonce: nonce, advertised: bob.publicKey))
    }

    /// Подпись под вызовом — это подпись под 32 случайными байтами, и
    /// ключ соглашения тоже 32 байта. Подпись под вызовом не должна
    /// годиться как доказательство привязки ключа.
    func test_challengeSignature_doesNotProveAnAgreementKey() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()

        // Мэллори выдала Бобу «вызов», равный её ключу соглашения, и
        // получила под ним честную подпись.
        let (trick, _) = try answer(as: bob, to: mallory.agreementKey)
        let (honest, _) = try answer(as: bob)

        let forged = honest.replacing(agreementKey: mallory.agreementKey,
                                      agreementProof: trick.signature)

        XCTAssertNil(NearbyHandshake.verify(hello: forged, nonce: nonce, advertised: bob.publicKey))
    }

    // MARK: - Сессионный ключ

    /// Тот же посредник, но подменяет сессионный ключ: подпись под ним
    /// должна быть от Боба, а не от кого угодно.
    func test_swappedSessionKey_isRejected() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let (honest, _) = try answer(as: bob)
        let mallorySession = try SessionKey(signedBy: mallory)

        XCTAssertNil(NearbyHandshake.verify(hello: honest.replacing(sessionKey: mallorySession.publicKey),
                                            nonce: nonce, advertised: bob.publicKey),
                     "Чужой ключ под подписью Боба")
        XCTAssertNil(NearbyHandshake.verify(hello: honest.replacing(sessionKey: mallorySession.publicKey,
                                                                    sessionProof: mallorySession.proof),
                                            nonce: nonce, advertised: bob.publicKey),
                     "Чужой ключ под чужой подписью")
    }

    /// Подпись под статическим ключом не годится как подпись под сессионным,
    /// хотя оба — 32 байта X25519: префиксы разные.
    func test_agreementProof_doesNotProveASessionKey() throws {
        let bob = DeviceIdentity()
        let (honest, _) = try answer(as: bob)

        let confused = honest.replacing(sessionKey: honest.agreementKey,
                                        sessionProof: honest.agreementProof)

        XCTAssertNil(NearbyHandshake.verify(hello: confused, nonce: nonce, advertised: bob.publicKey))
    }

    func test_eachSession_bringsAFreshKey() throws {
        let bob = DeviceIdentity()
        let (first, _) = try answer(as: bob)
        let (second, _) = try answer(as: bob)

        XCTAssertNotEqual(first.sessionKey, second.sessionKey)
        XCTAssertEqual(first.agreementKey, second.agreementKey, "Статический при этом тот же")
        XCTAssertEqual(first.publicKey, second.publicKey, "И личность та же")
    }

    // MARK: - Вызов

    func test_nonce_isDifferentEveryTime() {
        XCTAssertNotEqual(NearbyHandshake.newNonce(), NearbyHandshake.newNonce(),
                          "Одна и та же строка — одна и та же подпись, и её можно переиспользовать")
        XCTAssertEqual(NearbyHandshake.newNonce().count, NearbyHandshake.nonceSize)
    }

    /// Ради этого всё и затевалось: отпечаток у человека один, независимо от
    /// того, идёт связь рядом или через сервер.
    func test_address_isTheSameAsOnTheRelay() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob)

        let nearby = NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil)?.fingerprint

        XCTAssertEqual(nearby, DeviceIdentity.fingerprint(of: bob.publicKey))
        XCTAssertEqual(nearby, bob.fingerprint)
    }

    // MARK: - Пакеты

    func test_challengePacket_survivesTheWire() throws {
        let sent = NearbyHandshake.newNonce()
        let data = try JSONEncoder().encode(MultipeerPacket(challenge: sent))
        let restored = try JSONDecoder().decode(MultipeerPacket.self, from: data)

        XCTAssertEqual(restored.type, .challenge)
        XCTAssertEqual(restored.decodeChallenge(), sent)
    }

    func test_helloPacket_survivesTheWire() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob)

        let data = try JSONEncoder().encode(try MultipeerPacket(hello: hello))
        let restored = try JSONDecoder().decode(MultipeerPacket.self, from: data)

        XCTAssertEqual(restored.type, .hello)
        XCTAssertEqual(NearbyHandshake.verify(hello: try restored.decodeHello(),
                                              nonce: nonce,
                                              advertised: bob.publicKey)?.fingerprint,
                       bob.fingerprint)
    }
}
