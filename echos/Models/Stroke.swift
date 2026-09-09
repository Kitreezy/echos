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

    /// Кто нарисовал. Для своих штрихов имя тоже проставляется: стена
    /// переживает перезапуск, и через день «своё» надо как-то отличать.
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
