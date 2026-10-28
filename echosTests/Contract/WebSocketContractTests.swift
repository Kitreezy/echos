//
//  WebSocketContractTests.swift
//  echosTests
//
//  Набор сценариев, не привязанный к конкретной реализации `RawWebSocket`.
//
//  Реализации — аргументами: каждый сценарий прогоняется на каждой из
//  `RawSocketImplementation.allCases`. Проверить другой транспорт — добавить
//  случай в перечисление, код сценариев не меняется. Так сравнивали свой
//  клиент со Starscream, см. docs/adr/001-websocket-client.md; в XCTest
//  для этого служило наследование набора, которого в Swift Testing нет.
//

import Foundation
import Testing
@testable import echos

/// Реализации `RawWebSocket`, на которых гоняется контракт.
enum RawSocketImplementation: CaseIterable, CustomTestStringConvertible {
    case urlSession

    @MainActor
    func make(url: URL) -> any RawWebSocket {
        switch self {
        case .urlSession:
            URLSessionRawSocket(url: url)
        }
    }

    /// Попадает в отчёт рядом с упавшим тестом: видно, какая реализация.
    var testDescription: String {
        switch self {
        case .urlSession: "URLSession"
        }
    }
}

@MainActor
@Suite(.relayServer, .tags(.network))
final class WebSocketContractTests {

    private var server: RelayServer { RelayFixture.server }
    private let monitor = FakeNetworkMonitor()

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

    private func makeClient(_ implementation: RawSocketImplementation, named name: String? = nil) -> WebSocketClient {
        let url = server.url

        let client = WebSocketClient(networkMonitor: monitor) {
            implementation.make(url: url)
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

    @Test(arguments: RawSocketImplementation.allCases)
    func connect_reachesConnectedState(_ implementation: RawSocketImplementation) async {
        let client = makeClient(implementation)
        defer { client.disconnect() }

        client.connect()

        let connected = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        #expect(connected, "соединение не установилось")
    }

    @Test(arguments: RawSocketImplementation.allCases)
    func disconnect_returnsToDisconnected(_ implementation: RawSocketImplementation) async {
        let client = makeClient(implementation)
        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        client.disconnect()

        #expect(client.state == .disconnected)
    }

    // MARK: - Обмен

    @Test(arguments: RawSocketImplementation.allCases)
    func messageReachesAnotherClient(_ implementation: RawSocketImplementation) async throws {
        let alice = makeClient(implementation, named: "Alice")
        let bob = makeClient(implementation, named: "Bob")
        defer {
            alice.disconnect()
            bob.disconnect()
        }

        let incoming = bob.incomingMessages

        alice.connect()
        bob.connect()

        // Два сокета — ещё не двое представившихся: сервер пересылает
        // только от тех, чей hello уже принял.
        _ = await waitUntil(timeout: .seconds(5)) {
            self.server.received.filter { $0.kind == .hello }.count == 2
        }

        let payload = SealedPayload(version: 1, box: Data("контракт".utf8))
        await alice.send(try RelayEnvelope.message(payload,
                                                   from: "Alice",
                                                   to: identity(for: "Bob").fingerprint).encoded())

        let delivered = await firstElement(of: incoming, timeout: .seconds(5)) { data in
            guard let envelope = try? RelayEnvelope.decode(from: data) else {
                return false
            }
            return envelope.kind == .message
        }

        #expect(delivered != nil, "сообщение не дошло")
    }

    // MARK: - Живучесть

    @Test(arguments: RawSocketImplementation.allCases)
    func serverRestart_clientReconnectsOnItsOwn(_ implementation: RawSocketImplementation) async throws {
        let client = makeClient(implementation)
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        let attemptsBefore = client.connectionAttempts
        try await server.restart()

        let reconnected = await waitUntil(timeout: .seconds(15)) {
            client.state == .connected && client.connectionAttempts > attemptsBefore
        }

        #expect(reconnected, "клиент не вернулся после перезапуска сервера")
    }

    /// Heartbeat: если ping/pong не работает, соединение будет объявлено
    /// мёртвым по таймауту и клиент начнёт переподключаться на ровном месте.
    @Test(arguments: RawSocketImplementation.allCases)
    func heartbeat_keepsConnectionAlive(_ implementation: RawSocketImplementation) async {
        let client = makeClient(implementation)
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        let attemptsBefore = client.connectionAttempts

        // Несколько циклов ping/pong подряд.
        try? await Task.sleep(for: .seconds(1))

        #expect(client.state == .connected, "соединение объявлено мёртвым при живом сервере")
        #expect(client.connectionAttempts == attemptsBefore, "лишние переподключения при работающем ping/pong")
    }

    // MARK: - Реакция на сеть

    @Test(arguments: RawSocketImplementation.allCases)
    func networkLoss_pausesReconnects(_ implementation: RawSocketImplementation) async {
        let client = makeClient(implementation)
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        monitor.goOffline()

        let paused = await waitUntil(timeout: .seconds(5)) { client.state == .waitingForNetwork }

        #expect(paused)
    }

    @Test(arguments: RawSocketImplementation.allCases)
    func networkRestored_reconnectsImmediately(_ implementation: RawSocketImplementation) async {
        let client = makeClient(implementation)
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        monitor.goOffline()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .waitingForNetwork }

        monitor.goOnline()

        let reconnected = await waitUntil(timeout: .seconds(5)) { client.state == .connected }

        #expect(reconnected)
    }

    @Test(arguments: RawSocketImplementation.allCases)
    func messageSentWhileOffline_isDeliveredAfterReconnect(_ implementation: RawSocketImplementation) async throws {
        let client = makeClient(implementation, named: "Alice")
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil(timeout: .seconds(5)) { self.server.connectedClientCount == 1 }

        server.clearReceived()
        monitor.goOffline()
        _ = await waitUntil(timeout: .seconds(5)) { client.state == .waitingForNetwork }

        let payload = SealedPayload(version: 1, box: Data("из оффлайна".utf8))
        await client.send(try RelayEnvelope.message(payload, from: "Alice", to: "Bob").encoded())

        monitor.goOnline()

        let delivered = await waitUntil(timeout: .seconds(15)) {
            self.server.receivedMessageMarkers.contains("из оффлайна")
        }

        #expect(delivered, "отложенное сообщение потеряно")
        #expect(server.received.first?.kind == .hello, "очередь ушла раньше рукопожатия")
    }
}
