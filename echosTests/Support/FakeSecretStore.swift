//
//  FakeSecretStore.swift
//  echosTests
//
//  Keychain, которому можно приказать сломаться.
//

import Foundation
@testable import echos

final class FakeSecretStore: SecretStore, @unchecked Sendable {

    private let lock = NSLock()
    private var items: [String: Data] = [:]

    /// Что бросать на чтении, пока не снимут. `locked` — устройство ещё
    /// не разблокировали, запись на месте, но не достать.
    var readFailure: SecretStoreError?

    /// Что бросать на записи.
    var writeFailure: SecretStoreError?

    private(set) var reads = 0
    private(set) var writes = 0

    init(_ items: [String: Data] = [:]) {
        self.items = items
    }

    subscript(account: String) -> Data? {
        lock.withLock { items[account] }
    }

    func read(account: String) throws -> Data? {
        try lock.withLock {
            reads += 1
            if let readFailure {
                throw readFailure
            }
            return items[account]
        }
    }

    func write(_ data: Data, account: String) throws {
        try lock.withLock {
            writes += 1
            if let writeFailure {
                throw writeFailure
            }
            items[account] = data
        }
    }

    func delete(account: String) throws {
        lock.withLock { items[account] = nil }
    }
}
