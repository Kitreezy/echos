//
//  SpotlightTests.swift
//  echosTests
//
//  Системный поиск: что попадает в индекс, как по нажатию найти чат и что
//  удалённое из истории пропадает и из поиска.
//

import CoreSpotlight
import Foundation
import Testing
@testable import echos

@MainActor
struct SpotlightTests {

    // MARK: - Идентификаторы

    @Test(arguments: [
        SpotlightItems.Target.conversation(address: "a1b2c3"),
        .message(id: UUID(), address: "a1b2c3"),
        // У Multipeer адрес — имя устройства, двоеточие в нём возможно.
        .message(id: UUID(), address: "iPhone: Боб"),
        .conversation(address: "iPhone: Боб")
    ])
    func identifier_roundTrips(_ target: SpotlightItems.Target) {
        #expect(SpotlightItems.target(from: SpotlightItems.identifier(for: target)) == target)
    }

    @Test(arguments: ["", "person:", "message:", "message:not-a-uuid:bob",
                      "message:\(UUID().uuidString)", "message:\(UUID().uuidString):", "other:bob"])
    func foreignIdentifier_opensNothing(_ identifier: String) {
        #expect(SpotlightItems.target(from: identifier) == nil)
    }

    // MARK: - Записи

    @Test func incomingMessage_isTitledWithSender() throws {
        let message = Message(text: "встречаемся в семь", senderName: "Боб",
                              peerAddress: "bob", isFromMe: false, status: .sent)

        let item = try #require(SpotlightItems.message(message, peerName: nil))

        #expect(item.attributeSet.title == "Боб")
        #expect(item.attributeSet.textContent == "встречаемся в семь")
        #expect(item.domainIdentifier == SpotlightItems.domain(of: "bob"))
        #expect(item.expirationDate == .distantFuture, "Иначе через месяц пропадёт из поиска")
    }

    @Test func ownMessage_isTitledWithRecipient() throws {
        let message = Message(text: "ок", senderName: nil, peerAddress: "bob", isFromMe: true, status: .sent)

        let item = try #require(SpotlightItems.message(message, peerName: "Боб"))

        #expect(item.attributeSet.title == "Вы → Боб")
    }

    @Test func mosaic_isSearchableByWordNotBySquares() throws {
        let mosaic = try #require(Mosaic(columns: 2, rows: 1, cells: ["🟥", "🟦"]))
        let message = Message(text: mosaic.text, mosaic: mosaic, peerAddress: "bob", isFromMe: true, status: .sent)

        let item = try #require(SpotlightItems.message(message, peerName: "Боб"))

        #expect(item.attributeSet.textContent == "Мозаика")
    }

    @Test func messageWithoutConversation_isNotIndexed() {
        let message = Message(text: "куда?", peerAddress: nil, isFromMe: true, status: .sent)
        #expect(SpotlightItems.message(message, peerName: nil) == nil)
    }

    // MARK: - Хранилища за индексом

    @Test func savedMessage_isIndexed() async throws {
        let index = SpySearchIndex()
        let store = SearchIndexedMessageStore(SpyMessageStore(), index: index)
        let message = Message(text: "привет", peerAddress: "bob", isFromMe: true, status: .sent)

        try await store.saveMessage(message)

        #expect(index.indexed == [message.id])
    }

    @Test func deletedConversation_leavesSearch() async throws {
        let index = SpySearchIndex()
        let store = SearchIndexedMessageStore(SpyMessageStore(), index: index)

        try await store.deleteConverstaion(with: "bob")
        try await store.clearAll()

        #expect(index.removedConversations == ["bob"])
        #expect(index.removedAll == 1)
    }

    @Test func oldMessages_leaveSearchOneByOne() async throws {
        let index = SpySearchIndex()
        let spy = SpyMessageStore()
        let store = SearchIndexedMessageStore(spy, index: index)
        let old = Message(text: "давно", peerAddress: "bob", isFromMe: true,
                          timestamp: Date().addingTimeInterval(-40 * 86_400), status: .sent)
        let fresh = Message(text: "сейчас", peerAddress: "bob", isFromMe: true, status: .sent)
        try await store.saveMessage(old)
        try await store.saveMessage(fresh)

        try await store.deleteOldMessages(olderThan: 30)

        #expect(index.removed == [old.id], "Удаляется ровно то, что ушло из истории")
    }

    @Test func rememberedPeer_isFoundByName_andForgotten() async throws {
        let index = SpySearchIndex()
        let people = SearchIndexedKnownPeerStore(SpyKnownPeerStore(), index: index)

        try await people.remember(address: "bob", name: "Боб")
        try await people.forgetAll()

        #expect(index.names == ["bob": "Боб"])
        #expect(index.forgotten == ["bob"])
    }
}

@MainActor
private final class SpySearchIndex: SearchIndexing {
    private(set) var indexed: [UUID] = []
    private(set) var names: [String: String] = [:]
    private(set) var forgotten: [String] = []
    private(set) var removed: [UUID] = []
    private(set) var removedConversations: [String] = []
    private(set) var removedAll = 0

    func index(_ message: Message) async { indexed.append(message.id) }
    func remember(name: String, for address: String) async { names[address] = name }
    func forget(address: String) async { forgotten.append(address) }
    func remove(_ messages: [Message]) async { removed += messages.map(\.id) }
    func removeConversation(with address: String) async { removedConversations.append(address) }
    func removeAll() async { removedAll += 1 }
}
