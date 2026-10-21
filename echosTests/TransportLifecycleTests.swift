//
//  TransportLifecycleTests.swift
//  echosTests
//
//  Реакция транспорта на уход приложения в фон и возврат.
//
//  Раньше фон обрабатывал только экран радара: свернуть приложение из чата —
//  и сокет оставался умирать по таймауту, а собеседники ещё минуту видели
//  «призрака» в списке присутствия.
//
//  Теперь в фоне соединение живёт ещё немного — ради уведомления о
//  входящем, — и только потом закрывается штатно. Вернулись раньше —
//  соединение то же самое, представляться заново не надо.
//

import UIKit
import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.relayServer, .tags(.network))
struct TransportLifecycleTests {

    private var server: RelayServer { RelayFixture.server }
    // Подставной монитор, чтобы тесты не зависели от реальной сети машины.
    private let monitor = FakeNetworkMonitor()

    /// Свой центр уведомлений на тест. В XCTest годился общий: тесты шли по
    /// одному. Теперь они идут параллельно, и «приложение свернули» из одного
    /// теста сворачивало бы транспорты всех соседних — в том числе в других
    /// наборах.
    private let lifecycle = NotificationCenter()

    private func makeTransport(grace: Duration = .milliseconds(300)) -> WebSocketTransport {
        WebSocketTransport(url: server.url, displayName: "Alice",
                           networkMonitor: monitor, backgroundGrace: grace,
                           notificationCenter: lifecycle)
    }

    /// Соединение установлено с обеих сторон. Релей считает клиента своим
    /// раньше, чем клиент переводит своё состояние, и под нагрузкой
    /// параллельных тестов этот зазор успевал попасть в проверку: свернули
    /// приложение, а транспорт ещё `.connecting`.
    private func connected(_ transport: WebSocketTransport) async {
        _ = await waitUntil {
            self.server.connectedClientCount == 1 && transport.connectionState == .connected
        }
    }

    private func enterBackground() {
        lifecycle.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    private func enterForeground() {
        lifecycle.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // MARK: - Фон

    /// Свернули — соединение живёт ещё отсрочку: сообщение за это время
    /// дойдёт и станет уведомлением. Потом — закрываемся сами, штатно.
    @Test func background_keepsConnectionForTheGrace_thenCloses() async {
        let transport = makeTransport(grace: .milliseconds(400))
        defer { transport.stopDeviceDiscovery() }

        transport.startDeviceDiscovery()
        await connected(transport)

        enterBackground()

        try? await Task.sleep(for: .milliseconds(150))
        #expect(server.connectedClientCount == 1, "В отсрочку соединение живо")
        #expect(transport.connectionState == .connected)

        let released = await waitUntil { self.server.connectedClientCount == 0 }
        #expect(released, "После отсрочки сервер убирает нас из присутствия")
        #expect(transport.connectionState == .disconnected)
    }

    /// Вернулись до истечения отсрочки — соединение то же, hello заново
    /// не уходит.
    @Test func foregroundWithinGrace_keepsTheSameConnection() async {
        let transport = makeTransport(grace: .seconds(5))
        defer { transport.stopDeviceDiscovery() }

        transport.startDeviceDiscovery()
        // Представления, а не соединения: «hello» идёт отдельным кругом после
        // соединения, и под нагрузкой параллельных тестов приходил уже после
        // очистки журнала — тест ловил первое представление как повторное.
        _ = await waitUntil { self.server.introducedClientCount == 1 }
        server.clearReceived()

        enterBackground()
        try? await Task.sleep(for: .milliseconds(100))
        enterForeground()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(server.connectedClientCount == 1)
        #expect(!(server.received.contains { $0.kind == .hello }), "То же соединение — представляться заново незачем")

        // И отсрочка снята: по её истечении ничего не рвётся.
        try? await Task.sleep(for: .milliseconds(500))
        #expect(transport.connectionState == .connected)
    }

    @Test func foreground_restoresConnection() async {
        let transport = makeTransport()
        defer { transport.stopDeviceDiscovery() }

        transport.startDeviceDiscovery()
        await connected(transport)

        enterBackground()
        _ = await waitUntil { self.server.connectedClientCount == 0 }

        server.clearReceived()
        enterForeground()

        let restored = await waitUntil(timeout: .seconds(5)) {
            self.server.connectedClientCount == 1
        }

        #expect(restored)

        // Возврат — это новое подключение, значит надо представиться заново.
        let reannounced = await waitUntil(timeout: .seconds(5)) {
            self.server.received.contains { $0.kind == .hello }
        }
        #expect(reannounced)
    }

    /// Если поиск остановлен явно, возврат из фона не должен его воскрешать.
    @Test func foregroundAfterExplicitStop_staysDisconnected() async {
        let transport = makeTransport()

        transport.startDeviceDiscovery()
        await connected(transport)

        transport.stopDeviceDiscovery()
        _ = await waitUntil { self.server.connectedClientCount == 0 }

        enterForeground()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(self.server.connectedClientCount == 0)
    }

    // MARK: - Состояние для UI

    @Test func connectionState_isReportedInTransportTerms() async {
        let transport = makeTransport()
        defer { transport.stopDeviceDiscovery() }

        let states = transport.connectionStateUpdates
        transport.startDeviceDiscovery()

        let online = await firstElement(of: states, timeout: .seconds(5)) { $0 == .online }
        #expect(online == .online)

        monitor.goOffline()

        let waiting = await firstElement(of: transport.connectionStateUpdates,
                                         timeout: .seconds(5)) { $0 == .waitingForNetwork }
        #expect(waiting == .waitingForNetwork)
    }
}
