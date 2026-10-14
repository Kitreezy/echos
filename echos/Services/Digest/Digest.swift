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

/// Что сказать человеку, если пересказ не получился.
struct DigestFailure: Error, Equatable {
    let message: String
}

/// Кто пересказывает. В приложении — модель на устройстве, в тестах — заглушка.
@MainActor
protocol Digesting {
    var availability: DigestAvailability { get }

    /// Почему эти сообщения не пересказать, если не пересказать: модель
    /// знает не все языки, и узнать это лучше до вызова, а не от неё.
    func languageProblem(in messages: [Message]) -> String?

    /// Подготовить модель заранее, пока человек ещё не нажал кнопку.
    func prepare()

    /// Пересказ сообщений `messages` переписки с `peerName`.
    func digest(of messages: [Message], with peerName: String) -> AsyncThrowingStream<DigestProgress, Error>
}

/// Заглушка для систем, где модели нет. Кнопки при ней нет, поэтому
/// `digest` вызываться не должен — но если вызовут, ответ честный.
struct UnavailableDigester: Digesting {
    var availability: DigestAvailability { .never }

    func languageProblem(in messages: [Message]) -> String? { nil }

    func prepare() {}

    func digest(of messages: [Message], with peerName: String) -> AsyncThrowingStream<DigestProgress, Error> {
        AsyncThrowingStream { $0.finish(throwing: DigestFailure(message: "На этом устройстве пересказ недоступен.")) }
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
