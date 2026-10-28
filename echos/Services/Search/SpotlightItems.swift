//
//  SpotlightItems.swift
//  echos
//
//  Что echos кладёт в системный поиск и как узнать, что из него открыли.
//
//  Две записи: собеседник — чтобы найти чат по имени, и сообщение — чтобы
//  найти разговор по слову из него. Записи одного разговора лежат в одном
//  домене: удалить переписку из поиска можно одним вызовом, не перебирая
//  сообщения.
//
//  Идентификатор записи — единственное, что система вернёт, когда человек
//  нажмёт на результат. Поэтому адрес собеседника зашит в него же: по одному
//  id сообщения не понять, какой чат открывать.
//

import CoreSpotlight
import UniformTypeIdentifiers

enum SpotlightItems {

    /// Куда вести человека, который нажал на результат поиска.
    enum Target: Equatable {
        case conversation(address: String)
        case message(id: UUID, address: String)
    }

    private static let personPrefix = "person:"
    private static let messagePrefix = "message:"

    /// Домен всех записей одного разговора.
    static func domain(of address: String) -> String {
        "conversation:\(address)"
    }

    static func identifier(for target: Target) -> String {
        switch target {
        case let .conversation(address):
            personPrefix + address
        case let .message(id, address):
            // UUID фиксированной длины идёт первым: адрес у Multipeer — имя
            // устройства, и двоеточие в нём не запрещено.
            messagePrefix + id.uuidString + ":" + address
        }
    }

    static func target(from identifier: String) -> Target? {
        if identifier.hasPrefix(personPrefix) {
            let address = String(identifier.dropFirst(personPrefix.count))
            return address.isEmpty ? nil : .conversation(address: address)
        }

        guard identifier.hasPrefix(messagePrefix) else {
            return nil
        }
        let rest = identifier.dropFirst(messagePrefix.count)
        let uuidLength = 36
        guard rest.count > uuidLength + 1,
              let id = UUID(uuidString: String(rest.prefix(uuidLength))),
              rest.dropFirst(uuidLength).first == ":" else {
            return nil
        }
        return .message(id: id, address: String(rest.dropFirst(uuidLength + 1)))
    }

    static func person(address: String, name: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .contact)
        attributes.title = name
        attributes.contentDescription = "Чат в echos"
        attributes.displayName = name

        return CSSearchableItem(uniqueIdentifier: identifier(for: .conversation(address: address)),
                                domainIdentifier: domain(of: address),
                                attributeSet: attributes)
    }

    /// Запись о сообщении. `nil` — искать в нём нечего: сообщение без
    /// собеседника или пустое.
    ///
    /// У мозаики в поиск идёт не её текстовая форма — строка из квадратиков
    /// никому не поможет найти разговор, — а слово «Мозаика».
    static func message(_ message: Message, peerName: String?) -> CSSearchableItem? {
        guard let address = message.peerAddress else {
            return nil
        }
        let text = message.mosaic == nil ? message.text : "Мозаика"
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let name = peerName ?? message.senderName ?? "Собеседник"
        let attributes = CSSearchableItemAttributeSet(contentType: .message)
        attributes.title = message.isFromMe ? "Вы → \(name)" : name
        attributes.contentDescription = text
        attributes.textContent = text
        attributes.contentCreationDate = message.timestamp
        attributes.authorNames = [message.isFromMe ? "Вы" : name]

        let item = CSSearchableItem(uniqueIdentifier: identifier(for: .message(id: message.id, address: address)),
                                    domainIdentifier: domain(of: address),
                                    attributeSet: attributes)
        // По умолчанию система забывает запись через месяц. История в echos
        // живёт дольше — и в поиске должна жить столько же.
        item.expirationDate = .distantFuture
        return item
    }
}
