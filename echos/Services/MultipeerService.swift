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
    
    // MARK: - State
    
    /// Обнаружение устройства (peerID -> displayName)
    @MainActor
    private var discoveredPeers: [MCPeerID: String] = [:]
    
    /// AsyncStream для обнаружения устройств.
    private var peerStreamContinuation: AsyncStream<[Peer]>.Continuation?
    let peerStream: AsyncStream<[Peer]>
    
    // MARK: - Init
    
    override init() {
        // Используем имя устройства как peerID
        let deviceName = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: deviceName)
        
        var continuation: AsyncStream<[Peer]>.Continuation?
        self.peerStream = AsyncStream { cont in
            continuation = cont
        }
        self.peerStreamContinuation = continuation
        
        super.init()
    }
    
    // MARK: - Discovery
    
    /// Запускаем advertiser (объявляем себя) и browser (ищем других).
    func startDeviceDiscovery() {
        stopDeviceDiscovery()
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                               discoveryInfo: nil, // можем передавать метаданные
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
    
        print("[MultipeerService] Discovery stopped")
    }
    
    // MARK: - Helpers
    
    /// Конвертирм internal state в модели Peer для ViewModel.
    @MainActor
    private func emitPeers() {
        let peers = discoveredPeers.map { peerID, displayName in
            Peer(id: UUID(),    // временный ID
                 displayName: displayName,
                 status: .notConnected, // пока только обнаружение
                 lastSeen: Date())
        }
        peerStreamContinuation?.yield(peers)
    }
    
    deinit {
        stopDeviceDiscovery()
        peerStreamContinuation?.finish()
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
            // TODO step 4: создать MCSession и принять invite
            // Пока отклоняем автоматически
            invitationHandler(false, nil)
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
            emitPeers()
        }
    }
    
    /// Устройство пропало из радиуса.
    func browser(_ browser: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[Browser] Lost peer: '\(peerID.displayName)'")
            discoveredPeers.removeValue(forKey: peerID)
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
