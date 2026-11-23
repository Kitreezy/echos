//
//  Tags.swift
//  echosTests
//
//  Теги — чтобы запускать часть тестов по смыслу, а не по файлам.
//
//  Быстрый цикл при разработке пропускает `network`: эти тесты поднимают
//  настоящий сокет и тестовый релей и идут дольше всех. Тест-план Fast
//  делает именно это; полный план гоняет всё.
//

import Testing

extension Tag {
    /// Настоящий WebSocket и тестовый релей. Самые медленные.
    @Tag static var network: Self
    /// Шифрование и ключи: то, что нельзя сломать молча.
    @Tag static var crypto: Self
    /// Общее хранилище — UserDefaults, Core Data, Keychain.
    @Tag static var persistence: Self
    /// Разбор на тысячах сгенерированных входов (Fuzz/).
    @Tag static var fuzz: Self
}
