//
//  NetworkAwarenessTests.swift
//  echosTests
//
//  Как клиент реагирует на состояние сети.
//
//  Проверяется не «переподключился вообще», а «переподключился разумно»:
//  не долбится в отсутствующую сеть, возвращается мгновенно и замечает
//  смену интерфейса, о которой сокет не сообщает.
//

import Network
import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.relayServer, .tags(.network))
struct NetworkAwarenessTests {

    private var server: RelayServer { RelayFixture.server }
    // Подставной монитор, чтобы тесты не зависели от реальной сети машины.
    private let monitor = FakeNetworkMonitor()

    private func makeClient() -> WebSocketClient {
        let client = WebSocketClient(url: server.url, networkMonitor: monitor)
        client.pingInterval = .milliseconds(100)
        client.pongTimeout = .milliseconds(300)
        client.initialReconnectDelay = .milliseconds(50)
        client.maxReconnectDelay = .milliseconds(200)
        return client
    }

    // MARK: - Монитор запускается

    @Test func connect_startsNetworkMonitor() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()

        #expect(monitor.isRunning)
    }

    // MARK: - Сети нет

    @Test func connectWithoutNetwork_doesNotEvenTry() async {
        monitor.goOffline()

        let client = makeClient()
        defer { client.disconnect() }

        client.connect()

        #expect(client.state == .waitingForNetwork)
        #expect(client.connectionAttempts == 0, "Стучаться в отсутствующую сеть незачем")
    }

    @Test func networkLoss_pausesReconnectAttempts() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        monitor.goOffline()

        let paused = await waitUntil { client.state == .waitingForNetwork }
        #expect(paused)

        let attemptsAfterLoss = client.connectionAttempts
        try? await Task.sleep(for: .milliseconds(600))

        #expect(client.connectionAttempts == attemptsAfterLoss, "Пока пути нет, попытки идти не должны")
    }

    /// Сервер упал и сеть пропала выглядят для сокета одинаково, но требуют
    /// разного: в первом случае ретраим, во втором ждём.
    @Test func serverLossWithNetwork_keepsRetrying() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        await server.stop()

        let retried = await waitUntil(timeout: .seconds(5)) {
            client.connectionAttempts > attemptsBefore
        }

        #expect(retried, "Сеть есть — значит дело в сервере, надо пробовать снова")
        #expect(client.state != .waitingForNetwork)
    }

    // MARK: - Сеть вернулась

    @Test func networkRestored_reconnectsImmediately() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        monitor.goOffline()
        _ = await waitUntil { client.state == .waitingForNetwork }

        let attemptsBefore = client.connectionAttempts
        monitor.goOnline()

        let reconnected = await waitUntil(timeout: .seconds(5)) {
            client.state == .connected
        }

        #expect(reconnected)
        #expect(client.connectionAttempts > attemptsBefore)
    }

    /// После долгого оффлайна backoff вырос бы до потолка. Ждать эти секунды
    /// при включении Wi-Fi незачем — счётчик попыток сбрасывается.
    @Test func networkRestored_resetsBackoff() async {
        let client = makeClient()
        client.initialReconnectDelay = .seconds(2)
        client.maxReconnectDelay = .seconds(30)
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        monitor.goOffline()
        _ = await waitUntil { client.state == .waitingForNetwork }

        monitor.goOnline()

        // Если бы backoff не сбрасывался, ждать пришлось бы секунды.
        let reconnected = await waitUntil(timeout: .milliseconds(900)) {
            client.state == .connected
        }

        #expect(reconnected, "Возврат сети должен подключать сразу, а не по накопленной задержке")
    }

    // MARK: - Смена интерфейса

    /// Переход Wi-Fi ↔ LTE меняет локальный адрес: соединение уже мертво,
    /// хотя сокет об этом молчит. Ловится только по смене интерфейса.
    @Test func interfaceChange_forcesReconnect() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        monitor.goOnline(interface: .cellular)

        let reconnected = await waitUntil(timeout: .seconds(5)) {
            client.connectionAttempts > attemptsBefore && client.state == .connected
        }

        #expect(reconnected)
    }

    @Test func samePathReportedTwice_doesNotReconnect() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        monitor.goOnline(interface: .wifi)
        try? await Task.sleep(for: .milliseconds(300))

        #expect(client.connectionAttempts == attemptsBefore, "Тот же путь — не повод рвать живое соединение")
    }

    // MARK: - Очередь переживает оффлайн

    @Test func messageSentWhileOffline_isDeliveredWhenNetworkReturns() async throws {
        let client = makeClient()
        defer { client.disconnect() }

        RelayHandshake.install(on: client, as: "Alice")

        client.connect()
        _ = await waitUntil { self.server.connectedClientCount == 1 }

        server.clearReceived()
        monitor.goOffline()
        _ = await waitUntil { client.state == .waitingForNetwork }

        // Содержимое серверу не видно, поэтому метка — в самом конверте.
        let payload = SealedPayload(version: 1, box: Data("без сети".utf8))
        await client.send(try RelayEnvelope.message(payload, from: "Alice", to: "Bob").encoded())

        monitor.goOnline()

        let delivered = await waitUntil(timeout: .seconds(10)) {
            self.server.receivedMessageMarkers.contains("без сети")
        }

        #expect(delivered)
        #expect(server.received.first?.kind == .hello, "Представиться надо раньше, чем досылать очередь")
    }
}
