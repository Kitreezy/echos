//
//  ReactionTests.swift
//  echosTests
//
//  Реакции: своя ставится и снимается, чужая ложится на то сообщение, на
//  которое поставлена, и в ленту не попадает.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct ReactionTests {

    private let transport = LoopbackTransport()
    private let store = SpyMessageStore()
    private let viewModel = ChatViewModel()

    init() async {
        viewModel.persistenceFlushInterval = .milliseconds(50)
        viewModel.initialize(transport: transport, store: store, strokes: SpyStrokeStore())
        let transport = transport
        _ = await waitUntil { transport.pipelinesConnected >= 1 }
        viewModel.currentConversationPeer = "bob"
        viewModel.isConversationOnScreen = true
    }

    private func incoming(_ text: String) -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: false), senderName: "Bob")
    }

    // MARK: - Своя

    @Test func react_setsMineAndSendsIt() async {
        await viewModel.sendMessage("привет")
        let id = viewModel.messages[0].id

        await viewModel.react(to: id, with: "❤️")

        #expect(viewModel.messages[0].myReaction == "❤️")
        let sent = transport.sentMessages.last
        #expect(sent?.payload.reaction == ReactionPayload(targetID: id.uuidString, emoji: "❤️"))
        #expect(sent?.payload.text == "❤️", "Старая сборка увидит эмодзи текстом")
        #expect(sent?.recipient == "bob")
    }

    @Test func sameReactionAgain_removesIt() async {
        await viewModel.sendMessage("привет")
        let id = viewModel.messages[0].id

        await viewModel.react(to: id, with: "❤️")
        await viewModel.react(to: id, with: "❤️")

        #expect(viewModel.messages[0].myReaction == nil)
        #expect(transport.sentMessages.last?.payload.reaction?.emoji == "", "Снятие тоже уходит")
    }

    @Test func otherReaction_replacesMine() async {
        await viewModel.sendMessage("привет")
        let id = viewModel.messages[0].id

        await viewModel.react(to: id, with: "❤️")
        await viewModel.react(to: id, with: "🔥")

        #expect(viewModel.messages[0].myReaction == "🔥")
    }

    // MARK: - Чужая

    @Test func incomingReaction_landsOnTheTargetAndNotInTheFeed() async {
        await viewModel.sendMessage("моё")
        let id = viewModel.messages[0].id

        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: "👍"),
                                               senderName: "Bob"),
                       from: "bob")
        let landed = await waitUntil { self.viewModel.messages[0].peerReaction == "👍" }

        #expect(landed)
        #expect(viewModel.messages.count == 1, "Реакция — не сообщение")
        #expect(viewModel.unreadCounts["bob"] == nil, "И не непрочитанное")
    }

    @Test func incomingRemoval_clearsTheirs() async {
        await viewModel.sendMessage("моё")
        let id = viewModel.messages[0].id
        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: "👍"),
                                               senderName: "Bob"), from: "bob")
        _ = await waitUntil { self.viewModel.messages[0].peerReaction == "👍" }

        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: ""),
                                               senderName: "Bob"), from: "bob")
        let cleared = await waitUntil { self.viewModel.messages[0].peerReaction == nil }

        #expect(cleared)
    }

    /// Реакция от третьего лица на переписку с Бобом — не его дело.
    @Test func reactionFromSomeoneElse_isIgnored() async {
        await viewModel.sendMessage("Бобу")
        let id = viewModel.messages[0].id

        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: "😂"),
                                               senderName: "Carol"), from: "carol")
        try? await Task.sleep(for: .milliseconds(150))

        #expect(viewModel.messages[0].peerReaction == nil)
    }

    @Test func reaction_survivesTheWire() throws {
        let payload = MessagePayload(reaction: ReactionPayload(targetID: "abc", emoji: "🔥"), senderName: "A")
        let restored = try JSONDecoder().decode(MessagePayload.self, from: try JSONEncoder().encode(payload))

        #expect(restored.reaction == payload.reaction)
    }

    @Test func plainMessage_hasNoReactionOnTheWire() throws {
        let payload = MessagePayload(from: Message(text: "привет", isFromMe: true), senderName: "A")
        let wire = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        #expect(!wire.contains("reaction"))
    }
}
