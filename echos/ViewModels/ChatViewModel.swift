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
    
    var currentConversationPeer: String? = nil
    
    // MARK: - Services
    
    var multipeerService: MultipeerService?
    var messageStore: MessageStore?
    
    // MARK: - Typing State
    
    private var typingTimer: Task<Void, Never>?
    private let typingTimeout: TimeInterval = 3.0
    
    private var typingDebounceTimer: Task<Void, Never>?
    private let typingDebounceDelay: TimeInterval = 0.3
    private var isCurrentlyTyping = false
    
    // MARK: - Init
    
    init() {}
    
    // MARK: - Setup
    
    func initialize() {
        multipeerService = MultipeerService()
        messageStore = MessageStore()
        
        Task {
            await startListeningForMessages()
        }
        
        Task {
            await startListenForTyping()
        }
        
        Task {
            await loadMessageHistory()
        }
    }
    
    // MARK: - Persistence
    
    private func loadMessageHistory() async {
        guard let messageStore = messageStore else {
            print("[ChatViewModel] MessageStore not initialized")
            return
        }
        
        do {
            if let connectedPeer = peers.first(where: { $0.status == .connected }) {
                await switchToConversation(with: connectedPeer.displayName)
            } else {
                let all = try await messageStore.loadMessages()
                messages = all
                currentConversationPeer = nil
                print("[ChatViewModel] Loaded \(all.count) messages from storage")
            }
        }
        catch {
            print("[ChatViewModel] Failed to load messages: \(error.localizedDescription)")
            // в будущем можно бахнуть здесь alert
        }
    }
    
    func switchToConversation(with peerName: String) async {
        guard let messageStore = messageStore else {
            return
        }
        do {
            let filtered = try await messageStore.loadMessages(with: peerName)
            messages = filtered
            currentConversationPeer = peerName
            print("[ChatViewModel] Showing conversation with '\(peerName)': \(filtered.count) messages")
        }
        catch {
            print("[ChatViewModel] Failed to switch: \(error)")
        }
    }
    
    func showAllMessages() async {
        guard let messageStore = messageStore else {
            return
        }
        do {
            let all = try await messageStore.loadMessages()
            messages = all
            currentConversationPeer = nil
            print("[ChatViewModel] Showing all messages: \(all.count)")
        }
        catch {
            print("[ChatViewModel] Failed to load all: \(error)")
        }
    }
    
    func clearAllMessages() async throws {
        guard let messageStore = messageStore else {
            return
        }
        
        try await messageStore.clearAll()
        messages = []
        print("[ChatViewModel] Cleared all messages")
    }
    
    func clearCurrentConversationMessages() async throws {
        guard let messageStore = messageStore, let peerName = currentConversationPeer else {
            return
        }
        
        try await messageStore.deleteConverstaion(with: peerName)
        messages = []
        print("[ChatViewModel] Cleared conversation with '\(peerName)'")
    }
    
    // MARK: - Listening
    
    private func startListeningForMessages() async {
        guard let multipeerService = multipeerService else {
            return
        }
        for await playLoad in multipeerService.messageStream {
            let message = playLoad.toMessage()
            
            if currentConversationPeer == nil || message.senderName == currentConversationPeer {
                messages.append(message)
                print("[ChatViewModel] Received from '\(message.senderName ?? "unknown")': \(message.text.prefix(20))...")
            } else {
                print("[ChatViewModel] Silently saved message from '\(message.senderName ?? "unknown")' (different conversation)")
            }
            
            if let messageStore = messageStore {
                Task {
                    do {
                        try await messageStore.saveMessage(message)
                    }
                    catch {
                        print("[ChatViewModel] Failed to save received message: \(error)")
                    }
                }
            }
        }
    }
    
    private func startListenForTyping() async {
        guard let multipeerService = multipeerService else {
            return
        }
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
        guard let multipeerService = multipeerService else {
            return
        }
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
        guard let multipeerService = multipeerService else {
            return
        }
        isDiscovering = false
        multipeerService.stopDeviceDiscovery()
        connectionStatus = "Поиск остановлен"
        
        stopTyping()
    }
    
    private func updateConnectionStatus() {
        let connectedPeers = peers.filter { $0.status == .connected }
        let connectedCount = connectedPeers.count
        let discoveredCount = peers.count
        
        if connectedCount > 0 {
            let names = connectedPeers.map { $0.displayName }.joined(separator: ", ")
              connectionStatus = ">_< \(names)"
        } else if discoveredCount > 0 {
            connectionStatus = "Найдено: \(discoveredCount) устройства."
        } else {
            connectionStatus = "Нет устройств рядом"
        }
    }
    
    // MARK: - Messaging
    
    /// Отправка сообщения
    func sendMessage(_ text: String) async {
        guard let multipeerService = multipeerService else {
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        var message = Message(text: trimmed,
                              senderName: nil,
                              isFromMe: true,
                              status: .sending)
        messages.append(message)
        
        stopTyping()
        
        let playLoad = MessagePayload(from: message, senderName: multipeerService.myDisplayName)
        
        do {
            try await multipeerService.sendMessage(playLoad)
            
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx].status = .sent
                
                if let messageStore = messageStore {
                    Task {
                        do {
                            try await messageStore.saveMessage(messages[idx])
                        }
                        catch {
                            print("[ChatViewModel] Failed to save message: \(error)")
                        }
                    }
                }
            }
            print("[ChatViewModel] Message sent successfully")
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx].status = .failed
                
                if let messageStore = messageStore {
                    Task {
                        do {
                            try await messageStore.saveMessage(messages[idx])
                        }
                        catch {
                            print("[ChatViewModel] Failed to save message: \(error)")
                        }
                    }
                }
            }
            print("[ChatViewModel] Failed to send message: \(error)")
        }
    }
    
    // MARK: - Typing indication
    
    
    func startTyping() {
        guard let multipeerService = multipeerService else {
            return
        }
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
            
            let event = TypingEvent(type: .start,
                                    peerName: multipeerService.myDisplayName)
            try? await multipeerService.sendTypingEvent(event)
            print("[ChatViewModel] Sent typing start from '\(multipeerService.myDisplayName)'")
        }
        
        typingTimer = Task {
            try? await Task.sleep(for: .seconds(typingTimeout))
            
            if !Task.isCancelled {
                stopTyping()
            }
        }
    }
    
    func stopTyping() {
        guard let multipeerService = multipeerService else {
            return
        }
        
        typingDebounceTimer?.cancel()
        typingTimer?.cancel()
        typingDebounceTimer = nil
        typingTimer = nil
        
        guard isCurrentlyTyping else {
            return
        }
        
        isCurrentlyTyping = false
        
        Task {
            let event = TypingEvent(type: .stop,
                                    peerName: multipeerService.myDisplayName)
            try? await multipeerService.sendTypingEvent(event)
            print("[ChatViewModel] Sent typing stop from '\(multipeerService.myDisplayName)'")
        }
    }
}
