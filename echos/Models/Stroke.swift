//
//  Stroke.swift
//  echos
//

import CoreGraphics
import Foundation

/// Один росчерк на стене: от касания до отрыва пальца.
///
/// Точки хранятся в долях от 0 до 1, а не в пикселях. Стена у собеседника
/// может быть другого размера — на iPad шире, на SE уже, — и в абсолютных
/// координатах рисунок бы съезжал.
struct Stroke: Identifiable, Codable, Sendable, Equatable {

    let id: UUID

    /// Кто нарисовал — адрес, а не имя. Для своих штрихов он тоже
    /// проставляется: стена переживает перезапуск, и через день «своё» надо
    /// как-то отличать.
    let author: String

    /// Точки в долях ширины и высоты стены.
    let points: [Point]

    let createdAt: Date

    init(id: UUID = UUID(), author: String, points: [Point], createdAt: Date = Date()) {
        self.id = id
        self.author = author
        self.points = points
        self.createdAt = createdAt
    }

    /// Копия с проставленным автором.
    ///
    /// Нужна на приёме: автор внутри росчерка приходит от отправителя, а
    /// доверять можно только адресу, который подтвердил транспорт.
    func by(_ author: String) -> Stroke {
        Stroke(id: id, author: author, points: points, createdAt: createdAt)
    }

    struct Point: Codable, Sendable, Equatable {
        let x: Double
        let y: Double

        init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        init(_ point: CGPoint, in size: CGSize) {
            self.x = size.width > 0 ? Double(point.x / size.width) : 0
            self.y = size.height > 0 ? Double(point.y / size.height) : 0
        }

        func cgPoint(in size: CGSize) -> CGPoint {
            CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
        }
    }
}
