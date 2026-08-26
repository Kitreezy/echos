//
//  PeerTests.swift
//  echosTests
//
//  Unit: производные свойства модели Peer (чистые вычисления).
//

import XCTest
@testable import echos

final class PeerTests: XCTestCase {
    
    private func peer(rssi: Int?) -> Peer {
        Peer(displayName: "Alice", rssi: rssi)
    }
    
    // MARK: - signalPercentage
    
    func test_signalPercentage_atBounds() {
        XCTAssertEqual(peer(rssi: -100).signalPercentage, 0)
        XCTAssertEqual(peer(rssi: -30).signalPercentage, 100)
        XCTAssertEqual(peer(rssi: -65).signalPercentage, 50)
    }
    
    /// Значения за пределами шкалы должны обрезаться, а не давать <0 / >100.
    func test_signalPercentage_clampsOutOfRangeValues() {
        XCTAssertEqual(peer(rssi: -140).signalPercentage, 0)
        XCTAssertEqual(peer(rssi: 0).signalPercentage, 100)
    }
    
    func test_signalPercentage_withoutRSSI_isZero() {
        XCTAssertEqual(peer(rssi: nil).signalPercentage, 0)
    }
    
    // MARK: - formattedDistance
    
    func test_formattedDistance_roundsDownAndFallsBack() {
        XCTAssertEqual(Peer(displayName: "A", distance: 12.7).formattedDistance, "12M")
        XCTAssertEqual(Peer(displayName: "A", distance: nil).formattedDistance, "??M")
    }
    
    // MARK: - isActive
    
    func test_isActive_onlyWhenConnected() {
        XCTAssertTrue(Peer(displayName: "A", status: .connected).isActive)
        XCTAssertFalse(Peer(displayName: "A", status: .connecting).isActive)
        XCTAssertFalse(Peer(displayName: "A", status: .notConnected).isActive)
        XCTAssertFalse(Peer(displayName: "A", status: .failed).isActive)
    }
}
