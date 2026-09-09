//
//  WebSocketTransportTests.swift
//  echosTests
//
//  Вторая реализация `PeerTransport` против настоящего релея: два «устройства»
//  в одном процессе видят друг друга и обмениваются сообщениями.
//

import XCTest
@testable import echos

@MainActor
final class WebSocketTransportTests: XCTestCase {

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

    private func makeTransport(named name: String) -> WebSocketTransport {
        WebSocketTransport(url: server.url, displayName: name, networkMonitor: monitor)
    }

    /// Поднимает оба транспорта и ждёт, пока сервер увидит обоих.
    private func makePair() async -> (alice: WebSocketTransport, bob: WebSocketTransport) {
        let alice = makeTransport(named: "Alice")
        let bob = makeTransport(named: "Bob")

        alice.startDeviceDiscovery()
        bob.startDeviceDiscovery()

        _ = await waitUntil { self.server.connectedClientCount == 2 }

        return (alice, bob)
    }

    // MARK: - Присутствие

    func test_twoTransports_seeEachOtherInPeerStream() async {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        XCTAssertEqual(alice.connectionState, .connected)

        // Ждём именно появления собеседника: до этого поток успевает отдать
        // пустой список — присутствие с одной лишь Alice.
        let peers = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            !$0.isEmpty
        }

        XCTAssertEqual(peers?.map(\.displayName), ["Bob"],
                       "Себя в списке собеседников быть не должно")
        XCTAssertEqual(peers?.first?.status, .connected)
    }

    func test_peerIdentifiers_areStableAcrossPresenceUpdates() async {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let first = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            $0.contains { $0.displayName == "Bob" }
        }?.first?.id

        // Третий участник вызывает новую рассылку присутствия.
        let carol = makeTransport(named: "Carol")
        carol.startDeviceDiscovery()
        defer { carol.stopDeviceDiscovery() }

        let updated = await waitUntil(timeout: .seconds(5)) {
            self.server.connectedClientCount == 3
        }
        XCTAssertTrue(updated)

        let second = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            $0.count == 2
        }?.first { $0.displayName == "Bob" }?.id

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second, "Идентификатор пира не должен меняться от обновления к обновлению")
    }

    // MARK: - Обмен

    func test_message_isDeliveredToTheOtherTransport() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let incoming = bob.messageStream

        let payload = MessagePayload(from: Message(text: "привет из сети", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: "Bob")

        let received = await collect(incoming, count: 1, timeout: .seconds(5))

        XCTAssertEqual(received.first?.text, "привет из сети")
        XCTAssertEqual(received.first?.senderName, "Alice")
    }

    func test_typingEvent_isDeliveredToTheOtherTransport() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let incoming = bob.typingStream

        try await alice.sendTypingEvent(TypingEvent(type: .start, peerName: "Alice"), to: "Bob")

        let received = await collect(incoming, count: 1, timeout: .seconds(5))

        XCTAssertEqual(received.first?.type, .start)
        XCTAssertEqual(received.first?.peerName, "Alice")
    }

    /// Отправитель не должен получать собственное сообщение обратно.
    func test_sender_doesNotReceiveItsOwnMessage() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let echoed = alice.messageStream

        let payload = MessagePayload(from: Message(text: "эхо", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: "Bob")

        _ = await collect(bob.messageStream, count: 1, timeout: .seconds(5))
        let ownMessages = await collect(echoed, count: 1, timeout: .milliseconds(300))

        XCTAssertTrue(ownMessages.isEmpty)
    }

    // MARK: - Восстановление сессии

    /// После перезапуска сервера транспорт обязан не только переподключиться,
    /// но и заново представиться — иначе он будет «онлайн», но невидим.
    func test_afterServerRestart_transportReannouncesItself() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        // Считаем только то, что придёт после обрыва.
        server.clearReceived()
        try await server.restart()

        let reannounced = await waitUntil(timeout: .seconds(15)) {
            self.server.received.filter { $0.kind == .hello }.count >= 2
        }

        XCTAssertTrue(reannounced, "После реконнекта hello должен уйти повторно")
    }

    // MARK: - Ограничения релея

    func test_connectToUnknownPeer_throws() async {
        let alice = makeTransport(named: "Alice")
        alice.startDeviceDiscovery()
        defer { alice.stopDeviceDiscovery() }

        _ = await waitUntil { self.server.connectedClientCount == 1 }

        do {
            try await alice.connectToPeer(displayName: "Никого")
            XCTFail("Подключение к отсутствующему собеседнику должно падать")
        }
        catch {
            XCTAssertTrue(error is RelayError)
        }
    }
}
