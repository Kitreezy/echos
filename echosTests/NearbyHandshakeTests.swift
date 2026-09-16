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

    // MARK: - Честный собеседник

    func test_signedAnswer_givesTheAddress() throws {
        let bob = DeviceIdentity()
        let hello = try NearbyHandshake.answer(to: nonce, as: bob)

        let address = NearbyHandshake.verify(hello: hello,
                                             nonce: nonce,
                                             advertised: bob.publicKey)

        XCTAssertEqual(address, bob.fingerprint)
    }

    /// Подключились к нам первыми — объявления мы не видели, сверять не с чем.
    /// Подписи при этом достаточно: ключ и есть личность.
    func test_withoutAdvertisedKey_signatureIsEnough() throws {
        let bob = DeviceIdentity()
        let hello = try NearbyHandshake.answer(to: nonce, as: bob)

        XCTAssertEqual(NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil),
                       bob.fingerprint)
    }

    // MARK: - Самозванцы

    func test_answerToAnotherChallenge_isRejected() throws {
        let bob = DeviceIdentity()
        let hello = try NearbyHandshake.answer(to: Data("чужой вызов".utf8), as: bob)

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
        let hello = try NearbyHandshake.answer(to: nonce, as: carol)

        XCTAssertNil(NearbyHandshake.verify(hello: hello,
                                            nonce: nonce,
                                            advertised: bob.publicKey))
    }

    func test_forgedSignature_isRejected() throws {
        let bob = DeviceIdentity()

        let forged = HelloPayload(publicKey: bob.publicKey,
                                  signature: Data(repeating: 0, count: 64))

        XCTAssertNil(NearbyHandshake.verify(hello: forged,
                                            nonce: nonce,
                                            advertised: bob.publicKey))
    }

    func test_garbageInsteadOfKey_isRejected() throws {
        let hello = HelloPayload(publicKey: Data("не ключ".utf8),
                                 signature: Data(repeating: 0, count: 64))

        XCTAssertNil(NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil))
    }

    // MARK: - Вызов

    func test_nonce_isDifferentEveryTime() {
        XCTAssertNotEqual(NearbyHandshake.newNonce(), NearbyHandshake.newNonce(),
                          "Повторяющийся вызов позволил бы переиспользовать подпись")
    }

    // MARK: - Один адрес на оба транспорта

    /// Ради этого всё и затевалось: отпечаток у человека один, независимо от
    /// того, идёт связь рядом или через сервер.
    func test_address_isTheSameAsOnTheRelay() throws {
        let bob = DeviceIdentity()
        let hello = try NearbyHandshake.answer(to: nonce, as: bob)

        let nearby = NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil)

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
        let hello = try NearbyHandshake.answer(to: nonce, as: bob)

        let data = try JSONEncoder().encode(try MultipeerPacket(hello: hello))
        let restored = try JSONDecoder().decode(MultipeerPacket.self, from: data)

        XCTAssertEqual(restored.type, .hello)
        XCTAssertEqual(NearbyHandshake.verify(hello: try restored.decodeHello(),
                                              nonce: nonce,
                                              advertised: bob.publicKey),
                       bob.fingerprint)
    }
}
