//
//  BackgroundLease.swift
//  echos
//
//  Полминуты жизни после сворачивания.
//
//  Зачем: iOS замораживает свёрнутое приложение через несколько секунд, и
//  соединение с релеем с ним. Сообщение, пришедшее в это время, пропадает —
//  и уведомить о нём некому. `beginBackgroundTask` даёт около тридцати
//  секунд: этого хватает на «свернул ответить в другом приложении и
//  вернулся», а больше система и не даст. Дальше — честно отключаемся.
//

import UIKit

@MainActor
final class BackgroundLease {

    /// Сколько держим соединение после сворачивания. Меньше системного
    /// потолка, чтобы отключиться самим, а не быть убитыми.
    static let duration: Duration = .seconds(25)

    private let duration: Duration
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var expiry: Task<Void, Never>?

    /// - Parameter duration: сколько держать. По умолчанию — сколько даёт
    ///   система; тесты ставят меньше.
    init(duration: Duration = BackgroundLease.duration) {
        self.duration = duration
    }

    /// Взять отсрочку. `onExpire` вызывается один раз — когда время вышло
    /// или система потребовала закончить раньше.
    func begin(onExpire: @escaping @MainActor () -> Void) {
        end()

        task = UIApplication.shared.beginBackgroundTask(withName: "echos.relay.grace") { [weak self] in
            Task { @MainActor in
                self?.expire(onExpire)
            }
        }

        let duration = self.duration
        expiry = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else {
                return
            }
            self?.expire(onExpire)
        }
    }

    /// Вернулись раньше срока — отсрочка больше не нужна.
    func end() {
        expiry?.cancel()
        expiry = nil
        guard task != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }

    private func expire(_ onExpire: @MainActor () -> Void) {
        guard task != .invalid else {
            return
        }
        onExpire()
        end()
    }
}
