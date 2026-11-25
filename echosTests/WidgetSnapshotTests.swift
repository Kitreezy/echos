//
//  WidgetSnapshotTests.swift
//  echosTests
//
//  Unit: снапшот для виджета — формат файла кодируется и декодируется,
//  разговоры превращаются в записи без потерь. Договор с echosWidget —
//  единственный, кто читает файл, поэтому ломать формат нельзя молча.
//

import Foundation
import Testing
@testable import echos

struct WidgetSnapshotTests {

    @Test func snapshot_roundTripsThroughJSON() throws {
        let snapshot = WidgetChatsSnapshot(
            generatedAt: 1_723_000_000,
            conversations: [
                WidgetChatSnapshot(address: "deadbeef01",
                                   peerName: "Боб",
                                   preview: "Привет!",
                                   timestamp: 1_723_000_000,
                                   unreadCount: 2)
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(WidgetChatsSnapshot.self, from: data)

        #expect(restored == snapshot)
    }

    @Test func conversation_becomesEntry() {
        var mosaic = ConversationSummary(peerAddress: "aaa111",
                                         peerName: "Аня",
                                         lastMessage: "🟨⬜\n⬜🟨",
                                         lastMessageTime: Date(timeIntervalSince1970: 1_723_000_000),
                                         messageCount: 3,
                                         unreadCount: 0,
                                         isActive: true)
        mosaic.lastMessageIsMosaic = true
        let text = ConversationSummary(peerAddress: "bbb222",
                                       peerName: "Боб",
                                       lastMessage: "До встречи",
                                       lastMessageTime: Date(timeIntervalSince1970: 1_723_000_100),
                                       messageCount: 5,
                                       unreadCount: 2,
                                       isActive: false)

        let entries = [mosaic, text].map(entry(from:))

        #expect(entries[0].preview == "Мозаика",
                "Мозаика для виджета — слово, а не сетка эмодзи")
        #expect(entries[0].unreadCount == 0)
        #expect(entries[1].preview == "До встречи")
        #expect(entries[1].unreadCount == 2)
        #expect(entries[1].timestamp == 1_723_000_100)
    }

    private func entry(from conversation: ConversationSummary) -> WidgetChatSnapshot {
        let preview: String
        if conversation.lastMessageIsMosaic {
            preview = String(localized: "Мозаика")
        } else {
            preview = conversation.lastMessage
        }
        return WidgetChatSnapshot(address: conversation.peerAddress,
                                  peerName: conversation.peerName,
                                  preview: preview,
                                  timestamp: conversation.lastMessageTime.timeIntervalSince1970,
                                  unreadCount: conversation.unreadCount)
    }
}
