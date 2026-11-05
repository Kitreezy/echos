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
    private let pinning: CertificatePinning?

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private let broadcast = AsyncBroadcast<RawWebSocketEvent>()
    var events: AsyncStream<RawWebSocketEvent> { broadcast.stream }

    init(url: URL,
         configuration: URLSessionConfiguration = .ephemeral,
         publicKeyPins: Set<Data>? = nil) {
        self.url = url
        self.configuration = configuration
        let pins = publicKeyPins ?? CertificatePinning.pins(for: url)
        self.pinning = pins.map(CertificatePinning.init(publicKeyHashes:))
        super.init()
    }

    deinit {
        socket?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - RawWebSocket

    func open() {
        let session = URLSession(configuration: configuration,
                                 delegate: SocketDelegate(socket: self, pinning: pinning),
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

        // Обработчик бывает вызван дважды: когда соединение рвётся в момент
        // ping, приходит и ответ, и ошибка обрыва. Второе возобновление
        // продолжения — немедленный крэш, поэтому возобновляет только первый
        // вызов. Нашёл это параллельный прогон тестов: десятки соединений
        // рвутся одновременно, и стечение, редкое у одного пользователя,
        // случается каждый раз.
        let resumed = OnceFlag()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                guard resumed.claim() else {
                    return
                }
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
///
/// `weak let`, а не `weak var`: ссылка задаётся один раз при создании, и
/// неизменяемое поле позволяет классу быть `Sendable` без `@unchecked`.
/// Ссылка обнуляется, когда сокет уходит, — менять её больше некому.
private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate, Sendable {

    weak let socket: URLSessionRawSocket?
    let pinning: CertificatePinning?

    init(socket: URLSessionRawSocket, pinning: CertificatePinning?) {
        self.socket = socket
        self.pinning = pinning
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let pinning {
            guard pinning.evaluate(trust) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

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
