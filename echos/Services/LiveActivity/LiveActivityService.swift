//
//  LiveActivityService.swift
//  echos
//
//  Live Activity для состояния переписки: связь есть/пропала, сообщения
//  отправляются или ждут повтора. Обновления идут локально через
//  ActivityKit — сервер и пуши для этого не нужны.
//

import ActivityKit
import EchosLiveActivityKit
import Foundation
import OSLog
import UIKit

@MainActor
final class LiveActivityService {

    static let shared = LiveActivityService()

    private var lastAddress: String?
    private var lastState: EchosLiveActivityAttributes.ContentState?
    private var endTask: Task<Void, Never>?

    private init() {}

    /// Привести активность к текущему состоянию. Повторный вызов с тем же
    /// состоянием бесплатен: `ChatViewModel` звонит сюда из нескольких мест,
    /// а дёргать ActivityKit без изменений незачем.
    func sync(peerAddress: String,
              peerName: String,
              connectionText: String,
              isEncrypted: Bool,
              sendingCount: Int,
              failedCount: Int) {
        let state = EchosLiveActivityAttributes.ContentState(
            peerName: peerName,
            connectionText: connectionText,
            isEncrypted: isEncrypted,
            sendingCount: sendingCount,
            failedCount: failedCount
        )
        guard state != lastState || peerAddress != lastAddress else {
            return
        }
        lastAddress = peerAddress
        lastState = state

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.liveActivity.info("Live Activities выключены на устройстве")
            return
        }

        let attributes = EchosLiveActivityAttributes(peerAddress: peerAddress)
        let activities = Activity<EchosLiveActivityAttributes>.activities
        let matching = activities.first { $0.attributes.peerAddress == peerAddress }

        // Активность от прежнего собеседника больше не про этот чат.
        for activity in activities where activity.attributes.peerAddress != peerAddress {
            let boxed = UncheckedSendableBox(activity)
            Task { @MainActor in
                await boxed.value.end(dismissalPolicy: .immediate)
            }
        }

        if !shouldShow(state) {
            scheduleEnd(after: state.failedCount > 0 ? .seconds(12) : .seconds(6),
                        peerAddress: peerAddress,
                        finalState: state)
            return
        }

        endTask?.cancel()
        endTask = nil

        if let matching {
            let boxed = UncheckedSendableBox(matching)
            Task { @MainActor in
                await boxed.value.update(using: state)
            }
        } else {
            Task {
                do {
                    _ = try Activity<EchosLiveActivityAttributes>.request(
                        attributes: attributes,
                        contentState: state,
                        pushType: nil
                    )
                    Logger.liveActivity.info("Live Activity запущена для \(peerAddress, privacy: .private(mask: .hash))")
                }
                catch {
                    Logger.liveActivity.error("Live Activity не запустилась: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Закончить активность, если приложение больше не может сказать о
    /// связи ничего полезного: отправка завершилась, а собеседник не на
    /// связи.
    private func shouldShow(_ state: EchosLiveActivityAttributes.ContentState) -> Bool {
        state.isEncrypted || state.sendingCount > 0 || state.failedCount > 0
    }

    /// Не гаснуть мгновенно после последнего изменения: человек, успевший
    /// свернуть приложение, должен увидеть итог — «отправлено» или ошибку.
    private func scheduleEnd(after delay: Duration,
                             peerAddress: String,
                             finalState: EchosLiveActivityAttributes.ContentState) {
        endTask?.cancel()
        endTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  self?.lastAddress == peerAddress,
                  self?.lastState == finalState else {
                return
            }

            for activity in Activity<EchosLiveActivityAttributes>.activities {
                await activity.end(using: finalState, dismissalPolicy: .after(Date().addingTimeInterval(4)))
            }
            self?.lastAddress = nil
            self?.lastState = nil
        }
    }
}
