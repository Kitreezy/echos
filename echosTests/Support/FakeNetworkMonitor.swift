//
//  FakeNetworkMonitor.swift
//  echosTests
//
//  Подставной монитор сети.
//
//  Пропажу Wi-Fi на симуляторе не воспроизвести, а Network Link Conditioner
//  требует устройства. Здесь же любой сценарий разыгрывается за миллисекунды:
//  сеть исчезла, вернулась, сменился интерфейс.
//

import Foundation
import Network
@testable import echos

@MainActor
final class FakeNetworkMonitor: NetworkMonitoring {

    private(set) var currentPath: NetworkPathSnapshot?
    private(set) var isRunning = false

    private let broadcast = AsyncBroadcast<NetworkPathSnapshot>(replaysLatest: true)
    var pathUpdates: AsyncStream<NetworkPathSnapshot> { broadcast.stream }

    /// Стартовое состояние. По умолчанию сеть есть — так ведёт себя монитор
    /// на нормальном устройстве.
    init(initial: NetworkPathSnapshot? = NetworkPathSnapshot(isReachable: true, interface: .wifi)) {
        currentPath = initial
    }

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    // MARK: - Управление из теста

    func send(_ snapshot: NetworkPathSnapshot) {
        currentPath = snapshot
        broadcast.yield(snapshot)
    }

    func goOffline() {
        send(.unreachable)
    }

    func goOnline(interface: NWInterface.InterfaceType = .wifi) {
        send(NetworkPathSnapshot(isReachable: true, interface: interface))
    }
}
