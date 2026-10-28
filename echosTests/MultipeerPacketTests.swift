//
//  MultipeerPacketTests.swift
//  echosTests
//
//  Unit: сериализация пакетов. Без I/O, без Core Data — микросекунды.
//

import Foundation
import Testing
@testable import echos

struct MultipeerPacketTests {

    // MARK: - Round-trip

    /// Сообщение в пакете лежит запечатанным: пакет переносит его как есть.
    @Test func messagePacket_roundTrip_preservesSealedPayload() throws {
        let sealed = SealedPayload(version: 1, box: Data([1, 2, 3, 4]))

        let packet = try MultipeerPacket(message: sealed)
        // Пакет уходит по сети как Data — воспроизводим полный цикл.
        let wire = try JSONEncoder().encode(packet)
        let received = try JSONDecoder().decode(MultipeerPacket.self, from: wire)

        #expect(received.type == .message)
        #expect(try received.decodeMessage() == sealed)
    }

    @Test func typingPacket_roundTrip_preservesEvent() throws {
        let event = TypingEvent(type: .start, peerName: "Bob")

        let packet = try MultipeerPacket(typingEvent: event)
        let wire = try JSONEncoder().encode(packet)
        let received = try JSONDecoder().decode(MultipeerPacket.self, from: wire)

        #expect(received.type == .typing)

        let decoded = try received.decodeTypingEvent()
        #expect(decoded.type == .start)
        #expect(decoded.peerName == "Bob")
    }

    // MARK: - Несовпадение типа

    /// Тип пакета — единственное, что отличает сообщение от typing-события.
    /// Проверяем, что при неверной трактовке декодер честно падает,
    /// а не возвращает мусор.
    @Test func decodingTypingPacketAsMessage_throws() throws {
        let packet = try MultipeerPacket(typingEvent: TypingEvent(type: .stop, peerName: "Bob"))

        #expect(throws: (any Error).self) { try packet.decodeMessage() }
    }

    @Test func decodingMessagePacketAsTyping_throws() throws {
        let packet = try MultipeerPacket(message: SealedPayload(version: 1, box: Data([1])))

        #expect(throws: (any Error).self) { try packet.decodeTypingEvent() }
    }
}
