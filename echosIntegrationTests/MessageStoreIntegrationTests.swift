//
//  MessageStoreIntegrationTests.swift
//  echosIntegrationTests
//
//  Интеграция: MessageStore + реальный Core Data стек.
//

import Foundation
import Testing
import CoreData
@testable import echos

@MainActor
@Suite(.tags(.persistence))
struct MessageStoreIntegrationTests {

    private let stack = CoreDataTestStack.makeInMemory()
    private let store: MessageStore

    init() {
        store = MessageStore(context: stack.container.viewContext)
    }
    
    // MARK: - Save / Load round-trip
    
    @Test func saveMessage_thenLoad_preservesAllFields() async throws {
        let message = CoreDataTestStack.message("привет из теста",
                                                from: "Alice",
                                                isFromMe: false,
                                                status: .sent)
        
        try await store.saveMessage(message)
        let loaded = try await store.loadMessages()
        
        #expect(loaded.count == 1)
        let restored = try #require(loaded.first)
        #expect(restored.id == message.id)
        #expect(restored.text == "привет из теста")
        #expect(restored.senderName == "Alice")
        #expect(restored.isFromMe == false)
        #expect(restored.status == .sent)
        #expect(abs((restored.timestamp.timeIntervalSince1970) - (message.timestamp.timeIntervalSince1970)) <= 0.001)
    }
    
    /// Ответ лежит рядом с текстом, как мозаика, и переживает хранилище.
    func test_reply_survivesTheStore() async throws {
        let reply = MessageReply(id: UUID(), preview: "пойдёшь?", isFromMe: false)
        let message = Message(text: "да", peerAddress: "bob", isFromMe: true, status: .sent, replyTo: reply)

        try await store.saveMessage(message)
        let loaded = try await store.loadMessages(with: "bob")

        XCTAssertEqual(loaded.first?.replyTo, reply)
    }

    /// Мозаика лежит рядом с текстом и возвращается сеткой, а не текстом.
    @Test func mosaic_survivesTheStore() async throws {
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟥", "", "", "🟦"])!
        let message = Message(text: mosaic.text, mosaic: mosaic,
                              peerAddress: "bob", isFromMe: true, status: .sent)

        try await store.saveMessage(message)
        let loaded = try await store.loadMessages(with: "bob")
        let restored = try #require(loaded.first)

        #expect(restored.mosaic == mosaic)
        #expect(restored.text == mosaic.text)
    }

    @Test func markAsRead_touchesOnlyIncomingInThatConversation() async throws {
        try await store.saveMessage(Message(text: "от Кэрол", peerAddress: "carol", isFromMe: false, status: .sent, isRead: false))
        try await store.saveMessage(Message(text: "от Боба", peerAddress: "bob", isFromMe: false, status: .sent, isRead: false))
        try await store.saveMessage(Message(text: "Кэрол от меня", peerAddress: "carol", isFromMe: true, status: .sent, isRead: false))

        try await store.markAsRead(with: "carol")
        let all = try await store.loadMessages()

        #expect(all.first { $0.text == "от Кэрол" }?.isRead == true)
        #expect(all.first { $0.text == "от Боба" }?.isRead == false, "Чужая переписка не трогается")
        #expect(all.filter(\.isUnread).count == 1)
    }

    @Test func reactions_areStoredAndUpdated() async throws {
        var message = Message(text: "привет", peerAddress: "bob", isFromMe: true, status: .sent)
        try await store.saveMessage(message)

        message.myReaction = "❤️"
        message.peerReaction = "👍"
        try await store.saveMessage(message)

        let loaded = try await store.loadMessages(with: "bob")
        #expect(loaded.count == 1)
        #expect(loaded.first?.myReaction == "❤️")
        #expect(loaded.first?.peerReaction == "👍")
    }

    @Test func plainMessage_loadsWithoutMosaic() async throws {
        try await store.saveMessage(CoreDataTestStack.message("текст", isFromMe: true, status: .sent))
        let loaded = try await store.loadMessages()
        let restored = try #require(loaded.first)

        #expect(restored.mosaic == nil)
    }

    @Test func loadMessages_returnsEmptyArrayOnFreshStore() async throws {
        let loaded = try await store.loadMessages()
        
        #expect(loaded.isEmpty)
    }
    
    // MARK: - Upsert по id
    
    /// Главный сценарий продакшна: сообщение сохраняется дважды —
    /// сперва со статусом `.sending`, потом с `.sent` (или `.failed`).
    /// Дубля быть не должно, статус должен обновиться.
    @Test func savingSameMessageTwice_updatesStatusWithoutDuplicating() async throws {
        var message = CoreDataTestStack.message("отправляется", isFromMe: true, status: .sending)
        try await store.saveMessage(message)
        
        message.status = .sent
        try await store.saveMessage(message)
        
        let loaded = try await store.loadMessages()
        #expect(loaded.count == 1, "Повторное сохранение не должно создавать дубль")
        #expect(loaded.first?.status == .sent)
    }
    
    /// Обратная сторона upsert-а: при повторном сохранении обновляется
    /// ТОЛЬКО статус. Текст остаётся исходным — сообщения неизменяемы.
    @Test func savingSameId_withDifferentText_keepsOriginalText() async throws {
        let original = CoreDataTestStack.message("оригинал", isFromMe: true, status: .sending)
        try await store.saveMessage(original)
        
        let edited = Message(id: original.id,
                             text: "подменённый текст",
                             senderName: original.senderName,
                             isFromMe: original.isFromMe,
                             timestamp: original.timestamp,
                             status: .sent)
        try await store.saveMessage(edited)
        
        let loaded = try await store.loadMessages()
        #expect(loaded.count == 1)
        #expect(loaded.first?.text == "оригинал")
    }
    
    // MARK: - Сортировка
    
    @Test func loadMessages_sortsByTimestampAscending() async throws {
        try await store.saveMessage(CoreDataTestStack.message("третье", daysAgo: 0))
        try await store.saveMessage(CoreDataTestStack.message("первое", daysAgo: 5))
        try await store.saveMessage(CoreDataTestStack.message("второе", daysAgo: 2))
        
        let texts = try await store.loadMessages().map(\.text)
        
        #expect(texts == ["первое", "второе", "третье"])
    }
    
    // MARK: - Удаление по возрасту
    
    @Test func deleteOldMessages_removesOnlyThoseBeyondCutoff() async throws {
        try await store.saveMessage(CoreDataTestStack.message("старое", daysAgo: 30))
        try await store.saveMessage(CoreDataTestStack.message("на границе", daysAgo: 8))
        try await store.saveMessage(CoreDataTestStack.message("свежее", daysAgo: 1))
        
        try await store.deleteOldMessages(olderThan: 7)
        
        let texts = try await store.loadMessages().map(\.text)
        #expect(texts.sorted() == ["свежее"])
    }
    
    // MARK: - clearAll
    
    /// `clearAll` использует NSBatchDeleteRequest — он идёт напрямую в стор,
    /// МИМО viewContext. Тест проверяет, что последующее чтение всё-таки
    /// видит пустую базу (fetch перечитывает стор, поэтому видит).
    /// Если бы код держал объекты в памяти контекста — здесь был бы баг.
    @Test func clearAll_removesEverything() async throws {
        try await store.saveMessage(CoreDataTestStack.message("a", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("b", isFromMe: true))
        
        try await store.clearAll()
        
        let loaded = try await store.loadMessages()
        #expect(loaded.isEmpty)
    }
    
    // MARK: - Статистика
    
    @Test func getMessageStats_countsTotalsAndPerSender() async throws {
        try await store.saveMessage(CoreDataTestStack.message("1", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("2", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("3", from: "Bob"))
        try await store.saveMessage(CoreDataTestStack.message("4", isFromMe: true))
        
        let stats = try await store.getMessageStats()
        
        #expect(stats["total"] == 4)
        #expect(stats["fromMe"] == 1)
        #expect(stats["received"] == 3)
        #expect(stats["Alice"] == 2)
        #expect(stats["Bob"] == 1)
    }
    
    // MARK: - Фильтрация по собеседнику
    
    @Test func loadMessagesWithPeer_includesIncomingFromThatPeerOnly() async throws {
        try await store.saveMessage(CoreDataTestStack.message("от Алисы", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("от Боба", from: "Bob"))
        
        let alice = try await store.loadMessages(with: "Alice").map(\.text)
        
        #expect(alice == ["от Алисы"])
    }
    
    /// Раньше выборка была «всё моё плюс входящее с таким именем», и своя
    /// половина переписки была общей для всех чатов.
    @Test func loadMessagesWithPeer_keepsOutgoingInTheirOwnConversation() async throws {
        try await store.saveMessage(
            CoreDataTestStack.message("привет, Боб", peer: "Bob", isFromMe: true))
        try await store.saveMessage(CoreDataTestStack.message("ответ Боба", from: "Bob"))
        try await store.saveMessage(
            CoreDataTestStack.message("привет, Алиса", peer: "Alice", isFromMe: true))

        let withBob = try await store.loadMessages(with: "Bob").map(\.text)
        let withAlice = try await store.loadMessages(with: "Alice").map(\.text)

        #expect(withBob == ["привет, Боб", "ответ Боба"])
        #expect(withAlice == ["привет, Алиса"])
    }

    /// Удаление диалога раньше убирало только входящие: свои реплики
    /// оставались в базе навсегда, ни к чему не привязанные.
    @Test func deleteConversation_removesBothHalves() async throws {
        try await store.saveMessage(
            CoreDataTestStack.message("мой вопрос", peer: "Bob", isFromMe: true))
        try await store.saveMessage(CoreDataTestStack.message("ответ Боба", from: "Bob"))
        try await store.saveMessage(
            CoreDataTestStack.message("вопрос Алисе", peer: "Alice", isFromMe: true))

        try await store.deleteConverstaion(with: "Bob")

        let remaining = try await store.loadMessages().map(\.text)
        #expect(remaining == ["вопрос Алисе"])
    }

    /// Тёзка — другой человек, и переписка с ним отдельная.
    @Test func loadMessagesWithPeer_keepsNamesakesApart() async throws {
        try await store.saveMessage(
            CoreDataTestStack.message("от первого", from: "Bob", peer: "a1b2"))
        try await store.saveMessage(
            CoreDataTestStack.message("от второго", from: "Bob", peer: "c3d4"))

        let first = try await store.loadMessages(with: "a1b2").map(\.text)

        #expect(first == ["от первого"], "Раскладка по имени слила бы двух Бобов в одну переписку")
    }
}
