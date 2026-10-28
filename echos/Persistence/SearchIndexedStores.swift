//
//  SearchIndexedStores.swift
//  echos
//
//  Хранилища, которые держат системный поиск в согласии с историей.
//
//  Обёртки, а не вызовы индекса из `ChatViewModel`: сообщение сохраняется и
//  удаляется в нескольких местах, и про поиск в одном из них рано или
//  поздно забыли бы. Удалённая переписка, которая продолжает находиться
//  поиском, — утечка, а не мелкая неточность. Здесь мимо индекса в
//  хранилище не попасть.
//

import Foundation

@MainActor
final class SearchIndexedMessageStore: MessageStoring {

    private let store: any MessageStoring
    private let index: any SearchIndexing

    init(_ store: any MessageStoring, index: any SearchIndexing) {
        self.store = store
        self.index = index
    }

    func saveMessage(_ message: Message) async throws {
        try await store.saveMessage(message)
        await index.index(message)
    }

    func containsMessage(id: UUID) async throws -> Bool {
        try await store.containsMessage(id: id)
    }

    func loadMessages() async throws -> [Message] {
        try await store.loadMessages()
    }

    func loadMessages(with address: String) async throws -> [Message] {
        try await store.loadMessages(with: address)
    }

    func markAsRead(with address: String) async throws {
        try await store.markAsRead(with: address)
    }

    /// Хранилище не говорит, что именно удалило, — разница видна по тому,
    /// что было до и что осталось после.
    func deleteOldMessages(olderThan days: Int) async throws {
        let before = try await store.loadMessages()
        try await store.deleteOldMessages(olderThan: days)
        let kept = Set(try await store.loadMessages().map(\.id))
        await index.remove(before.filter { !kept.contains($0.id) })
    }

    func deleteConverstaion(with address: String) async throws {
        try await store.deleteConverstaion(with: address)
        await index.removeConversation(with: address)
    }

    func clearAll() async throws {
        try await store.clearAll()
        await index.removeAll()
    }

    func getMessageStats() async throws -> [String: Int] {
        try await store.getMessageStats()
    }
}

@MainActor
final class SearchIndexedKnownPeerStore: KnownPeerStoring {

    private let store: any KnownPeerStoring
    private let index: any SearchIndexing

    init(_ store: any KnownPeerStoring, index: any SearchIndexing) {
        self.store = store
        self.index = index
    }

    func loadKnownPeers() async throws -> [KnownPeer] {
        try await store.loadKnownPeers()
    }

    func remember(address: String, name: String) async throws {
        try await store.remember(address: address, name: name)
        await index.remember(name: name, for: address)
    }

    /// Забыть всех — значит и из поиска. Переписка при этом остаётся в
    /// истории, а значит, и в поиске: её стирает «Очистить всю историю».
    func forgetAll() async throws {
        let known = try await store.loadKnownPeers()
        try await store.forgetAll()
        for peer in known {
            await index.forget(address: peer.address)
        }
    }
}
