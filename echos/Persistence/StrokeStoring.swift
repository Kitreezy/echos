//
//  StrokeStoring.swift
//  echos
//
//  Абстракция над хранилищем росчерков — тот же шов, что у сообщений.
//

import Foundation

@MainActor
protocol StrokeStoring: AnyObject {

    /// Стена конкретного собеседника. Своя стена хранится под `nil`.
    func loadStrokes(wallOwner: String?) async throws -> [Stroke]

    func saveStroke(_ stroke: Stroke, wallOwner: String?) async throws

    func clearWall(_ wallOwner: String?) async throws
}

extension StrokeStore: StrokeStoring {}
