//
//  StubDigester.swift
//  echosTests
//
//  Пересказчик по сценарию: отдаёт заранее заданные шаги вместо модели.
//

import Foundation
@testable import echos

@MainActor
final class StubDigester: Digesting {

    var availability: DigestAvailability = .ready

    /// Что сказать про язык: `nil` — язык знаком.
    var languageProblem: String?

    func languageProblem(in messages: [Message]) -> String? {
        languageProblem
    }

    /// Что отдать по порядку.
    var script: [DigestProgress] = []

    /// Чем закончить: `nil` — успехом.
    var failure: Error?

    private(set) var preparedCount = 0
    private(set) var digested: [[Message]] = []

    func prepare() {
        preparedCount += 1
    }

    func digest(of messages: [Message], with peerName: String) -> AsyncThrowingStream<DigestProgress, Error> {
        digested.append(messages)
        let script = script
        let failure = failure
        return AsyncThrowingStream { continuation in
            for step in script {
                continuation.yield(step)
            }
            continuation.finish(throwing: failure)
        }
    }
}
