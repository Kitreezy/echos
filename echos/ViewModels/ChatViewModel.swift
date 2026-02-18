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
    
    /// Поток входящих сообщений (заглушка до step 4 - замена на Multipeer)
    private var messageStream: AsyncStream<Message>?
    private var streamContinuation: AsyncStream<Message>.Continuation?
    
    // MARK: - Init
    
    init() {
        Task {
            await startListeningForMessages()
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
    
    /// Имитация входящего typing..
    /// TODO step  5: получать из Multipeer data-пакета с type=typing.
    func simulateIncomingTyping(from peerName: String) async {
        typingPeerName = peerName
        try? await Task.sleep(for: .seconds(3))
        typingPeerName = nil
    }
    
    // MARK: - Incoming message (for testing)
    
    /// Инжектируем входящее сообщение в стрим (для теста)
    func injectIncomingMessage(_ message: Message) {
        streamContinuation?.yield(message)
    }
}
