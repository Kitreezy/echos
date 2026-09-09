//
//  RelayEnvelopeTests.swift
//  echosTests
//
//  Unit: формат конверта релея — чистая сериализация, без сети.
//

import XCTest
@testable import echos

final class RelayEnvelopeTests: XCTestCase {

    // MARK: - Round trip

    func test_messageEnvelope_roundTrip_preservesPayload() throws {
        let payload = MessagePayload(from: Message(text: "привет", isFromMe: true),
                                     senderName: "Alice")

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.message(payload, from: "Alice", to: "Bob").encoded()
        )

        XCTAssertEqual(restored.kind, .message)
        XCTAssertEqual(restored.sender, "Alice")
        XCTAssertEqual(try restored.decodeMessage().text, "привет")
    }

    func test_typingEnvelope_roundTrip_preservesEvent() throws {
        let event = TypingEvent(type: .stop, peerName: "Bob")

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.typing(event, from: "Bob", to: "Alice").encoded()
        )

        XCTAssertEqual(restored.kind, .typing)
        XCTAssertEqual(try restored.decodeTyping().type, .stop)
    }

    func test_presenceEnvelope_roundTrip_preservesNames() throws {
        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.presence(["Alice", "Bob"]).encoded()
        )

        XCTAssertEqual(try restored.decodePresence(), ["Alice", "Bob"])
    }

    // MARK: - Подмена отправителя

    /// Сервер проставляет отправителя сам: имя из конверта клиента —
    /// это то, чем он назвался, а не то, кем он является.
    func test_stamped_replacesSenderKeepingPayload() throws {
        let payload = MessagePayload(from: Message(text: "текст", isFromMe: true),
                                     senderName: "Mallory")

        let forged = try RelayEnvelope.message(payload, from: "Alice", to: "Bob")
        let corrected = forged.stamped(sender: "Mallory")

        XCTAssertEqual(corrected.sender, "Mallory")
        XCTAssertEqual(corrected.kind, .message)
        XCTAssertEqual(try corrected.decodeMessage().text, "текст")
    }

    // MARK: - Ошибки

    func test_decodingEmptyPayload_throws() throws {
        let hello = RelayEnvelope.hello(from: "Alice")

        XCTAssertThrowsError(try hello.decodeMessage()) { error in
            XCTAssertEqual(error as? RelayError, .emptyPayload)
        }
    }

    func test_decodingMessageAsTyping_throws() throws {
        let payload = MessagePayload(from: Message(text: "привет", isFromMe: true),
                                     senderName: "Alice")
        let envelope = try RelayEnvelope.message(payload, from: "Alice", to: "Bob")

        XCTAssertThrowsError(try envelope.decodeTyping())
    }
}
