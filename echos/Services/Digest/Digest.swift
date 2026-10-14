//
//  Digest.swift
//  echos
//
//  Пересказ пропущенного: что человек получает вместо того, чтобы листать.
//
//  Пересказ делается только на устройстве. Переписка шифруется сквозным
//  образом, релей её не видит — и отправить её языковой модели в облако
//  значило бы отдать открытый текст тому, кому его не показывает даже свой
//  сервер. Поэтому здесь нет выбора «облако или устройство»: либо модель
//  на телефоне, либо пересказа нет.
//
//  Всё в этом файле от модели не зависит и собирается под iOS 18: экран,
//  состояние и тесты живут без FoundationModels, а сама модель — за
//  протоколом `Digesting`.
//

import Foundation

/// Пересказ. Три вопроса, с которыми человек открывает чат после перерыва:
/// о чём говорили, чего от меня ждут, о чём договорились.
struct Digest: Equatable, Sendable {
    var points: [String] = []
    var questions: [String] = []
    var plans: [String] = []

    var isEmpty: Bool {
        points.isEmpty && questions.isEmpty && plans.isEmpty
    }
}

/// Ход работы. Длинная переписка в окно модели не влезает и читается
/// частями — человеку стоит видеть, что дело идёт, а не пустой экран.
enum DigestProgress: Equatable, Sendable {
    /// Читается часть `part` из `of`. Только для длинной переписки.
    case reading(part: Int, of: Int)
    /// Черновик пересказа: поля дописываются по мере генерации.
    case draft(Digest)
}

/// Можно ли пересказывать на этом устройстве.
enum DigestAvailability: Equatable, Sendable {
    case ready
    /// Сейчас нельзя, но может стать можно: Apple Intelligence выключен,
    /// модель ещё скачивается. Кнопку показываем — с объяснением.
    case notNow(String)
    /// Нельзя и не станет: старая iOS или устройство без Apple Intelligence.
    /// Кнопки нет вовсе — обещать то, чего не будет, незачем.
    case never
}

/// Как пересказывать эту переписку. Модель знает не все языки, и узнать
/// это лучше до вызова, а не от неё.
enum DigestPlan: Equatable, Sendable {
    /// Язык модели знаком — пересказываем как есть.
    case direct
    /// Модель языка не знает, но переводчик на устройстве знает: переписка
    /// переводится на язык-посредник, пересказ — обратно.
    case translate(from: Locale.Language, via: Locale.Language)
    /// То же, но языки для перевода ещё не скачаны. Скачивание — с
    /// согласия человека, через системный запрос.
    case download(from: Locale.Language, via: Locale.Language)
    /// Ни модель, ни переводчик языка не знают.
    case impossible(String)
}

/// Перевод списка строк с одного языка на другой — по строке на строку.
@MainActor
protocol Translating {
    func translate(_ texts: [String]) async throws -> [String]
}

/// Что сказать человеку, если пересказ не получился.
struct DigestFailure: Error, Equatable {
    let message: String
}

/// Кто пересказывает. В приложении — модель на устройстве, в тестах — заглушка.
@MainActor
protocol Digesting {
    var availability: DigestAvailability { get }

    /// Как пересказывать эти сообщения: напрямую, через перевод или никак.
    func plan(for messages: [Message]) async -> DigestPlan

    /// Переводчик для цепочки. Языки к этому моменту уже скачаны.
    func translator(from source: Locale.Language, to target: Locale.Language) -> any Translating

    /// Подготовить модель заранее, пока человек ещё не нажал кнопку.
    func prepare()

    /// Пересказ сообщений `messages` переписки с `peerName`.
    func digest(of messages: [Message], with peerName: String) -> AsyncThrowingStream<DigestProgress, Error>
}

/// Заглушка для систем, где модели нет. Кнопки при ней нет, поэтому
/// `digest` вызываться не должен — но если вызовут, ответ честный.
struct UnavailableDigester: Digesting {
    var availability: DigestAvailability { .never }

    func plan(for messages: [Message]) async -> DigestPlan { .direct }

    func translator(from source: Locale.Language, to target: Locale.Language) -> any Translating {
        NoTranslator()
    }

    func prepare() {}

    func digest(of messages: [Message], with peerName: String) -> AsyncThrowingStream<DigestProgress, Error> {
        AsyncThrowingStream { $0.finish(throwing: DigestFailure(message: "На этом устройстве пересказ недоступен.")) }
    }
}

private struct NoTranslator: Translating {
    func translate(_ texts: [String]) async throws -> [String] {
        throw DigestFailure(message: "На этом устройстве перевод недоступен.")
    }
}

extension Locale.Language {
    /// Название языка для человека — на языке его системы.
    var displayName: String {
        languageCode.flatMap { Locale.current.localizedString(forLanguageCode: $0.identifier) }
            ?? minimalIdentifier
    }
}

enum Digesters {

    /// Пересказчик для этой системы. Проверка версии — в рантайме: echos
    /// запускается на iOS 18, где фреймворка нет вовсе.
    @MainActor
    static func system() -> any Digesting {
        if #available(iOS 26.0, *) {
            return OnDeviceDigester()
        }
        return UnavailableDigester()
    }
}
