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
import XCTest
@testable import echos

@MainActor
final class NetworkAwarenessTests: XCTestCase {

    private var server: RelayServer!
    private var monitor: FakeNetworkMonitor!

    override func setUp() async throws {
        try await super.setUp()
        server = RelayServer()
        try await server.start()
        monitor = FakeNetworkMonitor()
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
        monitor = nil
        try await super.tearDown()
    }

    private func makeClient() -> WebSocketClient {
        let client = WebSocketClient(url: server.url, networkMonitor: monitor)
        client.pingInterval = .milliseconds(100)
        client.pongTimeout = .milliseconds(300)
        client.initialReconnectDelay = .milliseconds(50)
        client.maxReconnectDelay = .milliseconds(200)
        return client
    }

    // MARK: - Монитор запускается

    func test_connect_startsNetworkMonitor() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()

        XCTAssertTrue(monitor.isRunning)
    }

    // MARK: - Сети нет

    func test_connectWithoutNetwork_doesNotEvenTry() async {
        monitor.goOffline()

        let client = makeClient()
        defer { client.disconnect() }

        client.connect()

        XCTAssertEqual(client.state, .waitingForNetwork)
        XCTAssertEqual(client.connectionAttempts, 0,
                       "Стучаться в отсутствующую сеть незачем")
    }

    func test_networkLoss_pausesReconnectAttempts() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        monitor.goOffline()

        let paused = await waitUntil { client.state == .waitingForNetwork }
        XCTAssertTrue(paused)

        let attemptsAfterLoss = client.connectionAttempts
        try? await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(client.connectionAttempts, attemptsAfterLoss,
                       "Пока пути нет, попытки идти не должны")
    }

    /// Сервер упал и сеть пропала выглядят для сокета одинаково, но требуют
    /// разного: в первом случае ретраим, во втором ждём.
    func test_serverLossWithNetwork_keepsRetrying() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        await server.stop()

        let retried = await waitUntil(timeout: .seconds(5)) {
            client.connectionAttempts > attemptsBefore
        }

        XCTAssertTrue(retried, "Сеть есть — значит дело в сервере, надо пробовать снова")
        XCTAssertNotEqual(client.state, .waitingForNetwork)
    }

    // MARK: - Сеть вернулась

    func test_networkRestored_reconnectsImmediately() async {
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

        XCTAssertTrue(reconnected)
        XCTAssertGreaterThan(client.connectionAttempts, attemptsBefore)
    }

    /// После долгого оффлайна backoff вырос бы до потолка. Ждать эти секунды
    /// при включении Wi-Fi незачем — счётчик попыток сбрасывается.
    func test_networkRestored_resetsBackoff() async {
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

        XCTAssertTrue(reconnected, "Возврат сети должен подключать сразу, а не по накопленной задержке")
    }

    // MARK: - Смена интерфейса

    /// Переход Wi-Fi ↔ LTE меняет локальный адрес: соединение уже мертво,
    /// хотя сокет об этом молчит. Ловится только по смене интерфейса.
    func test_interfaceChange_forcesReconnect() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        monitor.goOnline(interface: .cellular)

        let reconnected = await waitUntil(timeout: .seconds(5)) {
            client.connectionAttempts > attemptsBefore && client.state == .connected
        }

        XCTAssertTrue(reconnected)
    }

    func test_samePathReportedTwice_doesNotReconnect() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        monitor.goOnline(interface: .wifi)
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(client.connectionAttempts, attemptsBefore,
                       "Тот же путь — не повод рвать живое соединение")
    }

    // MARK: - Очередь переживает оффлайн

    func test_messageSentWhileOffline_isDeliveredWhenNetworkReturns() async throws {
        let client = makeClient()
        defer { client.disconnect() }

        client.onConnected = { [weak client] in
            guard let hello = try? RelayEnvelope.hello(from: "Alice").encoded() else {
                return
            }
            await client?.send(hello)
        }

        client.connect()
        _ = await waitUntil { self.server.connectedClientCount == 1 }

        server.clearReceived()
        monitor.goOffline()
        _ = await waitUntil { client.state == .waitingForNetwork }

        let payload = MessagePayload(from: Message(text: "без сети", isFromMe: true),
                                     senderName: "Alice")
        await client.send(try RelayEnvelope.message(payload, from: "Alice", to: "Bob").encoded())

        monitor.goOnline()

        let delivered = await waitUntil(timeout: .seconds(10)) {
            self.server.receivedMessageTexts.contains("без сети")
        }

        XCTAssertTrue(delivered)
        XCTAssertEqual(server.received.first?.kind, .hello,
                       "Представиться надо раньше, чем досылать очередь")
    }
}
