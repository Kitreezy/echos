//
//  MosaicTemplateTests.swift
//  echosTests
//
//  Сохранённые мозаики: свежая первой, повторов нет, удаление работает.
//

import XCTest
@testable import echos

final class MosaicTemplateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserSettings.mosaicTemplates = []
    }

    override func tearDown() {
        UserSettings.mosaicTemplates = []
        super.tearDown()
    }

    private func mosaic(_ cell: String) -> Mosaic {
        Mosaic(columns: 2, rows: 2).setting(column: 0, row: 0, to: cell)
    }

    func test_saved_isFirst() {
        UserSettings.saveMosaicTemplate(mosaic("🟨"))
        UserSettings.saveMosaicTemplate(mosaic("🟦"))

        XCTAssertEqual(UserSettings.mosaicTemplates.first, mosaic("🟦"))
        XCTAssertEqual(UserSettings.mosaicTemplates.count, 2)
    }

    func test_sameMosaicTwice_movesItUpInsteadOfDuplicating() {
        UserSettings.saveMosaicTemplate(mosaic("🟨"))
        UserSettings.saveMosaicTemplate(mosaic("🟦"))
        UserSettings.saveMosaicTemplate(mosaic("🟨"))

        XCTAssertEqual(UserSettings.mosaicTemplates, [mosaic("🟨"), mosaic("🟦")])
    }

    func test_emptyMosaic_isNotSaved() {
        UserSettings.saveMosaicTemplate(Mosaic(columns: 4, rows: 4))
        XCTAssertTrue(UserSettings.mosaicTemplates.isEmpty, "Пустая сетка — не рисунок")
    }

    func test_delete_removesOnlyThatOne() {
        UserSettings.saveMosaicTemplate(mosaic("🟨"))
        UserSettings.saveMosaicTemplate(mosaic("🟦"))

        UserSettings.deleteMosaicTemplate(mosaic("🟨"))

        XCTAssertEqual(UserSettings.mosaicTemplates, [mosaic("🟦")])
    }

    func test_templates_surviveEncoding() {
        let rich = Mosaic(columns: 3, rows: 2, cells: ["🟥", "", "🟦", "🐱", "🍕", ""])!
        UserSettings.saveMosaicTemplate(rich)

        XCTAssertEqual(UserSettings.mosaicTemplates.first, rich)
    }

    func test_tooMany_areTrimmed() {
        for index in 0..<40 {
            UserSettings.saveMosaicTemplate(Mosaic(columns: 8, rows: 8)
                .setting(column: index % 8, row: index / 8, to: "🟨"))
        }
        XCTAssertLessThanOrEqual(UserSettings.mosaicTemplates.count, 24)
    }
}
