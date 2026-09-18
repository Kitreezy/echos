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
    /// Просьба прислать свою стену целиком.
    case wallRequest
    /// Ответ на неё: стена владельца как она есть у него.
    case wallState
}

/// Один человек в комнате.
///
/// Имя и адрес разделены намеренно. Имя человек выбирает сам, оно может
/// повторяться и меняться; `id` — отпечаток ключа, он уникален, и подделать
/// его нельзя, не имея закрытой части.
///
/// Ключи — те, которыми человек представился серверу. Необязательные,
/// потому что старый релей их не пересылает; такой участник в список не
/// попадёт — писать ему нечем.
struct RelayParticipant: Codable, Sendable {
    let id: String
    let name: String
    let publicKey: Data?
    let agreementKey: Data?
    let agreementProof: Data?
    let sessionKey: Data?
    let sessionProof: Data?

    /// Релей проверил App Attest: с этим ключом говорит настоящий iPhone с
    /// настоящим echos. Старый релей поля не шлёт — тогда `nil`.
    let attested: Bool?

    init(id: String, name: String, keys: KeyBundle? = nil, attested: Bool? = nil) {
        self.id = id
        self.name = name
        self.publicKey = keys?.publicKey
        self.agreementKey = keys?.agreementKey
        self.agreementProof = keys?.agreementProof
        self.sessionKey = keys?.sessionKey
        self.sessionProof = keys?.sessionProof
        self.attested = attested
    }

    /// Личность, если ключи на месте, сходятся между собой и с адресом.
    ///
    /// Сверка отпечатка с `id` обязательна: иначе релей мог бы поставить
    /// рядом с чужим адресом свои ключи.
    var verifiedIdentity: PeerIdentity? {
        guard let publicKey, let agreementKey, let agreementProof,
              let sessionKey, let sessionProof else {
            return nil
        }

        let bundle = KeyBundle(publicKey: publicKey,
                               agreementKey: agreementKey,
                               agreementProof: agreementProof,
                               sessionKey: sessionKey,
                               sessionProof: sessionProof)

        guard let identity = bundle.verified(), identity.fingerprint == id else {
            return nil
        }
        return identity
    }
}

struct RelayEnvelope: Codable, Sendable {

    let kind: RelayEnvelopeKind
    /// Отпечаток ключа отправителя. Сервер проставляет его сам, из ключа,
    /// которым клиент подтвердил подключение: содержимому конверта верить
    /// нельзя.
    let sender: String
    /// Отпечаток получателя. `nil` — всем, кроме отправителя.
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
                      as identity: DeviceIdentity,
                      session: SessionKey,
                      attestation: AttestationProof? = nil) throws -> RelayEnvelope {
        let proof = try HelloPayload(answering: challenge, as: identity, session: session,
                                     attestation: attestation)

        return RelayEnvelope(kind: .hello,
                             sender: sender,
                             payload: try JSONEncoder().encode(proof))
    }

    static func presence(_ participants: [RelayParticipant]) throws -> RelayEnvelope {
        RelayEnvelope(kind: .presence,
                      sender: "",
                      payload: try JSONEncoder().encode(participants))
    }

    /// Сообщение уходит только запечатанным: открытого текста релей не видит.
    static func message(_ sealed: SealedPayload,
                        from sender: String,
                        to recipient: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .message,
                      sender: sender,
                      recipient: recipient,
                      payload: try JSONEncoder().encode(sealed))
    }

    static func typing(_ event: TypingEvent,
                       from sender: String,
                       to recipient: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .typing,
                      sender: sender,
                      recipient: recipient,
                      payload: try JSONEncoder().encode(event))
    }

    /// Росчерк, как и сообщение, — только запечатанным.
    static func stroke(_ sealed: SealedPayload,
                       from sender: String,
                       to recipient: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .stroke,
                      sender: sender,
                      recipient: recipient,
                      payload: try JSONEncoder().encode(sealed))
    }

    static func wallRequest(from sender: String,
                            to recipient: String) -> RelayEnvelope {
        RelayEnvelope(kind: .wallRequest,
                      sender: sender,
                      recipient: recipient,
                      payload: nil)
    }

    static func wallState(_ sealed: SealedPayload,
                          from sender: String,
                          to recipient: String) throws -> RelayEnvelope {
        RelayEnvelope(kind: .wallState,
                      sender: sender,
                      recipient: recipient,
                      payload: try JSONEncoder().encode(sealed))
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

    func decodePresence() throws -> [RelayParticipant] {
        try decode([RelayParticipant].self)
    }

    func decodeMessage() throws -> SealedPayload {
        try decode(SealedPayload.self)
    }

    func decodeTyping() throws -> TypingEvent {
        try decode(TypingEvent.self)
    }

    func decodeStroke() throws -> SealedPayload {
        try decode(SealedPayload.self)
    }

    func decodeWallState() throws -> SealedPayload {
        try decode(SealedPayload.self)
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

/// Чем клиент подтверждает право на имя — и чем его потом шифровать.
///
/// `signature` — под вызовом, её проверяет тот, кто вызов выдал. Ключ
/// соглашения и подпись под ним проверяет уже собеседник, а не сервер:
/// серверу они не нужны, он их только передаёт дальше.
struct HelloPayload: Codable, Sendable {
    let publicKey: Data
    let signature: Data
    let agreementKey: Data
    let agreementProof: Data
    let sessionKey: Data
    let sessionProof: Data

    /// App Attest, если устройство им ручается. Все четыре либо есть, либо
    /// нет; в JSON отсутствующие не пишутся, и старый релей их не заметит.
    let attestKeyId: Data?
    let attestation: Data?
    let attestChallenge: Data?
    let assertion: Data?

    init(answering challenge: Data, as identity: DeviceIdentity, session: SessionKey,
         attestation: AttestationProof? = nil) throws {
        let bundle = try identity.keyBundle(session: session)
        self.publicKey = bundle.publicKey
        self.signature = try identity.signature(for: challenge)
        self.agreementKey = bundle.agreementKey
        self.agreementProof = bundle.agreementProof
        self.sessionKey = bundle.sessionKey
        self.sessionProof = bundle.sessionProof
        self.attestKeyId = attestation?.keyID
        self.attestation = attestation?.attestation
        self.attestChallenge = attestation?.challenge
        self.assertion = attestation?.assertion
    }

    /// Собрать вручную. Нужно тестам, которые проверяют, что подделка
    /// не проходит.
    init(publicKey: Data, signature: Data,
         agreementKey: Data, agreementProof: Data,
         sessionKey: Data, sessionProof: Data) {
        self.publicKey = publicKey
        self.signature = signature
        self.agreementKey = agreementKey
        self.agreementProof = agreementProof
        self.sessionKey = sessionKey
        self.sessionProof = sessionProof
        self.attestKeyId = nil
        self.attestation = nil
        self.attestChallenge = nil
        self.assertion = nil
    }

    /// Тот же ответ, но с другими ключами. Для тестов на подмену.
    func replacing(agreementKey: Data? = nil, agreementProof: Data? = nil,
                   sessionKey: Data? = nil, sessionProof: Data? = nil) -> HelloPayload {
        HelloPayload(publicKey: publicKey, signature: signature,
                     agreementKey: agreementKey ?? self.agreementKey,
                     agreementProof: agreementProof ?? self.agreementProof,
                     sessionKey: sessionKey ?? self.sessionKey,
                     sessionProof: sessionProof ?? self.sessionProof)
    }

    var keyBundle: KeyBundle {
        KeyBundle(publicKey: publicKey,
                  agreementKey: agreementKey, agreementProof: agreementProof,
                  sessionKey: sessionKey, sessionProof: sessionProof)
    }
}

enum RelayError: Error, LocalizedError, Equatable {
    case emptyPayload
    case notConnected
    case invalidURL
    /// Собеседника с таким адресом на релее нет — или его ключи не прошли.
    case noCipher(String)

    var errorDescription: String? {
        switch self {
        case .emptyPayload:  return "В конверте нет полезной нагрузки"
        case .notConnected:  return "Нет соединения с релеем"
        case .invalidURL:    return "Некорректный адрес релея"
        case .noCipher(let address): return "Нет ключа переписки с \(address)"
        }
    }
}
