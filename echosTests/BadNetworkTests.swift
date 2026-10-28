//
//  BadNetworkTests.swift
//  echosTests
//
//  Клиент на сети, которая есть, но плохая.
//
//  `NetworkAwarenessTests` проверяют сеть, которой нет: туда монитор пути
//  сообщает честно. Здесь путь есть всё время, а соединение зависает,
//  теряет pong и рвётся — монитор об этом не узнает, и заметить беду
//  клиент должен сам, по таймаутам.
//

import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.relayServer, .tags(.network))
struct BadNetworkTests {

    private var server: RelayServer { RelayFixture.server }
    private let monitor = FakeNetworkMonitor()

    private func makeClient(on network: BadNetwork) -> WebSocketClient {
        let client = WebSocketClient(networkMonitor: monitor) { network.makeSocket() }
        client.pingInterval = .milliseconds(100)
        client.pongTimeout = .milliseconds(300)
        client.connectTimeout = .milliseconds(300)
        client.sendTimeout = .milliseconds(300)
        client.initialReconnectDelay = .milliseconds(50)
        client.maxReconnectDelay = .milliseconds(200)
        RelayHandshake.install(on: client, as: "Alice")
        return client
    }

    // MARK: - Рукопожатие

    /// Без своего таймаута клиент висел бы в `connecting` до минуты — столько
    /// ждёт URLSession — и ни разу не попробовал бы снова.
    @Test func hangingHandshake_isAbandonedAndRetried() async {
        let network = BadNetwork(url: server.url)
        network.hangsOnOpen = true
        let client = makeClient(on: network)
        defer { client.disconnect() }

        client.connect()

        let retried = await waitUntil { network.attempts >= 3 }
        #expect(retried, "Зависшее рукопожатие надо бросать и пробовать снова")
        #expect(client.state == .connecting)

        network.hangsOnOpen = false

        let connected = await waitUntil { client.state == .connected }
        #expect(connected, "Сеть выздоровела — следующая попытка проходит")
    }

    // MARK: - Мигающее соединение

    /// Открылось и тут же оборвалось — и так раз за разом. Пока откат
    /// сбрасывался на открытии, каждая попытка шла с первой, самой короткой
    /// задержкой, и клиент долбил сервер без передышки.
    @Test func flappingConnection_backsOffInsteadOfHammering() async {
        let network = BadNetwork(url: server.url)
        network.dropsAfterOpen = .milliseconds(10)
        let client = makeClient(on: network)
        client.maxReconnectDelay = .seconds(5)
        defer { client.disconnect() }

        client.connect()
        try? await Task.sleep(for: .milliseconds(1200))

        // Задержки 50, 100, 200, 400, 800 мс, джиттер урезает каждую не
        // больше чем вдвое: за 1.2 с помещается не больше семи попыток.
        // Без отката их было бы два десятка.
        #expect(network.attempts <= 8, "Попыток: \(network.attempts)")
        #expect(network.attempts >= 3, "Переподключаться всё же надо")
    }

    // MARK: - Отправка

    /// Отправка, которая не возвращается, не должна ни повесить отправителя,
    /// ни потерять сообщение: оно возвращается в очередь и уходит, когда
    /// соединение поднимется заново.
    @Test func stalledSend_isRequeuedAndDeliveredAfterReconnect() async throws {
        let network = BadNetwork(url: server.url)
        let client = makeClient(on: network)
        defer { client.disconnect() }

        client.connect()
        // Сервер засчитывает подключение раньше, чем клиент узнаёт об
        // открытии. Без второго условия сообщение уходит в очередь как
        // офлайновое, и до заглохшей отправки дело не доходит.
        _ = await waitUntil { self.server.connectedClientCount == 1 && client.state == .connected }

        network.stallsSends = true
        let payload = SealedPayload(version: 1, box: Data("застрявшее".utf8))
        let started = ContinuousClock.now
        await client.send(try RelayEnvelope.message(payload, from: "Alice", to: "Bob").encoded())

        #expect(ContinuousClock.now - started < .seconds(2), "send не должен висеть дольше таймаута")

        network.stallsSends = false

        let reconnected = await waitUntil { network.attempts >= 2 }
        #expect(reconnected, "Заглохшее соединение надо пересоздать")

        let delivered = await waitUntil(timeout: .seconds(5)) {
            self.server.receivedMessageMarkers.contains("застрявшее")
        }
        #expect(delivered, "Сообщение из заглохшей отправки должно дойти после переподключения")
    }

    // MARK: - Тихая смерть

    /// Соединение умерло посередине: сокет выглядит живым, pong не приходит.
    /// Это единственный сбой, который замечает только heartbeat.
    @Test func lostPongs_areNoticedAndConnectionIsReplaced() async {
        let network = BadNetwork(url: server.url)
        let client = makeClient(on: network)
        defer { client.disconnect() }

        client.connect()
        _ = await waitUntil { client.state == .connected }

        network.losesPongs = true

        let replaced = await waitUntil(timeout: .seconds(3)) { network.attempts >= 2 }
        #expect(replaced, "Без pong соединение надо считать мёртвым и пересоздавать")
    }
}
