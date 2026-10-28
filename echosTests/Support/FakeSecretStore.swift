//
//  FakeSecretStore.swift
//  echosTests
//
//  Keychain, которому можно приказать сломаться.
//

import Foundation
import Synchronization
@testable import echos

final class FakeSecretStore: SecretStore {

    /// Всё изменяемое — в одном `Mutex`. Пока был `NSLock` и
    /// `@unchecked Sendable`, `readFailure` и `writeFailure` писались мимо
    /// замка, и компилятор об этом молчал. Теперь до состояния иначе как
    /// под замком не добраться.
    private struct State {
        var items: [String: Data]
        var readFailure: SecretStoreError?
        var writeFailure: SecretStoreError?
        var reads = 0
        var writes = 0
    }

    private let state: Mutex<State>

    /// Что бросать на чтении, пока не снимут. `locked` — устройство ещё
    /// не разблокировали, запись на месте, но не достать.
    var readFailure: SecretStoreError? {
        get { state.withLock { $0.readFailure } }
        set { state.withLock { $0.readFailure = newValue } }
    }

    /// Что бросать на записи.
    var writeFailure: SecretStoreError? {
        get { state.withLock { $0.writeFailure } }
        set { state.withLock { $0.writeFailure = newValue } }
    }

    var reads: Int { state.withLock { $0.reads } }
    var writes: Int { state.withLock { $0.writes } }

    init(_ items: [String: Data] = [:]) {
        state = Mutex(State(items: items))
    }

    subscript(account: String) -> Data? {
        state.withLock { $0.items[account] }
    }

    func read(account: String) throws -> Data? {
        try state.withLock { state in
            state.reads += 1
            if let readFailure = state.readFailure {
                throw readFailure
            }
            return state.items[account]
        }
    }

    func write(_ data: Data, account: String) throws {
        try state.withLock { state in
            state.writes += 1
            if let writeFailure = state.writeFailure {
                throw writeFailure
            }
            state.items[account] = data
        }
    }

    func delete(account: String) throws {
        state.withLock { $0.items[account] = nil }
    }
}
