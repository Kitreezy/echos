//
//  RelayProtocol.swift
//  echos
//
//  Формат сообщений между клиентом и релеем.
//
//  Форма конверта повторяет `MultipeerPacket`: тип + payload в `Data`.
//  Так один и тот же приём сериализации работает для обоих транспортов,
//  а модели (`MessagePayload`, `TypingEvent`) переиспользуются как есть.
//

import Foundation

enum RelayEnvelopeKind: String, Codable, Sendable {
    /// Сервер → клиент: случайная строка, которую нужно подписать.
    /// Приходит первой, сразу после установки соединения.
    case challenge
    /// Клиент → сервер: представиться и войти в комнату.
    ///
    /// В payload — открытый ключ и подпись под вызовом. Одного имени мало:
    /// назваться можно кем угодно, а подписать чужим ключом — нет.
    case hello
    /// Сервер → клиент: актуальный список тех, кто сейчас на релее.
    case presence
    /// В обе стороны: сообщение чата.
    case message
    /// В обе стороны: индикатор набора.
    case typing
    /// В обе стороны: росчерк на стене.
    case stroke
}

struct RelayEnvelope: Codable, Sendable {

    let kind: RelayEnvelopeKind
    /// Кто отправил. Сервер проставляет его сам, клиенту доверять нельзя.
    let sender: String
    /// Кому предназначено. `nil` — всем, кроме отправителя.
    ///
    /// Нужен для стены: росчерк адресован одному человеку, и при трёх
    /// участниках рассылать его всем неправильно.
    let recipient: String?
    let payload: Data?

    private init(kind: RelayEnvelopeKind,
                 sender: String,
                 recipient: String? = nil,
                 payload: Data?) {
        self.kind = kind
        self.sender = sender
        self.recipient = recipient
        self.payload = payload
    }

    // MARK: - Constructors

    static func hello(from sender: String,
                      answering challenge: Data,
                      as identity: DeviceIdentity) throws -> RelayEnvelope {
        let proof = HelloPayload(publicKey: identity.publicKey,
                                 signature: try identity.signature(for: challenge))

        return RelayEnvelope(kind: .hello,
                             sender: sender,
                             payload: try JSONEncoder().encode(proof))
    }

    static func presence(_ names: [String]) throws -> RelayEnvelope {
        RelayEnvelope(kind: .presence,
                      sender: "",
                      payload: try JSONEncoder().encode(names))
    }

    static func message(_ payload: MessagePayload,
                        from sender: String,
                        to recipient: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .message,
                      sender: sender,
                      recipient: recipient,
                      payload: try JSONEncoder().encode(payload))
    }

    static func typing(_ event: TypingEvent,
                       from sender: String,
                       to recipient: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .typing,
                      sender: sender,
                      recipient: recipient,
                      payload: try JSONEncoder().encode(event))
    }

    static func stroke(_ stroke: Stroke,
                       from sender: String,
                       to recipient: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .stroke,
                      sender: sender,
                      recipient: recipient,
                      payload: try JSONEncoder().encode(stroke))
    }

    // MARK: - Decoding

    /// Вызов лежит в payload как есть: это просто набор байтов,
    /// разбирать в нём нечего.
    func decodeChallenge() throws -> Data {
        guard let payload else {
            throw RelayError.emptyPayload
        }
        return payload
    }

    func decodePresence() throws -> [String] {
        try decode([String].self)
    }

    func decodeMessage() throws -> MessagePayload {
        try decode(MessagePayload.self)
    }

    func decodeTyping() throws -> TypingEvent {
        try decode(TypingEvent.self)
    }

    func decodeStroke() throws -> Stroke {
        try decode(Stroke.self)
    }

    private func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let payload else {
            throw RelayError.emptyPayload
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    // MARK: - Wire format

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(from data: Data) throws -> RelayEnvelope {
        try JSONDecoder().decode(RelayEnvelope.self, from: data)
    }

    /// Подменяет отправителя. Сервер вызывает это перед рассылкой, чтобы
    /// в конверте стояло имя, под которым клиент реально представился.
    func stamped(sender: String) -> RelayEnvelope {
        RelayEnvelope(kind: kind, sender: sender, recipient: recipient, payload: payload)
    }
}

/// Чем клиент подтверждает право на имя.
struct HelloPayload: Codable, Sendable {
    let publicKey: Data
    let signature: Data
}

enum RelayError: Error, LocalizedError, Equatable {
    case emptyPayload
    case notConnected
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .emptyPayload:  return "В конверте нет полезной нагрузки"
        case .notConnected:  return "Нет соединения с релеем"
        case .invalidURL:    return "Некорректный адрес релея"
        }
    }
}
