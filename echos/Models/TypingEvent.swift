//
//  TypingEvent.swift
//  echos
//
//  Created by Artem Rodionov on 21.02.2026.
//

import Foundation

enum TypingEventType: String, Codable {
    case start
    case stop
}

struct TypingEvent: Codable {
    
    let type: TypingEventType
    let peerName: String
    let timestamp: Double
    
    init(type: TypingEventType,
         peerName: String
    ) {
        self.type = type
        self.peerName = peerName
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Обертка для всех типов данных, чтобы различать сообщения, typing-события
/// и росчерки на стене
enum MultipeerDataType: String, Codable {
    case message
    case typing
    case stroke
    case wallRequest
    case wallState
    /// Случайная строка, которую просим подписать.
    case challenge
    /// Ответ на неё: открытый ключ и подпись.
    case hello
}

struct MultipeerPacket: Codable {
    
    let type: MultipeerDataType
    let playload: Data // MessagePayload или TypingEvent
    
    /// Сообщение идёт только запечатанным.
    init(message sealed: SealedPayload) throws {
        self.type = .message
        self.playload = try JSONEncoder().encode(sealed)
    }
    
    init(typingEvent: TypingEvent) throws {
        self.type = .typing
        self.playload = try JSONEncoder().encode(typingEvent)
    }
    
    /// Росчерк — только запечатанным: это содержимое, как и сообщение.
    init(stroke sealed: SealedPayload) throws {
        self.type = .stroke
        self.playload = try JSONEncoder().encode(sealed)
    }

    /// Просьба прислать стену. Содержимого у неё нет: важен сам факт и то,
    /// от кого она пришла.
    init(wallRequest: Void) {
        self.type = .wallRequest
        self.playload = Data()
    }

    init(wallState sealed: SealedPayload) throws {
        self.type = .wallState
        self.playload = try JSONEncoder().encode(sealed)
    }

    /// Вызов лежит в payload как есть: это просто набор байтов.
    init(challenge nonce: Data) {
        self.type = .challenge
        self.playload = nonce
    }

    init(hello: HelloPayload) throws {
        self.type = .hello
        self.playload = try JSONEncoder().encode(hello)
    }
    
    func decodeMessage() throws -> SealedPayload {
        try JSONDecoder().decode(SealedPayload.self, from: playload)
    }
    
    func decodeTypingEvent() throws -> TypingEvent {
        try JSONDecoder().decode(TypingEvent.self, from: playload)
    }
    
    func decodeStroke() throws -> SealedPayload {
        try JSONDecoder().decode(SealedPayload.self, from: playload)
    }

    func decodeWallState() throws -> SealedPayload {
        try JSONDecoder().decode(SealedPayload.self, from: playload)
    }

    func decodeChallenge() -> Data {
        playload
    }

    func decodeHello() throws -> HelloPayload {
        try JSONDecoder().decode(HelloPayload.self, from: playload)
    }
}
