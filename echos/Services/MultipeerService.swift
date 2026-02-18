//
//  MultipeerService.swift
//  echos
//
//  Created by Artem Rodionov on 18.02.2026.
//

import Foundation
import MultipeerConnectivity

final class MultipeerService: NSObject {
    
    // MARK: - Configuration
    
    /// Service type - идентификатор для поиска
    /// Формат: <app>-<feature>
    private let serviceType = "echos-chat"
    /// Уникальное имя устройства в сети (дефолт из Settings берем)
    private let myPeerID: MCPeerID
    
    // MARK: - Multipeer Components
    
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private var session: MCSession?
    
    // MARK: - State
    
    /// Обнаружение устройства (peerID -> displayName)
    @MainActor
    private var discoveredPeers: [MCPeerID: String] = [:]
    
    @MainActor
    private var connectedPeers: Set<MCPeerID> = []
    
    // MARK: - Streams
    
    /// Для обнаружения устройств.
    private var peerStreamContinuation: AsyncStream<[Peer]>.Continuation?
    let peerStream: AsyncStream<[Peer]>
    
    /// Для входащих сообщений
    private var messageStreamContinuation: AsyncStream<MessagePayload>.Continuation?
    let messageStream: AsyncStream<MessagePayload>
    
    // MARK: - Init
    
    override init() {
        // Используем имя устройства как peerID
        let deviceName = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: deviceName)
        
        var peerCont: AsyncStream<[Peer]>.Continuation?
        self.peerStream = AsyncStream { cont in
            peerCont = cont
        }
        self.peerStreamContinuation = peerCont
        
        var msgCong: AsyncStream<MessagePayload>.Continuation?
        self.messageStream = AsyncStream { cont in
            msgCong = cont
        }
        self.messageStreamContinuation = msgCong
        
        super.init()
    }
    
    // MARK: - Discovery
    
    /// Запускаем advertiser (объявляем себя) и browser (ищем других).
    func startDeviceDiscovery() {
        stopDeviceDiscovery()
        
        session = MCSession(peer: myPeerID,
                            securityIdentity: nil,  // TODO step 8: CryptoKit для end-to-end
                            encryptionPreference: .required)
        
        session?.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                               discoveryInfo: nil, // можно передавать метаданные
                                               serviceType: serviceType)
        
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        browser = MCNearbyServiceBrowser(peer: myPeerID,
                                         serviceType: serviceType)
        
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        print("[MultipeerService] Discovery started: advertising as '\(myPeerID.displayName)")
    }
    
    func stopDeviceDiscovery() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        
        session?.disconnect()
        session?.delegate = nil
        session = nil
    
        print("[MultipeerService] Discovery stopped")
    }
    
    // MARK: - Messaging
    
    func sendMessage(_ payload: MessagePayload) async throws {
        guard let session = session else {
            throw MultipeerError.noSession
        }
        
        let connectedPeers = await getConnectedPeers()
        guard !connectedPeers.isEmpty else {
            throw MultipeerError.noPeers
        }
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        
        // Отправляем всем подключённым peers
        try session.send(data, toPeers: Array(connectedPeers), with: .reliable)
        
        print("[Session] Sent message to \(connectedPeers.count) peer(s)")
    }
    
    @MainActor
    private func getConnectedPeers() -> Set<MCPeerID> {
        connectedPeers
    }
    
    // MARK: - Helpers
    
    /// Конвертирм internal state в модели Peer для ViewModel.
    @MainActor
    private func emitPeers() {
        let peers = discoveredPeers.map { peerID, displayName in
            let status: PeerStatus = connectedPeers.contains(peerID) ? .connected : .notConnected
            return Peer(id: UUID(),    // временный ID
                        displayName: displayName,
                        status: status,
                        lastSeen: Date())
        }
        peerStreamContinuation?.yield(peers)
    }
    
    deinit {
        stopDeviceDiscovery()
        peerStreamContinuation?.finish()
        messageStreamContinuation?.finish()
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    
    /// Кто-то нашёл нас и хочет подключиться (invite).
    /// step 4: здесь будем принимать/отклонять приглашения.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            print("[Advertiser] Received invite from '\(peerID.displayName)'")
            // Пока автоматически принимаем все приглашения
            // TODO step 6: показать UI-алерт для подтверждения
            guard let session = session else {
                invitationHandler(false, nil)
                return
            }
            
            invitationHandler(true, session)
            print("[Advertiser] Accepted invite from '\(peerID.displayName)'")
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: any Error) {
        Task { @MainActor in
            print("[Advertiser] Failed to start: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    
    /// Устройство найдено.
    func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            print("[Browser] Found peer '\(peerID.displayName)'")
            discoveredPeers[peerID] = peerID.displayName
            guard let session = session else {
                return
            }
            browser.invitePeer(peerID,
                               to: session,
                               withContext: nil,
                               timeout: 10)
            print("[Browser] Sent invite to '\(peerID.displayName)'")
            
            emitPeers()
        }
    }
    
    /// Устройство пропало из радиуса.
    func browser(_ browser: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[Browser] Lost peer: '\(peerID.displayName)'")
            discoveredPeers.removeValue(forKey: peerID)
            connectedPeers.remove(peerID)
            emitPeers()
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: any Error) {
        Task { @MainActor in
            print("[Browser] Failed to start: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
        
    // Состояние подключения изменилось
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .notConnected:
                print("[Session] '\(peerID.displayName)' disconnected")
                connectedPeers.remove(peerID)
                
            case .connecting:
                print("[Session] '\(peerID.displayName)' connecting...")
                
            case .connected:
                print("[Session] '\(peerID.displayName)' connected")
                connectedPeers.insert(peerID)
                
            @unknown default:
                break
            }
            emitPeers()
        }
    }
    
    // Получили данные
    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[Session] Received data from '\(peerID.displayName)'")
            
            let decoder = JSONDecoder()
            do {
                let playLoad = try decoder.decode(MessagePayload.self, from: data)
                messageStreamContinuation?.yield(playLoad)
            } catch {
                print("[Session] Failed to decode message: \(error)")
            }
        }
    }
    
    // MARK: — Unused MCSessionDelegate methods
    
    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {
        // Не используется streams
    }
    
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {
        // Не используется file transfers
    }
    
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: (any Error)?) {
        // Не используется file transfers
    }

}


// MARK: - Errors

enum MultipeerError: LocalizedError {
    case noSession
    case noPeers
    case sendFailed
    
    var errorDescription: String? {
        switch self {
        case .noSession:
            return "MCSession не создана"
            
        case .noPeers:
            return "Нет подключённых устройств"
            
        case .sendFailed:
            return "Не удалось отправить сообщение"
        }
    }
}
