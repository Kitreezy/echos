//
//  MosaicImageRenderer.swift
//  echos
//
//  Мозаика картинкой — чтобы унести наружу.
//
//  Внутри echos мозаика едет сеткой и у собеседника не разъезжается. В
//  другом мессенджере такого нет: там она превратится в текст, и ровно
//  не встанет. Картинка — единственный способ показать её снаружи такой,
//  какая она есть. Рисуется крупно, на своём фоне, с подписью «echos» в
//  углу — по ней и узнают, откуда рисунок.
//

import UIKit

enum MosaicImageRenderer {

    /// Клетка на картинке. Крупно: картинку смотрят, а не набирают.
    static let cellSize: CGFloat = 96
    static let padding: CGFloat = 48

    /// Сколько займёт картинка — до того, как её рисовать.
    static func size(for mosaic: Mosaic) -> CGSize {
        let grid = MosaicView()
        grid.cellSize = cellSize
        grid.show(mosaic)
        let gridSize = grid.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: gridSize.width + padding * 2,
                      height: gridSize.height + padding * 2 + captionHeight)
    }

    private static let captionHeight: CGFloat = 40

    @MainActor
    static func render(_ mosaic: Mosaic) -> UIImage {
        let grid = MosaicView()
        grid.cellSize = cellSize
        grid.show(mosaic)
        let gridSize = grid.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        grid.frame = CGRect(origin: CGPoint(x: padding, y: padding), size: gridSize)
        grid.layoutIfNeeded()

        let canvas = UIView(frame: CGRect(origin: .zero, size: size(for: mosaic)))
        canvas.backgroundColor = .surface
        canvas.addSubview(grid)

        let caption = UILabel()
        caption.text = "e c h o s"
        caption.font = Typography.micro
        caption.textColor = .inkMuted
        caption.sizeToFit()
        caption.frame.origin = CGPoint(x: canvas.bounds.width - padding - caption.bounds.width,
                                       y: canvas.bounds.height - padding / 2 - caption.bounds.height)
        canvas.addSubview(caption)
        canvas.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(bounds: canvas.bounds, format: format).image { context in
            canvas.layer.render(in: context.cgContext)
        }
    }
}
