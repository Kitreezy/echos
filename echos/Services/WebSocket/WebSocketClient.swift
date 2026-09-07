//
//  WebSocketClient.swift
//  echos
//
//  Клиент WebSocket поверх `URLSessionWebSocketTask` — без сторонних библиотек.
//
//  Сам по себе API сокета маленький: `send`, `receive`, `sendPing`, `cancel`.
//  Работы требует всё вокруг: превратить колбэки в поток, заметить обрыв,
//  переподключиться не заваливая сервер, и не потерять то, что не успело уйти.
//

import Foundation

@MainActor
final class WebSocketClient {

    // MARK: - State

    enum State: Sendable, Equatable {
        case disconnected
        case connecting
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

    private let url: URL
    private let sessionConfiguration: URLSessionConfiguration
    private let delegate = SocketDelegate()

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?

    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    /// `true` — пользователь явно отключился, переподключаться не нужно.
    private var isStopped = true
    private var reconnectAttempt = 0
    private var outbox: [Data] = []

    private(set) var connectionAttempts = 0

    // MARK: - Init

    init(url: URL, configuration: URLSessionConfiguration = .ephemeral) {
        self.url = url
        self.sessionConfiguration = configuration
        delegate.client = self
    }

    deinit {
        socket?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Lifecycle

    func connect() {
        guard isStopped else {
            return
        }

        isStopped = false
        reconnectAttempt = 0
        openConnection()
    }

    func disconnect() {
        isStopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownSocket(closeCode: .normalClosure)
        state = .disconnected
    }

    // MARK: - Sending

    /// Отправляет данные, а если соединения нет — откладывает до реконнекта.
    func send(_ data: Data) async {
        guard state == .connected, let socket else {
            enqueue(data)
            return
        }

        do {
            try await socket.send(.data(data))
        }
        catch {
            print("[WebSocketClient] Send failed: \(error.localizedDescription)")
            enqueue(data)
            handleFailure(on: socket)
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
                try await socket.send(.data(data))
            }
            catch {
                enqueue(data)
                handleFailure(on: socket)
                return
            }
        }
    }

    // MARK: - Connection

    private func openConnection() {
        teardownSocket(closeCode: nil)

        state = .connecting
        connectionAttempts += 1

        let session = URLSession(configuration: sessionConfiguration,
                                 delegate: delegate,
                                 delegateQueue: .main)
        self.session = session

        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(on: socket)
        }
    }

    /// Вызывается делегатом, когда handshake завершён.
    fileprivate func handleOpen(_ openedSocket: URLSessionWebSocketTask) {
        guard openedSocket === socket else {
            return  // событие от предыдущего, уже закрытого сокета
        }

        reconnectAttempt = 0
        state = .connected
        startHeartbeat(on: openedSocket)

        Task { [weak self] in
            await self?.onConnected?()
            await self?.flushOutbox()
        }
    }

    /// Вызывается делегатом при штатном закрытии со стороны сервера.
    fileprivate func handleClose(_ closedSocket: URLSessionWebSocketTask,
                                 code: URLSessionWebSocketTask.CloseCode) {
        guard closedSocket === socket else {
            return
        }

        print("[WebSocketClient] Closed by peer, code \(code.rawValue)")
        handleFailure(on: closedSocket)
    }

    /// Единая точка обработки обрыва: и «receive бросил», и «pong не пришёл»,
    /// и «сервер закрыл соединение» приводят сюда.
    private func handleFailure(on failedSocket: URLSessionWebSocketTask) {
        guard failedSocket === socket else {
            return
        }

        teardownSocket(closeCode: nil)

        guard !isStopped else {
            state = .disconnected
            return
        }

        state = .connecting
        scheduleReconnect()
    }

    private func teardownSocket(closeCode: URLSessionWebSocketTask.CloseCode?) {
        receiveTask?.cancel()
        receiveTask = nil

        heartbeatTask?.cancel()
        heartbeatTask = nil

        if let closeCode {
            socket?.cancel(with: closeCode, reason: nil)
        } else {
            socket?.cancel()
        }
        socket = nil

        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Receiving

    /// Мост от `receive()` к `AsyncStream`.
    ///
    /// `receive()` отдаёт ровно одно сообщение за вызов, поэтому его крутят в
    /// цикле. Он же и сигнализирует об обрыве: как только соединение умерло,
    /// вызов бросает — отдельного «onDisconnect» у сокета нет.
    private func receiveLoop(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()

                switch message {
                case .data(let data):
                    incoming.yield(data)

                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        incoming.yield(data)
                    }

                @unknown default:
                    break
                }
            }
            catch {
                guard !Task.isCancelled else {
                    return
                }
                print("[WebSocketClient] Receive failed: \(error.localizedDescription)")
                handleFailure(on: socket)
                return
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(on socket: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pingInterval else {
                    return
                }

                guard (try? await Task.sleep(for: interval)) != nil else {
                    return
                }

                guard let alive = await self?.ping(socket), !Task.isCancelled else {
                    return
                }

                if !alive {
                    print("[WebSocketClient] No pong in time, assuming connection is dead")
                    self?.handleFailure(on: socket)
                    return
                }
            }
        }
    }

    /// Пинг с таймаутом.
    ///
    /// Без гонки с таймером это не работает: если соединение оборвалось
    /// «тихо», колбэк pong не придёт никогда, и `await` повиснет навсегда —
    /// вместе с обнаружением обрыва.
    private func ping(_ socket: URLSessionWebSocketTask) async -> Bool {
        let boxed = UncheckedSendableBox(socket)
        let timeout = pongTimeout

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                (try? await boxed.value.sendPing()) != nil
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

// MARK: - URLSessionWebSocketDelegate

/// Делегат отдельным объектом: `URLSession` держит его сильно, а замыкать
/// эту ссылку на `@MainActor`-класс клиента нельзя — получится цикл.
private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {

    weak var client: WebSocketClient?

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        // delegateQueue задан как `.main`, поэтому мы уже на главном потоке.
        MainActor.assumeIsolated {
            client?.handleOpen(webSocketTask)
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        MainActor.assumeIsolated {
            client?.handleClose(webSocketTask, code: closeCode)
        }
    }
}

// MARK: - Helpers

extension URLSessionWebSocketTask {

    /// У `sendPing` нет async-варианта — только колбэк, поэтому мост строим
    /// сами. Тот же приём, что и для любого legacy-API с завершающим блоком.
    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

extension Duration {

    var inSeconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
