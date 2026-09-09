//
//  WebSocketClient.swift
//  echos
//
//  Политика живучести соединения — поверх любого транспорта.
//
//  Сам WebSocket API маленький: открыть, отправить, получить, пинг, закрыть.
//  Он вынесен за `RawWebSocket`. Здесь остаётся всё, ради чего клиент вообще
//  пишется: заметить обрыв, отличить «сервер упал» от «пропала сеть»,
//  переподключиться не заваливая сервер, не потерять неотправленное.
//
//  Эта часть от выбора библиотеки не зависит — что и проверяется прогоном
//  одних и тех же тестов против двух реализаций `RawWebSocket`.
//

import Foundation
import Network

@MainActor
final class WebSocketClient {

    // MARK: - State

    enum State: Sendable, Equatable {
        case disconnected
        case connecting
        /// Сети нет — ретраи приостановлены до появления пути. Отдельный
        /// случай, а не `connecting`: попытки в этот момент не идут, и
        /// пользователю честнее показать «нет сети», а не «подключаемся».
        case waitingForNetwork
        case connected
    }

    private(set) var state: State = .disconnected {
        didSet {
            guard state != oldValue else {
                return
            }
            print("[WebSocketClient] \(oldValue) → \(state)")
            stateBroadcast.yield(state)
        }
    }

    // MARK: - Configuration

    /// Как часто слать ping. Нужен не только для keep-alive: пока не пошлёшь
    /// пакет, обрыв «посередине» (роутер выкинул соединение из своей таблицы)
    /// никак себя не проявляет — сокет выглядит живым, но мёртв.
    var pingInterval: Duration = .seconds(15)

    /// Сколько ждать pong, прежде чем считать соединение мёртвым.
    var pongTimeout: Duration = .seconds(5)

    var initialReconnectDelay: Duration = .milliseconds(500)
    var maxReconnectDelay: Duration = .seconds(30)

    /// Сколько сообщений держать, пока соединения нет. Очередь ограничена
    /// намеренно: при долгом оффлайне безлимитная съест память.
    var outboxLimit = 64

    /// Рукопожатие, выполняемое после КАЖДОГО успешного подключения — и до
    /// того, как уйдёт отложенная очередь.
    ///
    /// Сервер после реконнекта не помнит о клиенте ничего, поэтому сначала
    /// надо представиться заново, и только потом досылать накопленное. Без
    /// этого порядка первое же отложенное сообщение приходит на сервер от
    /// «неизвестно кого» и молча выбрасывается.
    var onConnected: (@MainActor () async -> Void)?

    // MARK: - Streams

    private let incoming = AsyncBroadcast<Data>()
    private let stateBroadcast = AsyncBroadcast<State>(replaysLatest: true)

    var incomingMessages: AsyncStream<Data> { incoming.stream }
    var stateUpdates: AsyncStream<State> { stateBroadcast.stream }

    // MARK: - Private

    /// Фабрика транспорта. Сокет одноразовый: на каждое переподключение
    /// создаётся новый, поэтому храним способ его создать, а не сам объект.
    private let makeSocket: @MainActor () -> any RawWebSocket
    private let networkMonitor: any NetworkMonitoring

    private var socket: (any RawWebSocket)?

    private var eventsTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?

    /// Интерфейс, на котором стоит текущее соединение. Нужен, чтобы поймать
    /// переход Wi-Fi ↔ LTE.
    private var connectedInterface: NWInterface.InterfaceType?

    /// `true` — пользователь явно отключился, переподключаться не нужно.
    private var isStopped = true
    private var reconnectAttempt = 0
    private var outbox: [Data] = []

    private(set) var connectionAttempts = 0

    // MARK: - Init

    init(url: URL,
         configuration: URLSessionConfiguration = .ephemeral,
         networkMonitor: any NetworkMonitoring = NetworkMonitor.shared) {
        self.makeSocket = { URLSessionRawSocket(url: url, configuration: configuration) }
        self.networkMonitor = networkMonitor
    }

    /// Точка подмены транспорта — для контрактных тестов и для любой
    /// следующей реализации `RawWebSocket`.
    init(networkMonitor: any NetworkMonitoring = NetworkMonitor.shared,
         makeSocket: @escaping @MainActor () -> any RawWebSocket) {
        self.makeSocket = makeSocket
        self.networkMonitor = networkMonitor
    }

    // MARK: - Lifecycle

    func connect() {
        guard isStopped else {
            return
        }

        isStopped = false
        reconnectAttempt = 0

        networkMonitor.start()
        observeNetwork()

        // Если монитор уже знает, что сети нет, — даже не пытаемся.
        if networkMonitor.currentPath?.isReachable == false {
            state = .waitingForNetwork
            return
        }

        openConnection()
    }

    func disconnect() {
        isStopped = true

        networkTask?.cancel()
        networkTask = nil

        reconnectTask?.cancel()
        reconnectTask = nil

        teardownSocket()
        state = .disconnected
    }

    // MARK: - Network awareness

    /// Реакция на изменения сетевого пути.
    ///
    /// Три разных события, и на каждое своя реакция:
    /// пути нет — прекратить попытки; путь появился — подключиться немедленно,
    /// не досиживая backoff; сменился интерфейс — пересоздать соединение,
    /// потому что старое уже мертво, хоть и выглядит живым.
    private func observeNetwork() {
        guard networkTask == nil else {
            return
        }

        networkTask = Task { [weak self] in
            guard let updates = self?.networkMonitor.pathUpdates else {
                return
            }

            for await path in updates {
                self?.handle(path: path)
            }
        }
    }

    private func handle(path: NetworkPathSnapshot) {
        guard !isStopped else {
            return
        }

        guard path.isReachable else {
            print("[WebSocketClient] No network path, pausing reconnects")

            reconnectTask?.cancel()
            reconnectTask = nil
            teardownSocket()
            connectedInterface = nil
            state = .waitingForNetwork
            return
        }

        // Смена интерфейса меняет локальный адрес: соединение уже оборвано,
        // но узнать об этом иначе как по таймауту ping нельзя.
        let interfaceChanged = state == .connected
            && connectedInterface != nil
            && connectedInterface != path.interface

        if interfaceChanged {
            print("[WebSocketClient] Interface changed, reconnecting")
            teardownSocket()
        }

        guard state != .connected || interfaceChanged else {
            return
        }

        // Сеть вернулась — начинаем с чистого листа, а не с накопленной
        // задержки: ждать 30 секунд после включения Wi-Fi незачем.
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        openConnection()
    }

    // MARK: - Sending

    /// Отправляет данные, а если соединения нет — откладывает до реконнекта.
    func send(_ data: Data) async {
        guard state == .connected, let socket else {
            enqueue(data)
            return
        }

        do {
            try await socket.send(data)
        }
        catch {
            print("[WebSocketClient] Send failed: \(error.localizedDescription)")
            enqueue(data)
            handleFailure()
        }
    }

    private func enqueue(_ data: Data) {
        outbox.append(data)

        if outbox.count > outboxLimit {
            outbox.removeFirst(outbox.count - outboxLimit)
        }
    }

    private func flushOutbox() async {
        guard !outbox.isEmpty, let socket, state == .connected else {
            return
        }

        // Забираем очередь целиком: пока идут await'ы, в неё могут положить
        // новое, и повторно отправлять уже отправленное не нужно.
        let pending = outbox
        outbox.removeAll()

        for data in pending {
            do {
                try await socket.send(data)
            }
            catch {
                enqueue(data)
                handleFailure()
                return
            }
        }
    }

    // MARK: - Connection

    private func openConnection() {
        teardownSocket()

        state = .connecting
        connectionAttempts += 1

        let socket = makeSocket()
        self.socket = socket

        // Задача читает события ровно этого сокета и отменяется вместе с ним,
        // поэтому «эхо» от предыдущего соединения прийти не может.
        eventsTask = Task { [weak self] in
            for await event in socket.events {
                self?.handle(event: event)
            }
        }

        socket.open()
    }

    private func handle(event: RawWebSocketEvent) {
        switch event {
        case .opened:
            handleOpen()

        case .message(let data):
            incoming.yield(data)

        case .closed(let code, _):
            print("[WebSocketClient] Closed by peer, code \(code)")
            handleFailure()

        case .failed(let reason):
            print("[WebSocketClient] Failed: \(reason)")
            handleFailure()
        }
    }

    private func handleOpen() {
        reconnectAttempt = 0
        connectedInterface = networkMonitor.currentPath?.interface
        state = .connected
        startHeartbeat()

        Task { [weak self] in
            await self?.onConnected?()
            await self?.flushOutbox()
        }
    }

    /// Единая точка обработки обрыва: и «receive бросил», и «pong не пришёл»,
    /// и «сервер закрыл соединение» приводят сюда.
    private func handleFailure() {
        teardownSocket()
        connectedInterface = nil

        guard !isStopped else {
            state = .disconnected
            return
        }

        // Сеть и сервер отваливаются одинаково с точки зрения сокета, но
        // требуют разного: при отсутствии пути ретраи бессмысленны — ждём
        // сигнала монитора, он придёт сам.
        guard networkMonitor.currentPath?.isReachable != false else {
            state = .waitingForNetwork
            return
        }

        state = .connecting
        scheduleReconnect()
    }

    private func teardownSocket() {
        eventsTask?.cancel()
        eventsTask = nil

        heartbeatTask?.cancel()
        heartbeatTask = nil

        socket?.close()
        socket = nil
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pingInterval else {
                    return
                }

                guard (try? await Task.sleep(for: interval)) != nil else {
                    return
                }

                guard let alive = await self?.pingWithTimeout(), !Task.isCancelled else {
                    return
                }

                if !alive {
                    print("[WebSocketClient] No pong in time, assuming connection is dead")
                    self?.handleFailure()
                    return
                }
            }
        }
    }

    /// Пинг с таймаутом.
    ///
    /// Без гонки с таймером это не работает: если соединение оборвалось
    /// «тихо», pong не придёт никогда, и `await` повиснет навсегда — вместе
    /// с обнаружением обрыва.
    private func pingWithTimeout() async -> Bool {
        guard let socket else {
            return false
        }

        let boxed = UncheckedSendableBox(socket)
        let timeout = pongTimeout

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                (try? await boxed.value.ping()) != nil
            }

            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }

            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !isStopped else {
            return
        }

        reconnectAttempt += 1
        let delay = reconnectDelay(for: reconnectAttempt)
        print("[WebSocketClient] Reconnect #\(reconnectAttempt) in \(delay)")

        reconnectTask = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.openConnection()
        }
    }

    /// Экспоненциальный откат с потолком и джиттером.
    ///
    /// Джиттер нужен не для красоты: без него все клиенты, отвалившиеся при
    /// перезапуске сервера, вернутся ровно в один и тот же момент и положат
    /// его повторно.
    func reconnectDelay(for attempt: Int) -> Duration {
        let exponent = Double(min(attempt - 1, 16))
        let growth = initialReconnectDelay.inSeconds * pow(2, exponent)
        let capped = min(growth, maxReconnectDelay.inSeconds)

        return .seconds(capped * Double.random(in: 0.5...1.0))
    }
}

// MARK: - Helpers

extension Duration {

    var inSeconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
