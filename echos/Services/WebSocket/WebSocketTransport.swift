//
//  WebSocketTransport.swift
//  echos
//
//  Вторая реализация `PeerTransport` — через релей вместо Multipeer.
//
//  Отличие в модели связи. У Multipeer соединение устанавливается с каждым
//  устройством отдельно, поэтому там есть приглашения и статусы. Здесь
//  соединение одно — с сервером; все, кто на нём сейчас есть, доступны сразу.
//

import Foundation
import UIKit

@MainActor
final class WebSocketTransport: NSObject {

    // MARK: - Identity

    let myDisplayName: String

    // MARK: - Delegation

    /// Релей не спрашивает разрешения на подключение: соединение
    /// устанавливается с сервером, а не с конкретным собеседником.
    weak var approvalDelegate: PeerConnectionApproving?

    // MARK: - Streams

    private let peerBroadcast = AsyncBroadcast<[Peer]>(replaysLatest: true)
    private let messageBroadcast = AsyncBroadcast<MessagePayload>()
    private let typingBroadcast = AsyncBroadcast<TypingEvent>()

    var peerStream: AsyncStream<[Peer]> { peerBroadcast.stream }
    var messageStream: AsyncStream<MessagePayload> { messageBroadcast.stream }
    var typingStream: AsyncStream<TypingEvent> { typingBroadcast.stream }

    /// Состояние соединения с релеем — для индикатора в UI.
    var connectionState: WebSocketClient.State { client.state }

    var connectionStateUpdates: AsyncStream<TransportConnectionState> {
        let states = client.stateUpdates

        return AsyncStream { continuation in
            let task = Task {
                for await state in states {
                    continuation.yield(TransportConnectionState(state))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private let client: WebSocketClient
    private var readerTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    /// Пользователь включил поиск и не выключал. Отличается от «сейчас
    /// подключены»: в фоне соединения нет, но возобновлять его при возврате
    /// надо, а если поиск остановлен явно — не надо.
    private var isActive = false

    /// Имя → идентификатор. Релей оперирует именами, а `Peer` требует
    /// стабильный `id`, иначе SwiftUI будет пересоздавать строки списка.
    private var peerIdentifiers: [String: UUID] = [:]
    private var knownPeerNames: [String] = []

    // MARK: - Init

    init(url: URL,
         displayName: String = UserSettings.displayName,
         networkMonitor: any NetworkMonitoring = NetworkMonitor.shared) {
        self.myDisplayName = displayName
        self.client = WebSocketClient(url: url, networkMonitor: networkMonitor)
        super.init()
        observeAppLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - App Lifecycle

    /// Наблюдатели живут на уровне транспорта, а не экрана.
    ///
    /// Раньше фон обрабатывал только `DiscoveryViewController`, и уход в фон
    /// из чата, минуя радар, оставлял сокет умирать по таймауту. Транспорт же
    /// жив всё время, пока идёт сессия.
    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc
    private func appDidEnterBackground() {
        guard isActive else {
            return
        }

        // Закрываемся штатно, а не ждём, пока соединение умрёт само: так
        // сервер сразу уберёт нас из присутствия, и собеседники не будут
        // видеть призрака ещё минуту.
        client.disconnect()
        clearPeers()
    }

    @objc
    private func appWillEnterForeground() {
        guard isActive else {
            return
        }

        client.connect()
    }

    // MARK: - Discovery

    func startDeviceDiscovery() {
        isActive = true

        guard readerTask == nil else {
            client.connect()
            return
        }

        readerTask = Task { [weak self] in
            guard let messages = self?.client.incomingMessages else {
                return
            }

            for await data in messages {
                self?.handle(data)
            }
        }

        // Представиться надо при каждом подключении, а не только при первом:
        // после реконнекта сервер о нас ничего не помнит. Хук клиента
        // гарантирует, что hello уйдёт до отложенной очереди.
        client.onConnected = { [weak self] in
            await self?.sayHello()
        }

        // Пока связи нет, список собеседников недостоверен — чистим его.
        stateTask = Task { [weak self] in
            guard let states = self?.client.stateUpdates else {
                return
            }

            for await state in states where state != .connected {
                self?.clearPeers()
            }
        }

        client.connect()
    }

    func stopDeviceDiscovery() {
        isActive = false

        readerTask?.cancel()
        readerTask = nil

        stateTask?.cancel()
        stateTask = nil

        client.disconnect()
        clearPeers()
    }

    /// У релея нет пер-пирового подключения: если собеседник в списке
    /// присутствия, ему уже можно писать.
    func connectToPeer(displayName: String) async throws {
        guard knownPeerNames.contains(displayName) else {
            throw RelayError.notConnected
        }
    }

    // MARK: - Connection Management

    /// Разорвать связь с одним собеседником релей не позволяет — рвётся
    /// только соединение с сервером целиком.
    func disconnect(from displayName: String) {
        print("[WebSocketTransport] Per-peer disconnect is not supported by the relay")
    }

    func disconnectAll() {
        client.disconnect()
        clearPeers()
    }

    // MARK: - Messaging

    func sendMessage(_ payload: MessagePayload) async throws {
        try await send(.message(payload, from: myDisplayName))
    }

    func sendTypingEvent(_ event: TypingEvent) async throws {
        try await send(.typing(event, from: myDisplayName))
    }

    private func send(_ envelope: RelayEnvelope) async throws {
        await client.send(try envelope.encoded())
    }

    private func sayHello() async {
        try? await send(.hello(from: myDisplayName))
    }

    // MARK: - Incoming

    private func handle(_ data: Data) {
        do {
            let envelope = try RelayEnvelope.decode(from: data)

            switch envelope.kind {
            case .presence:
                updatePeers(names: try envelope.decodePresence())

            case .message:
                messageBroadcast.yield(try envelope.decodeMessage())

            case .typing:
                typingBroadcast.yield(try envelope.decodeTyping())

            case .hello:
                break  // сервер такое не шлёт
            }
        }
        catch {
            print("[WebSocketTransport] Failed to decode envelope: \(error.localizedDescription)")
        }
    }

    private func updatePeers(names: [String]) {
        // Себя в списке собеседников быть не должно.
        let others = names.filter { $0 != myDisplayName }.sorted()
        knownPeerNames = others

        let peers = others.map { name in
            Peer(id: identifier(for: name),
                 displayName: name,
                 status: .connected,
                 lastSeen: Date())
        }

        peerBroadcast.yield(peers)
    }

    private func clearPeers() {
        guard !knownPeerNames.isEmpty else {
            return
        }

        knownPeerNames = []
        peerBroadcast.yield([])
    }

    private func identifier(for name: String) -> UUID {
        if let existing = peerIdentifiers[name] {
            return existing
        }

        let identifier = UUID()
        peerIdentifiers[name] = identifier
        return identifier
    }
}

extension WebSocketTransport: PeerTransport {}

private extension TransportConnectionState {

    init(_ state: WebSocketClient.State) {
        switch state {
        case .disconnected:       self = .offline
        case .connecting:         self = .connecting
        case .waitingForNetwork:  self = .waitingForNetwork
        case .connected:          self = .online
        }
    }
}
