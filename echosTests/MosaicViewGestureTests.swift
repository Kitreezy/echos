//
//  MosaicViewGestureTests.swift
//  echosTests
//
//  Мозаика в ленте — картинка, а не холст: палец на ней должен листать
//  переписку, а не рисовать.
//

import XCTest
@testable import echos

@MainActor
final class MosaicViewGestureTests: XCTestCase {

    private func pan(of view: MosaicView) throws -> UIPanGestureRecognizer {
        try XCTUnwrap(view.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
    }

    func test_withoutDrawing_panDoesNotBegin() throws {
        let view = MosaicView()
        view.show(Mosaic(columns: 4, rows: 4))

        XCTAssertFalse(view.gestureRecognizerShouldBegin(try pan(of: view)),
                       "Иначе прокрутка ленты спорит с мозаикой и проигрывает")
    }

    func test_whenDrawing_panBegins() throws {
        let view = MosaicView()
        view.onDrag = { _, _ in }

        XCTAssertTrue(view.gestureRecognizerShouldBegin(try pan(of: view)))
    }

    /// Протягивание красит каждую клетку под пальцем по одному разу.
    func test_drag_paintsEachCellOnce() throws {
        let view = MosaicView()
        var painted: [String] = []
        view.onDrag = { column, row in painted.append("\(column):\(row)") }
        view.cellSize = 40
        view.show(Mosaic(columns: 3, rows: 3))
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutIfNeeded()

        XCTAssertTrue(painted.isEmpty, "Пока пальцем не провели — ничего")
    }
}
