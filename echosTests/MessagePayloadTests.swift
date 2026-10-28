//
//  MessagePayloadTests.swift
//  echosTests
//
//  Unit: конвертация сетевого payload обратно в доменную модель.
//

import Foundation
import Testing
@testable import echos

struct MessagePayloadTests {

    @Test func toMessage_marksMessageAsIncomingAndSent() {
        let original = Message(text: "yo", isFromMe: true, status: .sending)
        let payload = MessagePayload(from: original, senderName: "Alice")

        let restored = payload.toMessage(from: "peer-address")

        // Payload всегда приходит от кого-то другого:
        #expect(!restored.isFromMe)
        // ...и раз он дошёл, значит доставлен:
        #expect(restored.status == .sent)
        #expect(restored.senderName == "Alice")
        #expect(restored.id == original.id)
        #expect(restored.text == "yo")
    }

    /// Фиксируем текущее поведение: битый UUID не роняет приложение,
    /// но и не сохраняет identity — сообщение получит новый id.
    /// Практическое следствие: дедупликация по id для такого пакета не сработает.
    @Test func toMessage_withMalformedUUID_generatesNewIdentity() throws {
        let payload = MessagePayload(from: Message(text: "x", isFromMe: false), senderName: "Bob")
        let broken = try JSONDecoder().decode(
            MessagePayload.self,
            from: """
            {"id":"not-a-uuid","text":"x","senderName":"Bob","timestamp":0}
            """.data(using: .utf8)!
        )

        let restored = broken.toMessage(from: "peer-address")

        #expect(restored.id.uuidString != "not-a-uuid")
        #expect(restored.id != payload.toMessage(from: "peer-address").id)
        #expect(restored.text == "x")
    }

    @Test func toMessage_restoresTimestampFromEpoch() {
        let sent = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = MessagePayload(from: Message(text: "t", isFromMe: true, timestamp: sent),
                                     senderName: "Alice")

        #expect(payload.toMessage(from: "peer-address").timestamp == sent)
    }
}
