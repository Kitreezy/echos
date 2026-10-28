//
//  ReplyTests.swift
//  echosTests
//
//  Ответ на сообщение: ссылка едет в конверте, стороны в ней — с точки
//  зрения получателя, а текст цитаты — из своего экземпляра оригинала.
//

import XCTest
@testable import echos

@MainActor
final class ReplyTests: XCTestCase {

    private var transport: LoopbackTransport!
    private var viewModel: ChatViewModel!

    override func setUp() async throws {
        transport = LoopbackTransport()
        viewModel = ChatViewModel()
        viewModel.persistenceFlushInterval = .milliseconds(50)
        viewModel.initialize(transport: transport, store: SpyMessageStore(), strokes: SpyStrokeStore())
        _ = await waitUntil { self.transport.pipelinesConnected >= 1 }
        viewModel.currentConversationPeer = "bob"
        viewModel.currentConversationName = "Боб"
        viewModel.isConversationOnScreen = true
    }

    private func receive(_ message: Message) async {
        transport.emit(message: MessagePayload(from: message, senderName: "Боб"), from: "bob")
        _ = await waitUntil { self.viewModel.messages.contains { $0.id == message.id } }
    }

    // MARK: - Конверт

    func test_replyTravels_andSidesFlipForTheReceiver() async {
        let question = Message(text: "пойдёшь в кино?", isFromMe: false)
        await receive(question)

        await viewModel.sendMessage("да", replyingTo: viewModel.messages[0])

        let sent = transport.sentMessages.last?.payload
        XCTAssertEqual(sent?.reply, ReplyPayload(id: question.id.uuidString, preview: "пойдёшь в кино?",
                                                 isFromSender: false))
        // Боб получает: оригинал — его собственный.
        let atBob = sent?.toMessage(from: "me")
        XCTAssertEqual(atBob?.replyTo, MessageReply(id: question.id, preview: "пойдёшь в кино?", isFromMe: true))
    }

    func test_payloadFromAnOldBuild_isAPlainMessage() throws {
        let json = #"{"id":"\#(UUID().uuidString)","text":"привет","senderName":"Боб","timestamp":0}"#

        let payload = try JSONDecoder().decode(MessagePayload.self, from: Data(json.utf8))

        XCTAssertNil(payload.reply)
        XCTAssertNil(payload.toMessage(from: "bob").replyTo)
    }

    func test_mosaic_isQuotedByName() {
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!

        let reply = MessageReply(quoting: Message(text: mosaic.text, mosaic: mosaic, isFromMe: false))

        XCTAssertEqual(reply.preview, "мозаика")
    }

    func test_preview_isShort() {
        let reply = MessageReply(quoting: Message(text: String(repeating: "а", count: 1000), isFromMe: false))

        XCTAssertEqual(reply.preview.count, MessageReply.previewLength)
    }

    // MARK: - Цитата

    func test_quote_takesTheTextFromMyOwnCopy() async {
        let mine = Message(text: "встреча в 10", peerAddress: "bob", isFromMe: true, status: .sent)
        await viewModel.sendMessage(mine.text)
        let original = viewModel.messages[0]

        // Боб «цитирует» моё сообщение, но присылает другой текст.
        var forged = Message(text: "ок", isFromMe: false)
        forged = Message(id: forged.id, text: "ок", isFromMe: false,
                         replyTo: MessageReply(id: original.id, preview: "я тебе должен 1000", isFromMe: true))
        await receive(forged)

        let quote = viewModel.quote(for: viewModel.messages.last!)
        XCTAssertEqual(quote?.preview, "встреча в 10", "Показывается то, что я писал, а не то, что прислали")
        XCTAssertEqual(quote?.author, "Вы")
        XCTAssertEqual(quote?.index, 0)
    }

    func test_quote_withoutTheOriginal_fallsBackToThePreview() {
        let reply = Message(text: "да", isFromMe: false,
                            replyTo: MessageReply(id: UUID(), preview: "пойдёшь?", isFromMe: false))

        let quote = viewModel.quote(for: reply)

        XCTAssertEqual(quote?.preview, "пойдёшь?", "Историю очистили — цитата остаётся понятной")
        XCTAssertEqual(quote?.author, "Боб")
        XCTAssertNil(quote?.index, "Переходить некуда")
    }

    func test_plainMessage_hasNoQuote() {
        XCTAssertNil(viewModel.quote(for: Message(text: "привет", isFromMe: false)))
    }

    // MARK: - Пересказ

    func test_answeredMessages_areMyRepliesOnly() async {
        let question = Message(text: "пойдёшь?", isFromMe: false)
        await receive(question)
        await viewModel.sendMessage("да", replyingTo: viewModel.messages[0])
        // Ответ Боба на моё — не мой ответ.
        await receive(Message(text: "супер", isFromMe: false,
                              replyTo: MessageReply(id: viewModel.messages[1].id, preview: "да", isFromMe: false)))

        XCTAssertEqual(viewModel.answeredMessageIDs, [question.id])
    }
}
