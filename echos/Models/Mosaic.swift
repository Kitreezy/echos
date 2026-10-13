//
//  Mosaic.swift
//  echos
//
//  Рисунок из эмодзи на сетке.
//
//  Зачем: рисунки из эмодзи в чатах разъезжаются — у получателя другой
//  шрифт, другая ширина знака, перенос строки не там. Даже ровно набранная
//  сетка 5×5 у собеседника может стать 4×6. Поэтому мозаика ходит не
//  текстом, а сеткой: размер и клетки, — и рисуется у получателя из
//  клеток, одинаково с обеих сторон.
//
//  Текстовая форма при этом остаётся: она нужна для превью в списке
//  разговоров и чтобы унести рисунок в другой мессенджер — пусть и криво.
//

import Foundation

struct Mosaic: Codable, Equatable, Sendable {

    /// Сторона сетки — от одной до восьми клеток. Восемь — потолок: на
    /// экране телефона клетки меньше уже не разглядеть.
    static let sideRange = 1...8

    let columns: Int
    let rows: Int

    /// Клетки построчно, слева направо. Пустая строка — пустая клетка;
    /// иначе — один эмодзи.
    let cells: [String]

    /// Пустая сетка заданного размера.
    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        self.cells = Array(repeating: "", count: columns * rows)
    }

    /// Сетка с готовыми клетками. `nil`, если клеток не столько, сколько
    /// должно быть, размер вне допустимого или в клетке больше одного знака.
    init?(columns: Int, rows: Int, cells: [String]) {
        guard Self.sideRange.contains(columns), Self.sideRange.contains(rows),
              cells.count == columns * rows,
              cells.allSatisfy({ $0.count <= 1 }) else {
            return nil
        }
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }

    // MARK: - Клетки

    subscript(column: Int, row: Int) -> String {
        cells[row * columns + column]
    }

    /// Та же сетка с одной другой клеткой.
    func setting(column: Int, row: Int, to cell: String) -> Mosaic {
        var cells = self.cells
        cells[row * columns + column] = String(cell.prefix(1))
        return Mosaic(columns: columns, rows: rows, cells: cells) ?? self
    }

    var isEmpty: Bool {
        cells.allSatisfy(\.isEmpty)
    }

    /// Сколько клеток заполнено.
    var filledCount: Int {
        cells.filter { !$0.isEmpty }.count
    }

    // MARK: - Текст

    /// Пустая клетка в тексте. Идеографический пробел — единственный
    /// пробел, который в большинстве шрифтов близок по ширине к эмодзи.
    static let blank = "\u{3000}"

    /// Построчно, как текст. Ровность здесь не обещается — для неё есть
    /// сама сетка; текст нужен, где сетки нет.
    var text: String {
        (0..<rows)
            .map { row in
                (0..<columns)
                    .map { column in
                        let cell = self[column, row]
                        return cell.isEmpty ? Self.blank : cell
                    }
                    .joined()
            }
            .joined(separator: "\n")
    }

    // MARK: - Провод

    /// Проверка после разбора: сетка, пришедшая снаружи, может быть какой
    /// угодно. `Decodable` не даёт бросить из синтезированного init, поэтому
    /// проверяем отдельно и сразу после декодирования.
    var isValid: Bool {
        Mosaic(columns: columns, rows: rows, cells: cells) != nil
    }
}
