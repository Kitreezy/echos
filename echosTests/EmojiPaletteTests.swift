//
//  EmojiPaletteTests.swift
//  echosTests
//

import Foundation
import Testing
@testable import echos

struct EmojiPaletteTests {

    @Test func pixelGroupsComeFirst() {
        #expect(EmojiPalette.groups.prefix(4).map(\.id) == ["squares", "circles", "hearts", "stars"], "Из них складывают рисунки — им и быть под рукой")
    }

    @Test func everyGroupHasEmojis() {
        for group in EmojiPalette.groups {
            #expect(!group.emojis.isEmpty, "Пустая группа \(group.id)")
        }
    }

    /// Раньше палитра была списком из двух сотен знаков, набранных руками.
    /// Теперь она выводится из Unicode и заметно больше.
    @Test func paletteIsLarge() {
        #expect(EmojiPalette.all.count > 700)
    }

    @Test func noDuplicatesWithinAGroup() {
        for group in EmojiPalette.groups {
            #expect(Set(group.emojis).count == group.emojis.count, "Повторы в \(group.id)")
        }
    }

    /// В мозаике знак занимает клетку, и всё, что рисуется как текст, —
    /// дыра в рисунке.
    @Test func everyEmojiIsDrawnAsAnEmoji() {
        for group in EmojiPalette.groups {
            for emoji in group.emojis {
                let scalars = emoji.unicodeScalars
                let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
                    || scalars.contains { $0 == "\u{FE0F}" }
                #expect(isEmoji, "\(emoji) в \(group.id) — не эмодзи")
            }
        }
    }

    @Test func favouritesAreThere() {
        for emoji in ["🟨", "🔴", "❤️", "⭐", "😀", "🐱", "🍕", "🚀"] {
            #expect(EmojiPalette.all.contains(emoji), "\(emoji) потерялся")
        }
    }
}
