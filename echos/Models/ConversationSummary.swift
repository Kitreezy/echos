//
//  ConversationSummary.swift
//  echos
//
//  Created by Artem Rodionov on 27.02.2026.
//

import Foundation

/// Строка списка разговоров.
///
/// Идентичность — адрес: модель пересобирается на каждое обновление
/// списка, и случайный UUID на каждую копию заставлял бы diffable data
/// source каждый раз удалять и вставлять все строки. Равенство — по
/// содержимому: изменившаяся строка — то же самое место с новым
/// содержимым, и оно перерисовывается на месте.
struct ConversationSummary: Identifiable, Hashable {
    /// Стабильный идентификатор для diffable data source.
    var id: String { peerAddress }
    /// Адрес собеседника — по нему открывается чат.
    let peerAddress: String
    /// Имя для показа. Может повторяться и меняться, адресовать по нему нельзя.
    let peerName: String
    let lastMessage: String
    /// Последнее — мозаика. Текстовая форма у неё — сетка эмодзи: на экране
    /// это рисунок, а VoiceOver прочитал бы её знак за знаком.
    var lastMessageIsMosaic = false
    let lastMessageTime: Date
    let messageCount: Int
    let unreadCount: Int
    let isActive: Bool

    static func == (lhs: ConversationSummary, rhs: ConversationSummary) -> Bool {
        lhs.peerAddress == rhs.peerAddress
            && lhs.peerName == rhs.peerName
            && lhs.lastMessage == rhs.lastMessage
            && lhs.lastMessageIsMosaic == rhs.lastMessageIsMosaic
            && lhs.lastMessageTime == rhs.lastMessageTime
            && lhs.messageCount == rhs.messageCount
            && lhs.unreadCount == rhs.unreadCount
            && lhs.isActive == rhs.isActive
    }

    func hash(into hasher: inout Hasher) {
        // Только идентичность: содержимое — дело равенства, не хэша.
        hasher.combine(peerAddress)
    }
}
