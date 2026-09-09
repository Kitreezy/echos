//
//  URLSessionRawSocket.swift
//  echos
//
//  Транспорт на `URLSessionWebSocketTask` — без сторонних библиотек.
//
//  Здесь собрано всё, что действительно требует знания WebSocket API.
//  Размер этого файла — половина ответа на вопрос «что даёт библиотека».
//

import Foundation

@MainActor
final class URLSessionRawSocket: NSObject, RawWebSocket {

    private let url: URL
    private let configuration: URLSessionConfiguration
    private let delegate = SocketDelegate()

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private let broadcast = AsyncBroadcast<RawWebSocketEvent>()
    var events: AsyncStream<RawWebSocketEvent> { broadcast.stream }

    init(url: URL, configuration: URLSessionConfiguration = .ephemeral) {
        self.url = url
        self.configuration = configuration
        super.init()
        delegate.socket = self
    }

    deinit {
        socket?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - RawWebSocket

    func open() {
        let session = URLSession(configuration: configuration,
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

    func close() {
        receiveTask?.cancel()
        receiveTask = nil

        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil

        session?.invalidateAndCancel()
        session = nil

        broadcast.finish()
    }

    func send(_ data: Data) async throws {
        guard let socket else {
            throw RelayError.notConnected
        }
        try await socket.send(.data(data))
    }

    /// У `sendPing` нет async-варианта — только колбэк, поэтому мост строим
    /// сами. Тот же приём, что и для любого legacy-API с завершающим блоком.
    func ping() async throws {
        guard let socket else {
            throw RelayError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Receiving

    /// `receive()` отдаёт ровно одно сообщение за вызов, поэтому его крутят в
    /// цикле. Он же и сигнализирует об обрыве: как только соединение умерло,
    /// вызов бросает — отдельного «onDisconnect» у сокета нет.
    private func receiveLoop(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                switch try await socket.receive() {
                case .data(let data):
                    broadcast.yield(.message(data))

                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        broadcast.yield(.message(data))
                    }

                @unknown default:
                    break
                }
            }
            catch {
                guard !Task.isCancelled else {
                    return
                }
                broadcast.yield(.failed(error.localizedDescription))
                return
            }
        }
    }

    // MARK: - Delegate callbacks

    fileprivate func handleOpen() {
        broadcast.yield(.opened)
    }

    fileprivate func handleClose(code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        broadcast.yield(.closed(code: code.rawValue,
                                reason: reason.flatMap { String(data: $0, encoding: .utf8) }))
    }
}

// MARK: - URLSessionWebSocketDelegate

/// Делегат отдельным объектом: `URLSession` держит его сильно, а замыкать
/// эту ссылку на сам сокет нельзя — получится цикл.
private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {

    weak var socket: URLSessionRawSocket?

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        // delegateQueue задан как `.main`, поэтому мы уже на главном потоке.
        MainActor.assumeIsolated {
            socket?.handleOpen()
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        MainActor.assumeIsolated {
            socket?.handleClose(code: closeCode, reason: reason)
        }
    }
}
