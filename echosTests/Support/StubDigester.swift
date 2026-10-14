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

    var plan: DigestPlan = .direct

    /// Планы на ближайшие вызовы — прежде `plan`. Так изображается
    /// загрузка, которая заканчивается не сразу.
    var upcomingPlans: [DigestPlan] = []

    func plan(for messages: [Message]) async -> DigestPlan {
        upcomingPlans.isEmpty ? plan : upcomingPlans.removeFirst()
    }

    /// Переводчик по умолчанию помечает строку языком назначения:
    /// «привет» → «[en] привет». Так видно, что и куда переводилось.
    var translationFailure: Error?
    private(set) var translators: [StubTranslator] = []

    func translator(from source: Locale.Language, to target: Locale.Language) -> any Translating {
        let translator = StubTranslator(target: target, failure: translationFailure)
        translators.append(translator)
        return translator
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

@MainActor
final class StubTranslator: Translating {

    let target: Locale.Language
    let failure: Error?
    private(set) var received: [[String]] = []

    init(target: Locale.Language, failure: Error?) {
        self.target = target
        self.failure = failure
    }

    func translate(_ texts: [String]) async throws -> [String] {
        received.append(texts)
        if let failure {
            throw failure
        }
        return texts.map { "[\(target.minimalIdentifier)] \($0)" }
    }
}
