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
    /// Клиент → сервер: представиться и войти в комнату.
    case hello
    /// Сервер → клиент: актуальный список тех, кто сейчас на релее.
    case presence
    /// В обе стороны: сообщение чата.
    case message
    /// В обе стороны: индикатор набора.
    case typing
}

struct RelayEnvelope: Codable, Sendable {

    let kind: RelayEnvelopeKind
    /// Кто отправил. Сервер проставляет его сам, клиенту доверять нельзя.
    let sender: String
    let payload: Data?

    private init(kind: RelayEnvelopeKind, sender: String, payload: Data?) {
        self.kind = kind
        self.sender = sender
        self.payload = payload
    }

    // MARK: - Constructors

    static func hello(from sender: String) -> RelayEnvelope {
        RelayEnvelope(kind: .hello, sender: sender, payload: nil)
    }

    static func presence(_ names: [String]) throws -> RelayEnvelope {
        RelayEnvelope(kind: .presence,
                      sender: "",
                      payload: try JSONEncoder().encode(names))
    }

    static func message(_ payload: MessagePayload, from sender: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .message,
                      sender: sender,
                      payload: try JSONEncoder().encode(payload))
    }

    static func typing(_ event: TypingEvent, from sender: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .typing,
                      sender: sender,
                      payload: try JSONEncoder().encode(event))
    }

    // MARK: - Decoding

    func decodePresence() throws -> [String] {
        try decode([String].self)
    }

    func decodeMessage() throws -> MessagePayload {
        try decode(MessagePayload.self)
    }

    func decodeTyping() throws -> TypingEvent {
        try decode(TypingEvent.self)
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
        RelayEnvelope(kind: kind, sender: sender, payload: payload)
    }
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
