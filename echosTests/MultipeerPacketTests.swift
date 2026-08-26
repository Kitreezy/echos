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
    
    func test_messagePacket_roundTrip_preservesPayload() throws {
        let message = Message(text: "привет", isFromMe: true)
        let payload = MessagePayload(from: message, senderName: "Alice")
        
        let packet = try MultipeerPacket(message: payload)
        // Пакет уходит по сети как Data — воспроизводим полный цикл.
        let wire = try JSONEncoder().encode(packet)
        let received = try JSONDecoder().decode(MultipeerPacket.self, from: wire)
        
        XCTAssertEqual(received.type, .message)
        
        let decoded = try received.decodeMessage()
        XCTAssertEqual(decoded.id, message.id.uuidString)
        XCTAssertEqual(decoded.text, "привет")
        XCTAssertEqual(decoded.senderName, "Alice")
        XCTAssertEqual(decoded.timestamp, message.timestamp.timeIntervalSince1970, accuracy: 0.001)
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
        let payload = MessagePayload(from: Message(text: "hi", isFromMe: true), senderName: "Alice")
        let packet = try MultipeerPacket(message: payload)
        
        XCTAssertThrowsError(try packet.decodeTypingEvent())
    }
}
