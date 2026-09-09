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

import UIKit
import XCTest
@testable import echos

@MainActor
final class TransportLifecycleTests: XCTestCase {

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

    private func makeTransport() -> WebSocketTransport {
        WebSocketTransport(url: server.url, displayName: "Alice", networkMonitor: monitor)
    }

    private func enterBackground() {
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification,
                                        object: nil)
    }

    private func enterForeground() {
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification,
                                        object: nil)
    }

    // MARK: - Фон

    func test_background_closesConnectionPromptly() async {
        let transport = makeTransport()
        defer { transport.stopDeviceDiscovery() }

        transport.startDeviceDiscovery()
        _ = await waitUntil { self.server.connectedClientCount == 1 }

        enterBackground()

        let released = await waitUntil { self.server.connectedClientCount == 0 }

        XCTAssertTrue(released, "Сервер должен сразу убрать нас из присутствия")
        XCTAssertEqual(transport.connectionState, .disconnected)
    }

    func test_foreground_restoresConnection() async {
        let transport = makeTransport()
        defer { transport.stopDeviceDiscovery() }

        transport.startDeviceDiscovery()
        _ = await waitUntil { self.server.connectedClientCount == 1 }

        enterBackground()
        _ = await waitUntil { self.server.connectedClientCount == 0 }

        server.clearReceived()
        enterForeground()

        let restored = await waitUntil(timeout: .seconds(5)) {
            self.server.connectedClientCount == 1
        }

        XCTAssertTrue(restored)

        // Возврат — это новое подключение, значит надо представиться заново.
        let reannounced = await waitUntil(timeout: .seconds(5)) {
            self.server.received.contains { $0.kind == .hello }
        }
        XCTAssertTrue(reannounced)
    }

    /// Если поиск остановлен явно, возврат из фона не должен его воскрешать.
    func test_foregroundAfterExplicitStop_staysDisconnected() async {
        let transport = makeTransport()

        transport.startDeviceDiscovery()
        _ = await waitUntil { self.server.connectedClientCount == 1 }

        transport.stopDeviceDiscovery()
        _ = await waitUntil { self.server.connectedClientCount == 0 }

        enterForeground()
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(self.server.connectedClientCount, 0)
    }

    // MARK: - Состояние для UI

    func test_connectionState_isReportedInTransportTerms() async {
        let transport = makeTransport()
        defer { transport.stopDeviceDiscovery() }

        let states = transport.connectionStateUpdates
        transport.startDeviceDiscovery()

        let online = await firstElement(of: states, timeout: .seconds(5)) { $0 == .online }
        XCTAssertEqual(online, .online)

        monitor.goOffline()

        let waiting = await firstElement(of: transport.connectionStateUpdates,
                                         timeout: .seconds(5)) { $0 == .waitingForNetwork }
        XCTAssertEqual(waiting, .waitingForNetwork)
    }
}
