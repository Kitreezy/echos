//
//  KeychainSecretStoreIntegrationTests.swift
//  echosIntegrationTests
//
//  Настоящий Keychain симулятора под отдельным service. Здесь проверяется
//  не политика, а то, как Security отвечает на неудобные запросы: повторная
//  запись, удаление отсутствующего, доступность записи.
//

import Security
import XCTest
@testable import echos

final class KeychainSecretStoreIntegrationTests: XCTestCase {

    private var store: KeychainSecretStore!
    private let account = "test-key"

    override func setUp() {
        super.setUp()
        store = KeychainSecretStore(service: "com.echos.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        try? store.delete(account: account)
        super.tearDown()
    }

    func test_missing_readsAsNil() throws {
        XCTAssertNil(try store.read(account: account))
    }

    func test_roundTrip() throws {
        try store.write(Data([1, 2, 3]), account: account)

        XCTAssertEqual(try store.read(account: account), Data([1, 2, 3]))
    }

    func test_secondWrite_overwritesInsteadOfFailing() throws {
        // Голый SecItemAdd на этом месте вернул бы errSecDuplicateItem.
        try store.write(Data([1]), account: account)
        try store.write(Data([2]), account: account)

        XCTAssertEqual(try store.read(account: account), Data([2]))
    }

    func test_deleteMissing_isNotAnError() {
        XCTAssertNoThrow(try store.delete(account: account))
    }

    func test_deleted_readsAsNil() throws {
        try store.write(Data([1]), account: account)
        try store.delete(account: account)

        XCTAssertNil(try store.read(account: account))
    }

    func test_item_isAfterFirstUnlockThisDeviceOnly() throws {
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
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)

        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func test_accountsAreIndependent() throws {
        try store.write(Data([1]), account: account)
        try store.write(Data([2]), account: "other")
        defer { try? store.delete(account: "other") }

        XCTAssertEqual(try store.read(account: account), Data([1]))
        XCTAssertEqual(try store.read(account: "other"), Data([2]))
    }
}
