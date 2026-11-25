//
//  DatabaseRepair.swift
//  echos
//
//  Профилактика базы: убедиться, что хранилище открывается и считается,
//  а индекс системного поиска согласован с базой. Разрушительного здесь
//  ничего нет: чинить — значит сначала заметить рассинхрон, и пересборка
//  индекса — самое тяжёлое, что фон может себе позволить.
//

import Foundation
import OSLog

/// Итог одного прохода профилактики.
struct DatabaseRepairResult: Equatable, Sendable {
    /// Сколько сообщений насчитала база. `nil` — посчитать не удалось.
    var messageCount: Int?
    /// Индекс поиска был рассинхронизирован и пересобран.
    var reindexed = false
}

/// Профилактика Core Data и поискового индекса. Зависимости — замыкания:
/// фоновый сервис собирает продовую конфигурацию, тест — свою.
struct DatabaseRepair: Sendable {

    /// Посчитать сообщения в базе. Бросает, если база не открывается.
    var countMessages: @MainActor () throws -> Int
    /// Пересобрать поисковый индекс, если версия уехала. Возвращает,
    /// пересобирал ли.
    var reindexIfNeeded: @MainActor () async -> Bool

    @MainActor
    func repair() async -> DatabaseRepairResult {
        var result = DatabaseRepairResult()

        do {
            result.messageCount = try countMessages()
        } catch {
            // База не открылась: пересборка индекса на мёртвую базу — зря,
            // а чинить файлы Core Data из фона — нет инструмента. Фиксируем
            // неудачу неудачей — система даст ещё попытку.
            Logger.persistence.error("Профилактика: база не считается: \(error, privacy: .public)")
            return result
        }

        result.reindexed = await reindexIfNeeded()
        return result
    }
}
