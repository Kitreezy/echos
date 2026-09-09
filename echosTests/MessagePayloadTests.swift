//
//  MessagePayloadTests.swift
//  echosTests
//
//  Unit: конвертация сетевого payload обратно в доменную модель.
//

import XCTest
@testable import echos

final class MessagePayloadTests: XCTestCase {
    
    func test_toMessage_marksMessageAsIncomingAndSent() {
        let original = Message(text: "yo", isFromMe: true, status: .sending)
        let payload = MessagePayload(from: original, senderName: "Alice")
        
        let restored = payload.toMessage(from: "peer-address")
        
        // Payload всегда приходит от кого-то другого:
        XCTAssertFalse(restored.isFromMe)
        // ...и раз он дошёл, значит доставлен:
        XCTAssertEqual(restored.status, .sent)
        XCTAssertEqual(restored.senderName, "Alice")
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.text, "yo")
    }
    
    /// Фиксируем текущее поведение: битый UUID не роняет приложение,
    /// но и не сохраняет identity — сообщение получит новый id.
    /// Практическое следствие: дедупликация по id для такого пакета не сработает.
    func test_toMessage_withMalformedUUID_generatesNewIdentity() {
        let payload = MessagePayload(from: Message(text: "x", isFromMe: false), senderName: "Bob")
        let broken = try! JSONDecoder().decode(
            MessagePayload.self,
            from: """
            {"id":"not-a-uuid","text":"x","senderName":"Bob","timestamp":0}
            """.data(using: .utf8)!
        )
        
        let restored = broken.toMessage(from: "peer-address")
        
        XCTAssertNotEqual(restored.id.uuidString, "not-a-uuid")
        XCTAssertNotEqual(restored.id, payload.toMessage(from: "peer-address").id)
        XCTAssertEqual(restored.text, "x")
    }
    
    func test_toMessage_restoresTimestampFromEpoch() {
        let sent = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = MessagePayload(from: Message(text: "t", isFromMe: true, timestamp: sent),
                                     senderName: "Alice")
        
        XCTAssertEqual(payload.toMessage(from: "peer-address").timestamp, sent)
    }
}
