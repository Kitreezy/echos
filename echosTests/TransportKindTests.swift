//
//  TransportKindTests.swift
//  echosTests
//
//  Каким способом держать связь.
//

import XCTest
@testable import echos

final class TransportKindTests: XCTestCase {

    /// По умолчанию echos про тех, кто рядом. Дальняя связь требует интернета
    /// и чужого сервера — это выбор человека, а не наше решение за него.
    func test_byDefault_staysNearby() {
        XCTAssertEqual(PeerTransportFactory.kind(usesRelay: false, customURL: nil), .nearby)
    }

    func test_whenChosen_goesThroughTheBuiltInRelay() {
        XCTAssertEqual(PeerTransportFactory.kind(usesRelay: true, customURL: nil),
                       .relay(UserSettings.defaultRelayURL))
    }

    /// Свой адрес задают аргументом запуска ради проверки на поднятом рядом
    /// сервере. Это явная просьба, и переключатель для неё трогать не надо.
    func test_customAddress_isEnoughByItself() {
        let local = URL(string: "ws://mac.local:8080/ws")!

        XCTAssertEqual(PeerTransportFactory.kind(usesRelay: false, customURL: local),
                       .relay(local))
    }

    func test_customAddress_winsOverTheBuiltInOne() {
        let local = URL(string: "ws://mac.local:8080/ws")!

        XCTAssertEqual(PeerTransportFactory.kind(usesRelay: true, customURL: local),
                       .relay(local))
    }
}
