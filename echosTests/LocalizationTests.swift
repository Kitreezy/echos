//
//  LocalizationTests.swift
//  echosTests
//
//  String Catalog: формы множественного числа и согласие переводов с
//  исходником. Тест-планы запускают приложение на русском — так подписи
//  в тестах не зависят от языка симулятора.
//

import Foundation
import Testing
@testable import echos

struct LocalizationTests {

    // MARK: - Множественное число

    @Test(arguments: [
        (1, "1 непрочитанное"), (2, "2 непрочитанных"), (5, "5 непрочитанных"),
        (11, "11 непрочитанных"), (21, "21 непрочитанное"), (22, "22 непрочитанных")
    ])
    @MainActor
    func unread_inRussian(_ count: Int, _ expected: String) {
        #expect(ConversationCell.unread(count) == expected)
    }

    @Test(arguments: [(1, "1 unread"), (7, "7 unread")])
    func unread_inEnglish(_ count: Int, _ expected: String) {
        var resource = LocalizedStringResource("\(count) непрочитанных")
        resource.locale = Locale(identifier: "en")
        #expect(String(localized: resource) == expected)
    }

    // MARK: - Каталог

    /// Каталог — исходник, а не ресурс сборки: в приложение он попадает уже
    /// скомпилированным.
    private static var catalog: [String: Any] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "echos/Localizable.xcstrings")
        let data = (try? Data(contentsOf: url)) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static var entries: [(key: String, value: [String: Any])] {
        let strings = catalog["strings"] as? [String: [String: Any]] ?? [:]
        return strings.map { ($0.key, $0.value) }.sorted { $0.key < $1.key }
    }

    @Test func catalog_isReadable() {
        #expect(Self.catalog["sourceLanguage"] as? String == "ru")
        #expect(Self.entries.count > 100)
    }

    /// Переведено всё, что стоит переводить.
    @Test func everyString_hasEnglish() {
        let untranslated = Self.entries
            .filter { $0.value["shouldTranslate"] as? Bool != false }
            .filter { Self.english(of: $0.value).isEmpty }
            .map(\.key)
        #expect(untranslated.isEmpty, "Без перевода: \(untranslated)")
    }

    /// `%@` и `%lld` в переводе — те же и в том же количестве, что в
    /// исходнике. Иначе подставится не то значение, а то и упадёт.
    @Test func placeholders_matchSource() {
        let mismatched = Self.entries.flatMap { entry in
            Self.english(of: entry.value)
                .filter { Self.placeholders($0) != Self.placeholders(entry.key) }
                .map { "\(entry.key) → \($0)" }
        }
        #expect(mismatched.isEmpty, "Подстановки не совпадают: \(mismatched)")
    }

    /// Все английские значения строки: одно или по формам числа.
    private static func english(of entry: [String: Any]) -> [String] {
        guard let localizations = entry["localizations"] as? [String: Any],
              let english = localizations["en"] as? [String: Any] else {
            return []
        }
        if let unit = english["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [value]
        }
        let plural = (english["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return plural.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
    }

    private static func placeholders(_ text: String) -> [String] {
        let pattern = /%(?:\d+\$)?(?:lld|ld|d|@|f)/
        return text.matches(of: pattern).map { String($0.output) }.sorted()
    }
}
