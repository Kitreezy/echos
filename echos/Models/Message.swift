//
//  Message.swift
//  echos
//
//  Created by Artem Rodionov on 17.02.2026.
//

import Foundation

enum MessageStatus: Int, Codable {
    case sending = 0
    case sent = 1
    case failed = 2
}

struct Message: Identifiable, Equatable {
    let id: UUID
    /// Текст — для обычного сообщения он и есть содержимое, для мозаики —
    /// её текстовая форма: превью, старые сборки, копирование наружу.
    let text: String
    /// Точная форма, если это мозаика. Рисуется сеткой, а не текстом.
    let mosaic: Mosaic?
    /// Имя отправителя — для показа в бабблах. Заполняет его сам отправитель,
    /// поэтому раскладывать по нему переписку нельзя: для этого есть адрес.
    let senderName: String?
    /// Чья это переписка: адрес собеседника, независимо от направления.
    let peerAddress: String?
    let isFromMe: Bool
    let timestamp: Date
    var status: MessageStatus
    /// Прочитано ли. Своё — всегда; входящее — если пришло в открытый чат
    /// или чат потом открыли. Ради этого и считается непрочитанное.
    var isRead: Bool
    
    init(id: UUID = UUID(),
         text: String,
         mosaic: Mosaic? = nil,
         senderName: String? = nil,
         peerAddress: String? = nil,
         isFromMe: Bool,
         timestamp: Date = Date(),
         status: MessageStatus = .sending,
         isRead: Bool = true
    ) {
        self.id = id
        self.text = text
        self.mosaic = mosaic
        self.senderName = senderName
        self.peerAddress = peerAddress
        self.isFromMe = isFromMe
        self.timestamp = timestamp
        self.status = status
        self.isRead = isRead
    }

    var isUnread: Bool {
        !isFromMe && !isRead
    }

    /// Копия с проставленной перепиской.
    func inConversation(with address: String) -> Message {
        Message(id: id,
                text: text,
                mosaic: mosaic,
                senderName: senderName,
                peerAddress: address,
                isFromMe: isFromMe,
                timestamp: timestamp,
                status: status,
                isRead: isRead)
    }
}

/// Формат для сериализации при отправке через Multipeer
struct MessagePayload: Codable {
    let id: String          // UUID.uuidString
    let text: String
    let senderName: String
    let timestamp: Double   // Date().timeIntervalSince1970
    /// Мозаика, если это она. Необязательна: у обычного сообщения её нет,
    /// а старая сборка, не знающая о мозаике, увидит текстовую форму.
    let mosaic: Mosaic?
    
    init(from message: Message, senderName: String) {
        self.id = message.id.uuidString
        self.text = message.text
        self.senderName = senderName
        self.timestamp = message.timestamp.timeIntervalSince1970
        self.mosaic = message.mosaic
    }
    
    /// Конвертация обратно в Message (входящее — isFromMe = false).
    ///
    /// Адрес отправителя приходит снаружи, от транспорта: `senderName` внутри
    /// payload пишет сам отправитель, и верить ему нельзя.
    func toMessage(from sender: String) -> Message {
        // Сетка снаружи может быть какой угодно: не сошлась — остаётся
        // текстовая форма, она есть всегда.
        let mosaic = mosaic.flatMap { $0.isValid ? $0 : nil }

        return Message(
            id: UUID(uuidString: id) ?? UUID(),
            text: text,
            mosaic: mosaic,
            senderName: senderName,
            peerAddress: sender,
            isFromMe: false,
            timestamp: Date(timeIntervalSince1970: timestamp),
            status: .sent
        )
    }
}
