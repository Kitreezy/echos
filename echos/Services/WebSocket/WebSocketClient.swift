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
import OSLog

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
            Logger.relay.notice("\(String(describing: oldValue), privacy: .public) → \(String(describing: self.state), privacy: .public)")
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

    /// Сколько ждать открытия сокета. Без своего предела на сети с потерями
    /// рукопожатие висит до минуты — столько URLSession ждёт по умолчанию,
    /// — и всё это время откат не работает: клиент не подключён, но и
    /// неудачей это не считается.
    var connectTimeout: Duration = .seconds(10)

    /// Сколько ждать завершения одной отправки. На заглохшем соединении
    /// буфер сокета полон, и `send` не возвращается, пока сокет не умрёт
    /// сам, — а сообщение всё это время ни отправлено, ни в очереди.
    var sendTimeout: Duration = .seconds(10)

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
    private var connectTimeoutTask: Task<Void, Never>?

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
            Logger.relay.notice("No network path, pausing reconnects")

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
            Logger.relay.notice("Interface changed, reconnecting")
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
            try await send(data, over: socket)
        }
        catch {
            Logger.relay.error("Send failed: \(error.localizedDescription, privacy: .public)")
            enqueue(data)
            handleFailure()
        }
    }

    /// Отправка с пределом по времени.
    ///
    /// Сообщение, отправка которого не дождалась ответа, может всё-таки
    /// дойти: байты уже ушли, не вернулось только подтверждение. Его всё
    /// равно кладут обратно в очередь — лучше дубль, чем потеря. Дубли
    /// отсеивает получатель по `id` сообщения.
    private func send(_ data: Data, over socket: any RawWebSocket) async throws {
        try await withTimeout(sendTimeout) {
            try await socket.send(data)
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
                try await send(data, over: socket)
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
        startConnectTimeout()
    }

    /// Не открылся вовремя — считаем это такой же неудачей, как обрыв:
    /// следующая попытка пойдёт через откат.
    private func startConnectTimeout() {
        let timeout = connectTimeout
        connectTimeoutTask = Task { [weak self] in
            guard (try? await Task.sleep(for: timeout)) != nil else {
                return
            }
            guard let self, self.state == .connecting else {
                return
            }
            Logger.relay.error("Not opened in \(timeout, privacy: .public), giving up on this attempt")
            self.handleFailure()
        }
    }

    private func handle(event: RawWebSocketEvent) {
        switch event {
        case .opened:
            handleOpen()

        case .message(let data):
            incoming.yield(data)

        case .closed(let code, _):
            Logger.relay.notice("Closed by server, code \(String(describing: code), privacy: .public)")
            handleFailure()

        case .failed(let reason):
            Logger.relay.error("Failed: \(String(describing: reason), privacy: .public)")
            handleFailure()
        }
    }

    private func handleOpen() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil

        // Счётчик попыток здесь не сбрасывается: открыться и сразу упасть —
        // обычное дело на плохой сети, и сброс на открытии превращал откат
        // в долбёжку раз в полсекунды. Сбрасывает его первый pong —
        // доказательство, что соединение живое в обе стороны.
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

        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil

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
                    Logger.relay.error("No pong in time, assuming connection is dead")
                    self?.handleFailure()
                    return
                }

                self?.reconnectAttempt = 0
            }
        }
    }

    /// Пинг с таймаутом.
    ///
    /// Если соединение оборвалось «тихо», pong не придёт никогда, и без
    /// таймаута `await` повиснет навсегда — вместе с обнаружением обрыва.
    /// Раньше здесь была task group, и она висела всё равно: перед выходом
    /// группа ждёт и проигравший `ping()`. Нашёл это тест с теряющимися pong.
    private func pingWithTimeout() async -> Bool {
        guard let socket else {
            return false
        }

        do {
            try await withTimeout(pongTimeout) {
                try await socket.ping()
            }
            return true
        }
        catch {
            return false
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !isStopped else {
            return
        }

        reconnectAttempt += 1
        let delay = reconnectDelay(for: reconnectAttempt)
        Logger.relay.info("Reconnect #\(self.reconnectAttempt) in \(delay, privacy: .public)")

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

/// Операция, которой отведено не больше `timeout`.
///
/// Task group здесь не годится: перед выходом она дожидается всех детей, а
/// `sendPing` с колбэком и `send` у `URLSessionWebSocketTask` на отмену не
/// реагируют. Таймаут, ждущий зависшую операцию, ничего не ограничивает.
/// Поэтому результат отдаётся через continuation тому, кто успел первым, а
/// проигравшую операцию отменяют и бросают — она доживёт до закрытия сокета.
@MainActor
func withTimeout<T: Sendable>(_ timeout: Duration,
                              _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
    let race = TimeoutRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, timeout: timeout, operation: operation)
        }
    } onCancel: {
        Task { @MainActor in race.finish(.failure(CancellationError())) }
    }
}

/// Кто первый — операция, таймер или отмена снаружи — тот и возобновляет.
/// Всё на главном акторе, поэтому «первый» определяется без замков: шаги
/// не перемежаются.
@MainActor
private final class TimeoutRace<T: Sendable> {

    private var continuation: CheckedContinuation<T, Error>?
    private var isFinished = false
    private var tasks: [Task<Void, Never>] = []

    func start(_ continuation: CheckedContinuation<T, Error>,
               timeout: Duration,
               operation: @escaping @MainActor () async throws -> T) {
        // Отмена снаружи могла прийти раньше, чем continuation появился.
        guard !isFinished else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation

        tasks.append(Task { @MainActor in
            do {
                finish(.success(try await operation()))
            } catch {
                finish(.failure(error))
            }
        })
        tasks.append(Task { @MainActor in
            guard (try? await Task.sleep(for: timeout)) != nil else {
                return
            }
            finish(.failure(TimeoutError(duration: timeout)))
        })
    }

    func finish(_ result: Result<T, Error>) {
        guard !isFinished else {
            return
        }
        isFinished = true
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
        continuation = nil
    }
}

struct TimeoutError: Error, LocalizedError {
    let duration: Duration

    var errorDescription: String? {
        "Нет ответа за \(duration)"
    }
}

extension Duration {

    var inSeconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
