//
//  MosaicTests.swift
//  echosTests
//
//  Мозаика: сетка, её текстовая форма и то, что приходит снаружи.
//

import Foundation
import Testing
@testable import echos

struct MosaicTests {

    // MARK: - Сетка

    @Test func emptyGrid_hasTheRightNumberOfCells() {
        let mosaic = Mosaic(columns: 3, rows: 2)

        #expect(mosaic.cells.count == 6)
        #expect(mosaic.isEmpty)
        #expect(mosaic.filledCount == 0)
    }

    @Test func settingACell_changesOnlyThatCell() {
        let painted = Mosaic(columns: 3, rows: 3).setting(column: 1, row: 2, to: "🟥")

        #expect(painted[1, 2] == "🟥")
        #expect(painted.filledCount == 1)
        #expect(painted[0, 0] == "")
        #expect(painted[2, 2] == "")
    }

    /// В клетке — один знак. Эмодзи с модификаторами и флаги — это один
    /// знак для человека и один `Character` для Swift.
    @Test func cell_keepsOneCharacterOnly() {
        let painted = Mosaic(columns: 1, rows: 1).setting(column: 0, row: 0, to: "👍🏽👎")
        #expect(painted[0, 0] == "👍🏽")

        let flag = Mosaic(columns: 1, rows: 1).setting(column: 0, row: 0, to: "🇷🇺")
        #expect(flag[0, 0] == "🇷🇺")
    }

    /// Самые длинные настоящие эмодзи помещаются в клетку.
    @Test(arguments: ["👨🏻‍👩🏻‍👧🏻‍👦🏻", "🏳️‍⚧️", "1️⃣", "🇷🇺"])
    func longestRealEmoji_fitsACell(_ emoji: String) {
        #expect(Mosaic(columns: 1, rows: 1, cells: [emoji]) != nil)
    }

    /// Для `count` это один знак, но в нём тысячи кодовых точек. Нашла
    /// проверка на сгенерированных входах (Fuzz/ParserFuzzTests).
    @Test(arguments: ["a" + String(repeating: "\u{0301}", count: 5_000),
                      "🟥" + String(repeating: "\u{FE0F}", count: 1_000)])
    func oneGraphemeOfThousandsOfScalars_isRejected(_ cell: String) {
        #expect(cell.count == 1)
        #expect(Mosaic(columns: 1, rows: 1, cells: [cell]) == nil)
    }

    // MARK: - Границы

    /// Сетка, которой быть не может, не создаётся. Раньше это были три теста
    /// по нескольку проверок; теперь — таблица, и каждый случай отдельно.
    @Test(arguments: [
        (0, 1, [String]()),                          // размер меньше
        (9, 1, Array(repeating: "", count: 9)),      // размер больше
        (2, 2, ["", "", ""]),                        // клеток меньше, чем мест
        (2, 2, ["", "", "", "", ""]),                // клеток больше
        (1, 1, ["ab"])                               // в клетке больше одного знака
    ])
    func invalidGrid_isRejected(columns: Int, rows: Int, cells: [String]) {
        #expect(Mosaic(columns: columns, rows: rows, cells: cells) == nil)
    }

    /// Края допустимого размера — ещё сетка.
    @Test(arguments: [1, 8])
    func sizeAtTheBounds_isAccepted(side: Int) {
        #expect(Mosaic(columns: side, rows: side, cells: Array(repeating: "", count: side * side)) != nil)
    }

    // MARK: - Текст

    @Test func text_isRowByRow() {
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟥", "🟦", "🟩", "🟨"])!
        #expect(mosaic.text == "🟥🟦\n🟩🟨")
    }

    @Test func text_fillsEmptyCellsWithAWideBlank() {
        let mosaic = Mosaic(columns: 2, rows: 1, cells: ["", "🟦"])!
        #expect(mosaic.text == "\u{3000}🟦")
        #expect(mosaic.text.count == 2, "Пустая клетка — тоже один знак, иначе рисунок сползёт")
    }

    // MARK: - Провод

    @Test func mosaic_survivesTheWire() throws {
        let mosaic = Mosaic(columns: 3, rows: 2, cells: ["🟥", "", "🟦", "", "🟩", ""])!

        let restored = try JSONDecoder().decode(Mosaic.self, from: try JSONEncoder().encode(mosaic))

        #expect(restored == mosaic)
        #expect(restored.isValid)
    }

    /// Сетка снаружи может быть какой угодно — декодер её не проверяет.
    /// Проверяет `isValid`, и `MessagePayload` на неё смотрит.
    @Test func malformedMosaicFromTheWire_isDroppedButTextStays() throws {
        let json = """
        {"id":"\(UUID().uuidString)","text":"🟥🟦","senderName":"Alice","timestamp":1700000000,
         "mosaic":{"columns":2,"rows":2,"cells":["🟥","🟦"]}}
        """
        let payload = try JSONDecoder().decode(MessagePayload.self, from: Data(json.utf8))

        let message = payload.toMessage(from: "alice")

        #expect(message.mosaic == nil, "Клеток две, а должно быть четыре")
        #expect(message.text == "🟥🟦", "Текстовая форма остаётся")
    }

    @Test func oversizedMosaicFromTheWire_isDropped() throws {
        let cells = Array(repeating: "🟥", count: 100)
        let encodedCells = try #require(String(bytes: try JSONEncoder().encode(cells), encoding: .utf8))

        let raw = """
        {"id":"\(UUID().uuidString)","text":"x","senderName":"A","timestamp":1,
         "mosaic":{"columns":10,"rows":10,"cells":\(encodedCells)}}
        """
        let decoded = try JSONDecoder().decode(MessagePayload.self, from: Data(raw.utf8))

        #expect(decoded.toMessage(from: "a").mosaic == nil)
    }

    /// Обычное сообщение мозаики не несёт, и старая сборка, которая о ней
    /// не знает, разбирает такой payload как раньше.
    @Test func plainMessage_hasNoMosaicOnTheWire() throws {
        let payload = MessagePayload(from: Message(text: "привет", isFromMe: true), senderName: "A")
        let wire = try #require(String(bytes: try JSONEncoder().encode(payload), encoding: .utf8))

        #expect(!wire.contains("mosaic"))
    }

    @Test func mosaicMessage_carriesGridAndTextTogether() throws {
        let mosaic = Mosaic(columns: 2, rows: 1, cells: ["🟥", "🟦"])!
        let payload = MessagePayload(from: Message(text: mosaic.text, mosaic: mosaic, isFromMe: true),
                                     senderName: "A")

        let restored = try JSONDecoder().decode(MessagePayload.self, from: try JSONEncoder().encode(payload))
        let message = restored.toMessage(from: "a")

        #expect(message.mosaic == mosaic)
        #expect(message.text == "🟥🟦")
    }
}
