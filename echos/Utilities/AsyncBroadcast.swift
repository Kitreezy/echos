//
//  AsyncBroadcast.swift
//  echos
//
//  Мультикаст одного источника событий на нескольких подписчиков.
//
//  Зачем: `AsyncStream` рассчитан на ОДНОГО потребителя. Если по одному и тому
//  же стриму пойдут два `for await`, элементы не продублируются — они
//  РАЗДЕЛЯТСЯ между итераторами непредсказуемым образом. Отсюда и брался
//  костыль «подписка на peerStream живёт всё время жизни сервиса»: повторный
//  `initialize()` добавлял второго потребителя, и часть апдейтов уходила в
//  никуда.
//
//  `AsyncBroadcast` держит по одному continuation на подписчика и рассылает
//  каждое событие всем сразу. По сути это `share()` из swift-async-algorithms,
//  написанный руками — чтобы механика была видна, а не спрятана за оператором.
//

import Foundation

@MainActor
final class AsyncBroadcast<Element: Sendable> {

    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var latest: Element?
    private let replaysLatest: Bool
    private var isFinished = false

    /// - Parameter replaysLatest: отдавать новому подписчику последнее событие.
    ///   Нужно для состояния (список пиров): экран, подписавшийся позже, сразу
    ///   видит актуальную картину, а не ждёт следующего изменения.
    ///   Для разовых событий (сообщение, typing) — не нужно.
    init(replaysLatest: Bool = false) {
        self.replaysLatest = replaysLatest
    }

    /// Новый независимый поток. Каждое обращение к свойству — отдельный подписчик.
    var stream: AsyncStream<Element> {
        AsyncStream { continuation in
            guard !isFinished else {
                continuation.finish()
                return
            }

            let id = UUID()
            continuations[id] = continuation

            if replaysLatest, let latest {
                continuation.yield(latest)
            }

            // Подписка снимается сама, когда потребитель выходит из `for await`
            // или его задачу отменяют.
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    /// Сколько живых подписчиков сейчас. Используется в тестах.
    var subscriberCount: Int {
        continuations.count
    }

    func yield(_ element: Element) {
        guard !isFinished else {
            return
        }

        latest = element

        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    func finish() {
        isFinished = true

        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
