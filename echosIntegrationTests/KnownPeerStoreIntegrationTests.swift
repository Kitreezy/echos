//
//  KnownPeerStoreIntegrationTests.swift
//  echosIntegrationTests
//
//  Список знакомых на настоящем Core Data стеке.
//

import XCTest
@testable import echos

@MainActor
final class KnownPeerStoreIntegrationTests: XCTestCase {

    private var store: KnownPeerStore!

    override func setUp() async throws {
        try await super.setUp()
        store = KnownPeerStore(container: CoreDataTestStack.makeInMemory().container)
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    func test_rememberedPeer_isLoadedBack() async throws {
        try await store.remember(address: "a1b2", name: "Bob")

        let known = try await store.loadKnownPeers()

        XCTAssertEqual(known.map(\.address), ["a1b2"])
        XCTAssertEqual(known.map(\.name), ["Bob"])
    }

    /// Тёзка — отдельная запись: адрес другой, значит человек другой.
    func test_sameNameFromAnotherAddress_isASecondEntry() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        try await store.remember(address: "c3d4", name: "Bob")

        let known = try await store.loadKnownPeers()

        XCTAssertEqual(known.count, 2)
        XCTAssertEqual(Set(known.map(\.address)), ["a1b2", "c3d4"])
    }

    /// Повторный разговор под новым именем — принятие нового имени,
    /// а не вторая запись.
    func test_rememberingAgain_updatesTheNameInPlace() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        try await store.remember(address: "a1b2", name: "Роберт")

        let known = try await store.loadKnownPeers()

        XCTAssertEqual(known.count, 1)
        XCTAssertEqual(known.first?.name, "Роберт")
    }

    func test_firstSeen_survivesRepeatedConversations() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        let first = try await store.loadKnownPeers().first?.firstSeen

        try await store.remember(address: "a1b2", name: "Bob")
        let again = try await store.loadKnownPeers().first?.firstSeen

        XCTAssertEqual(first, again, "Знакомство состоялось однажды")
    }

    func test_forgetAll_leavesNobody() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        try await store.remember(address: "c3d4", name: "Carol")

        try await store.forgetAll()

        let known = try await store.loadKnownPeers()
        XCTAssertTrue(known.isEmpty)
    }

    /// Запомненное переживает пересоздание хранилища поверх той же базы —
    /// иначе после перезапуска все снова были бы незнакомцами.
    func test_memory_outlivesTheStoreObject() async throws {
        let container = CoreDataTestStack.makeInMemory().container

        let first = KnownPeerStore(container: container)
        try await first.remember(address: "a1b2", name: "Bob")

        let second = KnownPeerStore(container: container)
        let known = try await second.loadKnownPeers()

        XCTAssertEqual(known.map(\.name), ["Bob"])
    }
}
