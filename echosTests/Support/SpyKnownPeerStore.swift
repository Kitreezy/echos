//
//  SpyKnownPeerStore.swift
//  echosTests
//

import Foundation
@testable import echos

@MainActor
final class SpyKnownPeerStore: KnownPeerStoring {

    private(set) var remembered: [(address: String, name: String)] = []
    var preloaded: [KnownPeer] = []

    func loadKnownPeers() async throws -> [KnownPeer] {
        preloaded
    }

    func remember(address: String, name: String) async throws {
        remembered.append((address, name))
        preloaded.removeAll { $0.address == address }
        preloaded.append(KnownPeer(address: address,
                                   name: name,
                                   firstSeen: Date(),
                                   lastSeen: Date()))
    }

    func forgetAll() async throws {
        remembered.removeAll()
        preloaded.removeAll()
    }
}
