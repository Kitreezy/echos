//
//  RelayServer.swift
//  echosTests
//
//  Минимальный WebSocket-релей на `Network.framework` — тоже без сторонних
//  библиотек: `NWProtocolWebSocket` умеет и серверную сторону.
//
//  Логика простая: принял соединение → запомнил имя из `hello` → разослал
//  всем присутствие → всё остальное переслал остальным.
//

import CryptoKit
import Foundation
import Network
@testable import echos

@MainActor
final class RelayServer {

    // MARK: - Connection

    private final class Client {
        let connection: NWConnection
        var displayName: String?

        /// Что этот клиент должен подписать. Своя строка на каждое
        /// подключение — иначе подпись годилась бы повторно.
        let nonce: Data

        init(connection: NWConnection) {
            self.connection = connection
            self.nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        }
    }

    // MARK: - State

    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]

    /// Порт сохраняется между перезапусками: клиент переподключается по тому
    /// же адресу, поэтому поднимать сервер обратно надо там же.
    private(set) var port: NWEndpoint.Port?

    var url: URL {
        guard let port else {
            fatalError("Сервер ещё не запущен")
        }
        return URL(string: "ws://127.0.0.1:\(port.rawValue)")!
    }

    var connectedClientCount: Int {
        clients.count
    }

    /// Всё, что сервер принял от клиентов. Позволяет проверить доставку до
    /// сервера отдельно от того, слушал ли в этот момент кто-то ещё.
    private(set) var received: [RelayEnvelope] = []

    /// Забыть принятое. Нужно, чтобы отделить события до обрыва от событий
    /// после него.
    func clearReceived() {
        received.removeAll()
    }

    var receivedMessageTexts: [String] {
        received
            .filter { $0.kind == .message }
            .compactMap { try? $0.decodeMessage().text }
    }

    // MARK: - Lifecycle

    func start() async throws {
        let parameters = NWParameters.tcp
        // SO_REUSEADDR. Без него перезапуск на том же порту падает с
        // EADDRINUSE: сокет ещё висит в TIME_WAIT после cancel().
        parameters.allowLocalEndpointReuse = true

        let webSocketOptions = NWProtocolWebSocket.Options()
        // Отвечать на ping автоматически — иначе heartbeat клиента будет
        // считать живое соединение мёртвым.
        webSocketOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        let listener: NWListener
        if let port {
            listener = try NWListener(using: parameters, on: port)
        } else {
            listener = try NWListener(using: parameters)
        }
        self.listener = listener

        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated {
                self.accept(connection)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = ResumeGuard()

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.claim() {
                        continuation.resume()
                    }

                case .failed(let error), .waiting(let error):
                    print("[RelayServer] Listener failed: \(error)")
                    if resumed.claim() {
                        continuation.resume(throwing: error)
                    }

                default:
                    break
                }
            }

            listener.start(queue: .main)
        }

        port = listener.port
    }

    /// Останавливает сервер, обрывая все соединения, — имитация падения.
    ///
    /// Ждём фактической отмены, а не просто вызываем `cancel()`: он
    /// асинхронный, и пока старый listener жив, порт занят — следующий
    /// `start()` падает с EADDRINUSE.
    func stop() async {
        for client in clients.values {
            client.connection.forceCancel()
        }
        clients.removeAll()

        guard let listener else {
            return
        }
        self.listener = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumed = ResumeGuard()

            listener.newConnectionHandler = nil
            listener.stateUpdateHandler = { state in
                switch state {
                case .cancelled, .failed:
                    if resumed.claim() {
                        continuation.resume()
                    }

                default:
                    break
                }
            }

            if case .cancelled = listener.state, resumed.claim() {
                continuation.resume()
                return
            }

            listener.cancel()
        }
    }

    /// Уронить и поднять обратно на том же порту.
    func restart() async throws {
        await stop()
        try await start()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        clients[ObjectIdentifier(connection)] = client

        connection.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled:
                    self.remove(connection)

                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        receive(on: connection)

        // Вызов уходит первым: клиенту нечего подписывать, пока он его не
        // получил. Настоящий релей ведёт себя так же.
        if let challenge = try? challengeEnvelope(for: client).encoded() {
            send(challenge, over: connection)
        }
    }

    private func challengeEnvelope(for client: Client) throws -> RelayEnvelope {
        let json: [String: Any] = ["kind": "challenge",
                                   "sender": "",
                                   "payload": client.nonce.base64EncodedString()]

        return try RelayEnvelope.decode(from: JSONSerialization.data(withJSONObject: json))
    }

    private func remove(_ connection: NWConnection) {
        guard clients.removeValue(forKey: ObjectIdentifier(connection)) != nil else {
            return
        }

        broadcastPresence()
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }

                if let error {
                    print("[RelayServer] Receive failed: \(error.localizedDescription)")
                    self.remove(connection)
                    return
                }

                // Закрытие приходит как отдельный кадр с opcode .close.
                if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
                   metadata.opcode == .close {
                    self.remove(connection)
                    return
                }

                if let content {
                    self.handle(content, from: connection)
                }

                self.receive(on: connection)
            }
        }
    }

    // MARK: - Routing

    private func handle(_ data: Data, from connection: NWConnection) {
        guard let client = clients[ObjectIdentifier(connection)],
              let envelope = try? RelayEnvelope.decode(from: data) else {
            return
        }

        received.append(envelope)

        switch envelope.kind {
        case .hello:
            guard verify(envelope, from: client) else {
                print("[RelayServer] '\(envelope.sender)' failed the challenge")
                return
            }

            client.displayName = envelope.sender
            print("[RelayServer] '\(envelope.sender)' joined")
            broadcastPresence()

        case .message, .typing, .stroke:
            guard let sender = client.displayName else {
                return  // не представился — не обслуживаем
            }
            // Отправителя проставляет сервер: содержимому конверта от клиента
            // доверять нельзя, он может назваться кем угодно.
            relay(envelope.stamped(sender: sender), excluding: connection)

        case .presence, .challenge:
            break  // и то и другое рассылает только сервер
        }
    }

    /// Подпись под выданным вызовом — то же, что проверяет настоящий релей.
    private func verify(_ envelope: RelayEnvelope, from client: Client) -> Bool {
        guard !envelope.sender.isEmpty,
              let payload = envelope.payload,
              let proof = try? JSONDecoder().decode(HelloPayload.self, from: payload),
              let publicKey = try? Curve25519.Signing.PublicKey(
                  rawRepresentation: proof.publicKey) else {
            return false
        }

        return publicKey.isValidSignature(proof.signature, for: client.nonce)
    }

    private func broadcastPresence() {
        let names = clients.values.compactMap(\.displayName).sorted()

        guard let envelope = try? RelayEnvelope.presence(names),
              let data = try? envelope.encoded() else {
            return
        }

        for client in clients.values where client.displayName != nil {
            send(data, over: client.connection)
        }
    }

    private func relay(_ envelope: RelayEnvelope, excluding sender: NWConnection) {
        guard let data = try? envelope.encoded() else {
            return
        }

        for client in clients.values where client.connection !== sender {
            send(data, over: client.connection)
        }
    }

    private func send(_ data: Data, over connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "binary", metadata: [metadata])

        connection.send(content: data,
                        contentContext: context,
                        isComplete: true,
                        completion: .contentProcessed { error in
            if let error {
                print("[RelayServer] Send failed: \(error.localizedDescription)")
            }
        })
    }
}

/// `stateUpdateHandler` вызывается многократно, а continuation можно
/// возобновить ровно один раз.
private final class ResumeGuard: @unchecked Sendable {

    private var isClaimed = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isClaimed else {
            return false
        }

        isClaimed = true
        return true
    }
}
