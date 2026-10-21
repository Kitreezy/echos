//
//  Tags.swift
//  echosIntegrationTests
//
//  Тот же тег, что в echosTests/Support/Tags.swift: Swift Testing сравнивает
//  теги по имени, а не по модулю, и план Fast пропускает их одинаково.
//

import Testing

extension Tag {
    /// Общее хранилище — UserDefaults, Core Data, Keychain.
    @Tag static var persistence: Self
}
