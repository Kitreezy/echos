//
//  CompositeTransport.swift
//  echos
//
//  Оба канала разом: рядом через MultipeerConnectivity и через релей.
//
//  Зачем: до этого пользователь выбирал один канал руками, и «когда рядом
//  никого нет, разговор идёт через релей» было обещанием, а не фактом. Здесь
//  два списка сливаются в один, а отправка идёт по тому каналу, которому
//  принадлежит адрес. Слить есть чем: отпечаток ключа у человека один и
//  тот же, каким бы путём он ни пришёл.
//
//  ViewModel об этом не знает: снаружи это такой же `PeerTransport`.
//

import Foundation

enum CompositeTransportError: Error, Equatable {
    /// Адрес не виден ни по одному каналу.
    case unreachable(String)
}

@MainActor
final class CompositeTransport: PeerTransport {

    /// Какой канал владеет адресом.
    enum Channel: Equatable {
        case nearby
        case relay
    }

    private let nearby: any PeerTransport
    private let relay: any PeerTransport

    // MARK: - Identity

    var myDisplayName: String { nearby.myDisplayName }

    /// Адрес у обоих каналов один — отпечаток ключа устройства. Берём с
    /// релея: там он подтверждён сервером.
    var myAddress: String { relay.myAddress }

    var approvalDelegate: PeerConnectionApproving? {
        didSet {
            nearby.approvalDelegate = approvalDelegate
            relay.approvalDelegate = approvalDelegate
        }
    }

    // MARK: - Streams

    private let peerBroadcast = AsyncBroadcast<[Peer]>(replaysLatest: true)
    private let messageBroadcast = AsyncBroadcast<Addressed<MessagePayload>>()
    private let typingBroadcast = AsyncBroadcast<Addressed<TypingEvent>>()
    private let strokeBroadcast = AsyncBroadcast<Addressed<Stroke>>()
    private let wallRequestBroadcast = AsyncBroadcast<String>()
    private let wallStateBroadcast = AsyncBroadcast<Addressed<[Stroke]>>()
    private let connectionStateBroadcast = AsyncBroadcast<TransportConnectionState>(replaysLatest: true)

    var peerStream: AsyncStream<[Peer]> { peerBroadcast.stream }
    var messageStream: AsyncStream<Addressed<MessagePayload>> { messageBroadcast.stream }
    var typingStream: AsyncStream<Addressed<TypingEvent>> { typingBroadcast.stream }
    var strokeStream: AsyncStream<Addressed<Stroke>> { strokeBroadcast.stream }
    var wallRequestStream: AsyncStream<String> { wallRequestBroadcast.stream }
    var wallStateStream: AsyncStream<Addressed<[Stroke]>> { wallStateBroadcast.stream }
    var connectionStateUpdates: AsyncStream<TransportConnectionState> { connectionStateBroadcast.stream }

    // MARK: - State

    /// Последний список с каждого канала. Слияние пересчитывается от них,
    /// а не от накопленных событий: канал, замолчавший на середине, не
    /// оставляет после себя призраков.
    private var nearbyPeers: [Peer] = []
    private var relayPeers: [Peer] = []
    private var relayState: TransportConnectionState = .offline

    private var forwardingTasks: [Task<Void, Never>] = []

    init(nearby: any PeerTransport, relay: any PeerTransport) {
        self.nearby = nearby
        self.relay = relay
        forward()
    }

    // MARK: - Routing

    /// Кому принадлежит адрес.
    ///
    /// Рядом — в приоритете, но только когда сессия уже поднята: напрямую
    /// быстрее и не нужен интернет. Иначе релей, если он этого человека
    /// видит — там связь есть сразу. Рядом без сессии остаётся последним:
    /// подключение потребует подтверждения с той стороны.
    func channel(for address: String) -> Channel? {
        let seenNearby = nearbyPeers.first { $0.address == address }
        let seenOnRelay = relayPeers.contains { $0.address == address }

        if seenNearby?.status == .connected {
            return .nearby
        }
        if seenOnRelay {
            return .relay
        }
        return seenNearby == nil ? nil : .nearby
    }

    private func transport(for address: String) throws -> any PeerTransport {
        switch channel(for: address) {
        case .nearby:
            return nearby
        case .relay:
            return relay
        case nil:
            throw CompositeTransportError.unreachable(address)
        }
    }

    /// Один человек — одна строка, по тому каналу, что им владеет.
    private func mergePeers() {
        var merged: [String: Peer] = [:]

        for peer in relayPeers {
            merged[peer.address] = peer
        }
        for peer in nearbyPeers where channel(for: peer.address) == .nearby {
            merged[peer.address] = peer
        }

        // Тот же порядок, что у каналов по отдельности: по имени, тёзки —
        // по адресу. `Array.hasSameState` рассчитывает на стабильный порядок.
        let peers = merged.values.sorted {
            ($0.displayName, $0.address) < ($1.displayName, $1.address)
        }
        peerBroadcast.yield(peers)
    }

    /// Релей — единственный канал с состоянием, и его «нет сети» честно
    /// только про сервер. Если рядом кто-то подключён, связь есть.
    private func updateConnectionState() {
        let someoneNearby = nearbyPeers.contains { $0.status == .connected }
        connectionStateBroadcast.yield(someoneNearby ? .online : relayState)
    }

    // MARK: - Forwarding

    /// Задачи держат только потоки, не сами каналы. Когда составной
    /// транспорт освобождается, каналы уходят вместе с ним, их потоки
    /// завершаются, и задачи заканчиваются сами — `deinit` не нужен, а
    /// изолированный стейт из него и не потрогать.
    private func forward() {
        let nearbyPeerStream = nearby.peerStream
        let relayPeerStream = relay.peerStream
        let relayStates = relay.connectionStateUpdates

        forwardingTasks = [
            Task { [weak self] in
                for await peers in nearbyPeerStream {
                    guard let self else { return }
                    self.nearbyPeers = peers
                    self.mergePeers()
                    self.updateConnectionState()
                }
            },
            Task { [weak self] in
                for await peers in relayPeerStream {
                    guard let self else { return }
                    self.relayPeers = peers
                    self.mergePeers()
                }
            },
            Task { [weak self] in
                for await state in relayStates {
                    guard let self else { return }
                    self.relayState = state
                    self.updateConnectionState()
                }
            }
        ]

        for source in [nearby, relay] {
            let messages = source.messageStream
            let typing = source.typingStream
            let strokes = source.strokeStream
            let wallRequests = source.wallRequestStream
            let wallStates = source.wallStateStream

            forwardingTasks += [
                Task { [weak self] in
                    for await event in messages {
                        self?.messageBroadcast.yield(event)
                    }
                },
                Task { [weak self] in
                    for await event in typing {
                        self?.typingBroadcast.yield(event)
                    }
                },
                Task { [weak self] in
                    for await event in strokes {
                        self?.strokeBroadcast.yield(event)
                    }
                },
                Task { [weak self] in
                    for await event in wallRequests {
                        self?.wallRequestBroadcast.yield(event)
                    }
                },
                Task { [weak self] in
                    for await event in wallStates {
                        self?.wallStateBroadcast.yield(event)
                    }
                }
            ]
        }
    }

    // MARK: - Discovery

    func startDeviceDiscovery() {
        nearby.startDeviceDiscovery()
        relay.startDeviceDiscovery()
    }

    func stopDeviceDiscovery() {
        nearby.stopDeviceDiscovery()
        relay.stopDeviceDiscovery()
    }

    func connectToPeer(address: String) async throws {
        try await transport(for: address).connectToPeer(address: address)
    }

    // MARK: - Connection Management

    /// Отключение не маршрутизируется: человек может быть виден по обоим
    /// каналам, и просьба «отключись от него» касается обоих.
    func disconnect(from address: String) {
        nearby.disconnect(from: address)
        relay.disconnect(from: address)
    }

    func disconnectAll() {
        nearby.disconnectAll()
        relay.disconnectAll()
    }

    // MARK: - Messaging

    func sendMessage(_ payload: MessagePayload, to address: String) async throws {
        try await transport(for: address).sendMessage(payload, to: address)
    }

    func sendTypingEvent(_ event: TypingEvent, to address: String) async throws {
        try await transport(for: address).sendTypingEvent(event, to: address)
    }

    func sendStroke(_ stroke: Stroke, to address: String) async throws {
        try await transport(for: address).sendStroke(stroke, to: address)
    }

    func requestWall(from address: String) async throws {
        try await transport(for: address).requestWall(from: address)
    }

    func sendWall(_ strokes: [Stroke], to address: String) async throws {
        try await transport(for: address).sendWall(strokes, to: address)
    }
}
