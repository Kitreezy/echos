//
//  PeerTransport.swift
//  echos
//
//  Абстракция над транспортом для обмена с соседними устройствами.
//
//  Зачем: у транспорта две реализации — `MultipeerService` (устройства рядом,
//  через MultipeerConnectivity) и `WebSocketTransport` (через релей, из любой
//  сети). ViewModel не должна знать, какой из них подключён.
//
//  В тестах в этот же шов подставляется `LoopbackTransport`.
//

import Foundation

/// Подтверждение входящего подключения пользователем.
@MainActor
protocol PeerConnectionApproving: AnyObject {
    /// Показать UI для подтверждения подключения.
    /// - Returns: true если пользователь принял, false если отклонил
    func shouldAcceptConnection(from peerName: String) async -> Bool
}

@MainActor
protocol PeerTransport: AnyObject {
    
    // MARK: - Identity
    
    var myDisplayName: String { get }
    
    // MARK: - Delegation
    
    var approvalDelegate: PeerConnectionApproving? { get set }
    
    // MARK: - Streams
    
    /// Потоки мультикастовые: каждое обращение отдаёт НОВЫЙ независимый
    /// `AsyncStream`, и все подписчики получают одни и те же события.
    /// Реализация обязана держать по одному continuation на подписчика,
    /// иначе два `for await` начнут делить события
    /// между собой вместо того чтобы каждый получил все.
    
    var peerStream: AsyncStream<[Peer]> { get }
    var messageStream: AsyncStream<MessagePayload> { get }
    var typingStream: AsyncStream<TypingEvent> { get }
    
    // MARK: - Discovery
    
    func startDeviceDiscovery()
    func stopDeviceDiscovery()
    func connectToPeer(displayName: String) async throws
    
    // MARK: - Connection Management
    
    /// Пир адресуется отображаемым именем, а не транспортным идентификатором.
    /// Было `getPeerID(for:) -> MCPeerID?` плюс `disconnect(from: MCPeerID)` —
    /// связка, из-за которой тип из MultipeerConnectivity протекал и в
    /// протокол, и во все вызывающие места.
    func disconnect(from displayName: String)
    func disconnectAll()
    
    // MARK: - Messaging
    
    func sendMessage(_ payload: MessagePayload) async throws
    func sendTypingEvent(_ event: TypingEvent) async throws
}

extension MultipeerService: PeerTransport {}

// MARK: - Factory

enum PeerTransportFactory {

    /// Собирает транспорт по настройкам: задан адрес релея — идём через него,
    /// иначе остаёмся на MultipeerConnectivity.
    @MainActor
    static func make() -> any PeerTransport {
        if let relayURL = UserSettings.relayURL {
            print("[PeerTransportFactory] Relay transport: \(relayURL)")
            return WebSocketTransport(url: relayURL)
        }

        print("[PeerTransportFactory] Multipeer transport")
        return MultipeerService()
    }
}
