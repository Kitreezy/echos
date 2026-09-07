//
//  AsyncTestSupport.swift
//  echosTests
//
//  Хелперы для тестов над асинхронными потоками.
//

import Foundation
import XCTest

/// Ждёт выполнения условия, опрашивая его до таймаута.
///
/// Операторы вроде `debounce` и `throttle` дают результат не синхронно, а
/// «когда-то в пределах интервала», поэтому проверять их сразу после отправки
/// события нельзя.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)

    while ContinuousClock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: pollInterval)
    }

    return condition()
}

/// Ждёт первый элемент потока, удовлетворяющий условию.
///
/// Нужен для потоков состояния: они реплеят последнее значение новому
/// подписчику, поэтому «первый пришедший элемент» и «то, что мы ждём» —
/// разные вещи. Брать `collect(count: 1)` в таких случаях значит поймать
/// промежуточное состояние.
func firstElement<S: AsyncSequence>(
    of sequence: S,
    timeout: Duration = .seconds(2),
    where predicate: @escaping @Sendable (S.Element) -> Bool
) async -> S.Element? where S: Sendable, S.Element: Sendable {
    let finder = Task { () -> S.Element? in
        for try await element in sequence where predicate(element) {
            return element
        }
        return nil
    }

    let timer = Task {
        try? await Task.sleep(for: timeout)
        finder.cancel()
    }

    defer { timer.cancel() }

    return (try? await finder.value) ?? nil
}

/// Собирает не более `count` элементов потока, но не дольше таймаута.
func collect<S: AsyncSequence>(
    _ sequence: S,
    count: Int,
    timeout: Duration = .seconds(2)
) async -> [S.Element] where S: Sendable, S.Element: Sendable {
    let collector = Task {
        var collected: [S.Element] = []
        for try await element in sequence {
            collected.append(element)
            if collected.count >= count {
                break
            }
        }
        return collected
    }

    let timer = Task {
        try? await Task.sleep(for: timeout)
        collector.cancel()
    }

    defer { timer.cancel() }

    return (try? await collector.value) ?? []
}
