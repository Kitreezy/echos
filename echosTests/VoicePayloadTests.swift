//
//  VoicePayloadTests.swift
//  echosTests
//
//  Unit: голосовое через транспортный конверт — туда и обратно без
//  потерь, битая base64 не роняет сообщение.
//

import Foundation
import Testing
@testable import echos

struct VoicePayloadTests {

    private let attachment = VoiceAttachment(
        duration: 7,
        samples: Array(repeating: Float(0.5), count: VoiceAttachment.barCount),
        audio: Data("fake-m4a-bytes".utf8)
    )

    @Test func payload_roundTripsThroughJSON() throws {
        let payload = MessagePayload(from: Message(text: "🎤 Голосовое · 0:07",
                                                   voice: attachment,
                                                   isFromMe: true),
                                     senderName: "Боб")
        let data = try JSONEncoder().encode(payload)
        let restored = try JSONDecoder().decode(MessagePayload.self, from: data)

        let message = restored.toMessage(from: "peer-address")
        #expect(message.voice == attachment)
        #expect(message.text == "🎤 Голосовое · 0:07")
    }

    @Test func brokenBase64_voiceBecomesNil_messageSurvives() {
        let payload = VoicePayload(duration: 7,
                                   samples: [0.5],
                                   audio: "не base64!!")
        #expect(payload.attachment == nil)
    }

    @Test func textMessage_hasNoVoice() {
        let payload = MessagePayload(from: Message(text: "привет", isFromMe: true),
                                     senderName: "Боб")
        #expect(payload.voice == nil)
    }

    @Test func format_durationHasLeadingZero() {
        #expect(VoiceAttachment.format(duration: 7) == "0:07")
        #expect(VoiceAttachment.format(duration: 65) == "1:05")
        #expect(VoiceAttachment.format(duration: 600) == "10:00")
    }
}
