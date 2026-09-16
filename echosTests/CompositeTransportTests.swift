//
//  CompositeTransportTests.swift
//  echosTests
//
//  Составной транспорт: один список из двух каналов и отправка по тому,
//  которому принадлежит адрес. Каналы изображают два `LoopbackTransport`.
//

import XCTest
@testable import echos

@MainActor
final class CompositeTransportTests: XCTestCase {

    private var nearby: LoopbackTransport!
    private var relay: LoopbackTransport!
    private var transport: CompositeTransport!

    /// Последний слитый список.
    private var peers: [Peer] = []
    private var peersTask: Task<Void, Never>?

    override func setUp() async throws {
        nearby = LoopbackTransport()
        relay = LoopbackTransport()
        transport = CompositeTransport(nearby: nearby, relay: relay)

        let stream = transport.peerStream
        peersTask = Task { [weak self] in
            for await list in stream {
                self?.peers = list
            }
        }
    }

    override func tearDown() {
        peersTask?.cancel()
        transport = nil
    }

    private func payload(_ text: String) -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: false), senderName: "Me")
    }

    // MARK: - Слияние списков

    func test_peersFromBothChannels_showUpInOneList() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        relay.emit(peers: [Peer(address: "bbbb", displayName: "Борис", status: .connected)])

        let merged = await waitUntil { self.peers.count == 2 }
        XCTAssertTrue(merged)
        XCTAssertEqual(peers.map(\.address), ["aaaa", "bbbb"])
    }

    func test_samePersonOnBothChannels_isListedOnce() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        relay.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])

        let merged = await waitUntil {
            self.peers.count == 1 && self.transport.channel(for: "aaaa") == .nearby
        }
        XCTAssertTrue(merged)
    }

    func test_whenChannelGoesQuiet_itsPeersLeaveTheList() async {
        relay.emit(peers: [Peer(address: "bbbb", displayName: "Борис", status: .connected)])
        _ = await waitUntil { self.peers.count == 1 }

        relay.emit(peers: [])

        let gone = await waitUntil { self.peers.isEmpty }
        XCTAssertTrue(gone)
    }

    // MARK: - Кому принадлежит адрес

    func test_connectedNearby_winsOverRelay() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        relay.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        _ = await waitUntil { self.transport.channel(for: "aaaa") == .nearby }

        try? await transport.sendMessage(payload("привет"), to: "aaaa")

        XCTAssertEqual(nearby.sentMessages.count, 1)
        XCTAssertTrue(relay.sentMessages.isEmpty)
    }

    func test_nearbyWithoutSession_losesToRelay() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .notConnected)])
        relay.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        _ = await waitUntil { self.transport.channel(for: "aaaa") == .relay }

        try? await transport.sendMessage(payload("привет"), to: "aaaa")

        XCTAssertTrue(nearby.sentMessages.isEmpty)
        XCTAssertEqual(relay.sentMessages.count, 1)
    }

    func test_onlyNearbyWithoutSession_stillGoesNearby() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .notConnected)])
        _ = await waitUntil { self.transport.channel(for: "aaaa") == .nearby }

        try? await transport.sendMessage(payload("привет"), to: "aaaa")

        XCTAssertEqual(nearby.sentMessages.count, 1)
    }

    func test_unknownAddress_isUnreachable() async {
        do {
            try await transport.sendMessage(payload("привет"), to: "zzzz")
            XCTFail("отправка в никуда должна падать")
        } catch let error as CompositeTransportError {
            XCTAssertEqual(error, .unreachable("zzzz"))
        } catch {
            XCTFail("не та ошибка: \(error)")
        }
    }

    // MARK: - Входящее

    func test_incomingFromEitherChannel_reachesTheSameStream() async {
        var received: [String] = []
        let stream = transport.messageStream
        let task = Task {
            for await event in stream {
                received.append(event.value.text)
            }
        }
        defer { task.cancel() }

        nearby.emit(message: payload("рядом"))
        relay.emit(message: payload("издалека"))

        let both = await waitUntil { received.count == 2 }
        XCTAssertTrue(both)
        XCTAssertEqual(Set(received), ["рядом", "издалека"])
    }

    // MARK: - Состояние связи

    func test_relayState_isPassedThrough() async {
        var states: [TransportConnectionState] = []
        let stream = transport.connectionStateUpdates
        let task = Task {
            for await state in stream {
                states.append(state)
            }
        }
        defer { task.cancel() }

        relay.emit(connectionState: .waitingForNetwork)

        let got = await waitUntil { states.last == .waitingForNetwork }
        XCTAssertTrue(got)
    }

    func test_someoneConnectedNearby_meansOnline_evenWithoutNetwork() async {
        var states: [TransportConnectionState] = []
        let stream = transport.connectionStateUpdates
        let task = Task {
            for await state in stream {
                states.append(state)
            }
        }
        defer { task.cancel() }

        relay.emit(connectionState: .waitingForNetwork)
        _ = await waitUntil { states.last == .waitingForNetwork }

        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])

        let online = await waitUntil { states.last == .online }
        XCTAssertTrue(online)
    }

    // MARK: - Обнаружение

    func test_discovery_startsBothChannels() {
        transport.startDeviceDiscovery()

        XCTAssertTrue(nearby.isDiscovering)
        XCTAssertTrue(relay.isDiscovering)
    }
}
