//
//  ConversationSummary.swift
//  echos
//
//  Created by Artem Rodionov on 27.02.2026.
//

import Foundation

struct ConversationSummary: Identifiable {
    let id = UUID()
    let peerName: String
    let lastMessage: String
    let lastMessageTime: Date
    let messageCount: Int
    let unreadCount: Int
    let isActive: Bool
}
