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

    /// Сообщение в конверте лежит запечатанным: конверт переносит его как
    /// есть, не заглядывая внутрь.
    func test_messageEnvelope_roundTrip_preservesSealedPayload() throws {
        let sealed = SealedPayload(version: 1, box: Data([1, 2, 3, 4]))

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.message(sealed, from: "Alice", to: "Bob").encoded()
        )

        XCTAssertEqual(restored.kind, .message)
        XCTAssertEqual(restored.sender, "Alice")
        XCTAssertEqual(try restored.decodeMessage(), sealed)
    }

    func test_typingEnvelope_roundTrip_preservesEvent() throws {
        let event = TypingEvent(type: .stop, peerName: "Bob")

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.typing(event, from: "Bob", to: "Alice").encoded()
        )

        XCTAssertEqual(restored.kind, .typing)
        XCTAssertEqual(try restored.decodeTyping().type, .stop)
    }

    func test_presenceEnvelope_roundTrip_preservesParticipants() throws {
        let participants = [RelayParticipant(id: "a1b2", name: "Alice"),
                            RelayParticipant(id: "c3d4", name: "Bob")]

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.presence(participants).encoded()
        )

        let decoded = try restored.decodePresence()

        XCTAssertEqual(decoded.map(\.id), ["a1b2", "c3d4"])
        XCTAssertEqual(decoded.map(\.name), ["Alice", "Bob"])
    }

    /// Тёзки — разные люди, и присутствие должно их различать.
    func test_presenceEnvelope_keepsNamesakesApart() throws {
        let participants = [RelayParticipant(id: "a1b2", name: "Bob"),
                            RelayParticipant(id: "c3d4", name: "Bob")]

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.presence(participants).encoded()
        )

        XCTAssertEqual(try restored.decodePresence().map(\.id), ["a1b2", "c3d4"])
    }

    // MARK: - Подмена отправителя

    /// Сервер проставляет отправителя сам: имя из конверта клиента —
    /// это то, чем он назвался, а не то, кем он является.
    func test_stamped_replacesSenderKeepingPayload() throws {
        let sealed = SealedPayload(version: 1, box: Data([9, 8, 7]))

        let forged = try RelayEnvelope.message(sealed, from: "Alice", to: "Bob")
        let corrected = forged.stamped(sender: "Mallory")

        XCTAssertEqual(corrected.sender, "Mallory")
        XCTAssertEqual(corrected.kind, .message)
        XCTAssertEqual(try corrected.decodeMessage(), sealed)
    }

    // MARK: - Ошибки

    func test_decodingEmptyPayload_throws() throws {
        // Конверт без payload — то, что реально приходит по проводу,
        // если сервер прислал один заголовок.
        let json = #"{"kind":"hello","sender":"Alice"}"#
        let empty = try RelayEnvelope.decode(from: Data(json.utf8))

        XCTAssertThrowsError(try empty.decodeMessage()) { error in
            XCTAssertEqual(error as? RelayError, .emptyPayload)
        }
    }

    func test_decodingMessageAsTyping_throws() throws {
        let sealed = SealedPayload(version: 1, box: Data([1]))
        let envelope = try RelayEnvelope.message(sealed, from: "Alice", to: "Bob")

        XCTAssertThrowsError(try envelope.decodeTyping())
    }
}
