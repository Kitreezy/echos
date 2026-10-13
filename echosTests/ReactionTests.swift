//
//  ReactionTests.swift
//  echosTests
//
//  Реакции: своя ставится и снимается, чужая ложится на то сообщение, на
//  которое поставлена, и в ленту не попадает.
//

import XCTest
@testable import echos

@MainActor
final class ReactionTests: XCTestCase {

    private var transport: LoopbackTransport!
    private var store: SpyMessageStore!
    private var viewModel: ChatViewModel!

    override func setUp() async throws {
        transport = LoopbackTransport()
        store = SpyMessageStore()
        viewModel = ChatViewModel()
        viewModel.persistenceFlushInterval = .milliseconds(50)
        viewModel.initialize(transport: transport, store: store, strokes: SpyStrokeStore())
        _ = await waitUntil { self.transport.pipelinesConnected >= 1 }
        viewModel.currentConversationPeer = "bob"
        viewModel.isConversationOnScreen = true
    }

    private func incoming(_ text: String) -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: false), senderName: "Bob")
    }

    // MARK: - Своя

    func test_react_setsMineAndSendsIt() async {
        await viewModel.sendMessage("привет")
        let id = viewModel.messages[0].id

        await viewModel.react(to: id, with: "❤️")

        XCTAssertEqual(viewModel.messages[0].myReaction, "❤️")
        let sent = transport.sentMessages.last
        XCTAssertEqual(sent?.payload.reaction, ReactionPayload(targetID: id.uuidString, emoji: "❤️"))
        XCTAssertEqual(sent?.payload.text, "❤️", "Старая сборка увидит эмодзи текстом")
        XCTAssertEqual(sent?.recipient, "bob")
    }

    func test_sameReactionAgain_removesIt() async {
        await viewModel.sendMessage("привет")
        let id = viewModel.messages[0].id

        await viewModel.react(to: id, with: "❤️")
        await viewModel.react(to: id, with: "❤️")

        XCTAssertNil(viewModel.messages[0].myReaction)
        XCTAssertEqual(transport.sentMessages.last?.payload.reaction?.emoji, "", "Снятие тоже уходит")
    }

    func test_otherReaction_replacesMine() async {
        await viewModel.sendMessage("привет")
        let id = viewModel.messages[0].id

        await viewModel.react(to: id, with: "❤️")
        await viewModel.react(to: id, with: "🔥")

        XCTAssertEqual(viewModel.messages[0].myReaction, "🔥")
    }

    // MARK: - Чужая

    func test_incomingReaction_landsOnTheTargetAndNotInTheFeed() async {
        await viewModel.sendMessage("моё")
        let id = viewModel.messages[0].id

        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: "👍"),
                                               senderName: "Bob"),
                       from: "bob")
        let landed = await waitUntil { self.viewModel.messages[0].peerReaction == "👍" }

        XCTAssertTrue(landed)
        XCTAssertEqual(viewModel.messages.count, 1, "Реакция — не сообщение")
        XCTAssertNil(viewModel.unreadCounts["bob"], "И не непрочитанное")
    }

    func test_incomingRemoval_clearsTheirs() async {
        await viewModel.sendMessage("моё")
        let id = viewModel.messages[0].id
        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: "👍"),
                                               senderName: "Bob"), from: "bob")
        _ = await waitUntil { self.viewModel.messages[0].peerReaction == "👍" }

        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: ""),
                                               senderName: "Bob"), from: "bob")
        let cleared = await waitUntil { self.viewModel.messages[0].peerReaction == nil }

        XCTAssertTrue(cleared)
    }

    /// Реакция от третьего лица на переписку с Бобом — не его дело.
    func test_reactionFromSomeoneElse_isIgnored() async {
        await viewModel.sendMessage("Бобу")
        let id = viewModel.messages[0].id

        transport.emit(message: MessagePayload(reaction: ReactionPayload(targetID: id.uuidString, emoji: "😂"),
                                               senderName: "Carol"), from: "carol")
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(viewModel.messages[0].peerReaction)
    }

    func test_reaction_survivesTheWire() throws {
        let payload = MessagePayload(reaction: ReactionPayload(targetID: "abc", emoji: "🔥"), senderName: "A")
        let restored = try JSONDecoder().decode(MessagePayload.self, from: try JSONEncoder().encode(payload))

        XCTAssertEqual(restored.reaction, payload.reaction)
    }

    func test_plainMessage_hasNoReactionOnTheWire() throws {
        let payload = MessagePayload(from: Message(text: "привет", isFromMe: true), senderName: "A")
        let wire = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        XCTAssertFalse(wire.contains("reaction"))
    }
}
