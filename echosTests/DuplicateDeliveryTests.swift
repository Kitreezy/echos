//
//  DuplicateDeliveryTests.swift
//  echosTests
//
//  Одно и то же сообщение, пришедшее дважды.
//
//  На плохой сети отправитель не знает, дошло ли сообщение: отправка
//  оборвалась по таймауту, а байты, может быть, уже ушли. Он шлёт ещё раз —
//  и правильно, иначе сообщение терялось бы. Значит, повторы — штатная
//  ситуация, и разбираться с ними должен получатель.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct DuplicateDeliveryTests {

    private func makeViewModel(transport: LoopbackTransport,
                               store: SpyMessageStore = SpyMessageStore()) async -> ChatViewModel {
        let viewModel = ChatViewModel()
        viewModel.persistenceFlushInterval = .milliseconds(50)
        viewModel.initialize(transport: transport, store: store, strokes: SpyStrokeStore())
        _ = await waitUntil { transport.pipelinesConnected >= 1 }
        return viewModel
    }

    private func payload(_ text: String) -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: false), senderName: "Bob")
    }

    @Test func sameMessageTwice_isShownOnce() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        viewModel.currentConversationPeer = "bob"
        viewModel.isConversationOnScreen = true

        let message = payload("привет")
        transport.emit(message: message, from: "bob")
        transport.emit(message: message, from: "bob")
        transport.emit(message: payload("второе"), from: "bob")
        _ = await waitUntil { viewModel.messages.count >= 2 }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.messages.map(\.text) == ["привет", "второе"])
    }

    @Test func sameMessageTwice_isCountedAsOneUnread() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        let message = payload("привет")
        transport.emit(message: message, from: "bob")
        transport.emit(message: message, from: "bob")
        transport.emit(message: payload("второе"), from: "bob")
        _ = await waitUntil { (viewModel.unreadCounts["bob"] ?? 0) >= 2 }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.unreadCounts["bob"] == 2)
    }

    /// Повтор может прийти и после перезапуска — когда оригинал уже давно
    /// в хранилище, а в памяти о нём ничего нет.
    @Test func messageAlreadyInTheStore_isDropped() async throws {
        let store = SpyMessageStore()
        let message = payload("из прошлого")
        try await store.saveMessage(message.toMessage(from: "bob"))

        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport, store: store)

        transport.emit(message: message, from: "bob")
        transport.emit(message: payload("новое"), from: "bob")
        _ = await waitUntil { viewModel.unreadCounts["bob"] != nil }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.unreadCounts["bob"] == 1, "Посчитано только новое")
        #expect(viewModel.latestNotice?.preview == "новое")
    }
}
