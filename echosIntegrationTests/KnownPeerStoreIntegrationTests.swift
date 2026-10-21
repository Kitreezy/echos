//
//  KnownPeerStoreIntegrationTests.swift
//  echosIntegrationTests
//
//  Список знакомых на настоящем Core Data стеке.
//

import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.tags(.persistence))
struct KnownPeerStoreIntegrationTests {

    private let store = KnownPeerStore(container: CoreDataTestStack.makeInMemory().container)

    @Test func rememberedPeer_isLoadedBack() async throws {
        try await store.remember(address: "a1b2", name: "Bob")

        let known = try await store.loadKnownPeers()

        #expect(known.map(\.address) == ["a1b2"])
        #expect(known.map(\.name) == ["Bob"])
    }

    /// Тёзка — отдельная запись: адрес другой, значит человек другой.
    @Test func sameNameFromAnotherAddress_isASecondEntry() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        try await store.remember(address: "c3d4", name: "Bob")

        let known = try await store.loadKnownPeers()

        #expect(known.count == 2)
        #expect(Set(known.map(\.address)) == ["a1b2", "c3d4"])
    }

    /// Повторный разговор под новым именем — принятие нового имени,
    /// а не вторая запись.
    @Test func rememberingAgain_updatesTheNameInPlace() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        try await store.remember(address: "a1b2", name: "Роберт")

        let known = try await store.loadKnownPeers()

        #expect(known.count == 1)
        #expect(known.first?.name == "Роберт")
    }

    @Test func firstSeen_survivesRepeatedConversations() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        let first = try await store.loadKnownPeers().first?.firstSeen

        try await store.remember(address: "a1b2", name: "Bob")
        let again = try await store.loadKnownPeers().first?.firstSeen

        #expect(first == again, "Знакомство состоялось однажды")
    }

    @Test func forgetAll_leavesNobody() async throws {
        try await store.remember(address: "a1b2", name: "Bob")
        try await store.remember(address: "c3d4", name: "Carol")

        try await store.forgetAll()

        let known = try await store.loadKnownPeers()
        #expect(known.isEmpty)
    }

    /// Запомненное переживает пересоздание хранилища поверх той же базы —
    /// иначе после перезапуска все снова были бы незнакомцами.
    @Test func memory_outlivesTheStoreObject() async throws {
        let container = CoreDataTestStack.makeInMemory().container

        let first = KnownPeerStore(container: container)
        try await first.remember(address: "a1b2", name: "Bob")

        let second = KnownPeerStore(container: container)
        let known = try await second.loadKnownPeers()

        #expect(known.map(\.name) == ["Bob"])
    }
}
