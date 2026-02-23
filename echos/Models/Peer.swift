//
//  Peer.swift
//  echos
//
//  Created by Artem Rodionov on 17.02.2026.
//

import UIKit
import SwiftUICore

/// Статус подключения соседнего устройства
enum PeerStatus: Equatable {
    case notConnected
    case connecting
    case connected
}

struct Peer: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let status: PeerStatus
    let lastSeen: Date
    
    init(id: UUID = UUID(),
         displayName: String,
         status: PeerStatus = .notConnected,
         lastSeen: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.lastSeen = lastSeen
    }
    
    var statusIcon: String {
        switch status {
        case .notConnected:
            return "circle"
            
        case .connecting:
            return "circle.dotted"
            
        case .connected:
            return "circle.fill"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .notConnected:
            return .gray
            
        case .connecting:
            return .orange
            
        case .connected:
            return .green
        }
    }
    
    var statusLabel: String {
        switch status {
        case .notConnected:
            return "Не подключён"
            
        case .connecting:
            return "Подключение..."
            
        case .connected:
            return "Подключён"
        }
    }
    
    var isActive: Bool {
        status == .connected
    }
}
