//
//  ParserFuzzTests.swift
//  echosTests
//
//  Разбор того, что приходит снаружи, на тысячах испорченных входов.
//
//  Снаружи — от релея, от устройства рядом, из шифрованного конверта —
//  может прийти что угодно, и приложение не вправе на этом падать или
//  задумываться. Каждый тест здесь прогоняет функцию разбора на
//  сгенерированных входах и проверяет три вещи: процесс жив, один вход
//  разбирается быстро, а то, что разобралось, соблюдает инварианты модели.
//
//  Как воспроизвести находку — в Fuzzer.swift.
//

import CryptoKit
import Foundation
import Testing
@testable import echos

// Друг за другом, а не параллельно: семь тестов, нагружающих процессор
// разом, отнимали время у соседних тестов на таймерах — debounce и повторы
// подключения падали, не дождавшись своего часа.
@Suite(.tags(.fuzz), .serialized)
struct ParserFuzzTests {

    // MARK: - Образцы

    private static let alice = DeviceIdentity()
    private static let bob = DeviceIdentity()

    private struct Pair {
        let aliceSide: ConversationCipher
        let bobSide: ConversationCipher
    }

    private static func pair() throws -> Pair {
        let aliceSession = try SessionKey(signedBy: alice)
        let bobSession = try SessionKey(signedBy: bob)
        let aliceAsPeer = try #require(try alice.keyBundle(session: aliceSession).verified())
        let bobAsPeer = try #require(try bob.keyBundle(session: bobSession).verified())
        return Pair(aliceSide: try ConversationCipher(identity: alice, session: aliceSession, peer: bobAsPeer),
                    bobSide: try ConversationCipher(identity: bob, session: bobSession, peer: aliceAsPeer))
    }

    private static let mosaic = Mosaic(columns: 3, rows: 2, cells: ["🟥", "", "🟦", "", "👨‍👩‍👧‍👦", ""])!

    private static func payloads() -> [MessagePayload] {
        let plain = Message(text: "привет", isFromMe: true)
        let drawing = Message(text: mosaic.text, mosaic: mosaic, isFromMe: true)
        let reply = Message(text: "да", isFromMe: true,
                            replyTo: MessageReply(id: UUID(), preview: "пойдёшь?", isFromMe: false))
        return [plain, drawing, reply].map { MessagePayload(from: $0, senderName: "Alice") }
    }

    private static let stroke = Stroke(author: "a", points: [.init(x: 0.1, y: 0.2), .init(x: 0.5, y: 0.9)])

    private static func encoded<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    // MARK: - Конверт релея

    /// Всё, что транспорт делает с кадром от релея до расшифровки.
    @Test func relayEnvelope_neverCrashesOrHangs() throws {
        let pair = try Self.pair()
        let session = try SessionKey(signedBy: Self.alice)
        let keys = try Self.alice.keyBundle(session: session)
        let sealed = try pair.aliceSide.seal(Self.payloads()[0], kind: .message,
                                             from: Self.alice.fingerprint, to: Self.bob.fingerprint)
        let samples = try [
            RelayEnvelope.message(sealed, from: "Alice", to: Self.bob.fingerprint),
            RelayEnvelope.stroke(sealed, from: "Alice", to: Self.bob.fingerprint),
            RelayEnvelope.wallState(sealed, from: Self.alice.fingerprint, to: Self.bob.fingerprint),
            RelayEnvelope.wallRequest(from: Self.alice.fingerprint, to: Self.bob.fingerprint),
            RelayEnvelope.typing(TypingEvent(type: .start, peerName: "Alice"), from: "Alice", to: Self.bob.fingerprint),
            RelayEnvelope.hello(from: "Alice", answering: Data(repeating: 7, count: 32), as: Self.alice, session: session),
            RelayEnvelope.presence([RelayParticipant(id: Self.alice.fingerprint, name: "Alice", keys: keys)])
        ].map { try $0.encoded() } + [
            // Вызов шлёт только сервер, конструктора у клиента для него нет.
            Data(#"{"kind":"challenge","sender":"","payload":"AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="}"#.utf8)
        ]

        let report = Fuzz.run("relayEnvelope", generate: { Fuzz.input(from: samples, using: &$0) }, body: { data in
            guard let envelope = try? RelayEnvelope.decode(from: data) else {
                return
            }
            switch envelope.kind {
            case .presence:
                for participant in (try? envelope.decodePresence()) ?? [] {
                    // Чужой ключ с чужим адресом не должен проходить проверку.
                    if let identity = participant.verifiedIdentity {
                        #expect(identity.fingerprint == participant.id)
                    }
                }
            case .message, .stroke, .wallState:
                if let sealed = try? envelope.decodeMessage() {
                    _ = try? pair.bobSide.open(sealed, as: MessagePayload.self, kind: .message,
                                               from: Self.alice.fingerprint, to: Self.bob.fingerprint)
                }
            case .typing:
                _ = try? envelope.decodeTyping()
            case .challenge:
                _ = try? envelope.decodeChallenge()
            case .hello, .wallRequest:
                break
            }
        })
        #expect(report.slowest < Fuzz.slowInput, "Медленный вход, \(report.slowest): \(report.slowestInput.prefix(200))")
    }

    // MARK: - Шифрованный конверт

    /// Испорченный конверт либо не открывается, либо открывается ровно в
    /// то, что запечатали: AES-GCM не даёт получить третье.
    @Test(.tags(.crypto)) func sealedPayload_opensIntoOriginalOrNothing() throws {
        let pair = try Self.pair()
        let original = Self.payloads()[1]
        let sealed = try pair.aliceSide.seal(original, kind: .message,
                                             from: Self.alice.fingerprint, to: Self.bob.fingerprint)
        let samples = [Self.encoded(sealed)]

        var opened = 0
        let report = Fuzz.run("sealedPayload", generate: { Fuzz.input(from: samples, using: &$0) }, body: { data in
            guard let candidate = try? JSONDecoder().decode(SealedPayload.self, from: data),
                  let payload = try? pair.bobSide.open(candidate, as: MessagePayload.self, kind: .message,
                                                       from: Self.alice.fingerprint, to: Self.bob.fingerprint) else {
                return
            }
            opened += 1
            #expect(candidate.box == sealed.box, "Открылся изменённый шифртекст")
            #expect(payload.id == original.id && payload.text == original.text)
        })
        #expect(report.slowest < Fuzz.slowInput)
        print("[fuzz] sealedPayload: открылось \(opened) — все без изменений в шифртексте")
    }

    // MARK: - Сообщение и мозаика

    /// Расшифрованное сообщение — уже наше, но писал его не я. Мозаика из
    /// него — та, что ляжет на экран.
    @Test func messagePayload_keepsMosaicInvariants() async {
        let samples = Self.payloads().map(Self.encoded)

        var mosaics: [Mosaic] = []
        let report = Fuzz.run("messagePayload", generate: { Fuzz.input(from: samples, using: &$0) }, body: { data in
            guard let payload = try? JSONDecoder().decode(MessagePayload.self, from: data) else {
                return
            }
            let message = payload.toMessage(from: "bob")
            guard let mosaic = message.mosaic else {
                return
            }
            mosaics.append(mosaic)
            #expect(mosaic.isValid)
            #expect(Mosaic.sideRange.contains(mosaic.columns) && Mosaic.sideRange.contains(mosaic.rows))
            #expect(mosaic.cells.count == mosaic.columns * mosaic.rows)
            #expect(mosaic.cells.allSatisfy { $0.unicodeScalars.count <= Mosaic.maxScalarsPerCell },
                    "Клетка-«один знак» из тысяч кодовых точек")
            _ = mosaic.text
        })
        #expect(report.slowest < Fuzz.slowInput, "Медленный вход, \(report.slowest): \(report.slowestInput.prefix(200))")
        await Self.render(mosaics)
        print("[fuzz] messagePayload: мозаик разобрано \(mosaics.count)")
    }

    /// Случайная порча до клеток почти не доходит: сетка правильного
    /// размера после неё — редкость. Здесь входы строятся по форме мозаики:
    /// размеры у границ и за ними, клетки — из того, что ломает «один знак».
    @Test func mosaic_fromWire_keepsInvariants() async {
        var valid: [Mosaic] = []
        let cells = ["", "🟥", "👨🏻‍👩🏻‍👧🏻‍👦🏻", "🇷🇺", "1️⃣", "ab", "🟥🟦",
                     "a" + String(repeating: "\u{0301}", count: 5_000),
                     "🟥" + String(repeating: "\u{FE0F}", count: 1_000),
                     String(repeating: "\u{200D}", count: 50)]
        let sides = [-1, 0, 1, 2, 8, 9, Int.max]

        let report = Fuzz.run("mosaic", generate: { generator in
            let columns = sides.randomElement(using: &generator)!
            let rows = sides.randomElement(using: &generator)!
            let expected = (1...8).contains(columns) && (1...8).contains(rows) ? columns * rows : 4
            let count = Bool.random(using: &generator) ? expected : Int.random(in: 0...70, using: &generator)
            let grid: [String: Any] = [
                "columns": columns, "rows": rows,
                "cells": (0..<count).map { _ in cells.randomElement(using: &generator)! }
            ]
            return (try? JSONSerialization.data(withJSONObject: grid)) ?? Data()
        }, body: { data in
            guard let mosaic = try? JSONDecoder().decode(Mosaic.self, from: data), mosaic.isValid else {
                return
            }
            #expect(mosaic.cells.allSatisfy { $0.unicodeScalars.count <= Mosaic.maxScalarsPerCell },
                    "Клетка-«один знак» из тысяч кодовых точек")
            valid.append(mosaic)
            _ = mosaic.text
        })
        #expect(report.slowest < Fuzz.slowInput, "Медленный вход, \(report.slowest)")
        await Self.render(valid)
    }

    /// Отрисовать разобранные мозаики, как их увидит человек. На главном
    /// акторе — но по одной и не больше двадцати: долгий захват главного
    /// актора задерживает таймеры в соседних тестах, и те падают.
    private static func render(_ mosaics: [Mosaic]) async {
        let clock = ContinuousClock()
        for mosaic in mosaics.prefix(20) {
            let elapsed = await MainActor.run {
                clock.measure { _ = MosaicImageRenderer.render(mosaic) }
            }
            #expect(elapsed < Fuzz.slowInput, "Мозаика рисуется \(elapsed): \(mosaic.cells)")
        }
    }

    // MARK: - Росчерки

    @Test func strokes_decodeWithoutSurprises() {
        let samples = [Self.encoded(Self.stroke), Self.encoded([Self.stroke, Self.stroke])]

        let report = Fuzz.run("strokes", generate: { Fuzz.input(from: samples, using: &$0) }, body: { data in
            let strokes = (try? JSONDecoder().decode([Stroke].self, from: data))
                ?? (try? JSONDecoder().decode(Stroke.self, from: data)).map { [$0] } ?? []
            for stroke in strokes {
                for point in stroke.points {
                    let drawn = point.cgPoint(in: CGSize(width: 390, height: 600))
                    #expect(drawn.x.isFinite && drawn.y.isFinite)
                }
            }
        })
        #expect(report.slowest < Fuzz.slowInput)
    }

    // MARK: - Пакет Multipeer

    @Test func multipeerPacket_neverCrashesOrHangs() throws {
        let pair = try Self.pair()
        let session = try SessionKey(signedBy: Self.alice)
        let sealed = try pair.aliceSide.seal(Self.payloads()[0], kind: .message,
                                             from: Self.alice.fingerprint, to: Self.bob.fingerprint)
        let hello = try HelloPayload(answering: Data(repeating: 3, count: 32), as: Self.alice, session: session)
        let samples = try [
            MultipeerPacket(message: sealed),
            MultipeerPacket(typingEvent: TypingEvent(type: .stop, peerName: "Alice")),
            MultipeerPacket(stroke: sealed),
            MultipeerPacket(hello: hello),
            MultipeerPacket(challenge: Data(repeating: 9, count: 32))
        ].map(Self.encoded)

        let report = Fuzz.run("multipeerPacket", generate: { Fuzz.input(from: samples, using: &$0) }, body: { data in
            guard let packet = try? JSONDecoder().decode(MultipeerPacket.self, from: data) else {
                return
            }
            _ = try? packet.decodeMessage()
            _ = try? packet.decodeTypingEvent()
            _ = try? packet.decodeWallState()
            _ = packet.decodeChallenge()
            if let hello = try? packet.decodeHello() {
                let bundle = KeyBundle(publicKey: hello.publicKey, agreementKey: hello.agreementKey,
                                       agreementProof: hello.agreementProof, sessionKey: hello.sessionKey,
                                       sessionProof: hello.sessionProof)
                _ = bundle.verified()
            }
        })
        #expect(report.slowest < Fuzz.slowInput)
    }

    // MARK: - Строки

    /// Адрес приходит от собеседника как есть — и показывается на экране.
    @Test func addresses_neverCrash() {
        let samples = [Data(Self.alice.fingerprint.utf8), Data("iPhone: Боб".utf8), Data("93f440ee4f07d563".utf8)]

        let report = Fuzz.run("addresses", generate: { Fuzz.input(from: samples, using: &$0) }, body: { data in
            let address = String(bytes: data, encoding: .utf8) ?? ""
            _ = Fingerprint.display(address)
            _ = DeviceIdentity.fingerprint(of: data)
        })
        #expect(report.slowest < Fuzz.slowInput)
    }

    // MARK: - Вложенность

    /// Глубоко вложенный JSON — классический способ уронить разбор
    /// переполнением стека. Декодер должен отказаться, а не упасть.
    @Test(arguments: [1_000, 100_000])
    func deepNesting_isRejected(_ depth: Int) {
        let data = Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
        #expect((try? RelayEnvelope.decode(from: data)) == nil)
        #expect((try? JSONDecoder().decode(MessagePayload.self, from: data)) == nil)
    }
}
