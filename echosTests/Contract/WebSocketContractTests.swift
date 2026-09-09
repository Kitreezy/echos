//
//  WebSocketContractTests.swift
//  echosTests
//
//  Набор сценариев, не привязанный к конкретной реализации `RawWebSocket`.
//
//  Базовый класс гоняет `URLSessionRawSocket`. Чтобы проверить другой
//  транспорт, достаточно унаследоваться и подменить фабрику — код тестов
//  не меняется. Так сравнивали свой клиент со Starscream, см.
//  docs/adr/001-websocket-client.md.
//

import XCTest
@testable import echos

@MainActor
class WebSocketContractTests: XCTestCase {

    private(set) var server: RelayServer!
    private(set) var monitor: FakeNetworkMonitor!

    /// Точка подмены. Наследники возвращают свой транспорт.
    func makeRawSocket(url: URL) -> any RawWebSocket {
        URLSessionRawSocket(url: url)
    }

    /// Попадает в сообщения об ошибках: иначе при нескольких наследниках
    /// непонятно, какая реализация упала.
    var configurationName: String {
        "URLSession"
    }

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

    /// Ключ на имя: тесту нужен не только сам клиент, но и его адрес —
    /// адресовать по имени релей больше не умеет.
    private var identities: [String: DeviceIdentity] = [:]

    private func identity(for name: String) -> DeviceIdentity {
        if let existing = identities[name] {
            return existing
        }

        let created = DeviceIdentity()
        identities[name] = created
        return created
    }

    private func makeClient(named name: String? = nil) -> WebSocketClient {
        let url = server.url

        let client = WebSocketClient(networkMonitor: monitor) { [weak self] in
            self?.makeRawSocket(url: url) ?? URLSessionRawSocket(url: url)
        }

        client.pingInterval = .milliseconds(100)
        // Таймаут короче интервала: если pong не доходит наверх, клиент
        // обязан это заметить в пределах теста, а не «когда-нибудь».
        client.pongTimeout = .milliseconds(250)
        client.initialReconnectDelay = .milliseconds(50)
        client.maxReconnectDelay = .milliseconds(300)

        if let name {
            RelayHandshake.install(on: client, as: name, using: identity(for: name))
        }

        return client
    }

    // MARK: - Базовое соединение

    func test_connect_reachesConnectedState() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()

        let connected = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        XCTAssertTrue(connected, "\(configurationName): соединение не установилось")
    }

    func test_disconnect_returnsToDisconnected() async {
        let client = makeClient()
        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        client.disconnect()

        XCTAssertEqual(client.state, .disconnected, configurationName)
    }

    // MARK: - Обмен

    func test_messageReachesAnotherClient() async throws {
        let alice = makeClient(named: "Alice")
        let bob = makeClient(named: "Bob")
        defer {
            alice.disconnect()
            bob.disconnect()
        }

        let incoming = bob.incomingMessages

        alice.connect()
        bob.connect()

        _ = await waitUntil(timeout: .seconds(5)) { self.server.connectedClientCount == 2 }

        let payload = MessagePayload(from: Message(text: "контракт", isFromMe: true),
                                     senderName: "Alice")
        await alice.send(try RelayEnvelope.message(payload,
                                                   from: "Alice",
                                                   to: identity(for: "Bob").fingerprint).encoded())

        let delivered = await firstElement(of: incoming, timeout: .seconds(5)) { data in
            guard let envelope = try? RelayEnvelope.decode(from: data) else {
                return false
            }
            return envelope.kind == .message
        }

        XCTAssertNotNil(delivered, "\(configurationName): сообщение не дошло")
    }

    // MARK: - Живучесть

    func test_serverRestart_clientReconnectsOnItsOwn() async throws {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        try await server.restart()

        let reconnected = await waitUntil(timeout: .seconds(15)) {
            client.state == .connected && client.connectionAttempts > attemptsBefore
        }

        XCTAssertTrue(reconnected, "\(configurationName): клиент не вернулся после перезапуска сервера")
    }

    /// Heartbeat: если ping/pong не работает, соединение будет объявлено
    /// мёртвым по таймауту и клиент начнёт переподключаться на ровном месте.
    func test_heartbeat_keepsConnectionAlive() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        let attemptsBefore = client.connectionAttempts

        // Несколько циклов ping/pong подряд.
        try? await Task.sleep(for: .seconds(1))

        XCTAssertEqual(client.state, .connected,
                       "\(configurationName): соединение объявлено мёртвым при живом сервере")
        XCTAssertEqual(client.connectionAttempts, attemptsBefore,
                       "\(configurationName): лишние переподключения при работающем ping/pong")
    }

    // MARK: - Реакция на сеть

    func test_networkLoss_pausesReconnects() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        monitor.goOffline()

        let paused = await waitUntil(timeout: .seconds(5)) { client.state == .waitingForNetwork }

        XCTAssertTrue(paused, configurationName)
    }

    func test_networkRestored_reconnectsImmediately() async {
        let client = makeClient()
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        monitor.goOffline()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .waitingForNetwork }

        monitor.goOnline()

        let reconnected = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        XCTAssertTrue(reconnected, configurationName)
    }

    func test_messageSentWhileOffline_isDeliveredAfterReconnect() async throws {
        let client = makeClient(named: "Alice")
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { self.server.connectedClientCount == 1 }

        server.clearReceived()
        monitor.goOffline()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .waitingForNetwork }

        let payload = MessagePayload(from: Message(text: "из оффлайна", isFromMe: true),
                                     senderName: "Alice")
        await client.send(try RelayEnvelope.message(payload, from: "Alice", to: "Bob").encoded())

        monitor.goOnline()

        let delivered = await waitUntil(timeout: .seconds(15)) {
            self.server.receivedMessageTexts.contains("из оффлайна")
        }

        XCTAssertTrue(delivered, "\(configurationName): отложенное сообщение потеряно")
        XCTAssertEqual(server.received.first?.kind, .hello,
                       "\(configurationName): очередь ушла раньше рукопожатия")
    }
}
