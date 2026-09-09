//
//  StreamOperatorsTests.swift
//  echosTests
//
//  Unit: поведение операторов swift-async-algorithms на изолированных потоках.
//
//  Здесь нет ViewModel — только сами операторы, чтобы было видно, что именно
//  каждый из них делает с потоком.
//

import AsyncAlgorithms
import XCTest
@testable import echos

@MainActor
final class StreamOperatorsTests: XCTestCase {

    // MARK: - removeDuplicates

    /// `lastSeen` меняется на каждый emit, поэтому обычное `==` бесполезно —
    /// схлопывание работает только по содержательному сравнению.
    func test_removeDuplicates_collapsesPeerListsThatDifferOnlyByLastSeen() async {
        let (stream, continuation) = AsyncStream.makeStream(of: [Peer].self)
        let id = UUID()

        func snapshot(status: PeerStatus) -> [Peer] {
            [Peer(id: id, displayName: "Alice", status: status, lastSeen: Date(), rssi: -50)]
        }

        async let collected = collect(
            stream.removeDuplicates { $0.hasSameState(as: $1) },
            count: 2
        )

        continuation.yield(snapshot(status: .notConnected))
        continuation.yield(snapshot(status: .notConnected))  // отличается только lastSeen
        continuation.yield(snapshot(status: .connected))     // содержательное изменение
        continuation.finish()

        let received = await collected

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first?.first?.status, .notConnected)
        XCTAssertEqual(received.last?.first?.status, .connected)
    }

    func test_removeDuplicates_byEquatable_doesNotCollapsePeersWithFreshLastSeen() async {
        let (stream, continuation) = AsyncStream.makeStream(of: [Peer].self)
        let id = UUID()

        async let collected = collect(stream.removeDuplicates(), count: 2)

        continuation.yield([Peer(id: id, displayName: "Alice", lastSeen: Date())])
        try? await Task.sleep(for: .milliseconds(10))
        continuation.yield([Peer(id: id, displayName: "Alice", lastSeen: Date())])
        continuation.finish()

        let received = await collected

        XCTAssertEqual(received.count, 2, "Именно поэтому в проде используется removeDuplicates(by:)")
    }

    // MARK: - merge

    func test_merge_deliversElementsFromAllSources() async {
        let (peers, peersContinuation) = AsyncStream.makeStream(of: [Peer].self)
        let (messages, messagesContinuation) = AsyncStream.makeStream(of: Addressed<MessagePayload>.self)
        let (typing, typingContinuation) = AsyncStream.makeStream(of: Addressed<TypingEvent>.self)

        let merged = merge(
            peers.map(TransportEvent.peers),
            messages.map(TransportEvent.message),
            typing.map(TransportEvent.typing)
        )

        async let collected = collect(merged, count: 3)

        peersContinuation.yield([Peer(displayName: "Alice")])
        messagesContinuation.yield(Addressed(
            sender: "alice-address",
            value: MessagePayload(from: Message(text: "hi", isFromMe: false), senderName: "Alice")
        ))
        typingContinuation.yield(Addressed(sender: "alice-address",
                                           value: TypingEvent(type: .start, peerName: "Alice")))

        let received = await collected

        XCTAssertEqual(received.count, 3)
        XCTAssertTrue(received.contains { if case .peers = $0 { return true } else { return false } })
        XCTAssertTrue(received.contains { if case .message = $0 { return true } else { return false } })
        XCTAssertTrue(received.contains { if case .typing = $0 { return true } else { return false } })
    }

    // MARK: - debounce

    func test_debounce_emitsOnlyAfterPause() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)

        async let collected = collect(stream.debounce(for: .milliseconds(100)), count: 2)

        // Серия без пауз — наружу должно выйти только последнее значение.
        for value in 1...5 {
            continuation.yield(value)
            try? await Task.sleep(for: .milliseconds(10))
        }

        try? await Task.sleep(for: .milliseconds(200))

        // Отдельное значение после паузы — второе событие.
        continuation.yield(99)
        continuation.finish()

        let received = await collected

        XCTAssertEqual(received, [5, 99])
    }

    // MARK: - share

    /// `AsyncStream` — однопотребительский: два `for await` делят события.
    /// `share()` превращает его в широковещательный.
    func test_share_bothConsumersSeeEveryElement() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        let shared = stream.share()

        async let first = collect(shared, count: 3)
        async let second = collect(shared, count: 3)

        try? await Task.sleep(for: .milliseconds(50))

        continuation.yield(1)
        continuation.yield(2)
        continuation.yield(3)

        let (received1, received2) = await (first, second)

        XCTAssertEqual(received1, [1, 2, 3])
        XCTAssertEqual(received2, [1, 2, 3])
    }

    // MARK: - chunked

    func test_chunked_groupsElementsArrivingWithinInterval() async {
        let channel = AsyncChannel<Int>()

        let batches = channel.chunked(
            by: AsyncTimerSequence.repeating(every: .milliseconds(100))
        )

        async let collected = collect(batches, count: 2)

        Task {
            for value in 1...3 {
                await channel.send(value)
            }
            try? await Task.sleep(for: .milliseconds(200))
            await channel.send(99)
        }

        let received = await collected

        XCTAssertEqual(received.first, [1, 2, 3], "Всё, что пришло за окно, должно уехать одной пачкой")
        XCTAssertEqual(received.last, [99])
    }
}
