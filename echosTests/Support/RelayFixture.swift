//
//  RelayFixture.swift
//  echosTests
//
//  Тестовый релей на время каждого теста — трейтом `.relayServer`.
//
//  В XCTest релей поднимал `setUp`, а гасил `tearDown`: асинхронно, через
//  await. У Swift Testing подготовка — это `init`, а уборке переезжать
//  некуда: `deinit` не бывает асинхронным. Поэтому и подготовка, и уборка
//  живут в трейте: он оборачивает тест, поднимает релей до него и гасит
//  после — даже если тест упал. Тест берёт релей из `RelayFixture.server`.
//

import Testing
@testable import echos

struct RelayFixture: TestTrait, SuiteTrait, TestScoping {

    /// Релей текущего теста. Свой у каждого: тесты идут параллельно, и
    /// общий релей смешал бы их клиентов.
    @TaskLocal static var current: RelayServer?

    @MainActor
    static var server: RelayServer {
        guard let current else {
            fatalError("Тест без .relayServer обращается к релею")
        }
        return current
    }

    /// На наборе — для каждого теста внутри, а не один на весь набор.
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        // Для самого набора релей не нужен — только для тестов в нём.
        guard testCase != nil else {
            try await function()
            return
        }
        let server = await RelayServer()
        try await server.start()
        do {
            try await Self.$current.withValue(server) {
                try await function()
            }
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }
}

extension Trait where Self == RelayFixture {
    /// Свой тестовый релей на каждый тест.
    static var relayServer: Self { RelayFixture() }
}
