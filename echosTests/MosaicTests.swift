//
//  MosaicTests.swift
//  echosTests
//
//  Мозаика: сетка, её текстовая форма и то, что приходит снаружи.
//

import XCTest
@testable import echos

final class MosaicTests: XCTestCase {

    // MARK: - Сетка

    func test_emptyGrid_hasTheRightNumberOfCells() {
        let mosaic = Mosaic(columns: 3, rows: 2)

        XCTAssertEqual(mosaic.cells.count, 6)
        XCTAssertTrue(mosaic.isEmpty)
        XCTAssertEqual(mosaic.filledCount, 0)
    }

    func test_settingACell_changesOnlyThatCell() {
        let painted = Mosaic(columns: 3, rows: 3).setting(column: 1, row: 2, to: "🟥")

        XCTAssertEqual(painted[1, 2], "🟥")
        XCTAssertEqual(painted.filledCount, 1)
        XCTAssertEqual(painted[0, 0], "")
        XCTAssertEqual(painted[2, 2], "")
    }

    /// В клетке — один знак. Эмодзи с модификаторами и флаги — это один
    /// знак для человека и один `Character` для Swift.
    func test_cell_keepsOneCharacterOnly() {
        let painted = Mosaic(columns: 1, rows: 1).setting(column: 0, row: 0, to: "👍🏽👎")
        XCTAssertEqual(painted[0, 0], "👍🏽")

        let flag = Mosaic(columns: 1, rows: 1).setting(column: 0, row: 0, to: "🇷🇺")
        XCTAssertEqual(flag[0, 0], "🇷🇺")
    }

    // MARK: - Границы

    func test_sizeOutOfRange_isRejected() {
        XCTAssertNil(Mosaic(columns: 0, rows: 1, cells: []))
        XCTAssertNil(Mosaic(columns: 9, rows: 1, cells: Array(repeating: "", count: 9)))
        XCTAssertNotNil(Mosaic(columns: 8, rows: 8, cells: Array(repeating: "", count: 64)))
        XCTAssertNotNil(Mosaic(columns: 1, rows: 1, cells: [""]))
    }

    func test_wrongCellCount_isRejected() {
        XCTAssertNil(Mosaic(columns: 2, rows: 2, cells: ["", "", ""]))
        XCTAssertNil(Mosaic(columns: 2, rows: 2, cells: ["", "", "", "", ""]))
    }

    func test_multiCharacterCell_isRejected() {
        XCTAssertNil(Mosaic(columns: 1, rows: 1, cells: ["ab"]))
    }

    // MARK: - Текст

    func test_text_isRowByRow() {
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟥", "🟦", "🟩", "🟨"])!
        XCTAssertEqual(mosaic.text, "🟥🟦\n🟩🟨")
    }

    func test_text_fillsEmptyCellsWithAWideBlank() {
        let mosaic = Mosaic(columns: 2, rows: 1, cells: ["", "🟦"])!
        XCTAssertEqual(mosaic.text, "\u{3000}🟦")
        XCTAssertEqual(mosaic.text.count, 2, "Пустая клетка — тоже один знак, иначе рисунок сползёт")
    }

    // MARK: - Провод

    func test_mosaic_survivesTheWire() throws {
        let mosaic = Mosaic(columns: 3, rows: 2, cells: ["🟥", "", "🟦", "", "🟩", ""])!

        let restored = try JSONDecoder().decode(Mosaic.self, from: try JSONEncoder().encode(mosaic))

        XCTAssertEqual(restored, mosaic)
        XCTAssertTrue(restored.isValid)
    }

    /// Сетка снаружи может быть какой угодно — декодер её не проверяет.
    /// Проверяет `isValid`, и `MessagePayload` на неё смотрит.
    func test_malformedMosaicFromTheWire_isDroppedButTextStays() throws {
        let json = """
        {"id":"\(UUID().uuidString)","text":"🟥🟦","senderName":"Alice","timestamp":1700000000,
         "mosaic":{"columns":2,"rows":2,"cells":["🟥","🟦"]}}
        """
        let payload = try JSONDecoder().decode(MessagePayload.self, from: Data(json.utf8))

        let message = payload.toMessage(from: "alice")

        XCTAssertNil(message.mosaic, "Клеток две, а должно быть четыре")
        XCTAssertEqual(message.text, "🟥🟦", "Текстовая форма остаётся")
    }

    func test_oversizedMosaicFromTheWire_isDropped() throws {
        let cells = Array(repeating: "🟥", count: 100)

        let raw = """
        {"id":"\(UUID().uuidString)","text":"x","senderName":"A","timestamp":1,
         "mosaic":{"columns":10,"rows":10,"cells":\(String(decoding: try JSONEncoder().encode(cells), as: UTF8.self))}}
        """
        let decoded = try JSONDecoder().decode(MessagePayload.self, from: Data(raw.utf8))

        XCTAssertNil(decoded.toMessage(from: "a").mosaic)
    }

    /// Обычное сообщение мозаики не несёт, и старая сборка, которая о ней
    /// не знает, разбирает такой payload как раньше.
    func test_plainMessage_hasNoMosaicOnTheWire() throws {
        let payload = MessagePayload(from: Message(text: "привет", isFromMe: true), senderName: "A")
        let wire = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        XCTAssertFalse(wire.contains("mosaic"))
    }

    func test_mosaicMessage_carriesGridAndTextTogether() throws {
        let mosaic = Mosaic(columns: 2, rows: 1, cells: ["🟥", "🟦"])!
        let payload = MessagePayload(from: Message(text: mosaic.text, mosaic: mosaic, isFromMe: true),
                                     senderName: "A")

        let restored = try JSONDecoder().decode(MessagePayload.self, from: try JSONEncoder().encode(payload))
        let message = restored.toMessage(from: "a")

        XCTAssertEqual(message.mosaic, mosaic)
        XCTAssertEqual(message.text, "🟥🟦")
    }
}
