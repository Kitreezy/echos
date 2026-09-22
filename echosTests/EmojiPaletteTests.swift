//
//  EmojiPaletteTests.swift
//  echosTests
//

import XCTest
@testable import echos

final class EmojiPaletteTests: XCTestCase {

    func test_pixelGroupsComeFirst() {
        XCTAssertEqual(EmojiPalette.groups.prefix(4).map(\.id),
                       ["squares", "circles", "hearts", "stars"],
                       "Из них складывают рисунки — им и быть под рукой")
    }

    func test_everyGroupHasEmojis() {
        for group in EmojiPalette.groups {
            XCTAssertFalse(group.emojis.isEmpty, "Пустая группа \(group.id)")
        }
    }

    /// Раньше палитра была списком из двух сотен знаков, набранных руками.
    /// Теперь она выводится из Unicode и заметно больше.
    func test_paletteIsLarge() {
        XCTAssertGreaterThan(EmojiPalette.all.count, 700)
    }

    func test_noDuplicatesWithinAGroup() {
        for group in EmojiPalette.groups {
            XCTAssertEqual(Set(group.emojis).count, group.emojis.count, "Повторы в \(group.id)")
        }
    }

    /// В мозаике знак занимает клетку, и всё, что рисуется как текст, —
    /// дыра в рисунке.
    func test_everyEmojiIsDrawnAsAnEmoji() {
        for group in EmojiPalette.groups {
            for emoji in group.emojis {
                let scalars = emoji.unicodeScalars
                let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
                    || scalars.contains { $0 == "\u{FE0F}" }
                XCTAssertTrue(isEmoji, "\(emoji) в \(group.id) — не эмодзи")
            }
        }
    }

    func test_favouritesAreThere() {
        for emoji in ["🟨", "🔴", "❤️", "⭐", "😀", "🐱", "🍕", "🚀"] {
            XCTAssertTrue(EmojiPalette.all.contains(emoji), "\(emoji) потерялся")
        }
    }
}
