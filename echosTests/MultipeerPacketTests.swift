//
//  MultipeerPacketTests.swift
//  echosTests
//
//  Unit: сериализация пакетов. Без I/O, без Core Data — микросекунды.
//

import XCTest
@testable import echos

final class MultipeerPacketTests: XCTestCase {
    
    // MARK: - Round-trip
    
    /// Сообщение в пакете лежит запечатанным: пакет переносит его как есть.
    func test_messagePacket_roundTrip_preservesSealedPayload() throws {
        let sealed = SealedPayload(version: 1, box: Data([1, 2, 3, 4]))
        
        let packet = try MultipeerPacket(message: sealed)
        // Пакет уходит по сети как Data — воспроизводим полный цикл.
        let wire = try JSONEncoder().encode(packet)
        let received = try JSONDecoder().decode(MultipeerPacket.self, from: wire)
        
        XCTAssertEqual(received.type, .message)
        XCTAssertEqual(try received.decodeMessage(), sealed)
    }
    
    func test_typingPacket_roundTrip_preservesEvent() throws {
        let event = TypingEvent(type: .start, peerName: "Bob")
        
        let packet = try MultipeerPacket(typingEvent: event)
        let wire = try JSONEncoder().encode(packet)
        let received = try JSONDecoder().decode(MultipeerPacket.self, from: wire)
        
        XCTAssertEqual(received.type, .typing)
        
        let decoded = try received.decodeTypingEvent()
        XCTAssertEqual(decoded.type, .start)
        XCTAssertEqual(decoded.peerName, "Bob")
    }
    
    // MARK: - Несовпадение типа
    
    /// Тип пакета — единственное, что отличает сообщение от typing-события.
    /// Проверяем, что при неверной трактовке декодер честно падает,
    /// а не возвращает мусор.
    func test_decodingTypingPacketAsMessage_throws() throws {
        let packet = try MultipeerPacket(typingEvent: TypingEvent(type: .stop, peerName: "Bob"))
        
        XCTAssertThrowsError(try packet.decodeMessage())
    }
    
    func test_decodingMessagePacketAsTyping_throws() throws {
        let packet = try MultipeerPacket(message: SealedPayload(version: 1, box: Data([1])))
        
        XCTAssertThrowsError(try packet.decodeTypingEvent())
    }
}
