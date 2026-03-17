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
    case notConnected   // Голубой - можно подключиться
    case connecting     // Orange - в процессе
    case connected      // Зелёный - подключён
    case failed         // Розовый - не удалось / потеряна связь
}

struct Peer: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let status: PeerStatus
    let lastSeen: Date
    let rssi: Int?
    let distance: Double?
    
    init(id: UUID = UUID(),
         displayName: String,
         status: PeerStatus = .notConnected,
         lastSeen: Date = Date(),
         rssi: Int? = nil,
         distance: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.lastSeen = lastSeen
        self.rssi = rssi
        self.distance = distance
    }
    
    var signalPercentage: Int {
        guard let rssi = rssi else {
            return 0
        }
        // RSSI - от -100 (обычный) до -30 (сильный)
        let minRSSI: Double = -100
        let maxRSSI: Double = -30
        
        let clamped = max(min(Double(rssi), maxRSSI), minRSSI)
        let percentage = ((clamped - minRSSI) / (maxRSSI - minRSSI)) * 100
        
        return Int(percentage)
    }
    
    var formattedDistance: String {
        guard let distance = distance else {
            return "??M"
        }
        return "\(Int(distance))M"
    }
    
    var statusIcon: String {
        switch status {
        case .notConnected: 
            return "circle"
            
        case .connecting:
            return "circle.dotted"
            
        case .connected: 
            return "circle.fill"
            
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .notConnected:
            return Color(hex: "#00E5FF")  // secondary
            
        case .connecting:
            return .orange
            
        case .connected:
            return Color(hex: "#39FF14")    // primary
            
        case .failed:
            return Color(hex: "#FF2079")       // destructive
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
            
        case .failed:
            return "Недоступен"
        }
    }
    
    var isActive: Bool {
        status == .connected
    }
}
