//
//  Snapshot.swift
//  echosWidget
//
//  Снапшот последних чатов, который приложение кладёт в общий контейнер.
//  Виджет — отдельный таргет без доступа к модулю приложения, поэтому
//  модель здесь повторена; формат файла — единственная договорённость
//  между ними. Ломать его можно только вместе с
//  WidgetSnapshotWriter в приложении.
//

import Foundation

/// Один разговор для виджета.
struct WidgetChat: Codable, Hashable {
    /// Адрес собеседника: по нему строится ссылка echos://chat/<адрес>.
    let address: String
    let peerName: String
    let preview: String
    let timestamp: TimeInterval
    let unreadCount: Int

    /// Ссылка, которую открывает тап по виджету. Приложение само решает,
    /// что с ней делать (см. DeepLink и AppCoordinator).
    var deepLink: URL {
        URL(string: "echos://chat/\(address)")!
    }
}

/// Снапшот целиком: одна запись, один файл.
struct WidgetChatsSnapshot: Codable {
    let generatedAt: TimeInterval
    let conversations: [WidgetChat]
}

enum WidgetSnapshotLoader {

    static let groupIdentifier = "group.com.kitreezy.echos"
    static let fileName = "recent-chats.json"

    /// Что показать. `nil` — файла нет (приложение не писало или группа
    /// недоступна): виджет честно показывает пустое состояние, а не
    /// воображает данные.
    static func load() -> [WidgetChat]? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            return nil
        }
        let url = container.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetChatsSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.conversations
    }

    /// Данные для плейсхолдера на этапе предпросмотра в галерее виджетов.
    static let samples: [WidgetChat] = [
        WidgetChat(address: "demo-a", peerName: "Боб",
                   preview: "Встречаемся у главной сцены в семь", timestamp: Date().timeIntervalSince1970,
                   unreadCount: 2),
        WidgetChat(address: "demo-b", peerName: "Аня",
                   preview: "Мозаика", timestamp: Date().timeIntervalSince1970 - 900,
                   unreadCount: 0)
    ]
}
