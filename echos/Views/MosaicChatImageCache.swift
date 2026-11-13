//
//  MosaicChatImageCache.swift
//  echos
//
//  Отрисовка мозаик для ленты чата. Каждая мозаика — это до 64 UILabel с
//  раскладкой; собирать их внутри dequeue ячейки на длинной переписке
//  дорого. Поэтому в ленту идёт уже готовая картинка, а одинаковые мозаики
//  берутся из кэша.
//

import UIKit

/// Рисует мозаику размером для чата без построения дерева UIView — можно
/// выполнять до показа ячейки и вне главного потока.
enum MosaicChatImageRenderer {

    static let cellSize: CGFloat = 32
    static let spacing: CGFloat = 1

    static func render(_ mosaic: Mosaic) -> UIImage {
        let size = CGSize(width: CGFloat(mosaic.columns) * cellSize + CGFloat(mosaic.columns - 1) * spacing,
                          height: CGFloat(mosaic.rows) * cellSize + CGFloat(mosaic.rows - 1) * spacing)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: cellSize * 0.7),
            ]

            for row in 0..<mosaic.rows {
                for column in 0..<mosaic.columns {
                    let cell = mosaic[column, row]
                    guard !cell.isEmpty else {
                        continue
                    }

                    let rect = CGRect(x: CGFloat(column) * (cellSize + spacing),
                                      y: CGFloat(row) * (cellSize + spacing),
                                      width: cellSize,
                                      height: cellSize)
                    let textSize = cell.size(withAttributes: attributes)
                    let origin = CGPoint(x: rect.midX - textSize.width / 2,
                                         y: rect.midY - textSize.height / 2)
                    (cell as NSString).draw(at: origin, withAttributes: attributes)
                }
            }
        }
    }
}

/// Кэш живёт на главном акторе, потому что его читает `MessageCell` во
/// время `cellForRowAt`. Сама отрисовка уходит в фоновую задачу.
@MainActor
final class MosaicChatImageCache {

    static let shared = MosaicChatImageCache()

    private let images = NSCache<NSString, UIImage>()

    private init() {
        images.countLimit = 300
    }

    func image(for mosaic: Mosaic) -> UIImage? {
        images.object(forKey: mosaic.chatImageCacheKey)
    }

    func insert(_ image: UIImage, for mosaic: Mosaic) {
        images.setObject(image, forKey: mosaic.chatImageCacheKey)
    }

    /// Подготовить изображение заранее. Повторный вызов бесплатен: после
    /// первой отрисовки результат берётся из кэша.
    func prepare(_ mosaic: Mosaic) async {
        guard image(for: mosaic) == nil else {
            return
        }

        let rendered = await Task.detached(priority: .utility) { () -> UIImage? in
            guard !Task.isCancelled else {
                return nil
            }
            return MosaicChatImageRenderer.render(mosaic)
        }.value

        if let rendered, !Task.isCancelled {
            insert(rendered, for: mosaic)
        }
    }
}

private extension Mosaic {
    var chatImageCacheKey: NSString {
        let cells = cells.joined(separator: "\u{1}")
        return "\(columns)x\(rows):\(cells)" as NSString
    }
}
