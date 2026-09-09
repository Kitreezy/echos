//
//  StarscreamRawSocket.swift
//  echos
//
//  Тот же транспорт, но на Starscream — для сравнения с `URLSessionRawSocket`.
//
//  СПАЙК. В основную ветку не идёт: echos принципиально живёт без сторонних
//  зависимостей. Файл существует, чтобы сравнение считалось цифрами и
//  прогоном тестов, а не пересказом чужих статей.
//
//  Важная деталь, которую видно только в исходниках: у Starscream два движка.
//  По умолчанию (`useCustomEngine: true`) работает WSEngine — собственная
//  реализация фрейминга поверх Network.framework. NativeEngine, который
//  оборачивает `URLSessionWebSocketTask`, включается явно. То есть «нативно
//  против Starscream» — на самом деле сравнение трёх конфигураций.
//

import Foundation
import Starscream

@MainActor
final class StarscreamRawSocket: RawWebSocket {

    /// Какой движок просить у Starscream.
    enum EngineKind {
        /// Собственный фрейминг Starscream. Умеет permessage-deflate,
        /// свой pinning и отдаёт события, которых у URLSession нет.
        case starscream
        /// Обёртка вокруг `URLSessionWebSocketTask` — того же API, на котором
        /// написан `URLSessionRawSocket`.
        case native
    }

    private let socket: WebSocket
    private let broadcast = AsyncBroadcast<RawWebSocketEvent>()
    var events: AsyncStream<RawWebSocketEvent> { broadcast.stream }

    /// Ожидание pong. У Starscream `write(ping:)` завершается по факту
    /// отправки, а сам pong приходит отдельным событием — как и у
    /// `URLSessionWebSocketTask`, ждать ответ приходится вручную.
    private var pongContinuation: CheckedContinuation<Void, Error>?

    init(url: URL, engine: EngineKind = .starscream) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        socket = WebSocket(request: request, useCustomEngine: engine == .starscream)
        socket.callbackQueue = .main

        socket.onEvent = { [weak self] event in
            // callbackQueue задан как `.main` — мы уже на главном потоке.
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    // MARK: - RawWebSocket

    func open() {
        socket.connect()
    }

    func close() {
        // Поток закрываем первым: после `disconnect()` Starscream ещё пришлёт
        // `.cancelled`, и наверху это выглядело бы как аварийный обрыв.
        broadcast.finish()
        resumePong(throwing: RelayError.notConnected)
        socket.disconnect()
    }

    /// Отправка с ожиданием подтверждения.
    ///
    /// ВАЖНО: `@Sendable` у замыкания — не украшение. Колбэк Starscream
    /// объявлен как `(() -> ())?`, без `@Sendable`, поэтому компилятор считает
    /// его унаследовавшим изоляцию главного актора от `send(_:)`. А вызывает
    /// его библиотека со своей внутренней очереди — и Swift 6 на входе в
    /// изолированное замыкание проверяет исполнителя и роняет процесс
    /// (`EXC_BREAKPOINT` в `dispatch_assert_queue_fail`).
    ///
    /// Компилятор такое не ловит: тип колбэка ничего не обещает. Падает
    /// только в рантайме и только когда действительно доходит до отправки.
    func send(_ data: Data) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            socket.write(data: data, completion: { @Sendable in
                continuation.resume()
            })
        }
    }

    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard pongContinuation == nil else {
                continuation.resume(throwing: RelayError.notConnected)
                return
            }

            pongContinuation = continuation
            socket.write(ping: Data())
        }
    }

    // MARK: - Events

    private func handle(_ event: WebSocketEvent) {
        switch event {
        case .connected:
            broadcast.yield(.opened)

        case .binary(let data):
            broadcast.yield(.message(data))

        case .text(let text):
            if let data = text.data(using: .utf8) {
                broadcast.yield(.message(data))
            }

        case .pong:
            resumePong()

        case .ping:
            break  // Starscream отвечает сам, respondToPingWithPong по умолчанию

        case .disconnected(let reason, let code):
            resumePong(throwing: RelayError.notConnected)
            broadcast.yield(.closed(code: Int(code), reason: reason))

        case .peerClosed:
            resumePong(throwing: RelayError.notConnected)
            broadcast.yield(.closed(code: 1000, reason: "peer closed"))

        case .error(let error):
            resumePong(throwing: RelayError.notConnected)
            broadcast.yield(.failed(error?.localizedDescription ?? "unknown"))

        case .cancelled:
            resumePong(throwing: RelayError.notConnected)
            broadcast.yield(.failed("cancelled"))

        case .viabilityChanged(let isViable):
            // Событие, которого у URLSession нет: Starscream прокидывает
            // наблюдение NWConnection за живучестью пути. У нас эту роль уже
            // играет NetworkMonitor, поэтому только логируем.
            print("[StarscreamRawSocket] viability: \(isViable)")

        case .reconnectSuggested(let shouldReconnect):
            // Только ПОДСКАЗКА. Переподключение Starscream не делает —
            // вся политика живучести остаётся на вызывающем коде.
            print("[StarscreamRawSocket] reconnect suggested: \(shouldReconnect)")
        }
    }

    private func resumePong(throwing error: Error? = nil) {
        guard let continuation = pongContinuation else {
            return
        }
        pongContinuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
