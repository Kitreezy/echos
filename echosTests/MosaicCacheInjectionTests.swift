//
//  MosaicCacheInjectionTests.swift
//  echosTests
//
//  Unit: чат и ячейки работают с инъектированным кэшем мозаик — тестовый
//  экземпляр не трогает синглтон.
//

import Foundation
import UIKit
import Testing
@testable import echos

@MainActor
struct MosaicCacheInjectionTests {

    private func heartMosaic() -> Mosaic {
        // Сердечки по диагонали 2×2. Ячейки через failable init:
        // пустые строки — пропуски сетки.
        Mosaic(columns: 2, rows: 2, cells: ["❤️", "", "", "❤️"])!
    }

    /// Prefetch чата готовит картинку в тот кэш, что передали в
    /// инициализатор, — а не в глобальный shared.
    @Test func chatPrefetch_usesInjectedCache() async {
        let injected = MosaicChatImageCache()
        let shared = MosaicChatImageCache.shared
        let mosaic = heartMosaic()
        let viewModel = ChatViewModel()
        viewModel.messages = [Message(text: "", mosaic: mosaic, isFromMe: false)]

        let chat = ChatViewController(viewModel: viewModel, cache: injected)
        chat.tableView(UITableView(), prefetchRowsAt: [IndexPath(row: 0, section: 0)])

        let prepared = await waitUntil { injected.image(for: mosaic) != nil }
        #expect(prepared, "Prefetch не подготовил картинку в инъектированном кэше")
        #expect(shared.image(for: mosaic) == nil,
                "Prefetch утёк в синглтон вместо инъектированного кэша")
    }

    /// Ячейка рисует и кладёт результат в свой кэш: подменили свойство —
    /// синглтон чист.
    @Test func messageCell_usesAssignedCache() {
        let assigned = MosaicChatImageCache()
        let shared = MosaicChatImageCache.shared
        let mosaic = heartMosaic()

        let cell = MessageCell(style: .default, reuseIdentifier: MessageCell.reuseID)
        cell.mosaicCache = assigned
        cell.configure(with: Message(text: "", mosaic: mosaic, isFromMe: false))

        #expect(assigned.image(for: mosaic) != nil,
                "Ячейка не положила отрисованную мозаику в свой кэш")
        #expect(shared.image(for: mosaic) == nil,
                "Ячейка утёкла в синглтон вместо присвоенного кэша")
    }
}
