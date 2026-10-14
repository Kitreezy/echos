//
//  DigestTranscript.swift
//  echos
//
//  Переписка в том виде, в каком её читает модель, и нарезка под её окно.
//
//  Окно у модели на устройстве — 4096 токенов на всё сразу: инструкции,
//  схему ответа, саму переписку и ответ. Вечер активной переписки туда не
//  влезает. Поэтому длинное читается частями: каждая часть сжимается в
//  заметки, заметки — в пересказ. Здесь только нарезка; сколько токенов в
//  строке, решает тот, кто её вызывает: точный счёт есть у модели лишь с
//  iOS 26.4, до неё — оценка.
//

import Foundation
import NaturalLanguage

enum DigestTranscript {

    /// По строке на сообщение: «кто: что». Переводы строк внутри сообщения
    /// схлопываются — иначе продолжение сообщения выглядит для модели как
    /// реплика без автора.
    static func lines(of messages: [Message], with peerName: String) -> [String] {
        messages.map { message in
            let author = message.isFromMe ? "Я" : peerName
            let content = message.mosaic == nil
                ? message.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                // Мозаика в текстовой форме — сетка эмодзи. Пересказывать
                // её нечего, а токенов она съедает как абзац.
                : "[рисунок]"
            return "\(author): \(content)"
        }
    }

    /// Части не больше `budget` токенов. Порядок строк сохраняется, строки
    /// не разрываются — кроме той, что одна не влезает: её хвост отрезается.
    static func chunks(of lines: [String],
                       budget: Int,
                       measure: (String) async throws -> Int) async rethrows -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []
        var used = 0

        for line in lines {
            var line = line
            var cost = try await measure(line) + 1  // +1 — перевод строки
            if cost > budget {
                line = try await truncate(line, to: budget - 1, measure: measure)
                cost = try await measure(line) + 1
            }
            if used + cost > budget, !current.isEmpty {
                chunks.append(current)
                current = []
                used = 0
            }
            current.append(line)
            used += cost
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    /// Укоротить строку до `budget` токенов. Токены по символам не делятся
    /// ровно, поэтому режется с запасом и перемеривается.
    private static func truncate(_ line: String,
                                 to budget: Int,
                                 measure: (String) async throws -> Int) async rethrows -> String {
        var text = line
        var cost = try await measure(text)
        while cost > budget, text.count > 1 {
            let keep = max(1, text.count * budget / cost * 9 / 10)
            text = String(text.prefix(keep)) + "…"
            cost = try await measure(text)
        }
        return text
    }

    /// Язык переписки — по всему тексту сразу: короткое «ок» одно по себе
    /// языка не выдаёт. Распознаватель — тоже модель на устройстве, из
    /// NaturalLanguage, и тоже ничего никуда не отправляет.
    static func dominantLanguage(of messages: [Message]) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(messages.filter { $0.mosaic == nil }.map(\.text).joined(separator: "\n"))
        guard let language = recognizer.dominantLanguage, language != .undetermined else {
            return nil
        }
        return Locale.Language(identifier: language.rawValue)
    }

    /// Оценка без модели: с запасом, по два символа на токен. Для латиницы
    /// честнее четыре, но кириллица дробится мельче, а ошибиться в большую
    /// сторону дешевле: лишняя часть стоит секунды, переполненное окно —
    /// ошибки.
    static func estimatedTokens(_ text: String) -> Int {
        text.count / 2 + 1
    }
}
