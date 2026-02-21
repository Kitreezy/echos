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

/// Обертка для всех типов данных, чтобы различать сообщения и typing-события
enum MultipeerDataType: String, Codable {
    case message
    case typing
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
    
    func decodeMessage() throws -> MessagePayload {
        try JSONDecoder().decode(MessagePayload.self, from: playload)
    }
    
    func decodeTypingEvent() throws -> TypingEvent {
        try JSONDecoder().decode(TypingEvent.self, from: playload)
    }
}
