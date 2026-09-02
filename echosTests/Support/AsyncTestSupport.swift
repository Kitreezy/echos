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
