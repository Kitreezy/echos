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
    var connectionStatus: String = "Не подлючён"
    var isDiscovering: Bool = false
    var typingPeerName: String? = nil  // nil - никто не печатает
    
    // MARK: - Services
    
    private let multipeerService = MultipeerService()
    
    /// Поток входящих сообщений (заглушка до step 4 - замена на Multipeer)
    private var messageStream: AsyncStream<Message>?
    private var streamContinuation: AsyncStream<Message>.Continuation?
    
    // MARK: - Init
    
    init() {
        setupMessageStream()
    }
    
    // MARK: - Stream messages
    
    private func setupMessageStream() {
        var (stream, continuation) = AsyncStream.makeStream(of: Message.self)
        
        self.messageStream = stream
        self.streamContinuation = continuation
    }
    
    func startListeningForMessages() async {
        guard let stream = messageStream else {
            return
        }
        for await message in stream {
            messages.append(message)
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
        let count = peers.count
        
        switch count {
        case 0:
            connectionStatus = "Нет устройств рядом"
            
        case 1:
            connectionStatus = "1 устройство рядом"
            
        default:
            connectionStatus = "\(count) устройств рядом"
        }
    }
    
    // MARK: - Messaging
    
    /// Отправка сообщения
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        var message = Message(text: trimmed, isFromMe: true)
        messages.append(message)
        
        // TODO step 4: serialise → MCSession.send
        try? await Task.sleep(for: .milliseconds(300))
        
        // Обновление статуса после отправки
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx].status = .sent
        }
    }
    
    // MARK: - Typing indication
    
    /// Имитация входящего typing (заглушка).
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
