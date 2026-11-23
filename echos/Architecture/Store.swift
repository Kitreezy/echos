//
//  Store.swift
//  echos
//
//  Однонаправленный поток данных своими руками: Store + Reducer + Effect
//  на async/await. Без Combine, без реактивных подписок.
//
//  Договор простой:
//  - Состояние меняется ТОЛЬКО в редьюсере — чистой функции
//    `(inout State, Action) -> [Effect]`. Никаких подпорок извне.
//  - Экран шлёт действия (`send`) и читает состояние. Обратной дороги нет.
//  - Эффект — асинхронная работа (сеть, модель, ожидание), которая по
//    итогам шлёт новые действия. Поток прогресса — тоже действия.
//
//  Отличие от наблюдаемого MVVM, которым живёт остальное приложение:
//  там модель сама мутирует когда угодно, и экран ловит изменения
//  подпиской. Здесь переходы видны в одном месте и проверяются как
//  таблица: состояние + действие → состояние + эффекты.
//

import Foundation
import Observation

/// Асинхронная работа, порождённая редьюсером. Получает `send` и шлёт
/// действия по итогам — один или много, как потянет поток. Замыкание
/// изолировано на главный актор: эффект живёт там же, где состояние,
/// а сеть и модель всё равно уходят в suspension.
struct Effect<Action: Sendable> {

    let body: @MainActor (@escaping @MainActor (Action) -> Void) async -> Void

    /// Тихая работа без итога: записать, закрыть, освободить.
    static func fireAndForget(
        _ work: @escaping @MainActor () async -> Void
    ) -> Effect {
        Effect { _ in await work() }
    }

    /// Одно действие по итогу.
    static func send(_ action: Action) -> Effect {
        Effect { send in await send(action) }
    }

    static var none: Effect {
        Effect { _ in }
    }
}

/// Хранилище состояния и единственный исполнитель действий.
@MainActor
@Observable
final class Store<State, Action: Sendable> {

    /// Читай напрямую — наблюдение через @Observable, подписок нет.
    private(set) var state: State

    private let reduce: (inout State, Action) -> [Effect<Action>]

    /// Живые эффекты. Вместе с хранилищем умирают — закрытый экран
    /// останавливает модель, как раньше останавливала отмена задачи.
    private var effectTasks: [Task<Void, Never>] = []

    init(initialState: State,
         reducer: @escaping (inout State, Action) -> [Effect<Action>]) {
        self.state = initialState
        self.reduce = reducer
    }

    isolated deinit {
        effectTasks.forEach { $0.cancel() }
    }

    /// Единственный вход. Редьюсер меняет состояние, эффекты уходят в
    /// фон; результаты возвращаются новыми действиями через тот же вход.
    func send(_ action: Action) {
        let effects = reduce(&state, action)
        for effect in effects {
            effectTasks.append(Task { [weak self] in
                await effect.body { action in
                    self?.send(action)
                }
            })
        }
    }
}
