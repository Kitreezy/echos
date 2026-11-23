//
//  CompositionRootTests.swift
//  echosTests
//
//  Unit: корень композиции собирает граф явно — решение об окружении
//  принимает он, экземпляры общие на весь граф, тест подменяет любое
//  звено без глобальных синглтонов.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct CompositionRootTests {

    /// Решение «UI-тесты → демо-транспорт» живёт в корне, а не в фабрике
    /// в глубине ViewModel: собираем граф для окружения явно.
    @Test func uiTestsEnvironment_buildsDemoTransport() {
        let root = CompositionRoot(environment: .uiTests)
        #expect(root.viewModel.makeTransport() is DemoTransport)
    }

    @Test func productionEnvironment_buildsRealTransport() {
        let root = CompositionRoot(environment: .production)
        #expect(!(root.viewModel.makeTransport() is DemoTransport),
                "Продовый граф не должен получать демо-транспорт")
    }

    /// Граф — это одни и те же экземпляры, а не серия независимых
    /// конструкторов: координатор работает с той же моделью и тем же кэшем.
    @Test func graphSharesInstances() {
        let root = CompositionRoot(environment: .uiTests)
        #expect(root.coordinator.viewModel === root.viewModel)
        #expect(root.coordinator.mosaicCache === root.mosaicCache)
    }
}
