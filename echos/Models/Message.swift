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
    let text: String
    /// Имя отправителя — для показа в бабблах. Заполняет его сам отправитель,
    /// поэтому раскладывать по нему переписку нельзя: для этого есть адрес.
    let senderName: String?
    /// Чья это переписка: адрес собеседника, независимо от направления.
    let peerAddress: String?
    let isFromMe: Bool
    let timestamp: Date
    var status: MessageStatus
    
    init(id: UUID = UUID(),
         text: String,
         senderName: String? = nil,
         peerAddress: String? = nil,
         isFromMe: Bool,
         timestamp: Date = Date(),
         status: MessageStatus = .sending
    ) {
        self.id = id
        self.text = text
        self.senderName = senderName
        self.peerAddress = peerAddress
        self.isFromMe = isFromMe
        self.timestamp = timestamp
        self.status = status
    }

    /// Копия с проставленной перепиской.
    func inConversation(with address: String) -> Message {
        Message(id: id,
                text: text,
                senderName: senderName,
                peerAddress: address,
                isFromMe: isFromMe,
                timestamp: timestamp,
                status: status)
    }
}

/// Формат для сериализации при отправке через Multipeer
struct MessagePayload: Codable {
    let id: String          // UUID.uuidString
    let text: String
    let senderName: String
    let timestamp: Double   // Date().timeIntervalSince1970
    
    init(from message: Message, senderName: String) {
        self.id = message.id.uuidString
        self.text = message.text
        self.senderName = senderName
        self.timestamp = message.timestamp.timeIntervalSince1970
    }
    
    /// Конвертация обратно в Message (входящее — isFromMe = false).
    ///
    /// Адрес отправителя приходит снаружи, от транспорта: `senderName` внутри
    /// payload пишет сам отправитель, и верить ему нельзя.
    func toMessage(from sender: String) -> Message {
        Message(
            id: UUID(uuidString: id) ?? UUID(),
            text: text,
            senderName: senderName,
            peerAddress: sender,
            isFromMe: false,
            timestamp: Date(timeIntervalSince1970: timestamp),
            status: .sent
        )
    }
}
