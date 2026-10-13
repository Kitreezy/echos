//
//  SpyMessageStore.swift
//  echosTests
//
//  Хранилище-шпион: запоминает порядок записей, не трогая Core Data.
//

import Foundation
@testable import echos

@MainActor
final class SpyMessageStore: MessageStoring {

    private(set) var saved: [Message] = []

    var savedTexts: [String] {
        saved.map(\.text)
    }

    func saveMessage(_ message: Message) async throws {
        saved.append(message)
    }

    func loadMessages() async throws -> [Message] {
        saved
    }

    func loadMessages(with peerName: String) async throws -> [Message] {
        saved.filter { $0.senderName == peerName }
    }

    private(set) var markedAsRead: [String] = []

    func markAsRead(with address: String) async throws {
        markedAsRead.append(address)
        saved = saved.map { message in
            guard message.peerAddress == address, !message.isFromMe else {
                return message
            }
            var read = message
            read.isRead = true
            return read
        }
    }

    func deleteOldMessages(olderThan days: Int) async throws {}

    func deleteConverstaion(with peerName: String) async throws {
        saved.removeAll { $0.senderName == peerName }
    }

    func clearAll() async throws {
        saved.removeAll()
    }

    func getMessageStats() async throws -> [String: Int] {
        ["total": saved.count]
    }
}
