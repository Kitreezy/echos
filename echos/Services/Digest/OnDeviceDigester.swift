//
//  OnDeviceDigester.swift
//  echos
//
//  Пересказ моделью Apple на устройстве — через FoundationModels.
//
//  Модель небольшая, около трёх миллиардов параметров, и это определяет
//  всё устройство пересказа:
//
//  Ответ — не текст, а тип. `@Generable` описывает структуру, и модель
//  при декодировании физически не может выйти за её схему: нет «вот ваш
//  JSON:», нет лишних полей, нет разбора строк. Описания в `@Guide` —
//  часть промпта, а ограничения вроде `.maximumCount` — часть декодера.
//
//  Окно мало, поэтому длинное читается частями, и каждая часть — в новой
//  сессии: сессия копит историю, и вторая часть в старой сессии ехала бы
//  вместе с первой и её ответом.
//
//  Инструкции — по-английски: на них модель обучалась следовать лучше
//  всего. Язык ответа задаётся отдельно — «как в переписке». Русского среди
//  языков модели нет вовсе: такую переписку пересказывает цепочка через
//  перевод на устройстве — см. `plan(for:)` и DigestViewModel.
//
//  Модель ничего не умеет делать, кроме ответа по схеме: инструментов у
//  сессии нет. Поэтому чужое сообщение вида «забудь инструкции» худшее,
//  чего добьётся, — неверного пересказа, а не действия от имени человека.
//

import Foundation
import FoundationModels
import OSLog
import Translation

@available(iOS 26.0, *)
@Generable(description: "A summary of chat messages the user missed")
struct GeneratedDigest {
    // Порядок полей — порядок генерации. Главное первым: при потоковом
    // выводе оно появляется на экране раньше, пока дописывается остальное.
    @Guide(description: "Main topics of the messages, most important first. One short sentence each.",
           .maximumCount(4))
    var points: [String]

    @Guide(description: "Questions the other person asked the user that still wait for an answer. Empty if there are none.",
           .maximumCount(3))
    var questions: [GeneratedQuestion]

    @Guide(description: "Agreed times, places or tasks: who does what and when. Empty if there are none.",
           .maximumCount(3))
    var plans: [String]
}

/// Вопрос вместе с вариантами ответа — в том же проходе, что и пересказ.
/// Отдельным запросом пришлось бы заново отдать модели всю переписку:
/// у сессий нет общей памяти, а окно и так почти занято ею.
@available(iOS 26.0, *)
@Generable(description: "A question waiting for the user's answer")
struct GeneratedQuestion {
    // Номер — первым: модель сначала находит сообщение, потом пересказывает
    // вопрос из него. Наоборот она чаще ссылается на соседнее.
    @Guide(description: "The number in square brackets of the message where the question was asked.")
    var messageNumber: Int

    @Guide(description: "The question, as one short sentence.")
    var question: String

    // Сначала вопрос, потом ответы: так модель пишет ответы, уже
    // сформулировав, на что отвечает.
    @Guide(description: """
        Replies the user could send to the other person, written as the user, one short sentence \
        each. Each reply gives a different answer: agree, decline, or ask to clarify.
        """,
           .count(2...3))
    var replies: [String]
}

@available(iOS 26.0, *)
@Generable(description: "Notes on one part of a longer chat")
struct PartNotes {
    @Guide(description: "Short notes keeping names, times, places, questions and agreements.",
           .maximumCount(5))
    var notes: [String]
}

@available(iOS 26.0, *)
@MainActor
final class OnDeviceDigester: Digesting {

    private let model = SystemLanguageModel.default

    /// Сколько токенов окна держать под ответ. Это же — потолок ответа:
    /// модель, которая разговорилась, упрётся в него, а не в край окна.
    /// Варианты ответа добавили к пересказу до девяти коротких фраз —
    /// запас под них взят из места под переписку.
    private let responseReserve = 1000

    /// Сколько раз сжимать заметки в заметки. На практике хватает одного:
    /// из части в полторы тысячи токенов выходит пять коротких строк.
    private let maximumRounds = 3

    /// Жадная выборка — всегда самый вероятный токен. Пересказу фантазия
    /// не нужна, а одинаковый ответ на одинаковую переписку проще проверять.
    private var options: GenerationOptions {
        GenerationOptions(sampling: .greedy, maximumResponseTokens: responseReserve)
    }

    /// Сессия, прогретая заранее. Забирается первым же пересказом.
    private var warmSession: LanguageModelSession?

    var availability: DigestAvailability {
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .never
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notNow("Пересказ делает Apple Intelligence прямо на телефоне. Включите его в Настройках → Apple Intelligence и Siri.")
        case .unavailable(.modelNotReady):
            return .notNow("Модель ещё загружается на телефон. Попробуйте чуть позже.")
        case .unavailable:
            return .notNow("Модель на устройстве сейчас недоступна.")
        }
    }

    /// Язык-посредник для перевода. Английский — не только потому, что
    /// модель его знает: на нём она и обучалась следовать инструкциям лучше
    /// всего, и пары с ним у переводчика есть почти для любого языка.
    private let pivot = Locale.Language(identifier: "en")

    func plan(for messages: [Message]) async -> DigestPlan {
        // Не распознали — пробуем напрямую: худшее, что будет, — та же
        // ошибка о языке от модели, только позже.
        guard let language = DigestTranscript.dominantLanguage(of: messages),
              !model.supportedLanguages.contains(where: { $0.languageCode == language.languageCode }) else {
            return .direct
        }

        // Переводить надо в обе стороны: туда — переписку, обратно — пересказ.
        let languages = LanguageAvailability()
        let there = await languages.status(from: language, to: pivot)
        let back = await languages.status(from: pivot, to: language)
        switch (there, back) {
        case (.installed, .installed):
            return .translate(from: language, via: pivot)
        case (.supported, .supported), (.supported, .installed), (.installed, .supported):
            return .download(from: language, via: pivot)
        default:
            return .impossible("Модель на устройстве не знает языка этой переписки (\(language.displayName)), "
                + "и перевести его на телефоне нельзя. Список языков задаёт Apple.")
        }
    }

    func translator(from source: Locale.Language, to target: Locale.Language) -> any Translating {
        InstalledTranslator(source: source, target: target)
    }

    /// Загрузить модель в память, пока человек читает чат. Первый ответ
    /// без этого заметно дольше: веса поднимаются с диска.
    func prepare() {
        guard case .ready = availability, warmSession == nil else {
            return
        }
        let session = LanguageModelSession(model: model, instructions: Self.digestInstructions)
        session.prewarm()
        warmSession = session
    }

    func digest(of messages: [Message], with peerName: String) -> AsyncThrowingStream<DigestProgress, Error> {
        let lines = DigestTranscript.lines(of: messages, with: peerName)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(lines, of: messages, with: peerName, into: continuation)
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: DigestFailure(message: Self.explain(error)))
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    // Не всё приходит перечислением: сбой внутри системной
                    // службы модели долетает сырым NSError. «Доступна» в
                    // `availability` ещё не значит «ответит».
                    Logger.digest.error("Model failed: \(error)")
                    continuation.finish(throwing: DigestFailure(message: "Модель на устройстве не ответила. Попробуйте позже."))
                }
            }
            // Закрыли экран — модель останавливается, а не дописывает
            // пересказ, который никто не увидит.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Пересказ

    private func run(_ lines: [String],
                     of messages: [Message],
                     with peerName: String,
                     into continuation: AsyncThrowingStream<DigestProgress, Error>.Continuation) async throws {
        let budget = await transcriptBudget()
        var lines = lines
        var chunks = await DigestTranscript.chunks(of: lines, budget: budget, measure: measure)

        // Длинное — частями: каждая часть в заметки, заметки — заново
        // в части, пока всё не уляжется в одно окно.
        var round = 0
        while chunks.count > 1 {
            round += 1
            guard round <= maximumRounds else {
                // Не сошлось — пересказываем самое свежее, а не падаем.
                chunks = [chunks[chunks.count - 1]]
                break
            }
            var notes: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                continuation.yield(.reading(part: index + 1, total: chunks.count))
                let session = LanguageModelSession(model: model, instructions: Self.notesInstructions)
                let response = try await session.respond(to: Self.prompt(chunk, with: peerName),
                                                         generating: PartNotes.self,
                                                         options: options)
                notes += response.content.notes
            }
            lines = notes
            chunks = await DigestTranscript.chunks(of: lines, budget: budget, measure: measure)
        }

        let session = takeWarmSession()
        let stream = session.streamResponse(to: Self.prompt(chunks.first ?? [], with: peerName),
                                            generating: GeneratedDigest.self,
                                            options: options)
        // Каждый снимок — вся структура целиком на текущий момент: поля,
        // до которых модель не дошла, пустые, последний пункт — недописан.
        for try await snapshot in stream {
            continuation.yield(.draft(Digest(snapshot.content, numbering: messages)))
        }
    }

    private func takeWarmSession() -> LanguageModelSession {
        defer { warmSession = nil }
        return warmSession ?? LanguageModelSession(model: model, instructions: Self.digestInstructions)
    }

    // MARK: - Окно

    /// Сколько токенов окна остаётся на переписку: всё, кроме инструкций,
    /// схемы ответа и места под сам ответ. Считается по пересказу — его
    /// инструкции и схема длиннее, чем у заметок.
    ///
    /// Счёт — вспомогательный: не удалось посчитать точно — считаем по
    /// оценке, но пересказ из-за этого не срываем.
    private func transcriptBudget() async -> Int {
        let framing = 60  // «The other person is …» и заголовок над перепиской
        // Схему модель тоже читает: она уходит в промпт вместе с описаниями
        // полей. До 26.4 её не измерить — берём с запасом.
        var overhead = DigestTranscript.estimatedTokens(Self.digestInstructions) + 400
        if #available(iOS 26.4, *),
           let instructions = try? await model.tokenCount(for: Instructions(Self.digestInstructions)),
           let schema = try? await model.tokenCount(for: GeneratedDigest.generationSchema) {
            overhead = instructions + schema
        }
        return model.contextSize - overhead - responseReserve - framing
    }

    private func measure(_ text: String) async -> Int {
        if #available(iOS 26.4, *), let exact = try? await model.tokenCount(for: text) {
            return exact
        }
        return DigestTranscript.estimatedTokens(text)
    }

    // MARK: - Промпты

    private static let digestInstructions = """
        You summarize chat messages the user missed. Each line is "[number] author: text". \
        Lines by "Я" are written by the user, other lines by the other person.
        Use only what is written in the messages. Never invent names, times, places or facts.
        Write every item as one short sentence in the same language as the messages.
        Replies to questions are written by the user to the other person: natural, friendly, not formal.
        """

    private static let notesInstructions = """
        You read one part of a longer chat and write short notes for a summary made later. \
        Each line is "[number] author: text". Lines by "Я" are written by the user, other lines by the other person.
        Keep names, times, places, questions and agreements. Use only what is written.
        Start every note about a question with the number of its message in square brackets, like "[12] ..."
        Write the notes in the same language as the messages.
        """

    private static func prompt(_ lines: [String], with peerName: String) -> String {
        "The other person is \(peerName). Messages:\n" + lines.joined(separator: "\n")
    }

    // MARK: - Ошибки

    static func explain(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .unsupportedLanguageOrLocale:
            return "Модель на устройстве не работает с языком этой переписки: список языков задаёт Apple."
        case .guardrailViolation, .refusal:
            return "Модель отказалась пересказывать эту переписку: встроенный фильтр Apple счёл её содержание чувствительным."
        case .exceededContextWindowSize:
            return "Переписка не поместилась в память модели."
        case .assetsUnavailable:
            return "Модель сейчас недоступна — возможно, ещё загружается. Попробуйте позже."
        case .rateLimited:
            return "Система притормозила модель. Попробуйте ещё раз."
        case .concurrentRequests:
            return "Модель занята предыдущим пересказом."
        case .decodingFailure, .unsupportedGuide:
            return "Модель ответила не по форме. Попробуйте ещё раз."
        @unknown default:
            return "Пересказ не получился: \(error.localizedDescription)"
        }
    }
}

@available(iOS 26.0, *)
extension Digest {
    /// `numbering` — сообщения в том порядке, в каком модель видела их
    /// номера: по ним номер вопроса становится ссылкой на сообщение.
    init(_ partial: GeneratedDigest.PartiallyGenerated, numbering messages: [Message]) {
        self.init(points: partial.points ?? [],
                  // Вопрос без текста — ещё не начатый: в черновик не идёт.
                  questions: (partial.questions ?? []).compactMap { question in
                      guard let text = question.question, !text.isEmpty else {
                          return nil
                      }
                      return DigestQuestion(text: text,
                                            replies: question.replies ?? [],
                                            messageID: DigestTranscript.message(numbered: question.messageNumber,
                                                                                in: messages)?.id)
                  },
                  plans: partial.plans ?? [])
    }
}
