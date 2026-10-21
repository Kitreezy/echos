//
//  ResendTests.swift
//  echosTests
//
//  Повтор неотправленного: то же сообщение, с тем же идентификатором.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct ResendTests {

    private func makeViewModel(transport: LoopbackTransport) async -> ChatViewModel {
        let viewModel = ChatViewModel()
        viewModel.initialize(transport: transport, store: SpyMessageStore(), strokes: SpyStrokeStore())
        viewModel.currentConversationPeer = "bob"
        viewModel.currentConversationName = "Bob"
        return viewModel
    }

    @Test func failedMessage_isSentAgainWithTheSameID() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.sendingFails = true
        await viewModel.sendMessage("не дошло")
        let failed = viewModel.messages[0]
        #expect(failed.status == .failed)
        #expect(transport.sentMessages.isEmpty)

        transport.sendingFails = false
        await viewModel.resend(failed.id)

        #expect(viewModel.messages.count == 1, "Повтор — не новое сообщение")
        #expect(viewModel.messages[0].status == .sent)
        #expect(transport.sentMessages.count == 1)
        #expect(transport.sentMessages[0].payload.id == failed.id.uuidString, "Тот же идентификатор: собеседник не сохранит дубль")
        #expect(transport.sentMessages[0].recipient == "bob")
    }

    @Test func failedMosaic_isSentAgainAsAGrid() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!

        transport.sendingFails = true
        await viewModel.sendMosaic(mosaic)
        transport.sendingFails = false
        await viewModel.resend(viewModel.messages[0].id)

        #expect(viewModel.messages[0].status == .sent)
        #expect(transport.sentMessages.first?.payload.mosaic == mosaic)
    }

    @Test func sentMessage_isNotResent() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        await viewModel.sendMessage("дошло")
        await viewModel.resend(viewModel.messages[0].id)

        #expect(transport.sentMessages.count == 1, "Дошедшее второй раз не уходит")
    }

    @Test func resend_failsAgainQuietly() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.sendingFails = true
        await viewModel.sendMessage("всё ещё нет сети")
        await viewModel.resend(viewModel.messages[0].id)

        #expect(viewModel.messages[0].status == .failed)
        #expect(viewModel.messages.count == 1)
    }

    /// Повторяется по адресу переписки, а не по открытой сейчас: человек
    /// мог уйти в другой чат, а повторить — из списка позже.
    @Test func resend_goesToTheMessagesOwnConversation() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.sendingFails = true
        await viewModel.sendMessage("Бобу")
        transport.sendingFails = false
        viewModel.currentConversationPeer = "carol"
        await viewModel.resend(viewModel.messages[0].id)

        #expect(transport.sentMessages.first?.recipient == "bob")
    }
}
