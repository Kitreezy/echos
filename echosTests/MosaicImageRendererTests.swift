//
//  MosaicImageRendererTests.swift
//  echosTests
//

import Foundation
import Testing
@testable import echos

@MainActor
struct MosaicImageRendererTests {

    @Test func image_hasRoomForEveryCellAndTheCaption() {
        let mosaic = Mosaic(columns: 4, rows: 2, cells: Array(repeating: "🟨", count: 8))!
        let image = MosaicImageRenderer.render(mosaic)

        let cells = MosaicImageRenderer.cellSize
        let padding = MosaicImageRenderer.padding
        #expect(image.size.width >= 4 * cells + 2 * padding)
        #expect(image.size.height >= 2 * cells + 2 * padding)
        #expect(image.scale == 2, "Картинка для экрана, не для печати")
    }

    @Test func size_matchesRender() {
        let mosaic = Mosaic(columns: 3, rows: 3)
        #expect(MosaicImageRenderer.render(mosaic).size == MosaicImageRenderer.size(for: mosaic))
    }

    @Test func wideAndTall_differ() {
        let wide = Mosaic(columns: 8, rows: 2)
        let tall = Mosaic(columns: 2, rows: 8)

        #expect(MosaicImageRenderer.size(for: wide).width > MosaicImageRenderer.size(for: tall).width)
        #expect(MosaicImageRenderer.size(for: wide).height < MosaicImageRenderer.size(for: tall).height)
    }
}
