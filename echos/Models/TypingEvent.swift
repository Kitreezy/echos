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
}

struct MultipeerPacket: Codable {
    
    let type: MultipeerDataType
    let playload: Data // MessagePayload или TypingEvent
    
    init(message: MessagePayload) throws {
        self.type = .message
        self.playload = try JSONEncoder().encode(message)
    }
    
    init(typingEvent: TypingEvent) throws {
        self.type = .typing
        self.playload = try JSONEncoder().encode(typingEvent)
    }
    
    init(stroke: Stroke) throws {
        self.type = .stroke
        self.playload = try JSONEncoder().encode(stroke)
    }

    /// Просьба прислать стену. Содержимого у неё нет: важен сам факт и то,
    /// от кого она пришла.
    init(wallRequest: Void) {
        self.type = .wallRequest
        self.playload = Data()
    }

    init(wallState strokes: [Stroke]) throws {
        self.type = .wallState
        self.playload = try JSONEncoder().encode(strokes)
    }
    
    func decodeMessage() throws -> MessagePayload {
        try JSONDecoder().decode(MessagePayload.self, from: playload)
    }
    
    func decodeTypingEvent() throws -> TypingEvent {
        try JSONDecoder().decode(TypingEvent.self, from: playload)
    }
    
    func decodeStroke() throws -> Stroke {
        try JSONDecoder().decode(Stroke.self, from: playload)
    }

    func decodeWallState() throws -> [Stroke] {
        try JSONDecoder().decode([Stroke].self, from: playload)
    }
}
