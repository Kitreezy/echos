//
//  RelayEnvelopeTests.swift
//  echosTests
//
//  Unit: формат конверта релея — чистая сериализация, без сети.
//

import Foundation
import Testing
@testable import echos

struct RelayEnvelopeTests {

    // MARK: - Round trip

    /// Сообщение в конверте лежит запечатанным: конверт переносит его как
    /// есть, не заглядывая внутрь.
    @Test func messageEnvelope_roundTrip_preservesSealedPayload() throws {
        let sealed = SealedPayload(version: 1, box: Data([1, 2, 3, 4]))

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.message(sealed, from: "Alice", to: "Bob").encoded()
        )

        #expect(restored.kind == .message)
        #expect(restored.sender == "Alice")
        #expect(try restored.decodeMessage() == sealed)
    }

    @Test func typingEnvelope_roundTrip_preservesEvent() throws {
        let event = TypingEvent(type: .stop, peerName: "Bob")

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.typing(event, from: "Bob", to: "Alice").encoded()
        )

        #expect(restored.kind == .typing)
        #expect(try restored.decodeTyping().type == .stop)
    }

    @Test func presenceEnvelope_roundTrip_preservesParticipants() throws {
        let participants = [RelayParticipant(id: "a1b2", name: "Alice"),
                            RelayParticipant(id: "c3d4", name: "Bob")]

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.presence(participants).encoded()
        )

        let decoded = try restored.decodePresence()

        #expect(decoded.map(\.id) == ["a1b2", "c3d4"])
        #expect(decoded.map(\.name) == ["Alice", "Bob"])
    }

    /// Тёзки — разные люди, и присутствие должно их различать.
    @Test func presenceEnvelope_keepsNamesakesApart() throws {
        let participants = [RelayParticipant(id: "a1b2", name: "Bob"),
                            RelayParticipant(id: "c3d4", name: "Bob")]

        let restored = try RelayEnvelope.decode(
            from: try RelayEnvelope.presence(participants).encoded()
        )

        #expect(try restored.decodePresence().map(\.id) == ["a1b2", "c3d4"])
    }

    // MARK: - Подмена отправителя

    /// Сервер проставляет отправителя сам: имя из конверта клиента —
    /// это то, чем он назвался, а не то, кем он является.
    @Test func stamped_replacesSenderKeepingPayload() throws {
        let sealed = SealedPayload(version: 1, box: Data([9, 8, 7]))

        let forged = try RelayEnvelope.message(sealed, from: "Alice", to: "Bob")
        let corrected = forged.stamped(sender: "Mallory")

        #expect(corrected.sender == "Mallory")
        #expect(corrected.kind == .message)
        #expect(try corrected.decodeMessage() == sealed)
    }

    // MARK: - Ошибки

    @Test func decodingEmptyPayload_throws() throws {
        // Конверт без payload — то, что реально приходит по проводу,
        // если сервер прислал один заголовок.
        let json = #"{"kind":"hello","sender":"Alice"}"#
        let empty = try RelayEnvelope.decode(from: Data(json.utf8))

        #expect(throws: RelayError.emptyPayload) { try empty.decodeMessage() }
    }

    @Test func decodingMessageAsTyping_throws() throws {
        let sealed = SealedPayload(version: 1, box: Data([1]))
        let envelope = try RelayEnvelope.message(sealed, from: "Alice", to: "Bob")

        #expect(throws: (any Error).self) { try envelope.decodeTyping() }
    }
}
