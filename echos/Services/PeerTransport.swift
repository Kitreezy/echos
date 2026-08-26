//
//  PeerTransport.swift
//  echos
//
//  Абстракция над транспортом для обмена с соседними устройствами.
//
//  Зачем: `MultipeerConnectivity` требует двух реальных устройств и разрешения
//  на локальную сеть — в тестах его поднять нельзя. Протокол даёт шов (seam),
//  в который в интеграционных тестах подставляется `LoopbackTransport`.
//

import Foundation
import MultipeerConnectivity

@MainActor
protocol PeerTransport: AnyObject {
    
    // MARK: - Identity
    
    var myDisplayName: String { get }
    
    // MARK: - Delegation
    
    var invitationDelegate: MultipeerInvitationDelegate? { get set }
    
    // MARK: - Streams
    
    var peerStream: AsyncStream<[Peer]> { get }
    var messageStream: AsyncStream<MessagePayload> { get }
    var typingStream: AsyncStream<TypingEvent> { get }
    
    // MARK: - Discovery
    
    func startDeviceDiscovery()
    func stopDeviceDiscovery()
    func connectToPeer(displayName: String) async throws
    
    // MARK: - Connection Management
    
    func getPeerID(for displayName: String) -> MCPeerID?
    func disconnect(from peerID: MCPeerID)
    func disconnectAll()
    
    // MARK: - Messaging
    
    func sendMessage(_ payload: MessagePayload) async throws
    func sendTypingEvent(_ event: TypingEvent) async throws
}

extension MultipeerService: PeerTransport {}
