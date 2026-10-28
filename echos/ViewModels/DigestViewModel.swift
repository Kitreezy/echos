//
//  DigestViewModel.swift
//  echos
//
//  Состояние экрана пересказа: поток от модели — в то, что видит человек.
//
//  Если модель не знает языка переписки, пересказ собирается цепочкой из
//  двух моделей на устройстве: переводчик переводит сообщения на язык,
//  который модель знает, модель пересказывает, переводчик переводит
//  пересказ обратно. Цепочка живёт здесь, а не в пересказчике: каждое
//  звено подменяется в тестах отдельно, и видно, что куда пришло.
//

import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class DigestViewModel {

    enum State: Equatable {
        /// Модель ещё не ответила ни словом.
        case starting
        /// Языки для перевода не скачаны — нужно согласие человека.
        case needsDownload(language: String)
        /// Человек согласился, система качает. Сколько осталось, система
        /// приложению не говорит — только «готово» или «нет».
        case downloading(language: String)
        /// Переписка переводится на язык модели.
        case translating
        /// Длинная переписка читается частями.
        case reading(part: Int, total: Int)
        /// Пересказ пишется: на экране то, что уже есть.
        case writing(Digest)
        /// Пересказ пишется на языке-посреднике — показывать его рано.
        case composing
        /// Готовый пересказ переводится обратно.
        case translatingBack
        case done(Digest)
        case failed(String)
    }

    private(set) var state: State = .starting

    /// Через какой язык шёл перевод — для подписи под пересказом. `nil` —
    /// пересказано напрямую.
    private(set) var translatedVia: String?

    /// Что скачать перед переводом. Экран отдаёт это системе через
    /// `.translationTask`: скачать языки можно только так.
    private(set) var pendingDownload: (source: Locale.Language, target: Locale.Language)?

    /// На какие сообщения человек уже ответил. Вопросы из них отмечаются
    /// отвеченными, и вариантов под ними больше нет.
    var answered: Set<UUID> = []

    /// Сколько вопросов готового пересказа ещё ждут ответа.
    var unansweredCount: Int {
        guard case let .done(digest) = state else {
            return 0
        }
        return digest.questions.filter { !isAnswered($0) }.count
    }

    func isAnswered(_ question: DigestQuestion) -> Bool {
        question.messageID.map(answered.contains) ?? false
    }

    /// Как часто спрашивать систему, скачались ли языки.
    var downloadPollInterval: Duration = .seconds(2)

    let peerName: String
    let messageCount: Int

    private let messages: [Message]
    private let digester: any Digesting

    init(messages: [Message], peerName: String, digester: any Digesting) {
        self.messages = messages
        self.peerName = peerName
        self.messageCount = messages.count
        self.digester = digester
    }

    /// Пересказать, если пересказа ещё нет. Экран живёт, пока не сменилось
    /// пропущенное: открыть его второй раз — значит увидеть готовое, а не
    /// ждать модель заново. Прерванное закрытием — начинается сначала.
    func startIfNeeded() async {
        if case .done = state {
            return
        }
        await start()
    }

    /// Пересказать. Отмена задачи — закрытый экран — останавливает модель.
    func start() async {
        if case .notNow(let reason) = digester.availability {
            state = .failed(reason)
            return
        }
        state = .starting
        translatedVia = nil
        pendingDownload = nil

        do {
            switch await digester.plan(for: messages) {
            case .direct:
                let digest = try await compose(from: messages, showingDrafts: true)
                state = .done(digest)
            case let .translate(source, pivot):
                state = .done(try await composeTranslated(from: source, via: pivot))
            case let .download(source, pivot):
                pendingDownload = (source, pivot)
                state = .needsDownload(language: source.displayName)
            case let .impossible(reason):
                state = .failed(reason)
            }
        } catch is CancellationError {
            // Закрыли экран — сказать некому.
        } catch let failure as DigestFailure {
            state = .failed(failure.message)
        } catch {
            state = .failed("Пересказ не получился.")
        }
    }

    /// Человек нажал «Скачать». Системное окно появится следом; до тех пор
    /// и после него экран не должен выглядеть так, будто ничего не нажато.
    func beginDownload() {
        guard let pair = pendingDownload else {
            return
        }
        state = .downloading(language: pair.source.displayName)
    }

    /// Ждать, пока языки скачаются, и продолжить пересказ.
    ///
    /// `prepareTranslation` возвращается, когда закрыто системное окно, а
    /// не когда закончилась загрузка: закрыть окно можно и посреди неё, и
    /// качать система продолжит без приложения. Поэтому готовность
    /// проверяется отдельно — опросом, пока экран открыт.
    func waitForLanguages() async {
        beginDownload()
        while !Task.isCancelled {
            if case .download = await digester.plan(for: messages) {
                try? await Task.sleep(for: downloadPollInterval)
                continue
            }
            await start()
            return
        }
    }

    /// Человек отказался скачивать языки или скачивание сорвалось.
    func downloadFailed() {
        state = .failed("Языки для перевода не скачались. Их можно скачать и вручную: Настройки → Приложения → Перевод → Языки.")
    }

    // MARK: - Звенья

    private func compose(from messages: [Message], showingDrafts: Bool) async throws -> Digest {
        var latest = Digest()
        for try await progress in digester.digest(of: messages, with: peerName) {
            switch progress {
            case let .reading(part, total):
                state = .reading(part: part, total: total)
            case let .draft(digest):
                latest = digest
                state = showingDrafts ? .writing(digest) : .composing
            }
        }
        guard !latest.isEmpty else {
            throw DigestFailure(message: "Модель не нашла в пропущенном, что пересказать.")
        }
        return latest
    }

    private func composeTranslated(from source: Locale.Language, via pivot: Locale.Language) async throws -> Digest {
        translatedVia = pivot.displayName

        state = .translating
        let there = digester.translator(from: source, to: pivot)
        let translatedTexts = try await translating { try await there.translate(messages.map(\.text)) }
        let translated = zip(messages, translatedTexts).map { message, text in
            // Мозаику не переводим: это сетка эмодзи, и в пересказ она всё
            // равно идёт как «[рисунок]».
            message.mosaic == nil ? message.withText(text) : message
        }

        let digest = try await compose(from: translated, showingDrafts: false)

        state = .translatingBack
        let back = digester.translator(from: pivot, to: source)
        // Одной пачкой, а не по разделу: переводчик поднимается один раз.
        let returned = try await translating { try await back.translate(digest.texts) }
        return digest.replacingTexts(returned)
    }

    /// Ошибки переводчика — своими словами: его ошибки человеку ничего не
    /// скажут, а сорвавшийся перевод — уже понятная причина.
    private func translating(_ work: () async throws -> [String]) async throws -> [String] {
        do {
            return try await work()
        } catch let error as CancellationError {
            throw error
        } catch let failure as DigestFailure {
            throw failure
        } catch {
            Logger.digest.error("Translation failed: \(error, privacy: .public)")
            throw DigestFailure(message: "Перевод на устройстве не получился.")
        }
    }
}

private extension Message {
    /// То же сообщение с другим текстом — переведённым.
    func withText(_ text: String) -> Message {
        Message(id: id, text: text, mosaic: mosaic, senderName: senderName, peerAddress: peerAddress,
                isFromMe: isFromMe, timestamp: timestamp, status: status, isRead: isRead)
    }
}
