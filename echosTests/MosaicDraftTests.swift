//
//  MosaicDraftTests.swift
//  echosTests
//
//  Набросок мозаики переживает уход из чата и перезапуск — по переписке.
//

import Foundation
import Testing
@testable import echos

/// Черновики лежат в общем UserDefaults, и тесты набора пишут в одни и те
/// же ключи — поэтому по очереди. В XCTest это было даром: методы класса и
/// так шли подряд.
@Suite(.serialized, .tags(.persistence))
final class MosaicDraftTests {

    deinit {
        UserSettings.setMosaicDraft(nil, for: "bob")
        UserSettings.setMosaicDraft(nil, for: "carol")
    }

    @Test func draft_isKeptPerConversation() {
        let forBob = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", ""])!
        let forCarol = Mosaic(columns: 3, rows: 3).setting(column: 1, row: 1, to: "🟦")

        UserSettings.setMosaicDraft(forBob, for: "bob")
        UserSettings.setMosaicDraft(forCarol, for: "carol")

        #expect(UserSettings.mosaicDraft(for: "bob") == forBob)
        #expect(UserSettings.mosaicDraft(for: "carol") == forCarol)
    }

    @Test func emptyDraft_isNotKept() {
        UserSettings.setMosaicDraft(Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", ""]), for: "bob")
        UserSettings.setMosaicDraft(Mosaic(columns: 4, rows: 4), for: "bob")

        #expect(UserSettings.mosaicDraft(for: "bob") == nil, "Пустая сетка — не набросок")
    }

    @Test func nilClearsTheDraft() {
        UserSettings.setMosaicDraft(Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", ""]), for: "bob")
        UserSettings.setMosaicDraft(nil, for: "bob")

        #expect(UserSettings.mosaicDraft(for: "bob") == nil)
    }

    @Test func unknownConversation_hasNoDraft() {
        #expect(UserSettings.mosaicDraft(for: "nobody") == nil)
    }
}
