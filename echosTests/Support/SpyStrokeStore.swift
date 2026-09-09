//
//  SpyStrokeStore.swift
//  echosTests
//

import Foundation
@testable import echos

@MainActor
final class SpyStrokeStore: StrokeStoring {

    private(set) var saved: [(stroke: Stroke, wallOwner: String?)] = []
    var preloaded: [Stroke] = []

    func loadStrokes(wallOwner: String?) async throws -> [Stroke] {
        preloaded
    }

    func saveStroke(_ stroke: Stroke, wallOwner: String?) async throws {
        saved.append((stroke, wallOwner))
    }

    func clearWall(_ wallOwner: String?) async throws {
        saved.removeAll { $0.wallOwner == wallOwner }
    }
}
