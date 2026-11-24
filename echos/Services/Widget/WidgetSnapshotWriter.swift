//
//  WidgetSnapshotWriter.swift
//  echos
//
//  Снапшот последних чатов для виджета. Приложение пишет маленький JSON
//  в общий контейнер App Groups; виджет читает его, когда система строит
//  временную шкалу. Формат файла — договорённость с echosWidget/Snapshot.swift:
//  менять только вместе.
//

import Foundation
import OSLog
import WidgetKit

/// Один разговор для виджета. Зеркало WidgetChat в таргете виджета.
struct WidgetChatSnapshot: Codable, Equatable {
    let address: String
    let peerName: String
    let preview: String
    let timestamp: TimeInterval
    let unreadCount: Int
}

/// Снапшот целиком. Зеркало WidgetChatsSnapshot в таргете виджета.
struct WidgetChatsSnapshot: Codable, Equatable {
    let generatedAt: TimeInterval
    let conversations: [WidgetChatSnapshot]
}

@MainActor
enum WidgetSnapshotWriter {

    static let groupIdentifier = "group.com.kitreezy.echos"
    static let fileName = "recent-chats.json"
    static let widgetKind = "RecentChats"

    /// Общий контейнер приложения и виджета. Без App Groups (для них нужна
    /// платная учётка разработчика) контейнера нет: тогда виджет живёт с
    /// заглушкой, и это честнее, чем притворяться. Проект уже носит
    /// entitlement — в симуляторе всё работает полностью.
    static var containerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// Сколько разговоров влезает в самый большой поддерживаемый виджет.
    private static let visibleLimit = 4

    /// Переписать снапшот и попросить виджет перестроить шкалу.
    /// Дёшево (пара килобайт), но вызывается часто — дёргают с дебаунсом.
    static func update(with conversations: [ConversationSummary]) {
        guard let container = containerURL else {
            return
        }

        let snapshot = WidgetChatsSnapshot(
            generatedAt: Date().timeIntervalSince1970,
            conversations: conversations.prefix(visibleLimit).map(makeEntry)
        )
        let url = container.appendingPathComponent(fileName)

        do {
            let data = try JSONEncoder().encode(snapshot)
            // .atomic: виджет никогда не читает половину файла.
            try data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        } catch {
            Logger.lifecycle.error("Widget snapshot write failed: \(error, privacy: .public)")
        }
    }

    private static func makeEntry(from conversation: ConversationSummary) -> WidgetChatSnapshot {
        let preview: String
        if conversation.lastMessageIsMosaic {
            // Как в Spotlight: сетка эмодзи на виджете — строка квадратиков.
            preview = String(localized: "Мозаика")
        } else {
            preview = conversation.lastMessage
        }
        return WidgetChatSnapshot(
            address: conversation.peerAddress,
            peerName: conversation.peerName,
            preview: preview,
            timestamp: conversation.lastMessageTime.timeIntervalSince1970,
            unreadCount: conversation.unreadCount
        )
    }
}
