//
//  KeychainSecretStoreIntegrationTests.swift
//  echosIntegrationTests
//
//  Настоящий Keychain симулятора под отдельным service. Здесь проверяется
//  не политика, а то, как Security отвечает на неудобные запросы: повторная
//  запись, удаление отсутствующего, доступность записи.
//

import Security
import Foundation
import Testing
@testable import echos

@Suite(.tags(.persistence))
final class KeychainSecretStoreIntegrationTests {

    /// Свой сервис на каждый тест: Keychain общий для всех тестов процесса,
    /// а в Swift Testing они идут параллельно.
    private let store = KeychainSecretStore(service: "com.echos.tests.\(UUID().uuidString)")
    private let account = "test-key"

    deinit {
        try? store.delete(account: account)
    }

    @Test func missing_readsAsNil() throws {
        #expect(try store.read(account: account) == nil)
    }

    @Test func roundTrip() throws {
        try store.write(Data([1, 2, 3]), account: account)

        #expect(try store.read(account: account) == Data([1, 2, 3]))
    }

    @Test func secondWrite_overwritesInsteadOfFailing() throws {
        // Голый SecItemAdd на этом месте вернул бы errSecDuplicateItem.
        try store.write(Data([1]), account: account)
        try store.write(Data([2]), account: account)

        #expect(try store.read(account: account) == Data([2]))
    }

    @Test func deleteMissing_isNotAnError() {
        #expect(throws: Never.self) { try store.delete(account: account) }
    }

    @Test func deleted_readsAsNil() throws {
        try store.write(Data([1]), account: account)
        try store.delete(account: account)

        #expect(try store.read(account: account) == nil)
    }

    @Test func item_isAfterFirstUnlockThisDeviceOnly() throws {
        // Доступность — единственное, что отличает «ключ уезжает в чужой
        // бэкап» от «не уезжает», и её надо прочитать обратно, а не верить коду.
        try store.write(Data([1]), account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)

        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func accountsAreIndependent() throws {
        try store.write(Data([1]), account: account)
        try store.write(Data([2]), account: "other")
        defer { try? store.delete(account: "other") }

        #expect(try store.read(account: account) == Data([1]))
        #expect(try store.read(account: "other") == Data([2]))
    }
}
