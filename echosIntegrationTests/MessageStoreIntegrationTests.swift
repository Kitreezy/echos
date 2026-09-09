//
//  MessageStoreIntegrationTests.swift
//  echosIntegrationTests
//
//  Интеграция: MessageStore + реальный Core Data стек.
//

import XCTest
import CoreData
@testable import echos

@MainActor
final class MessageStoreIntegrationTests: XCTestCase {
    
    private var stack: PersistenceController!
    private var store: MessageStore!
    
    override func setUp() async throws {
        try await super.setUp()
        stack = CoreDataTestStack.makeInMemory()
        store = MessageStore(context: stack.container.viewContext)
    }
    
    override func tearDown() async throws {
        store = nil
        stack = nil
        try await super.tearDown()
    }
    
    // MARK: - Save / Load round-trip
    
    func test_saveMessage_thenLoad_preservesAllFields() async throws {
        let message = CoreDataTestStack.message("привет из теста",
                                                from: "Alice",
                                                isFromMe: false,
                                                status: .sent)
        
        try await store.saveMessage(message)
        let loaded = try await store.loadMessages()
        
        XCTAssertEqual(loaded.count, 1)
        let restored = try XCTUnwrap(loaded.first)
        XCTAssertEqual(restored.id, message.id)
        XCTAssertEqual(restored.text, "привет из теста")
        XCTAssertEqual(restored.senderName, "Alice")
        XCTAssertEqual(restored.isFromMe, false)
        XCTAssertEqual(restored.status, .sent)
        XCTAssertEqual(restored.timestamp.timeIntervalSince1970,
                       message.timestamp.timeIntervalSince1970,
                       accuracy: 0.001)
    }
    
    func test_loadMessages_returnsEmptyArrayOnFreshStore() async throws {
        let loaded = try await store.loadMessages()
        
        XCTAssertTrue(loaded.isEmpty)
    }
    
    // MARK: - Upsert по id
    
    /// Главный сценарий продакшна: сообщение сохраняется дважды —
    /// сперва со статусом `.sending`, потом с `.sent` (или `.failed`).
    /// Дубля быть не должно, статус должен обновиться.
    func test_savingSameMessageTwice_updatesStatusWithoutDuplicating() async throws {
        var message = CoreDataTestStack.message("отправляется", isFromMe: true, status: .sending)
        try await store.saveMessage(message)
        
        message.status = .sent
        try await store.saveMessage(message)
        
        let loaded = try await store.loadMessages()
        XCTAssertEqual(loaded.count, 1, "Повторное сохранение не должно создавать дубль")
        XCTAssertEqual(loaded.first?.status, .sent)
    }
    
    /// Обратная сторона upsert-а: при повторном сохранении обновляется
    /// ТОЛЬКО статус. Текст остаётся исходным — сообщения неизменяемы.
    func test_savingSameId_withDifferentText_keepsOriginalText() async throws {
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
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.text, "оригинал")
    }
    
    // MARK: - Сортировка
    
    func test_loadMessages_sortsByTimestampAscending() async throws {
        try await store.saveMessage(CoreDataTestStack.message("третье", daysAgo: 0))
        try await store.saveMessage(CoreDataTestStack.message("первое", daysAgo: 5))
        try await store.saveMessage(CoreDataTestStack.message("второе", daysAgo: 2))
        
        let texts = try await store.loadMessages().map(\.text)
        
        XCTAssertEqual(texts, ["первое", "второе", "третье"])
    }
    
    // MARK: - Удаление по возрасту
    
    func test_deleteOldMessages_removesOnlyThoseBeyondCutoff() async throws {
        try await store.saveMessage(CoreDataTestStack.message("старое", daysAgo: 30))
        try await store.saveMessage(CoreDataTestStack.message("на границе", daysAgo: 8))
        try await store.saveMessage(CoreDataTestStack.message("свежее", daysAgo: 1))
        
        try await store.deleteOldMessages(olderThan: 7)
        
        let texts = try await store.loadMessages().map(\.text)
        XCTAssertEqual(texts.sorted(), ["свежее"])
    }
    
    // MARK: - clearAll
    
    /// `clearAll` использует NSBatchDeleteRequest — он идёт напрямую в стор,
    /// МИМО viewContext. Тест проверяет, что последующее чтение всё-таки
    /// видит пустую базу (fetch перечитывает стор, поэтому видит).
    /// Если бы код держал объекты в памяти контекста — здесь был бы баг.
    func test_clearAll_removesEverything() async throws {
        try await store.saveMessage(CoreDataTestStack.message("a", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("b", isFromMe: true))
        
        try await store.clearAll()
        
        let loaded = try await store.loadMessages()
        XCTAssertTrue(loaded.isEmpty)
    }
    
    // MARK: - Статистика
    
    func test_getMessageStats_countsTotalsAndPerSender() async throws {
        try await store.saveMessage(CoreDataTestStack.message("1", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("2", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("3", from: "Bob"))
        try await store.saveMessage(CoreDataTestStack.message("4", isFromMe: true))
        
        let stats = try await store.getMessageStats()
        
        XCTAssertEqual(stats["total"], 4)
        XCTAssertEqual(stats["fromMe"], 1)
        XCTAssertEqual(stats["received"], 3)
        XCTAssertEqual(stats["Alice"], 2)
        XCTAssertEqual(stats["Bob"], 1)
    }
    
    // MARK: - Фильтрация по собеседнику
    
    func test_loadMessagesWithPeer_includesIncomingFromThatPeerOnly() async throws {
        try await store.saveMessage(CoreDataTestStack.message("от Алисы", from: "Alice"))
        try await store.saveMessage(CoreDataTestStack.message("от Боба", from: "Bob"))
        
        let alice = try await store.loadMessages(with: "Alice").map(\.text)
        
        XCTAssertEqual(alice, ["от Алисы"])
    }
    
    /// Раньше выборка была «всё моё плюс входящее с таким именем», и своя
    /// половина переписки была общей для всех чатов.
    func test_loadMessagesWithPeer_keepsOutgoingInTheirOwnConversation() async throws {
        try await store.saveMessage(
            CoreDataTestStack.message("привет, Боб", peer: "Bob", isFromMe: true))
        try await store.saveMessage(CoreDataTestStack.message("ответ Боба", from: "Bob"))
        try await store.saveMessage(
            CoreDataTestStack.message("привет, Алиса", peer: "Alice", isFromMe: true))

        let withBob = try await store.loadMessages(with: "Bob").map(\.text)
        let withAlice = try await store.loadMessages(with: "Alice").map(\.text)

        XCTAssertEqual(withBob, ["привет, Боб", "ответ Боба"])
        XCTAssertEqual(withAlice, ["привет, Алиса"])
    }

    /// Удаление диалога раньше убирало только входящие: свои реплики
    /// оставались в базе навсегда, ни к чему не привязанные.
    func test_deleteConversation_removesBothHalves() async throws {
        try await store.saveMessage(
            CoreDataTestStack.message("мой вопрос", peer: "Bob", isFromMe: true))
        try await store.saveMessage(CoreDataTestStack.message("ответ Боба", from: "Bob"))
        try await store.saveMessage(
            CoreDataTestStack.message("вопрос Алисе", peer: "Alice", isFromMe: true))

        try await store.deleteConverstaion(with: "Bob")

        let remaining = try await store.loadMessages().map(\.text)
        XCTAssertEqual(remaining, ["вопрос Алисе"])
    }

    /// Тёзка — другой человек, и переписка с ним отдельная.
    func test_loadMessagesWithPeer_keepsNamesakesApart() async throws {
        try await store.saveMessage(
            CoreDataTestStack.message("от первого", from: "Bob", peer: "a1b2"))
        try await store.saveMessage(
            CoreDataTestStack.message("от второго", from: "Bob", peer: "c3d4"))

        let first = try await store.loadMessages(with: "a1b2").map(\.text)

        XCTAssertEqual(first, ["от первого"],
                       "Раскладка по имени слила бы двух Бобов в одну переписку")
    }
}
