//
//  MultipeerService.swift
//  echos
//
//  Created by Artem Rodionov on 18.02.2026.
//

import Foundation
@preconcurrency import MultipeerConnectivity

/// Делегатные методы MultipeerConnectivity приходят с фоновых очередей,
/// поэтому они помечены `nonisolated` и явно прыгают на главный актор.
@MainActor
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
    
    weak var approvalDelegate: PeerConnectionApproving?
    
    // MARK: - Multipeer Components
    
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private var session: MCSession?
    
    // MARK: - State
    
    /// Обнаружение устройства (peerID -> displayName)
    private var discoveredPeers: [MCPeerID: String] = [:]
    
    /// Для ручного подключения
    private var discoveredPeerIDs: [String: MCPeerID] = [:]
    
    private var connectingPeers: Set<MCPeerID> = []
    
    private var connectedPeers: Set<MCPeerID> = []
    
    private var peerUUIDs: [MCPeerID: UUID] = [:]
    
    private var peerRSSI: [MCPeerID: Int] = [:]
    
    private var peerDistances: [MCPeerID: Double] = [:]
    
    // MARK: - Streams
    
    /// Потоки мультикастовые: каждое обращение к свойству отдаёт новый
    /// независимый `AsyncStream`, и все подписчики получают одни и те же
    /// события. 
    
    /// Для обнаружения устройств. Реплеит последний список: экран, открытый
    /// после начала поиска, сразу видит уже найденные устройства.
    private let peerBroadcast = AsyncBroadcast<[Peer]>(replaysLatest: true)
    var peerStream: AsyncStream<[Peer]> { peerBroadcast.stream }
    
    /// Для входящих сообщений
    private let messageBroadcast = AsyncBroadcast<MessagePayload>()
    var messageStream: AsyncStream<MessagePayload> { messageBroadcast.stream }
    
    /// Для typing-событий
    private let typingBroadcast = AsyncBroadcast<TypingEvent>()
    var typingStream: AsyncStream<TypingEvent> { typingBroadcast.stream }
    
    /// Для росчерков на стене
    private let strokeBroadcast = AsyncBroadcast<Stroke>()
    var strokeStream: AsyncStream<Stroke> { strokeBroadcast.stream }
    
    // MARK: - Init
    
    override init() {
        let displayName = UserSettings.displayName
        self.myPeerID = MCPeerID(displayName: displayName)

        super.init()
        print("[lifecycle] MultipeerService init — advertising as '\(displayName)'")
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
            simulateRSSIUpdates()
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
    private func simulateRSSIUpdates() {
        for peerID in discoveredPeers.keys {
            let rssi = Int.random(in: -90...(-40))
            peerRSSI[peerID] = rssi
            peerDistances[peerID] = calculateDistance(from: rssi)
        }
        emitPeers()
        
        Task {
            try? await Task.sleep(for: .seconds(3))
            simulateRSSIUpdates()
        }
    }
    
    // MARK: - Manual Connection
    
    func connectToPeer(displayName: String) async throws {
        guard let peerID = discoveredPeerIDs[displayName] else {
            throw MultipeerError.peerNotFound
        }
        
        guard let browser = browser, let session = session else {
            throw MultipeerError.noSession
        }
        
        connectingPeers.insert(peerID)
        emitPeers()
        
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
    
    func disconnect(from displayName: String) {
        guard let session = session,
              let peerID = discoveredPeerIDs[displayName] else {
            return
        }
        
        print("[MultipeerService] Disconnecting from '\(peerID.displayName)'")

        // MCSession не имеет метода disconnect для одного peer
        // Нужно пересоздать session без этого peer
        // Или просто удалить из connectedPeers и обновить UI

        connectedPeers.remove(peerID)
        emitPeers()

        session.disconnect()
    }

    func disconnectAll() {
        session?.disconnect()
        
        connectedPeers.removeAll()
        connectingPeers.removeAll()
        emitPeers()
        print("[MultipeerService] Disconnected from all peers")
    }
    
    // MARK: - Messaging
    
    func sendMessage(_ payload: MessagePayload, to peerName: String) async throws {
        guard let session = session else {
            throw MultipeerError.noSession
        }
        
        let peerID = try connectedPeerID(named: peerName)
        
        let packet = try MultipeerPacket(message: payload)
        let data = try JSONEncoder().encode(packet)
        
        try session.send(data, toPeers: [peerID], with: .reliable)
        
        print("[Session] Sent message to '\(peerName)'")
    }
    
    /// Общая проверка для адресной отправки: собеседник найден и на связи.
    private func connectedPeerID(named peerName: String) throws -> MCPeerID {
        guard let peerID = discoveredPeerIDs[peerName],
              connectedPeers.contains(peerID) else {
            throw MultipeerError.peerNotFound
        }
        return peerID
    }
    
    // MARK: - Typing
    
    func sendTypingEvent(_ event: TypingEvent, to peerName: String) async throws {
        guard let session = session else {
            throw MultipeerError.noSession
        }
        
        let peerID = try connectedPeerID(named: peerName)
        
        let packet = try MultipeerPacket(typingEvent: event)
        let data = try JSONEncoder().encode(packet)
        
        try session.send(data, toPeers: [peerID], with: .unreliable)
        print("[Session] Sent typing event to '\(peerName)': \(event.type)")
    }

    /// Росчерк уходит одному — владельцу стены — и `.reliable`: индикатор
    /// набора можно потерять, а пропавший штрих оставит на стене дыру,
    /// которую нечем восполнить.
    func sendStroke(_ stroke: Stroke, to peerName: String) async throws {
        guard let session = session else {
            throw MultipeerError.noSession
        }
        
        let peerID = try connectedPeerID(named: peerName)
        
        let packet = try MultipeerPacket(stroke: stroke)
        let data = try JSONEncoder().encode(packet)
        
        try session.send(data, toPeers: [peerID], with: .reliable)
        print("[Session] Sent stroke to '\(peerName)' with \(stroke.points.count) points")
    }
    
    // MARK: - Helpers
    
    private func getStableUUID(for peerID: MCPeerID) -> UUID {
        if let existing = peerUUIDs[peerID] {
            return existing
        }
        let newUUId = UUID()
        peerUUIDs[peerID] = newUUId
        return newUUId
    }
    
    /// Конвертирм internal state в модели Peer для ViewModel.
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
        // Сортировка обязательна: `discoveredPeers` — словарь, порядок его
        // обхода меняется от вызова к вызову. Без стабильного порядка список
        // «дёргается» в UI, а `removeDuplicates` на стороне потребителя не
        // может опознать два одинаковых по сути обновления.
        .sorted { $0.displayName < $1.displayName }

        peerBroadcast.yield(peers)
    }
    
    /// `deinit` вызывается вне главного актора, поэтому изолированный стейт
    /// здесь трогать нельзя. Закрывать потоки руками и не нужно: вместе с
    /// сервисом освобождаются броадкастеры, а `AsyncStream` завершается сам,
    /// когда его continuation деаллоцируется.
    /// Остановку advertiser/browser/session делает `stopDeviceDiscovery()`.
    deinit {
        print("[lifecycle] MultipeerService deinit")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    
    /// Кто-то нашёл нас и хочет подключиться (invite).
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Замыкание из MultipeerConnectivity не помечено `@Sendable`, но
        // фреймворк гарантирует, что вызвать его можно ровно один раз
        // с любой очереди. Оборачиваем явно, чтобы протащить на главный актор.
        let respond = UncheckedSendableBox(invitationHandler)
        Task { @MainActor in
            let invitationHandler = respond.value
            print("[Advertiser] Received invite from '\(peerID.displayName)'")
            guard let session = session else {
                invitationHandler(false, nil)
                return
            }
            
            if discoveredPeers[peerID] == nil {
                discoveredPeers[peerID] = peerID.displayName
                discoveredPeerIDs[peerID.displayName] = peerID
            }
            
            if let delegate = approvalDelegate {
                let shouldAccept = await delegate.shouldAcceptConnection(from: peerID.displayName)
                
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
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: any Error) {
        Task { @MainActor in
            print("[Advertiser] Failed to start: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    
    /// Устройство найдено.
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
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
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
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
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: any Error) {
        Task { @MainActor in
            print("[Browser] Failed to start: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
        
    // Состояние подключения изменилось
    nonisolated func session(_ session: MCSession,
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
    nonisolated func session(_ session: MCSession,
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
                    messageBroadcast.yield(payload)
                    
                case .typing:
                    print("[Session] Recived typing event from '\(peerID.displayName)")
                    let event = try packet.decodeTypingEvent()
                    typingBroadcast.yield(event)
                    
                case .stroke:
                    print("[Session] Recived stroke from '\(peerID.displayName)")
                    let stroke = try packet.decodeStroke()
                    strokeBroadcast.yield(stroke)
                }
                
            } catch {
                print("[Session] Failed to decode message: \(error)")
            }
        }
    }
    
    // MARK: — Unused MCSessionDelegate methods
    
    nonisolated func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {
        // Не используется streams
    }
    
    nonisolated func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {
        // Не используется file transfers
    }
    
    nonisolated func session(_ session: MCSession,
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
