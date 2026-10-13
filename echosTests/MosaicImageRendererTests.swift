//
//  MosaicImageRendererTests.swift
//  echosTests
//

import XCTest
@testable import echos

@MainActor
final class MosaicImageRendererTests: XCTestCase {

    func test_image_hasRoomForEveryCellAndTheCaption() {
        let mosaic = Mosaic(columns: 4, rows: 2, cells: Array(repeating: "🟨", count: 8))!
        let image = MosaicImageRenderer.render(mosaic)

        let cells = MosaicImageRenderer.cellSize
        let padding = MosaicImageRenderer.padding
        XCTAssertGreaterThanOrEqual(image.size.width, 4 * cells + 2 * padding)
        XCTAssertGreaterThanOrEqual(image.size.height, 2 * cells + 2 * padding)
        XCTAssertEqual(image.scale, 2, "Картинка для экрана, не для печати")
    }

    func test_size_matchesRender() {
        let mosaic = Mosaic(columns: 3, rows: 3)
        XCTAssertEqual(MosaicImageRenderer.render(mosaic).size, MosaicImageRenderer.size(for: mosaic))
    }

    func test_wideAndTall_differ() {
        let wide = Mosaic(columns: 8, rows: 2)
        let tall = Mosaic(columns: 2, rows: 8)

        XCTAssertGreaterThan(MosaicImageRenderer.size(for: wide).width, MosaicImageRenderer.size(for: tall).width)
        XCTAssertLessThan(MosaicImageRenderer.size(for: wide).height, MosaicImageRenderer.size(for: tall).height)
    }
}
