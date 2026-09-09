//
//  NetworkMonitoring.swift
//  echos
//
//  Состояние сетевого пути как поток событий.
//
//  Зачем: без него клиент переподключается вслепую. При выключенном Wi-Fi он
//  честно долбится по таймеру, жжёт батарею и раздувает backoff до потолка —
//  а когда сеть возвращается, ждёт эти секунды вместо мгновенного коннекта.
//
//  Протокол нужен для тестов: пропажу сети на симуляторе не воспроизвести,
//  зато подставной монитор позволяет проиграть любой сценарий.
//

import Foundation
import Network

/// Снимок состояния сети.
struct NetworkPathSnapshot: Sendable, Equatable {

    /// Есть ли вообще путь наружу.
    let isReachable: Bool

    /// Через что идём. Смена интерфейса — отдельное событие: при переходе
    /// Wi-Fi ↔ LTE меняется локальный адрес, и старое TCP-соединение рвётся
    /// молча — сокет об этом не сообщит.
    let interface: NWInterface.InterfaceType?

    /// Сотовая связь или личная точка доступа.
    let isExpensive: Bool

    init(isReachable: Bool,
         interface: NWInterface.InterfaceType? = nil,
         isExpensive: Bool = false) {
        self.isReachable = isReachable
        self.interface = interface
        self.isExpensive = isExpensive
    }

    static let unreachable = NetworkPathSnapshot(isReachable: false)
}

@MainActor
protocol NetworkMonitoring: AnyObject {

    /// Текущее состояние. `nil` — монитор ещё не получил первый путь.
    var currentPath: NetworkPathSnapshot? { get }

    /// Поток изменений. Мультикастовый и реплеит последнее значение:
    /// подписавшийся позже сразу узнаёт, есть ли сеть.
    var pathUpdates: AsyncStream<NetworkPathSnapshot> { get }

    func start()
    func stop()
}

@MainActor
final class NetworkMonitor: NetworkMonitoring {

    static let shared = NetworkMonitor()

    private(set) var currentPath: NetworkPathSnapshot?

    private let broadcast = AsyncBroadcast<NetworkPathSnapshot>(replaysLatest: true)
    var pathUpdates: AsyncStream<NetworkPathSnapshot> { broadcast.stream }

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.echos.network-monitor")

    init() {}

    func start() {
        guard monitor == nil else {
            return
        }

        let monitor = NWPathMonitor()
        self.monitor = monitor

        // Колбэк приходит с собственной очереди — прыгаем на главный актор,
        // где живёт всё остальное состояние.
        monitor.pathUpdateHandler = { path in
            let snapshot = NetworkPathSnapshot(path)

            Task { @MainActor [weak self] in
                self?.apply(snapshot)
            }
        }

        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.pathUpdateHandler = nil
        monitor?.cancel()
        monitor = nil
    }

    private func apply(_ snapshot: NetworkPathSnapshot) {
        guard snapshot != currentPath else {
            return
        }

        currentPath = snapshot
        print("[NetworkMonitor] reachable: \(snapshot.isReachable), interface: \(String(describing: snapshot.interface))")
        broadcast.yield(snapshot)
    }
}

private extension NetworkPathSnapshot {

    init(_ path: NWPath) {
        self.init(isReachable: path.status == .satisfied,
                  interface: path.availableInterfaces.first?.type,
                  isExpensive: path.isExpensive)
    }
}
