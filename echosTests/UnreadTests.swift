//
//  UnreadTests.swift
//  echosTests
//
//  Непрочитанное и баннер: входящее не в открытый чат ждёт человека.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct UnreadTests {

    private func makeViewModel(transport: LoopbackTransport,
                               store: SpyMessageStore = SpyMessageStore(),
                               open peer: String? = "bob") async -> ChatViewModel {
        let viewModel = ChatViewModel()
        viewModel.persistenceFlushInterval = .milliseconds(50)
        viewModel.initialize(transport: transport, store: store, strokes: SpyStrokeStore())
        _ = await waitUntil { transport.pipelinesConnected >= 1 }
        viewModel.currentConversationPeer = peer
        viewModel.isConversationOnScreen = peer != nil
        return viewModel
    }

    private func payload(_ text: String, mosaic: Mosaic? = nil) -> MessagePayload {
        MessagePayload(from: Message(text: text, mosaic: mosaic, isFromMe: false), senderName: "Carol")
    }

    @Test func messageToAnotherChat_countsAsUnreadAndRaisesANotice() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(message: payload("привет"), from: "carol")
        let counted = await waitUntil { viewModel.unreadCounts["carol"] == 1 }

        #expect(counted)
        #expect(viewModel.messages.isEmpty, "В открытый чат с Бобом чужое не попадает")
        #expect(viewModel.latestNotice?.address == "carol")
        #expect(viewModel.latestNotice?.preview == "привет")
        #expect(viewModel.latestNotice?.name == "Carol", "Имя — из сообщения, пока человека нет рядом")
    }

    @Test func messageToTheOpenChat_isReadAndSilent() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(message: payload("привет"), from: "bob")
        _ = await waitUntil { viewModel.messages.count == 1 }

        #expect(viewModel.messages[0].isRead)
        #expect(viewModel.unreadCounts["bob"] == nil)
        #expect(viewModel.latestNotice == nil, "О том, что и так на экране, говорить незачем")
    }

    /// Собеседник назначен, но экран чата не открыт — например, главный
    /// экран после принятого приглашения. Его сообщение — непрочитанное.
    @Test func messageToTheAssignedButHiddenChat_isUnread() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        viewModel.isConversationOnScreen = false

        transport.emit(message: payload("привет"), from: "bob")
        let counted = await waitUntil { viewModel.unreadCounts["bob"] == 1 }

        #expect(counted)
        #expect(viewModel.latestNotice?.address == "bob")
        #expect(viewModel.messages.first?.isRead == false)
    }

    @Test func mosaicNotice_carriesTheGrid() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!

        transport.emit(message: payload(mosaic.text, mosaic: mosaic), from: "carol")
        _ = await waitUntil { viewModel.latestNotice != nil }

        #expect(viewModel.latestNotice?.mosaic == mosaic)
        #expect(viewModel.latestNotice?.preview == "мозаика")
    }

    @Test func unread_accumulatesPerSender() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(message: payload("раз"), from: "carol")
        transport.emit(message: payload("два"), from: "carol")
        transport.emit(message: payload("три"), from: "dave")
        _ = await waitUntil { viewModel.unreadCounts["carol"] == 2 && viewModel.unreadCounts["dave"] == 1 }

        #expect(viewModel.totalUnread == 3)
    }

    @Test func openingTheChat_clearsUnread_andMarksTheStore() async {
        let transport = LoopbackTransport()
        let store = SpyMessageStore()
        let viewModel = await makeViewModel(transport: transport, store: store)

        transport.emit(message: payload("привет"), from: "carol")
        _ = await waitUntil { viewModel.unreadCounts["carol"] == 1 }

        await viewModel.switchToConversation(with: "carol")

        #expect(viewModel.unreadCounts["carol"] == nil)
        #expect(store.markedAsRead == ["carol"])
    }

    /// При запуске точки должны быть на месте — счёт берётся из хранилища.
    @Test func unreadCounts_areLoadedFromTheStore() async throws {
        let store = SpyMessageStore()
        try await store.saveMessage(Message(text: "не читал", peerAddress: "carol", isFromMe: false, isRead: false))
        try await store.saveMessage(Message(text: "читал", peerAddress: "carol", isFromMe: false, isRead: true))
        try await store.saveMessage(Message(text: "моё", peerAddress: "carol", isFromMe: true, isRead: false))

        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport, store: store, open: nil)
        let loaded = await waitUntil { viewModel.unreadCounts["carol"] == 1 }

        #expect(loaded, "Своё непрочитанным не бывает, прочитанное — тоже")
    }

    @Test func conversationSummary_countsUnread() async throws {
        let store = SpyMessageStore()
        try await store.saveMessage(Message(text: "раз", peerAddress: "carol", isFromMe: false, isRead: false))
        try await store.saveMessage(Message(text: "два", peerAddress: "carol", isFromMe: false, isRead: false))

        let viewModel = await makeViewModel(transport: LoopbackTransport(), store: store, open: nil)
        let summaries = await viewModel.getAllConversations()

        #expect(summaries.first?.unreadCount == 2)
    }
}
