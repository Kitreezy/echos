//
//  AsyncBroadcastTests.swift
//  echosTests
//
//  Unit: мультикаст поверх AsyncStream.
//
//  Главное, что здесь проверяется, — регрессия исходной проблемы: один
//  `AsyncStream` на всех делит события между потребителями, а броадкаст
//  доставляет каждому все.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct AsyncBroadcastTests {

    // MARK: - Мультикаст

    @Test func twoSubscribers_eachReceivesEveryElement() async {
        let broadcast = AsyncBroadcast<Int>()

        let first = broadcast.stream
        let second = broadcast.stream

        async let firstValues = collect(first, count: 3)
        async let secondValues = collect(second, count: 3)

        // Даём подписчикам встать в цикл до первой отправки.
        _ = await waitUntil { broadcast.subscriberCount == 2 }

        broadcast.yield(1)
        broadcast.yield(2)
        broadcast.yield(3)

        let (received1, received2) = await (firstValues, secondValues)

        #expect(received1 == [1, 2, 3])
        #expect(received2 == [1, 2, 3])
    }

    // MARK: - Реплей последнего значения

    @Test func replaysLatest_lateSubscriberSeesLastElement() async {
        let broadcast = AsyncBroadcast<Int>(replaysLatest: true)
        broadcast.yield(42)

        let received = await collect(broadcast.stream, count: 1)

        #expect(received == [42])
    }

    @Test func withoutReplay_lateSubscriberWaitsForNextElement() async {
        let broadcast = AsyncBroadcast<Int>()
        broadcast.yield(42)

        let stream = broadcast.stream
        async let values = collect(stream, count: 1)

        _ = await waitUntil { broadcast.subscriberCount == 1 }
        broadcast.yield(7)

        let received = await values

        #expect(received == [7], "Подписчик без реплея не должен видеть события до подписки")
    }

    // MARK: - Снятие подписки

    @Test func subscriberCount_dropsWhenConsumerStops() async {
        let broadcast = AsyncBroadcast<Int>()

        let consumer = Task {
            for await _ in broadcast.stream {
                break
            }
        }

        _ = await waitUntil { broadcast.subscriberCount == 1 }
        broadcast.yield(1)
        await consumer.value

        let released = await waitUntil { broadcast.subscriberCount == 0 }
        #expect(released, "onTermination должен снимать подписку сам")
    }

    @Test func finish_terminatesAllSubscribers() async {
        let broadcast = AsyncBroadcast<Int>()

        let consumer = Task {
            var count = 0
            for await _ in broadcast.stream {
                count += 1
            }
            return count
        }

        _ = await waitUntil { broadcast.subscriberCount == 1 }
        broadcast.yield(1)
        broadcast.finish()

        let count = await consumer.value

        #expect(count == 1)
        #expect(broadcast.subscriberCount == 0)
    }

    @Test func yieldAfterFinish_isIgnored() async {
        let broadcast = AsyncBroadcast<Int>()
        broadcast.finish()
        broadcast.yield(1)

        let received = await collect(broadcast.stream, count: 1, timeout: .milliseconds(200))

        #expect(received.isEmpty)
    }
}
