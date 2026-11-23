//
//  EmojiPalette.swift
//  echos
//
//  Чем рисовать мозаику.
//
//  Системная клавиатура для этого не годится: она закрывает полэкрана и
//  раскладывает эмодзи по назначению, а не по тому, как они выглядят.
//  Здесь порядок обратный: сначала то, из чего складываются пиксели —
//  квадраты, круги, сердца, звёзды, — а дальше всё остальное.
//
//  «Всё остальное» не переписано руками: список выводится из свойств
//  Unicode. Знак попадает в палитру, если система рисует его как эмодзи
//  сама по себе, без добавок. Так палитра не отстаёт от системы: вышла
//  новая версия iOS с новыми эмодзи — они появятся сами.
//

import Foundation

struct EmojiPalette {

    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        let emojis: [String]
    }

    /// Ради чего всё затевалось: из этих знаков складывают рисунки.
    /// Они первыми, и порядок внутри — по цвету, а не по кодам.
    private static let pixels: [Group] = [
        Group(id: "squares", title: String(localized: "квадраты"),
              emojis: ["🟥", "🟧", "🟨", "🟩", "🟦", "🟪", "🟫", "⬛", "⬜",
                       "🔲", "🔳", "▪️", "▫️", "◾", "◽", "◼️", "◻️"]),
        Group(id: "circles", title: String(localized: "круги"),
              emojis: ["🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "🟤", "⚫", "⚪",
                       "🔘", "⭕", "🔺", "🔻", "🔶", "🔷", "🔸", "🔹", "💠"]),
        Group(id: "hearts", title: String(localized: "сердца"),
              emojis: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🤎", "🖤", "🤍",
                       "💖", "💗", "💓", "💞", "💕", "💘", "💝", "❣️", "💔"]),
        Group(id: "stars", title: String(localized: "звёзды"),
              emojis: ["⭐", "🌟", "✨", "💫", "⚡", "🔥", "💥", "❄️", "☀️",
                       "🌙", "🌈", "☁️", "💧", "🌊", "🎇", "🎆", "✴️", "❇️"])
    ]

    // Колонки выровнены, чтобы таблицу можно было читать как таблицу.
    // swiftlint:disable comma

    /// Остальное — блоками Unicode. Названия приблизительные: внутри блока
    /// знаки соседствуют по смыслу, но границы у блоков свои, и делить их
    /// точнее значило бы выписывать тысячу знаков руками.
    private static let blocks: [(id: String, title: String, ranges: [ClosedRange<UInt32>])] = [
        ("faces",   String(localized: "лица"),      [0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97F,
                                  0x1FAE0...0x1FAEF]),
        ("hands",   String(localized: "жесты"),     [0x1F440...0x1F450, 0x1F590...0x1F596, 0x1F918...0x1F91F,
                                  0x1FAF0...0x1FAFF]),
        ("animals", String(localized: "звери"),     [0x1F400...0x1F43F, 0x1F980...0x1F9AE]),
        ("nature",  String(localized: "природа"),   [0x1F300...0x1F32F, 0x1F330...0x1F343, 0x1F386...0x1F397]),
        ("food",    String(localized: "еда"),       [0x1F344...0x1F37F, 0x1F950...0x1F96F]),
        ("things",  String(localized: "вещи"),      [0x1F4A0...0x1F4FF, 0x1F6E0...0x1F6FF, 0x1FA70...0x1FA7F,
                                  0x1FA80...0x1FA8F]),
        ("travel",  String(localized: "дорога"),    [0x1F680...0x1F6DF, 0x1F3D4...0x1F3F0]),
        ("symbols", String(localized: "символы"),   [0x2600...0x27BF, 0x1F500...0x1F53F, 0x1F550...0x1F567])
    ]
    // swiftlint:enable comma

    static let groups: [Group] = pixels + blocks.map { block in
        Group(id: block.id, title: block.title, emojis: emojis(in: block.ranges))
    }

    /// Знаки, которые система сама рисует как эмодзи. Остальное — буквы,
    /// стрелки и служебные знаки: в мозаике они выглядят как мусор.
    private static func emojis(in ranges: [ClosedRange<UInt32>]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for range in ranges {
            for code in range {
                guard let scalar = Unicode.Scalar(code),
                      scalar.properties.isEmojiPresentation else {
                    continue
                }
                let emoji = String(scalar)
                if seen.insert(emoji).inserted {
                    result.append(emoji)
                }
            }
        }
        return result
    }

    /// Всё подряд — чтобы проверить, что кисть из палитры.
    static let all: Set<String> = Set(groups.flatMap(\.emojis))
}
