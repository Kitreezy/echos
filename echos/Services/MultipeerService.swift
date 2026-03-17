//
//  MultipeerService.swift
//  echos
//
//  Created by Artem Rodionov on 18.02.2026.
//

import Foundation
import MultipeerConnectivity

@MainActor
protocol MultipeerInvitationDelegate: AnyObject {
    /// Показать UI для подтверждения подключения.
    /// - Returns: true если пользователь принял, false если отклонил
    func shouldAcceptInvitation(from peerName: String) async -> Bool
}

final class MultipeerService: NSObject {
    
    // MARK: - Configuration
    
    /// Service type - идентификатор для поиска
    /// Формат: <app>-<feature>
    private let serviceType = "echos-chat"
    /// Уникальное имя устройства в сети (дефолт из Settings берем)
    private let myPeerID: MCPeerID
    
    // MARK: — Public API для получения имени
    
    var myDisplayName: String {
        myPeerID.displayName
    }
    
    // MARK: - Delegation
    
    weak var invitationDelegate: MultipeerInvitationDelegate?
    
    // MARK: - Multipeer Components
    
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private var session: MCSession?
    
    // MARK: - State
    
    /// Обнаружение устройства (peerID -> displayName)
    @MainActor
    private var discoveredPeers: [MCPeerID: String] = [:]
    
    /// Для ручного подключения
    @MainActor
    private var discoveredPeerIDs: [String: MCPeerID] = [:]
    
    @MainActor
    private var connectingPeers: Set<MCPeerID> = []
    
    @MainActor
    private var connectedPeers: Set<MCPeerID> = []
    
    @MainActor
    private var peerUUIDs: [MCPeerID: UUID] = [:]
    
    @MainActor
    private var peerRSSI: [MCPeerID: Int] = [:]
    
    @MainActor
    private var peerDistances: [MCPeerID: Double] = [:]
    
    // MARK: - Streams
    
    /// Для обнаружения устройств.
    private var peerStreamContinuation: AsyncStream<[Peer]>.Continuation?
    let peerStream: AsyncStream<[Peer]>
    
    /// Для входащих сообщений
    private var messageStreamContinuation: AsyncStream<MessagePayload>.Continuation?
    let messageStream: AsyncStream<MessagePayload>
    
    /// Для typing-событий
    private var  typingStreamContinuation: AsyncStream<TypingEvent>.Continuation?
    let typingStream: AsyncStream<TypingEvent>
    
    // MARK: - Init
    
    override init() {
        let displayName = UserSettings.displayName
        self.myPeerID = MCPeerID(displayName: displayName)

        // Peer stream
        let (peerStream, peerCont) = AsyncStream.makeStream(of: [Peer].self)
        self.peerStream = peerStream
        self.peerStreamContinuation = peerCont

        // Message stream
        let (msgStream, msgCont) = AsyncStream.makeStream(of: MessagePayload.self)
        self.messageStream = msgStream
        self.messageStreamContinuation = msgCont

        // Typing stream
        let (typingStream, typingCont) = AsyncStream.makeStream(of: TypingEvent.self)
        self.typingStream = typingStream
        self.typingStreamContinuation = typingCont

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
        
        // Временно решение: симуляция RSSI для найденных peers
        Task {
            try? await Task.sleep(for: .seconds(2))
            await simulateRSSIUpdates()
        }
        
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
    
    // Симуляция RSSI (пока нет Core Bluetooth)
    @MainActor
    private func simulateRSSIUpdates() {
        for peerID in discoveredPeers.keys {
            let rssi = Int.random(in: -90...(-40))
            peerRSSI[peerID] = rssi
            peerDistances[peerID] = calculateDistance(from: rssi)
        }
        emitPeers()
        
        Task {
            try? await Task.sleep(for: .seconds(3))
            await simulateRSSIUpdates()
        }
    }
    
    // MARK: - Manual Connection
    
    func connectToPeer(displayName: String) async throws {
        guard let peerID = await discoveredPeerIDs[displayName] else {
            throw MultipeerError.peerNotFound
        }
        
        guard let browser = browser, let session = session else {
            throw MultipeerError.noSession
        }
        
        await MainActor.run {
            connectingPeers.insert(peerID)
            emitPeers()
        }
        
        print("[Browser] Manually connecting to '\(displayName)'")
        browser.invitePeer(peerID,
                           to: session,
                           withContext: nil,
                           timeout: 10)
    }
    
    // MARK: - RSSI Calculation
    /// Приблизительное вычисление дистанции (пока без интеграции CoreBluetooth)
    private func calculateDistance(from rssi: Int) -> Double {
        let txPower: Double = -40
        let pathLossExponent = 2.5
        
        let ratio = (txPower - Double(rssi)) / (10 * pathLossExponent)
        let distance = pow(10, ratio)
        
        return max(1, min(distance, 100))
    }
    
    // MARK: - Connection Managment
    
    @MainActor
    func getPeerID(for displayName: String) -> MCPeerID? {
        discoveredPeerIDs[displayName]
    }
    
    func disconnect(from peerID: MCPeerID) {
        guard let session = session else {
            return
        }
        
        Task { @MainActor in
            print("[MultipeerService] Disconnecting from '\(peerID.displayName)'")
            
            // MCSession не имеет метода disconnect для одного peer
            // Нужно пересоздать session без этого peer
            // Или просто удалить из connectedPeers и обновить UI
            
            connectedPeers.remove(peerID)
            emitPeers()
            
            session.disconnect()
        }
    }

    func disconnectAll() {
        session?.disconnect()
        
        Task { @MainActor in
            connectedPeers.removeAll()
            connectingPeers.removeAll()
            emitPeers()
            print("[MultipeerService] Disconnected from all peers")
        }
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
        
        let packet = try MultipeerPacket(message: payload)
        let data = try JSONEncoder().encode(packet)
        
        // Отправляем всем подключённым peers
        try session.send(data, toPeers: Array(connectedPeers), with: .reliable)
        
        print("[Session] Sent message to \(connectedPeers.count) peer(s)")
    }
    
    // MARK: - Typing
    
    func sendTypingEvent(_ event: TypingEvent) async throws {
        guard let session = session else {
            throw MultipeerError.noSession
        }
        
        let connectedPeers = await getConnectedPeers()
        guard !connectedPeers.isEmpty else {
            throw MultipeerError.noPeers
        }
        
        let packet = try MultipeerPacket(typingEvent: event)
        let data = try JSONEncoder().encode(packet)
        
        try session.send(data, toPeers: Array(connectedPeers), with: .unreliable)
        print("[Session] Sent typing event: \(event.type)")
    }
    
    @MainActor
    private func getConnectedPeers() -> Set<MCPeerID> {
        connectedPeers
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func getStableUUID(for peerID: MCPeerID) -> UUID {
        if let existing = peerUUIDs[peerID] {
            return existing
        }
        let newUUId = UUID()
        peerUUIDs[peerID] = newUUId
        return newUUId
    }
    
    /// Конвертирм internal state в модели Peer для ViewModel.
    @MainActor
    private func emitPeers() {
        let peers = discoveredPeers.map { peerID, displayName in
            let status: PeerStatus
            
            if connectedPeers.contains(peerID) {
                status = .connected
            } else if connectingPeers.contains(peerID) {
                status = .connecting
            } else {
                status = .notConnected
            }
            return Peer(id: getStableUUID(for: peerID),
                        displayName: displayName,
                        status: status,
                        lastSeen: Date(),
                        rssi: peerRSSI[peerID],
                        distance: peerDistances[peerID])
        }
        peerStreamContinuation?.yield(peers)
    }
    
    deinit {
        stopDeviceDiscovery()
        peerStreamContinuation?.finish()
        messageStreamContinuation?.finish()
        typingStreamContinuation?.finish()
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    
    /// Кто-то нашёл нас и хочет подключиться (invite).
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            print("[Advertiser] Received invite from '\(peerID.displayName)'")
            guard let session = session else {
                invitationHandler(false, nil)
                return
            }
            
            if discoveredPeers[peerID] == nil {
                discoveredPeers[peerID] = peerID.displayName
                discoveredPeerIDs[peerID.displayName] = peerID
            }
            
            if let delegate = invitationDelegate {
                let shouldAccept = await delegate.shouldAcceptInvitation(from: peerID.displayName)
                
                if shouldAccept {
                    connectingPeers.insert(peerID)
                    emitPeers()
                    invitationHandler(true, session)
                    print("[Advertiser] Accepted invite from '\(peerID.displayName)'")
                } else {
                    invitationHandler(false, session)
                    print("[Advertiser] Declined invite from '\(peerID.displayName)'")
                }
            } else {
                connectingPeers.insert(peerID)
                emitPeers()
                invitationHandler(true, session)
                print("[Advertiser] Auto-accepted invite from '\(peerID.displayName)'")
            }
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
            discoveredPeerIDs[peerID.displayName] = peerID
            
            if let rssiString = info?["RSSI"],
               let rssi = Int(rssiString) {
                peerRSSI[peerID] = rssi
                peerDistances[peerID] = calculateDistance(from: rssi)
                print("[MultipeerService] RSSI for \(peerID.displayName): \(rssi) dBm (~\(Int(peerDistances[peerID] ?? 0))m)")
            }
            
            emitPeers()
        }
    }
    
    /// Устройство пропало из радиуса.
    func browser(_ browser: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[Browser] Lost peer: '\(peerID.displayName)'")
            discoveredPeers.removeValue(forKey: peerID)
            discoveredPeerIDs.removeValue(forKey: peerID.displayName)
            connectedPeers.remove(peerID)
            
            peerRSSI.removeValue(forKey: peerID)
            peerDistances.removeValue(forKey: peerID)
            
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
                connectingPeers.remove(peerID)
                
            case .connecting:
                print("[Session] '\(peerID.displayName)' connecting...")
                connectingPeers.insert(peerID)
                
            case .connected:
                print("[Session] '\(peerID.displayName)' connected")
                connectingPeers.remove(peerID)
                connectedPeers.insert(peerID)
                
                if discoveredPeers[peerID] == nil {
                    discoveredPeers[peerID] = peerID.displayName
                    discoveredPeerIDs[peerID.displayName] = peerID
                }
                
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
            let decoder = JSONDecoder()
            
            do {
                let packet = try decoder.decode(MultipeerPacket.self, from: data)
                
                switch packet.type {
                case .message:
                    print("[Session] Recived message from '\(peerID.displayName)")
                    let payload = try packet.decodeMessage()
                    messageStreamContinuation?.yield(payload)
                    
                case .typing:
                    print("[Session] Recived typing event from '\(peerID.displayName)")
                    let event = try packet.decodeTypingEvent()
                    typingStreamContinuation?.yield(event)
                }
                
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
    case peerNotFound
    
    var errorDescription: String? {
        switch self {
        case .noSession:
            return "MCSession не создана"
            
        case .noPeers:
            return "Нет подключённых устройств"
            
        case .sendFailed:
            return "Не удалось отправить сообщение"
            
        case .peerNotFound:
            return "Устройство не найдено"
        }
    }
}
