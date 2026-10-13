//
//  MosaicDraftTests.swift
//  echosTests
//
//  Набросок мозаики переживает уход из чата и перезапуск — по переписке.
//

import XCTest
@testable import echos

final class MosaicDraftTests: XCTestCase {

    override func tearDown() {
        UserSettings.setMosaicDraft(nil, for: "bob")
        UserSettings.setMosaicDraft(nil, for: "carol")
        super.tearDown()
    }

    func test_draft_isKeptPerConversation() {
        let forBob = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", ""])!
        let forCarol = Mosaic(columns: 3, rows: 3).setting(column: 1, row: 1, to: "🟦")

        UserSettings.setMosaicDraft(forBob, for: "bob")
        UserSettings.setMosaicDraft(forCarol, for: "carol")

        XCTAssertEqual(UserSettings.mosaicDraft(for: "bob"), forBob)
        XCTAssertEqual(UserSettings.mosaicDraft(for: "carol"), forCarol)
    }

    func test_emptyDraft_isNotKept() {
        UserSettings.setMosaicDraft(Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", ""]), for: "bob")
        UserSettings.setMosaicDraft(Mosaic(columns: 4, rows: 4), for: "bob")

        XCTAssertNil(UserSettings.mosaicDraft(for: "bob"), "Пустая сетка — не набросок")
    }

    func test_nilClearsTheDraft() {
        UserSettings.setMosaicDraft(Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", ""]), for: "bob")
        UserSettings.setMosaicDraft(nil, for: "bob")

        XCTAssertNil(UserSettings.mosaicDraft(for: "bob"))
    }

    func test_unknownConversation_hasNoDraft() {
        XCTAssertNil(UserSettings.mosaicDraft(for: "nobody"))
    }
}
