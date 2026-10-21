//
//  NearbyHandshakeTests.swift
//  echosTests
//
//  Подтверждение личности у тех, кто рядом.
//

import CryptoKit
import Foundation
import Testing
@testable import echos

@Suite(.tags(.crypto))
struct NearbyHandshakeTests {

    private let nonce = Data("случайная строка от нас".utf8)

    /// Честный ответ Боба на наш вызов, с его сессионным ключом.
    private func answer(as identity: DeviceIdentity, to nonce: Data? = nil) throws -> (HelloPayload, SessionKey) {
        let session = try SessionKey(signedBy: identity)
        return (try NearbyHandshake.answer(to: nonce ?? self.nonce, as: identity, session: session), session)
    }

    // MARK: - Честный собеседник

    @Test func signedAnswer_givesTheAddress() throws {
        let bob = DeviceIdentity()
        let (hello, session) = try answer(as: bob)

        let peer = NearbyHandshake.verify(hello: hello,
                                          nonce: nonce,
                                          advertised: bob.publicKey)

        #expect(peer?.fingerprint == bob.fingerprint)
        #expect(peer?.agreementKey == bob.agreementKey, "Вместе с адресом приходит ключ, которым его шифровать")
        #expect(peer?.sessionKey == session.publicKey, "И сессионный — для этой сессии")
    }

    /// Подключились к нам первыми — объявления мы не видели, сверять не с чем.
    /// Подписи при этом достаточно: ключ и есть личность.
    @Test func withoutAdvertisedKey_signatureIsEnough() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob)

        #expect(NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil)?.fingerprint == bob.fingerprint)
    }

    // MARK: - Самозванцы

    @Test func answerToAnotherChallenge_isRejected() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob, to: Data("чужой вызов".utf8))

        #expect(NearbyHandshake.verify(hello: hello,
                                            nonce: nonce,
                                            advertised: bob.publicKey) == nil)
    }

    /// Самое важное: в объявлении один ключ, в ответе другой. Так выглядела бы
    /// попытка показаться в списке одним человеком, а в переписке оказаться
    /// другим.
    @Test func keyDifferentFromTheAdvertisedOne_isRejected() throws {
        let bob = DeviceIdentity()
        let carol = DeviceIdentity()
        let (hello, _) = try answer(as: carol)

        #expect(NearbyHandshake.verify(hello: hello,
                                            nonce: nonce,
                                            advertised: bob.publicKey) == nil)
    }

    @Test func forgedSignature_isRejected() throws {
        let bob = DeviceIdentity()
        let (honest, _) = try answer(as: bob)

        let forged = HelloPayload(publicKey: bob.publicKey,
                                  signature: Data(repeating: 0, count: 64),
                                  agreementKey: honest.agreementKey,
                                  agreementProof: honest.agreementProof,
                                  sessionKey: honest.sessionKey,
                                  sessionProof: honest.sessionProof)

        #expect(NearbyHandshake.verify(hello: forged,
                                            nonce: nonce,
                                            advertised: bob.publicKey) == nil)
    }

    @Test func garbageInsteadOfKey_isRejected() throws {
        let hello = HelloPayload(publicKey: Data("не ключ".utf8),
                                 signature: Data(repeating: 0, count: 64),
                                 agreementKey: Data("тоже не ключ".utf8),
                                 agreementProof: Data(repeating: 0, count: 64),
                                 sessionKey: Data("и это".utf8),
                                 sessionProof: Data(repeating: 0, count: 64))

        #expect(NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil) == nil)
    }

    // MARK: - Ключ соглашения

    /// Подпись под вызовом честная, а ключ соглашения подменён. Именно так
    /// выглядел бы посредник, который хочет читать переписку.
    @Test func swappedAgreementKey_isRejected() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let (honest, _) = try answer(as: bob)

        let swapped = honest.replacing(agreementKey: mallory.agreementKey)

        #expect(NearbyHandshake.verify(hello: swapped, nonce: nonce, advertised: bob.publicKey) == nil)
    }

    /// Ключ соглашения чужой и подпись под ним чужая — но подпись под
    /// вызовом всё ещё от Боба. Привязка должна быть к его ключу.
    @Test func agreementKeyProvenByAnotherIdentity_isRejected() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let (honest, _) = try answer(as: bob)
        let malloryBundle = try mallory.keyBundle(session: try SessionKey(signedBy: mallory))

        let hijacked = honest.replacing(agreementKey: malloryBundle.agreementKey,
                                        agreementProof: malloryBundle.agreementProof)

        #expect(NearbyHandshake.verify(hello: hijacked, nonce: nonce, advertised: bob.publicKey) == nil)
    }

    /// Подпись под вызовом — это подпись под 32 случайными байтами, и
    /// ключ соглашения тоже 32 байта. Подпись под вызовом не должна
    /// годиться как доказательство привязки ключа.
    @Test func challengeSignature_doesNotProveAnAgreementKey() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()

        // Мэллори выдала Бобу «вызов», равный её ключу соглашения, и
        // получила под ним честную подпись.
        let (trick, _) = try answer(as: bob, to: mallory.agreementKey)
        let (honest, _) = try answer(as: bob)

        let forged = honest.replacing(agreementKey: mallory.agreementKey,
                                      agreementProof: trick.signature)

        #expect(NearbyHandshake.verify(hello: forged, nonce: nonce, advertised: bob.publicKey) == nil)
    }

    // MARK: - Сессионный ключ

    /// Тот же посредник, но подменяет сессионный ключ: подпись под ним
    /// должна быть от Боба, а не от кого угодно.
    @Test func swappedSessionKey_isRejected() throws {
        let bob = DeviceIdentity()
        let mallory = DeviceIdentity()
        let (honest, _) = try answer(as: bob)
        let mallorySession = try SessionKey(signedBy: mallory)

        #expect(NearbyHandshake.verify(hello: honest.replacing(sessionKey: mallorySession.publicKey),
                                            nonce: nonce, advertised: bob.publicKey) == nil, "Чужой ключ под подписью Боба")
        #expect(NearbyHandshake.verify(hello: honest.replacing(sessionKey: mallorySession.publicKey,
                                                                    sessionProof: mallorySession.proof),
                                            nonce: nonce, advertised: bob.publicKey) == nil, "Чужой ключ под чужой подписью")
    }

    /// Подпись под статическим ключом не годится как подпись под сессионным,
    /// хотя оба — 32 байта X25519: префиксы разные.
    @Test func agreementProof_doesNotProveASessionKey() throws {
        let bob = DeviceIdentity()
        let (honest, _) = try answer(as: bob)

        let confused = honest.replacing(sessionKey: honest.agreementKey,
                                        sessionProof: honest.agreementProof)

        #expect(NearbyHandshake.verify(hello: confused, nonce: nonce, advertised: bob.publicKey) == nil)
    }

    @Test func eachSession_bringsAFreshKey() throws {
        let bob = DeviceIdentity()
        let (first, _) = try answer(as: bob)
        let (second, _) = try answer(as: bob)

        #expect(first.sessionKey != second.sessionKey)
        #expect(first.agreementKey == second.agreementKey, "Статический при этом тот же")
        #expect(first.publicKey == second.publicKey, "И личность та же")
    }

    // MARK: - Вызов

    @Test func nonce_isDifferentEveryTime() {
        #expect(NearbyHandshake.newNonce() != NearbyHandshake.newNonce(), "Одна и та же строка — одна и та же подпись, и её можно переиспользовать")
        #expect(NearbyHandshake.newNonce().count == NearbyHandshake.nonceSize)
    }

    /// Ради этого всё и затевалось: отпечаток у человека один, независимо от
    /// того, идёт связь рядом или через сервер.
    @Test func address_isTheSameAsOnTheRelay() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob)

        let nearby = NearbyHandshake.verify(hello: hello, nonce: nonce, advertised: nil)?.fingerprint

        #expect(nearby == DeviceIdentity.fingerprint(of: bob.publicKey))
        #expect(nearby == bob.fingerprint)
    }

    // MARK: - Пакеты

    @Test func challengePacket_survivesTheWire() throws {
        let sent = NearbyHandshake.newNonce()
        let data = try JSONEncoder().encode(MultipeerPacket(challenge: sent))
        let restored = try JSONDecoder().decode(MultipeerPacket.self, from: data)

        #expect(restored.type == .challenge)
        #expect(restored.decodeChallenge() == sent)
    }

    @Test func helloPacket_survivesTheWire() throws {
        let bob = DeviceIdentity()
        let (hello, _) = try answer(as: bob)

        let data = try JSONEncoder().encode(try MultipeerPacket(hello: hello))
        let restored = try JSONDecoder().decode(MultipeerPacket.self, from: data)

        #expect(restored.type == .hello)
        #expect(NearbyHandshake.verify(hello: try restored.decodeHello(),
                                              nonce: nonce,
                                              advertised: bob.publicKey)?.fingerprint == bob.fingerprint)
    }
}
