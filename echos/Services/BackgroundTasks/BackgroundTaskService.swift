//
//  BackgroundTaskService.swift
//  echos
//
//  Фоновые задачи системы: ротация секретов и профилактика базы
//  (BGProcessingTask), свежий снапшот для виджета (BGAppRefreshTask).
//
//  Договор с системой: обработчики регистрируются до конца запуска
//  приложения, каждый запуск заканчивается setTaskCompleted — иначе
//  система быстро перестаёт давать слоты. Планирование следующего запуска
//  — сразу после выполнения текущего, а не жёстко по расписанию: фон
//  у iOS — просьба, не обещание.
//

import BackgroundTasks
import CoreData
import Foundation
import OSLog
import UIKit

/// Идентификаторы, разрешённые в Info.plist (BGTaskSchedulerPermittedIdentifiers).
enum BackgroundTaskID: String, Sendable {
    /// Ротация секретов + профилактика базы.
    case secretRotation = "com.kitreezy.echos.secret-rotation"
    /// Обновление снапшота виджета.
    case widgetRefresh = "com.kitreezy.echos.widget-refresh"
}

/// Как часто просить слот. Большие интервалы — у системы мало слотов,
/// и лучше просить редко о нужном, чем часто о любом.
enum BackgroundTaskPolicy {
    /// Секреты перетасовывать чаще незачем: запись не гниёт.
    static let rotationInterval: TimeInterval = 24 * 60 * 60
    /// Виджет должен быть свежим к утру, не к минуте.
    static let refreshInterval: TimeInterval = 6 * 60 * 60
}

@MainActor
final class BackgroundTaskService {

    /// Продовый экземпляр. Работу собираем здесь же — сервис это и есть
    /// корень этих двух задач. Через вычисляемое свойство, а не статический
    /// инициализатор: сборка работы требует главного актора, а статик-let
    /// его инициализатором не считается.
    @MainActor
    static var shared: BackgroundTaskService {
        if let instance {
            return instance
        }
        let service = BackgroundTaskService(
            rotateSecrets: {
                let rotation = SecretRotation(store: KeychainSecretStore(service: "com.echos.identity"))
                return try rotation.rotate()
            },
            repairDatabase: {
                await DatabaseRepair(
                    countMessages: {
                        let context = PersistenceController.shared.container.viewContext
                        let request: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
                        return try context.count(for: request)
                    },
                    reindexIfNeeded: {
                        guard UserSettings.searchIndexVersion != SpotlightIndex.version else {
                            return false
                        }
                        await SpotlightIndex.shared.rebuild(messages: MessageStore(),
                                                            people: KnownPeerStore())
                        return true
                    }
                ).repair()
            },
            refreshWidget: {
                let viewModel = ChatViewModel()
                let conversations = await viewModel.getAllConversations()
                WidgetSnapshotWriter.update(with: conversations)
            }
        )
        instance = service
        return service
    }

    @MainActor
    private static var instance: BackgroundTaskService?

    private let rotateSecrets: @MainActor () throws -> SecretRotationResult
    private let repairDatabase: @MainActor () async -> DatabaseRepairResult
    private let refreshWidget: @MainActor () async -> Void

    init(rotateSecrets: @escaping @MainActor () throws -> SecretRotationResult,
         repairDatabase: @escaping @MainActor () async -> DatabaseRepairResult,
         refreshWidget: @escaping @MainActor () async -> Void) {
        self.rotateSecrets = rotateSecrets
        self.repairDatabase = repairDatabase
        self.refreshWidget = refreshWidget
    }

    // MARK: - Регистрация

    /// Обработчики должны быть зарегистрированы до конца запуска —
    /// UIKit держит приложение, пока didFinishLaunching не вернулся, и
    /// система после него launchHandler уже не подменит.
    func registerHandlers() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskID.secretRotation.rawValue,
            using: nil
        ) { task in
            // launchHandler — вне главного актора; вся работа, включая
            // expirationHandler, уходит туда целиком.
            Task { @MainActor [weak self] in
                self?.handleSecretRotation(task)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskID.widgetRefresh.rawValue,
            using: nil
        ) { task in
            Task { @MainActor [weak self] in
                self?.handleWidgetRefresh(task)
            }
        }
    }

    // MARK: - Планирование

    /// Запланировать обе задачи. Вызвать при запуске и после каждого
    /// выполнения. Система может и не дать слот — это её право.
    func scheduleAll() {
        scheduleSecretRotation()
        if UIApplication.shared.backgroundRefreshStatus != .denied {
            scheduleWidgetRefresh()
        } else {
            Logger.lifecycle.info("Фоновое обновление выключено человеком — виджет обновляется только из приложения")
        }
    }

    private func scheduleSecretRotation() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskID.secretRotation.rawValue)
        request.earliestBeginDate = Date.now.addingTimeInterval(BackgroundTaskPolicy.rotationInterval)
        // Секреты и база — своё устройство, сеть не нужна.
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        submit(request)
    }

    private func scheduleWidgetRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskID.widgetRefresh.rawValue)
        request.earliestBeginDate = Date.now.addingTimeInterval(BackgroundTaskPolicy.refreshInterval)
        submit(request)
    }

    private func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.lifecycle.error("Фоновую задачу не приняли: \(request.identifier, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Выполнение

    private func handleSecretRotation(_ task: BGTask) {
        guard let processing = task as? BGProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }
        processing.expirationHandler = {
            processing.setTaskCompleted(success: false)
        }

        Task { [weak self] in
            guard let self else {
                processing.setTaskCompleted(success: false)
                return
            }
            var success = true

            do {
                let rotation = try rotateSecrets()
                Logger.identity.info("Ротация секретов: переписано \(rotation.rotated), вылечено \(rotation.healed), заперт: \(rotation.skippedLocked)")
            } catch {
                success = false
                Logger.identity.error("Ротация секретов не удалась: \(error, privacy: .public)")
            }

            let repair = await repairDatabase()
            if repair.messageCount == nil {
                success = false
            }
            Logger.persistence.info("Профилактика базы: сообщений \(String(describing: repair.messageCount)), индекс пересобран: \(repair.reindexed)")

            // Слот отработал — просим следующий, пока система не забыла.
            scheduleSecretRotation()
            processing.setTaskCompleted(success: success)
        }
    }

    private func handleWidgetRefresh(_ task: BGTask) {
        guard let refresh = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }
        refresh.expirationHandler = {
            refresh.setTaskCompleted(success: false)
        }

        Task { [weak self] in
            await self?.refreshWidget()
            self?.scheduleWidgetRefresh()
            refresh.setTaskCompleted(success: true)
        }
    }
}
