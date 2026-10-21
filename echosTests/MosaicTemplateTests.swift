//
//  MosaicTemplateTests.swift
//  echosTests
//
//  Сохранённые мозаики: свежая первой, повторов нет, удаление работает.
//

import Foundation
import Testing
@testable import echos

/// Шаблоны — общий список в UserDefaults: тесты набора идут по очереди,
/// иначе один очищает список посреди другого.
@Suite(.serialized, .tags(.persistence))
final class MosaicTemplateTests {

    init() {
        UserSettings.mosaicTemplates = []
    }

    deinit {
        UserSettings.mosaicTemplates = []
    }

    private func mosaic(_ cell: String) -> Mosaic {
        Mosaic(columns: 2, rows: 2).setting(column: 0, row: 0, to: cell)
    }

    @Test func saved_isFirst() {
        UserSettings.saveMosaicTemplate(mosaic("🟨"))
        UserSettings.saveMosaicTemplate(mosaic("🟦"))

        #expect(UserSettings.mosaicTemplates.first == mosaic("🟦"))
        #expect(UserSettings.mosaicTemplates.count == 2)
    }

    @Test func sameMosaicTwice_movesItUpInsteadOfDuplicating() {
        UserSettings.saveMosaicTemplate(mosaic("🟨"))
        UserSettings.saveMosaicTemplate(mosaic("🟦"))
        UserSettings.saveMosaicTemplate(mosaic("🟨"))

        #expect(UserSettings.mosaicTemplates == [mosaic("🟨"), mosaic("🟦")])
    }

    @Test func emptyMosaic_isNotSaved() {
        UserSettings.saveMosaicTemplate(Mosaic(columns: 4, rows: 4))
        #expect(UserSettings.mosaicTemplates.isEmpty, "Пустая сетка — не рисунок")
    }

    @Test func delete_removesOnlyThatOne() {
        UserSettings.saveMosaicTemplate(mosaic("🟨"))
        UserSettings.saveMosaicTemplate(mosaic("🟦"))

        UserSettings.deleteMosaicTemplate(mosaic("🟨"))

        #expect(UserSettings.mosaicTemplates == [mosaic("🟦")])
    }

    @Test func templates_surviveEncoding() {
        let rich = Mosaic(columns: 3, rows: 2, cells: ["🟥", "", "🟦", "🐱", "🍕", ""])!
        UserSettings.saveMosaicTemplate(rich)

        #expect(UserSettings.mosaicTemplates.first == rich)
    }

    @Test func tooMany_areTrimmed() {
        for index in 0..<40 {
            UserSettings.saveMosaicTemplate(Mosaic(columns: 8, rows: 8)
                .setting(column: index % 8, row: index / 8, to: "🟨"))
        }
        #expect(UserSettings.mosaicTemplates.count <= 24)
    }
}
