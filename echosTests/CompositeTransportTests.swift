//
//  CompositeTransportTests.swift
//  echosTests
//
//  Составной транспорт: один список из двух каналов и отправка по тому,
//  которому принадлежит адрес. Каналы изображают два `LoopbackTransport`.
//

import Foundation
import Testing
@testable import echos

@MainActor
final class CompositeTransportTests {

    private let nearby = LoopbackTransport()
    private let relay = LoopbackTransport()
    private let transport: CompositeTransport

    /// Последний слитый список. Пишет его фоновая задача — поэтому набор
    /// класс, а не структура: задаче нужна ссылка на него.
    private var peers: [Peer] = []
    private var peersTask: Task<Void, Never>?

    init() {
        transport = CompositeTransport(nearby: nearby, relay: relay)

        let stream = transport.peerStream
        peersTask = Task { [weak self] in
            for await list in stream {
                self?.peers = list
            }
        }
    }

    /// Уборка — в `deinit`: Swift Testing создаёт набор на каждый тест и
    /// отпускает после. `isolated` — потому что задача принадлежит главному
    /// актору, а обычный `deinit` к нему доступа не имеет.
    isolated deinit {
        peersTask?.cancel()
    }

    private func payload(_ text: String) -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: false), senderName: "Me")
    }

    // MARK: - Слияние списков

    @Test func peersFromBothChannels_showUpInOneList() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        relay.emit(peers: [Peer(address: "bbbb", displayName: "Борис", status: .connected)])

        let merged = await waitUntil { self.peers.count == 2 }
        #expect(merged)
        #expect(peers.map(\.address) == ["aaaa", "bbbb"])
    }

    @Test func samePersonOnBothChannels_isListedOnce() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        relay.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])

        let merged = await waitUntil {
            self.peers.count == 1 && self.transport.channel(for: "aaaa") == .nearby
        }
        #expect(merged)
    }

    @Test func whenChannelGoesQuiet_itsPeersLeaveTheList() async {
        relay.emit(peers: [Peer(address: "bbbb", displayName: "Борис", status: .connected)])
        _ = await waitUntil { self.peers.count == 1 }

        relay.emit(peers: [])

        let gone = await waitUntil { self.peers.isEmpty }
        #expect(gone)
    }

    // MARK: - Кому принадлежит адрес

    @Test func connectedNearby_winsOverRelay() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        relay.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        _ = await waitUntil { self.transport.channel(for: "aaaa") == .nearby }

        try? await transport.sendMessage(payload("привет"), to: "aaaa")

        #expect(nearby.sentMessages.count == 1)
        #expect(relay.sentMessages.isEmpty)
    }

    @Test func nearbyWithoutSession_losesToRelay() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .notConnected)])
        relay.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .connected)])
        _ = await waitUntil { self.transport.channel(for: "aaaa") == .relay }

        try? await transport.sendMessage(payload("привет"), to: "aaaa")

        #expect(nearby.sentMessages.isEmpty)
        #expect(relay.sentMessages.count == 1)
    }

    @Test func onlyNearbyWithoutSession_stillGoesNearby() async {
        nearby.emit(peers: [Peer(address: "aaaa", displayName: "Алиса", status: .notConnected)])
        _ = await waitUntil { self.transport.channel(for: "aaaa") == .nearby }

        try? await transport.sendMessage(payload("привет"), to: "aaaa")

        #expect(nearby.sentMessages.count == 1)
    }

    @Test func unknownAddress_isUnreachable() async {
        do {
            try await transport.sendMessage(payload("привет"), to: "zzzz")
            Issue.record("отправка в никуда должна падать")
        } catch let error as CompositeTransportError {
            #expect(error == .unreachable("zzzz"))
        } catch {
            Issue.record("не та ошибка: \(error)")
        }
    }

    // MARK: - Входящее

    @Test func incomingFromEitherChannel_reachesTheSameStream() async {
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
        #expect(both)
        #expect(Set(received) == ["рядом", "издалека"])
    }

    // MARK: - Состояние связи

    @Test func relayState_isPassedThrough() async {
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
        #expect(got)
    }

    @Test func someoneConnectedNearby_meansOnline_evenWithoutNetwork() async {
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
        #expect(online)
    }

    // MARK: - Обнаружение

    @Test func discovery_startsBothChannels() {
        transport.startDeviceDiscovery()

        #expect(nearby.isDiscovering)
        #expect(relay.isDiscovering)
    }
}
