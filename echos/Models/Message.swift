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

    /// Реакции. Переписка один на один, поэтому у каждой стороны — не
    /// больше одной на сообщение: своя и собеседника.
    var myReaction: String?
    var peerReaction: String?

    /// На какое сообщение это ответ. `nil` — просто сообщение.
    let replyTo: MessageReply?

    init(id: UUID = UUID(),
         text: String,
         mosaic: Mosaic? = nil,
         senderName: String? = nil,
         peerAddress: String? = nil,
         isFromMe: Bool,
         timestamp: Date = Date(),
         status: MessageStatus = .sending,
         isRead: Bool = true,
         myReaction: String? = nil,
         peerReaction: String? = nil,
         replyTo: MessageReply? = nil
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
        self.myReaction = myReaction
        self.peerReaction = peerReaction
        self.replyTo = replyTo
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
                isRead: isRead,
                myReaction: myReaction,
                peerReaction: peerReaction,
                replyTo: replyTo)
    }
}

/// Ссылка ответа на оригинал.
///
/// Кроме идентификатора, хранится короткий текст оригинала: историю могли
/// очистить, а цитата должна остаться понятной. Показывается он, только
/// если оригинала нет под рукой, — свой экземпляр надёжнее того, что
/// прислали: собеседник мог процитировать «моё» сообщение, которого я не
/// писал.
struct MessageReply: Codable, Equatable, Sendable {
    let id: UUID
    let preview: String
    /// Чей оригинал — с точки зрения этого устройства.
    let isFromMe: Bool

    /// Сколько текста оригинала носить с собой. Цитате хватит строки.
    static let previewLength = 140

    init(id: UUID, preview: String, isFromMe: Bool) {
        self.id = id
        self.preview = String(preview.prefix(Self.previewLength))
        self.isFromMe = isFromMe
    }

    /// Ответ на это сообщение.
    init(quoting message: Message) {
        self.init(id: message.id,
                  preview: message.mosaic == nil ? message.text : "мозаика",
                  isFromMe: message.isFromMe)
    }
}

/// Ссылка на оригинал в конверте. Сторона записана от лица отправителя
/// конверта: «моё» у него — «чужое» у получателя.
struct ReplyPayload: Codable, Equatable {
    let id: String
    let preview: String
    let isFromSender: Bool
}

/// Реакция на сообщение: на какое и какая.
struct ReactionPayload: Codable, Equatable, Sendable {
    let targetID: String
    /// Один эмодзи; пустая строка — снять.
    let emoji: String
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
    /// Реакция, если это она. Едет тем же конвертом, что и сообщение, —
    /// ни транспорту, ни релею новый род не нужен. Старая сборка увидит
    /// эмодзи текстом; текст для этого и заполняется.
    let reaction: ReactionPayload?
    /// На что это ответ. Старая сборка поле не знает и покажет просто
    /// сообщение — без цитаты, но целиком.
    let reply: ReplyPayload?

    init(from message: Message, senderName: String) {
        self.id = message.id.uuidString
        self.text = message.text
        self.senderName = senderName
        self.timestamp = message.timestamp.timeIntervalSince1970
        self.mosaic = message.mosaic
        self.reaction = nil
        self.reply = message.replyTo.map {
            ReplyPayload(id: $0.id.uuidString, preview: $0.preview, isFromSender: $0.isFromMe)
        }
    }

    /// Реакция на чужое или своё сообщение. `emoji` пустая — реакция снята.
    init(reaction: ReactionPayload, senderName: String) {
        self.id = UUID().uuidString
        self.text = reaction.emoji.isEmpty ? "" : reaction.emoji
        self.senderName = senderName
        self.timestamp = Date().timeIntervalSince1970
        self.mosaic = nil
        self.reaction = reaction
        self.reply = nil
    }

    /// Конвертация обратно в Message (входящее — isFromMe = false).
    ///
    /// Адрес отправителя приходит снаружи, от транспорта: `senderName` внутри
    /// payload пишет сам отправитель, и верить ему нельзя.
    func toMessage(from sender: String) -> Message {
        // Сетка снаружи может быть какой угодно: не сошлась — остаётся
        // текстовая форма, она есть всегда.
        let mosaic = mosaic.flatMap { $0.isValid ? $0 : nil }
        let replyTo = reply.flatMap { reply in
            UUID(uuidString: reply.id).map {
                MessageReply(id: $0, preview: reply.preview, isFromMe: !reply.isFromSender)
            }
        }

        return Message(
            id: UUID(uuidString: id) ?? UUID(),
            text: text,
            mosaic: mosaic,
            senderName: senderName,
            peerAddress: sender,
            isFromMe: false,
            timestamp: Date(timeIntervalSince1970: timestamp),
            status: .sent,
            replyTo: replyTo
        )
    }
}
