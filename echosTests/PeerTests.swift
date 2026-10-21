//
//  PeerTests.swift
//  echosTests
//
//  Unit: производные свойства модели Peer (чистые вычисления).
//

import Foundation
import Testing
@testable import echos

struct PeerTests {
    
    private func peer(rssi: Int?) -> Peer {
        Peer(displayName: "Alice", rssi: rssi)
    }
    
    // MARK: - signalPercentage
    
    /// RSSI → процент: края шкалы, середина, выход за пределы — обрезается,
    /// а не даёт <0 или >100, — и отсутствие сигнала. Пары — через zip:
    /// иначе Swift Testing перемножил бы два списка.
    @Test(arguments: zip([-100, -30, -65, -140, 0, nil] as [Int?],
                         [0, 100, 50, 0, 100, 0]))
    func signalPercentage(rssi: Int?, expected: Int) {
        #expect(peer(rssi: rssi).signalPercentage == expected)
    }
    
    // MARK: - formattedDistance
    
    @Test func formattedDistance_roundsDownAndFallsBack() {
        #expect(Peer(displayName: "A", distance: 12.7).formattedDistance == "12M")
        #expect(Peer(displayName: "A", distance: nil).formattedDistance == "??M")
    }
    
    // MARK: - isActive
    
    @Test func isActive_onlyWhenConnected() {
        #expect(Peer(displayName: "A", status: .connected).isActive)
        #expect(!(Peer(displayName: "A", status: .connecting).isActive))
        #expect(!(Peer(displayName: "A", status: .notConnected).isActive))
        #expect(!(Peer(displayName: "A", status: .failed).isActive))
    }
}
