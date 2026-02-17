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
    var connectionStatus: String = "Поиск устройства..."
    var isDiscovering: Bool = false
    var typingPeerName: String? = nil  // nil - никто не печатает
    
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
        
        // Заглушка: имитация нахождение устройств через 1.5 ceк
        // TODO step 3: замена на MultipeerConnectivity
        try? await Task.sleep(for: .seconds(1.5))
        
        let mockPeers: [Peer] = [
            Peer(displayName: "iPhone Артем", status: .connected),
            Peer(displayName: "iPhone Борис", status: .notConnected),
        ]
        peers = mockPeers
        connectionStatus = "\(mockPeers.filter(\.isActive).count) устройств рядом"
    }
    
    func stopDeviceDiscovery() {
        isDiscovering = false
        connectionStatus = "Поиск остановлен"
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
