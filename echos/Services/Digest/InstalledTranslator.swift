//
//  InstalledTranslator.swift
//  echos
//
//  Перевод на устройстве — фреймворком Translation.
//
//  Translation — ещё одна модель Apple на телефоне, отдельная от языковой:
//  по паре небольших моделей на язык, скачиваются они из Настроек или по
//  запросу приложения. Перевод, как и пересказ, никуда не отправляется —
//  поэтому цепочку «перевод → пересказ → перевод» можно строить из
//  зашифрованной переписки, ничего не нарушая.
//
//  Сессия здесь — из iOS 26, без SwiftUI: она умеет только уже скачанные
//  языки. Скачать их может лишь сессия из `.translationTask` — она
//  показывает системный запрос; этим занимается экран пересказа.
//

import Foundation
import Translation

@available(iOS 26.0, *)
struct InstalledTranslator: Translating {

    let source: Locale.Language
    let target: Locale.Language

    /// Вне главного актора: сессия и запросы не Sendable, и рождаются они
    /// здесь же — с главного актора их пришлось бы переправлять, а Swift 6
    /// этого не пропустит. Наружу уходят только строки.
    nonisolated func translate(_ texts: [String]) async throws -> [String] {
        // Пустое переводчику не отдаём: перевести его нечем, а ошибка на
        // одной строке валит всю пачку.
        let indexed = texts.enumerated().filter {
            !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !indexed.isEmpty else {
            return texts
        }

        let session = TranslationSession(installedSource: source, target: target)
        // Пачкой, а не по одной: модель переводчика поднимается один раз.
        // Порядок ответов не обещан — сводим по идентификатору.
        let requests = indexed.map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        let responses = try await session.translations(from: requests)

        var result = texts
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id) {
                result[index] = response.targetText
            }
        }
        return result
    }
}
