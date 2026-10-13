//
//  ResendTests.swift
//  echosTests
//
//  Повтор неотправленного: то же сообщение, с тем же идентификатором.
//

import XCTest
@testable import echos

@MainActor
final class ResendTests: XCTestCase {

    private func makeViewModel(transport: LoopbackTransport) async -> ChatViewModel {
        let viewModel = ChatViewModel()
        viewModel.initialize(transport: transport, store: SpyMessageStore(), strokes: SpyStrokeStore())
        viewModel.currentConversationPeer = "bob"
        viewModel.currentConversationName = "Bob"
        return viewModel
    }

    func test_failedMessage_isSentAgainWithTheSameID() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.sendingFails = true
        await viewModel.sendMessage("не дошло")
        let failed = viewModel.messages[0]
        XCTAssertEqual(failed.status, .failed)
        XCTAssertTrue(transport.sentMessages.isEmpty)

        transport.sendingFails = false
        await viewModel.resend(failed.id)

        XCTAssertEqual(viewModel.messages.count, 1, "Повтор — не новое сообщение")
        XCTAssertEqual(viewModel.messages[0].status, .sent)
        XCTAssertEqual(transport.sentMessages.count, 1)
        XCTAssertEqual(transport.sentMessages[0].payload.id, failed.id.uuidString,
                       "Тот же идентификатор: собеседник не сохранит дубль")
        XCTAssertEqual(transport.sentMessages[0].recipient, "bob")
    }

    func test_failedMosaic_isSentAgainAsAGrid() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!

        transport.sendingFails = true
        await viewModel.sendMosaic(mosaic)
        transport.sendingFails = false
        await viewModel.resend(viewModel.messages[0].id)

        XCTAssertEqual(viewModel.messages[0].status, .sent)
        XCTAssertEqual(transport.sentMessages.first?.payload.mosaic, mosaic)
    }

    func test_sentMessage_isNotResent() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        await viewModel.sendMessage("дошло")
        await viewModel.resend(viewModel.messages[0].id)

        XCTAssertEqual(transport.sentMessages.count, 1, "Дошедшее второй раз не уходит")
    }

    func test_resend_failsAgainQuietly() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.sendingFails = true
        await viewModel.sendMessage("всё ещё нет сети")
        await viewModel.resend(viewModel.messages[0].id)

        XCTAssertEqual(viewModel.messages[0].status, .failed)
        XCTAssertEqual(viewModel.messages.count, 1)
    }

    /// Повторяется по адресу переписки, а не по открытой сейчас: человек
    /// мог уйти в другой чат, а повторить — из списка позже.
    func test_resend_goesToTheMessagesOwnConversation() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.sendingFails = true
        await viewModel.sendMessage("Бобу")
        transport.sendingFails = false
        viewModel.currentConversationPeer = "carol"
        await viewModel.resend(viewModel.messages[0].id)

        XCTAssertEqual(transport.sentMessages.first?.recipient, "bob")
    }
}
