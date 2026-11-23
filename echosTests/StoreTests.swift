//
//  StoreTests.swift
//  echosTests
//
//  Unit: ядро однонаправленного потока — редьюсер применяется синхронно,
//  результаты эффектов возвращаются действиями, смерть стора гасит эффекты.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct StoreTests {

    private struct State: Equatable {
        var count = 0
    }

    private enum Action: Equatable {
        case increment
        case squareAsync
        case squared(Int)
    }

    private func makeStore() -> Store<State, Action> {
        Store(initialState: State()) { state, action in
            switch action {
            case .increment:
                state.count += 1
                return []
            case .squareAsync:
                // Эффект захватывает значение, а не inout: редьюсер
                // остаётся чистой функцией.
                let value = state.count
                return [Effect { send in
                    await send(.squared(value * value))
                }]
            case let .squared(value):
                state.count = value
                return []
            }
        }
    }

    @Test func send_appliesReducerSynchronously() {
        let store = makeStore()

        store.send(.increment)

        #expect(store.state.count == 1)
    }

    /// Эффект не меняет состояние напрямую — только через новое действие.
    @Test func effectResult_comesBackAsAction() async {
        let store = makeStore()
        store.send(.increment)
        store.send(.increment)

        store.send(.squareAsync)

        let squared = await waitUntil { store.state.count == 4 }
        #expect(squared, "Результат эффекта не вернулся действием")
    }

    /// Умер стор — замолчали эффекты: закрытый экран не шлёт действий.
    @Test func deinit_cancelsRunningEffects() async {
        let counter = EffectCounter()
        var store: Store<State, Action>? = Store(initialState: State()) { _, _ in
            [Effect { _ in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(10))
                    await counter.bump()
                }
            }]
        }
        store?.send(.increment)
        try? await Task.sleep(for: .milliseconds(100))
        let beforeDeath = await counter.value

        store = nil
        try? await Task.sleep(for: .milliseconds(300))
        let afterDeath = await counter.value
        try? await Task.sleep(for: .milliseconds(200))
        let settled = await counter.value

        #expect(afterDeath > beforeDeath, "Эффект не работал, пока стор был жив")
        #expect(settled == afterDeath, "Эффект продолжил работу после смерти стора")
    }
}

/// Счётчик, до которого эффекту есть дело из любого актора.
private actor EffectCounter {
    private(set) var value = 0
    func bump() {
        value += 1
    }
}
