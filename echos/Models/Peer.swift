//
//  Peer.swift
//  echos
//
//  Created by Artem Rodionov on 17.02.2026.
//

import Foundation

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
