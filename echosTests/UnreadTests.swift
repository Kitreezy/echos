//
//  UnreadTests.swift
//  echosTests
//
//  Непрочитанное и баннер: входящее не в открытый чат ждёт человека.
//

import XCTest
@testable import echos

@MainActor
final class UnreadTests: XCTestCase {

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

    func test_messageToAnotherChat_countsAsUnreadAndRaisesANotice() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(message: payload("привет"), from: "carol")
        let counted = await waitUntil { viewModel.unreadCounts["carol"] == 1 }

        XCTAssertTrue(counted)
        XCTAssertTrue(viewModel.messages.isEmpty, "В открытый чат с Бобом чужое не попадает")
        XCTAssertEqual(viewModel.latestNotice?.address, "carol")
        XCTAssertEqual(viewModel.latestNotice?.preview, "привет")
        XCTAssertEqual(viewModel.latestNotice?.name, "Carol", "Имя — из сообщения, пока человека нет рядом")
    }

    func test_messageToTheOpenChat_isReadAndSilent() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(message: payload("привет"), from: "bob")
        _ = await waitUntil { viewModel.messages.count == 1 }

        XCTAssertTrue(viewModel.messages[0].isRead)
        XCTAssertNil(viewModel.unreadCounts["bob"])
        XCTAssertNil(viewModel.latestNotice, "О том, что и так на экране, говорить незачем")
    }

    /// Собеседник назначен, но экран чата не открыт — например, главный
    /// экран после принятого приглашения. Его сообщение — непрочитанное.
    func test_messageToTheAssignedButHiddenChat_isUnread() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        viewModel.isConversationOnScreen = false

        transport.emit(message: payload("привет"), from: "bob")
        let counted = await waitUntil { viewModel.unreadCounts["bob"] == 1 }

        XCTAssertTrue(counted)
        XCTAssertEqual(viewModel.latestNotice?.address, "bob")
        XCTAssertEqual(viewModel.messages.first?.isRead, false)
    }

    func test_mosaicNotice_carriesTheGrid() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!

        transport.emit(message: payload(mosaic.text, mosaic: mosaic), from: "carol")
        _ = await waitUntil { viewModel.latestNotice != nil }

        XCTAssertEqual(viewModel.latestNotice?.mosaic, mosaic)
        XCTAssertEqual(viewModel.latestNotice?.preview, "мозаика")
    }

    func test_unread_accumulatesPerSender() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(message: payload("раз"), from: "carol")
        transport.emit(message: payload("два"), from: "carol")
        transport.emit(message: payload("три"), from: "dave")
        _ = await waitUntil { viewModel.unreadCounts["carol"] == 2 && viewModel.unreadCounts["dave"] == 1 }

        XCTAssertEqual(viewModel.totalUnread, 3)
    }

    func test_openingTheChat_clearsUnread_andMarksTheStore() async {
        let transport = LoopbackTransport()
        let store = SpyMessageStore()
        let viewModel = await makeViewModel(transport: transport, store: store)

        transport.emit(message: payload("привет"), from: "carol")
        _ = await waitUntil { viewModel.unreadCounts["carol"] == 1 }

        await viewModel.switchToConversation(with: "carol")

        XCTAssertNil(viewModel.unreadCounts["carol"])
        XCTAssertEqual(store.markedAsRead, ["carol"])
    }

    /// При запуске точки должны быть на месте — счёт берётся из хранилища.
    func test_unreadCounts_areLoadedFromTheStore() async throws {
        let store = SpyMessageStore()
        try await store.saveMessage(Message(text: "не читал", peerAddress: "carol", isFromMe: false, isRead: false))
        try await store.saveMessage(Message(text: "читал", peerAddress: "carol", isFromMe: false, isRead: true))
        try await store.saveMessage(Message(text: "моё", peerAddress: "carol", isFromMe: true, isRead: false))

        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport, store: store, open: nil)
        let loaded = await waitUntil { viewModel.unreadCounts["carol"] == 1 }

        XCTAssertTrue(loaded, "Своё непрочитанным не бывает, прочитанное — тоже")
    }

    func test_conversationSummary_countsUnread() async throws {
        let store = SpyMessageStore()
        try await store.saveMessage(Message(text: "раз", peerAddress: "carol", isFromMe: false, isRead: false))
        try await store.saveMessage(Message(text: "два", peerAddress: "carol", isFromMe: false, isRead: false))

        let viewModel = await makeViewModel(transport: LoopbackTransport(), store: store, open: nil)
        let summaries = await viewModel.getAllConversations()

        XCTAssertEqual(summaries.first?.unreadCount, 2)
    }
}
