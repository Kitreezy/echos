//
//  DigestViewModel.swift
//  echos
//
//  Состояние экрана пересказа: поток от модели — в то, что видит человек.
//

import Foundation
import Observation

@MainActor
@Observable
final class DigestViewModel {

    enum State: Equatable {
        /// Модель ещё не ответила ни словом.
        case starting
        /// Длинная переписка читается частями.
        case reading(part: Int, of: Int)
        /// Пересказ пишется: на экране то, что уже есть.
        case writing(Digest)
        case done(Digest)
        case failed(String)
    }

    private(set) var state: State = .starting

    let peerName: String
    let messageCount: Int

    private let messages: [Message]
    private let digester: any Digesting

    init(messages: [Message], peerName: String, digester: any Digesting) {
        self.messages = messages
        self.peerName = peerName
        self.messageCount = messages.count
        self.digester = digester
    }

    /// Пересказать. Отмена задачи — закрытый экран — останавливает модель.
    func start() async {
        if case .notNow(let reason) = digester.availability {
            state = .failed(reason)
            return
        }
        if let problem = digester.languageProblem(in: messages) {
            state = .failed(problem)
            return
        }
        state = .starting

        var latest = Digest()
        do {
            for try await progress in digester.digest(of: messages, with: peerName) {
                switch progress {
                case let .reading(part, total):
                    state = .reading(part: part, of: total)
                case let .draft(digest):
                    latest = digest
                    state = .writing(digest)
                }
            }
            state = latest.isEmpty
                ? .failed("Модель не нашла в пропущенном, что пересказать.")
                : .done(latest)
        } catch is CancellationError {
            // Закрыли экран — сказать некому.
        } catch let failure as DigestFailure {
            state = .failed(failure.message)
        } catch {
            state = .failed("Пересказ не получился.")
        }
    }
}
