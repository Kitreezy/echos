//
//  WebSocketClientTests.swift
//  echosTests
//
//  Integration по сути: клиент разговаривает с настоящим WebSocket-сервером
//  на `NWListener`, поднятым в этом же процессе. Мок здесь бесполезен —
//  проверяется как раз то, что происходит при реальном обрыве TCP.
//

import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.relayServer, .tags(.network))
struct WebSocketClientTests {

    private var server: RelayServer { RelayFixture.server }
    // Подставной монитор, чтобы тесты не зависели от реальной сети машины.
    private let monitor = FakeNetworkMonitor()

    /// Клиент, который представляется серверу при каждом подключении —
    /// так же, как это делает `WebSocketTransport`.
    private func makeClient(named name: String) -> WebSocketClient {
        let client = makeClient()

        RelayHandshake.install(on: client, as: name)

        return client
    }

    private func makeClient() -> WebSocketClient {
        let client = WebSocketClient(url: server.url, networkMonitor: monitor)
        // Интервалы прода — секунды; в тестах ждать столько нельзя.
        client.pingInterval = .milliseconds(100)
        client.pongTimeout = .milliseconds(300)
        client.initialReconnectDelay = .milliseconds(50)
        client.maxReconnectDelay = .milliseconds(200)
        return client
    }

    // MARK: - Подключение

    @Test func connect_reachesConnectedState() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()

        let connected = await waitUntil { client.state == .connected }

        #expect(connected)
    }

    @Test func disconnect_returnsToDisconnected() async {
        let client = makeClient()
        client.connect()
        _ = await waitUntil { client.state == .connected }

        client.disconnect()

        #expect(client.state == .disconnected)
    }

    // MARK: - Обмен

    @Test func sentEnvelope_reachesAnotherClient() async throws {
        let sender = makeClient(named: "Alice")
        let receiver = makeClient(named: "Bob")
        defer {
            sender.disconnect()
            receiver.disconnect()
        }

        let incoming = receiver.incomingMessages

        sender.connect()
        receiver.connect()

        // Порядок подключений не гарантирован, поэтому ждём присутствие
        // именно с обоими именами, а не первое пришедшее.
        let bothPresent = await firstElement(of: incoming, timeout: .seconds(5)) { data in
            guard let envelope = try? RelayEnvelope.decode(from: data),
                  envelope.kind == .presence,
                  let participants = try? envelope.decodePresence() else {
                return false
            }
            // Имена, а не адреса: адреса тут случайные, а проверяем мы то,
            // что оба клиента дошли до присутствия.
            return participants.map(\.name).sorted() == ["Alice", "Bob"]
        }

        #expect(bothPresent != nil, "Оба клиента должны попасть в список присутствия")
    }

    // MARK: - Живучесть

    /// Ключевой сценарий: сервер упал и поднялся, клиент вернулся сам.
    @Test func serverRestart_clientReconnectsOnItsOwn() async throws {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        let attemptsBefore = client.connectionAttempts

        try await server.restart()

        let reconnected = await waitUntil(timeout: .seconds(10)) {
            client.state == .connected && client.connectionAttempts > attemptsBefore
        }

        #expect(reconnected, "После перезапуска сервера клиент обязан вернуться сам")
    }

    /// Сообщение, отправленное без соединения, не теряется — уходит после
    /// восстановления связи.
    @Test func messageSentWhileOffline_isDeliveredAfterReconnect() async throws {
        let sender = makeClient(named: "Alice")
        defer { sender.disconnect() }

        sender.connect()
        _ = await waitUntil { self.server.connectedClientCount == 1 }

        // Роняем сервер и пишем в пустоту. Всё принятое до обрыва забываем,
        // чтобы проверять именно порядок событий после восстановления.
        server.clearReceived()
        await server.stop()
        _ = await waitUntil { sender.state != .connected }

        // Содержимое серверу не видно, поэтому метка — в самом конверте.
        let payload = SealedPayload(version: 1, box: Data("из оффлайна".utf8))
        await sender.send(try RelayEnvelope.message(payload, from: "Alice", to: "Bob").encoded())

        // Поднимаем обратно — дальше клиент возвращается и представляется сам.
        try await server.start()

        let delivered = await waitUntil(timeout: .seconds(15)) {
            self.server.receivedMessageMarkers.contains("из оффлайна")
        }

        #expect(delivered, "Отложенное сообщение должно уйти после восстановления связи")

        // Порядок важен: hello обязан прийти раньше сообщения, иначе сервер
        // не знает, от кого оно, и выбрасывает его.
        let kinds = server.received.map(\.kind)
        #expect(kinds.first == .hello)
    }

    // MARK: - Backoff

    @Test func reconnectDelay_growsExponentiallyAndIsCapped() {
        let client = makeClient()
        client.initialReconnectDelay = .seconds(1)
        client.maxReconnectDelay = .seconds(30)

        // Джиттер — половина интервала, поэтому проверяем границы, а не значение.
        #expect(client.reconnectDelay(for: 1).inSeconds >= 0.5)
        #expect(client.reconnectDelay(for: 1).inSeconds <= 1.0)

        #expect(client.reconnectDelay(for: 3).inSeconds >= 2.0)
        #expect(client.reconnectDelay(for: 3).inSeconds <= 4.0)

        #expect(client.reconnectDelay(for: 50).inSeconds <= 30.0, "Потолок должен держать задержку конечной")
    }

    @Test func reconnectDelay_isJittered() {
        let client = makeClient()
        client.initialReconnectDelay = .seconds(10)
        client.maxReconnectDelay = .seconds(60)

        let delays = (0..<20).map { _ in client.reconnectDelay(for: 3).inSeconds }

        #expect(Set(delays).count > 1, "Без разброса все клиенты вернутся одновременно и снова положат сервер")
    }
}
