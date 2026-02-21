//
//  ChatViewModel.swift
//  echos
//
//  Created by Artem Rodionov on 17.02.2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {
    
    // MARK: - State (автоматически наблюдаемое)
    
    var messages: [Message] = []
    var peers: [Peer] = []
    var connectionStatus: String = "Не подключён"
    var isDiscovering: Bool = false
    var typingPeerName: String? = nil  // nil - никто не печатает
    
    // MARK: - Services
    
    private let multipeerService = MultipeerService()
    
    // MARK: - Typing State
    
    private var typingTimer: Task<Void, Never>?
    private let typingTimeout: TimeInterval = 3.0
    
    private var typingDebounceTimer: Task<Void, Never>?
    private let typingDebounceDelay: TimeInterval = 0.3
    private var isCurrentlyTyping = false
    
    // MARK: - Init
    
    init() {
        
        Task {
            await startListeningForMessages()
        }
        
        Task {
            await startListenForTyping()
        }
    }
    
    // MARK: - Listening
    
    private func startListeningForMessages() async {
        for await playLoad in multipeerService.messageStream {
            let message = playLoad.toMessage()
            messages.append(message)
            print("[ChatViewModel] Received message: \(message.text)")
            // TODO step 7: сохранить в Core Data
        }
    }
    
    private func startListenForTyping() async {
        for await event in multipeerService.typingStream {
            handleTypingEvent(event)
        }
    }
    
    func handleTypingEvent(_ event: TypingEvent) {
        switch event.type {
        case .start:
            typingPeerName = event.peerName
            print("[ChatViewModel] '\(event.peerName)' started typing...")
            
        case .stop:
            if typingPeerName == event.peerName {
                typingPeerName = nil
                print("[ChatViewModel] '\(event.peerName)' stopped typing")
            }
        }
    }
    
    // MARK: - Discovery
    
    /// Запуск обнаружения устройств
    func startDeviceDiscovery() async {
        isDiscovering = true
        connectionStatus = "Ищем устройства..."
        
        multipeerService.startDeviceDiscovery()
        
        Task {
            for await discoveredPeers in multipeerService.peerStream {
                self.peers = discoveredPeers
                updateConnectionStatus()
            }
        }
    }
    
    func stopDeviceDiscovery() {
        isDiscovering = false
        multipeerService.stopDeviceDiscovery()
        connectionStatus = "Поиск остановлен"
        
        stopTyping()
    }
    
    private func updateConnectionStatus() {
        let connectedCount = peers.filter { $0.status == .connected }.count
        let discoveredCount = peers.count
        
        if connectedCount > 0 {
            connectionStatus = "Подключено: \(connectedCount) из \(discoveredCount)"
        } else if discoveredCount > 0 {
            connectionStatus = "Найдено: \(discoveredCount), подключение..."
        } else {
            connectionStatus = "Нет устройств рядом"
        }
    }
    
    // MARK: - Messaging
    
    /// Отправка сообщения
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        var message = Message(text: trimmed, isFromMe: true, status: .sending)
        messages.append(message)
        
        stopTyping()
        
        let playLoad = MessagePayload(from: message)
        
        do {
            try await multipeerService.sendMessage(playLoad)
            
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx].status = .sent
            }
            print("[ChatViewModel] Message sent successfully")
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx].status = .failed
            }
            print("[ChatViewModel] Failed to send message: \(error)")
        }
    }
    
    // MARK: - Typing indication
    
    
    func startTyping() {
        typingDebounceTimer?.cancel()
        
        if isCurrentlyTyping {
            typingTimer?.cancel()
            typingTimer = Task {
                try? await Task.sleep(for: .seconds(typingTimeout))
                if !Task.isCancelled {
                    stopTyping()
                }
            }
            return
        }
        
        typingDebounceTimer = Task {
            try? await Task.sleep(for: .seconds(typingDebounceDelay))
            
            guard !Task.isCancelled else {
                return
            }
            
            isCurrentlyTyping = true
            
            let event = TypingEvent(type: .start, peerName: multipeerService.displayName)
            try? await multipeerService.sendTypingEvent(event)
            print("[ChatViewModel] Sent typing start from '\(multipeerService.displayName)'")
        }
        
        typingTimer = Task {
            try? await Task.sleep(for: .seconds(typingTimeout))
            
            if !Task.isCancelled {
                stopTyping()
            }
        }
    }
    
    func stopTyping() {
        typingDebounceTimer?.cancel()
        typingTimer?.cancel()
        typingDebounceTimer = nil
        typingTimer = nil
        
        guard isCurrentlyTyping else {
            return
        }
        
        isCurrentlyTyping = false
        
        Task {
            let event = TypingEvent(type: .stop, peerName: multipeerService.displayName)
            try? await multipeerService.sendTypingEvent(event)
            print("[ChatViewModel] Sent typing stop from '\(multipeerService.displayName)'")
        }
    }
}
