//
//  TransportKindTests.swift
//  echosTests
//
//  Каким способом держать связь.
//

import Foundation
import Testing
@testable import echos

struct TransportKindTests {

    /// По умолчанию echos про тех, кто рядом. Дальняя связь требует интернета
    /// и чужого сервера — это выбор человека, а не наше решение за него.
    @Test func byDefault_staysNearby() {
        #expect(PeerTransportFactory.kind(usesRelay: false, customURL: nil) == .nearby)
    }

    @Test func whenChosen_goesThroughTheBuiltInRelay() {
        #expect(PeerTransportFactory.kind(usesRelay: true, customURL: nil) == .relay(UserSettings.defaultRelayURL))
    }

    /// Свой адрес задают аргументом запуска ради проверки на поднятом рядом
    /// сервере. Это явная просьба, и переключатель для неё трогать не надо.
    @Test func customAddress_isEnoughByItself() {
        let local = URL(string: "ws://mac.local:8080/ws")!

        #expect(PeerTransportFactory.kind(usesRelay: false, customURL: local) == .relay(local))
    }

    @Test func customAddress_winsOverTheBuiltInOne() {
        let local = URL(string: "ws://mac.local:8080/ws")!

        #expect(PeerTransportFactory.kind(usesRelay: true, customURL: local) == .relay(local))
    }
}
