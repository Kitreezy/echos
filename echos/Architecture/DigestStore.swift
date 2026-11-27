//
//  DigestStore.swift
//  echos
//
//  Экран пересказа на однонаправленном потоке (см. Store.swift): состояние
//  меняет только редьюсер ниже, экран шлёт действия и читает состояние.
//  Бывший DigestViewModel существовал рядом на наблюдаемом MVVM — сравнение
//  подходов в README.
//

import Foundation
import OSLog

// MARK: - Состояние

struct DigestState {

    /// Этап пересказа — то, что видит человек.
    enum Phase: Equatable {
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

    var phase: Phase = .starting

    /// Через какой язык шёл перевод — для подписи под пересказом. `nil` —
    /// пересказано напрямую.
    var translatedVia: String?

    /// Что скачать перед переводом. Экран отдаёт это системе через
    /// `.translationTask`: скачать языки можно только так.
    var pendingDownload: (source: Locale.Language, target: Locale.Language)?

    /// Язык-посредник и язык переписки цепочки перевода. Внутренние: нужны
    /// эффекту обратного перевода, редьюсер запоминает их при выборе плана.
    var pivotLanguage: Locale.Language?
    var sourceLanguage: Locale.Language?

    /// На какие сообщения человек уже ответил. Вопросы из них отмечаются
    /// отвеченными, и вариантов под ними больше нет.
    var answered: Set<UUID> = []

    /// Показные данные экрана. В состоянии, потому что стор — единственное,
    /// что экран читает; редьюсер их не меняет никогда.
    var peerName: String = ""
    var messageCount: Int = 0
}

extension DigestState {
    func isAnswered(_ question: DigestQuestion) -> Bool {
        question.messageID.map(answered.contains) ?? false
    }

    /// Сколько вопросов готового пересказа ещё ждут ответа.
    var unansweredCount: Int {
        guard case let .done(digest) = phase else {
            return 0
        }
        return digest.questions.filter { !isAnswered($0) }.count
    }
}

// MARK: - Действия

enum DigestAction {

    /// Вход на экран: пересказать, если готового ещё нет. Экран живёт,
    /// пока не сменилось пропущенное, — повторный `.start` готовое не трогает.
    case start
    /// Человек нажал «Скачать» / системный запрос прошёл. До окна и после
    /// него экран не должен выглядеть так, будто ничего не нажато.
    case beginDownload
    /// Скачивание отклонено или сорвалось.
    case downloadFailed
    /// Отмеченные ответы прислал хозяин экрана (чат).
    case syncAnswered(Set<UUID>)

    // Дальше — внутренние: их шлют только эффекты. Экран их не знает.

    /// План выбран: напрямую, через перевод, сначала скачать или никак.
    case planned(DigestPlan)
    case readProgress(part: Int, total: Int)
    case draft(Digest, showDrafts: Bool)
    /// Что делать с готовым пересказом: показать или перевести обратно.
    case composeFinished(Result<Digest, DigestFailure>, next: ComposeNext)
    case translatedThere([Message])
    case translateFailed(DigestFailure)
    case backTranslated(Result<Digest, DigestFailure>)
}

enum ComposeNext: Equatable {
    /// Цепочки не было — пересказ готов как есть.
    case finish
    /// Писался на языке-посреднике — переводим обратно.
    case translateBack
}

// MARK: - Окружение

/// Что нужно эффектам: то, что раньше VM держала полями. Редьюсер
/// окружения не трогает — только эффекты.
struct DigestEnvironment: Sendable {
    let messages: [Message]
    let peerName: String
    let digester: any Digesting
    var downloadPollInterval: Duration = .seconds(2)
}

// MARK: - Стор

typealias DigestStore = Store<DigestState, DigestAction>

extension DigestStore {
    convenience init(messages: [Message],
                     peerName: String,
                     digester: any Digesting,
                     downloadPollInterval: Duration = .seconds(2)) {
        let environment = DigestEnvironment(messages: messages,
                                            peerName: peerName,
                                            digester: digester,
                                            downloadPollInterval: downloadPollInterval)
        var initial = DigestState()
        initial.peerName = peerName
        initial.messageCount = messages.count
        self.init(initialState: initial) { state, action in
            digestReducer(&state, action, environment: environment)
        }
    }
}

// MARK: - Редьюсер

/// Чистая функция переходов: состояние + действие → новое состояние +
/// эффекты. Никакого async здесь намеренно — асинхронность живёт в
/// эффектах, и проверять таблицу переходов можно синхронно.
@MainActor
private func digestReducer(_ state: inout DigestState,
                           _ action: DigestAction,
                           environment: DigestEnvironment) -> [Effect<DigestAction>] {
    switch action {
    case .start:
        // Открыть экран второй раз — значит увидеть готовое, а не ждать
        // модель заново. Прерванное (не done) — начинается с начала.
        if case .done = state.phase {
            return []
        }
        if case .notNow(let reason) = environment.digester.availability {
            state.phase = .failed(reason)
            return []
        }
        state.phase = .starting
        state.translatedVia = nil
        state.pendingDownload = nil
        return [.plan(environment)]

    case let .planned(plan):
        switch plan {
        case .direct:
            return [.compose(environment, messages: environment.messages,
                             showingDrafts: true, next: .finish)]
        case let .translate(source, pivot):
            state.sourceLanguage = source
            state.translatedVia = pivot.displayName
            state.pivotLanguage = pivot
            state.phase = .translating
            return [.translateThere(environment, source: source, pivot: pivot)]
        case let .download(source, pivot):
            state.sourceLanguage = source
            state.pivotLanguage = pivot
            state.pendingDownload = (source, pivot)
            state.phase = .needsDownload(language: source.displayName)
            return []
        case let .impossible(reason):
            state.phase = .failed(reason)
            return []
        }

    case .beginDownload:
        guard let pair = state.pendingDownload else {
            return []
        }
        state.phase = .downloading(language: pair.source.displayName)
        return [.pollUntilDownloaded(environment)]

    case .downloadFailed:
        state.phase = .failed(String(localized: "Языки для перевода не скачались. Их можно скачать и вручную: Настройки → Приложения → Перевод → Языки."))
        return []

    case let .syncAnswered(ids):
        state.answered = ids
        return []

    case let .readProgress(part, total):
        state.phase = .reading(part: part, total: total)
        return []

    case let .draft(digest, showDrafts):
        // Недописанный вариант на языке-посреднике показывать рано.
        state.phase = showDrafts ? .writing(digest) : .composing
        return []

    case let .composeFinished(result, next):
        switch (result, next) {
        case let (.success(digest), .finish):
            guard !digest.isEmpty else {
                state.phase = .failed(String(localized: "Модель не нашла в пропущенном, что пересказать."))
                return []
            }
            state.phase = .done(digest)
            return []
        case let (.success(digest), .translateBack):
            guard let source = state.sourceLanguage, let pivot = state.pivotLanguage else {
                // Без языков цепочки обратный перевод не собрать — честнее
                // показать пересказ как есть, чем падать.
                state.phase = .done(digest)
                return []
            }
            state.phase = .translatingBack
            return [.translateBack(environment, digest: digest, source: source, pivot: pivot)]
        case let (.failure(failure), _):
            state.phase = .failed(failure.message)
            return []
        }

    case let .translatedThere(messages):
        return [.compose(environment, messages: messages,
                         showingDrafts: false, next: .translateBack)]

    case let .translateFailed(failure):
        state.phase = .failed(failure.message)
        return []

    case let .backTranslated(result):
        switch result {
        case let .success(digest):
            state.phase = .done(digest)
        case let .failure(failure):
            state.phase = .failed(failure.message)
        }
        return []
    }
}

// MARK: - Эффекты

private extension Effect where Action == DigestAction {

    /// Спросить план у пересказчика.
    static func plan(_ environment: DigestEnvironment) -> Effect {
        Effect { send in
            let plan = await environment.digester.plan(for: environment.messages)
            await send(.planned(plan))
        }
    }

    /// Читать поток модели. Прогресс идёт в состояние действиями — по одному
    /// на событие потока, без реактивных подписок.
    static func compose(_ environment: DigestEnvironment,
                        messages: [Message],
                        showingDrafts: Bool,
                        next: ComposeNext) -> Effect {
        Effect { send in
            do {
                var latest = Digest()
                for try await progress in environment.digester.digest(of: messages,
                                                                      with: environment.peerName) {
                    switch progress {
                    case let .reading(part, total):
                        await send(.readProgress(part: part, total: total))
                    case let .draft(digest):
                        latest = digest
                        await send(.draft(digest, showDrafts: showingDrafts))
                    }
                }
                await send(.composeFinished(.success(latest), next: next))
            } catch is CancellationError {
                // Закрыли экран — сказать некому. Стор мёртв вместе с задачей.
            } catch let failure as DigestFailure {
                await send(.composeFinished(.failure(failure), next: next))
            } catch {
                await send(.composeFinished(
                    .failure(DigestFailure(message: String(localized: "Пересказ не получился."))),
                    next: next
                ))
            }
        }
    }

    /// Первая ступень цепочки: переписка — на язык модели.
    static func translateThere(_ environment: DigestEnvironment,
                               source: Locale.Language,
                               pivot: Locale.Language) -> Effect {
        Effect { send in
            let translator = environment.digester.translator(from: source, to: pivot)
            do {
                let texts = try await translator.translate(environment.messages.map(\.text))
                let translated = zip(environment.messages, texts).map { message, text in
                    // Мозаику не переводим: это сетка эмодзи, и в пересказ
                    // она всё равно идёт как «[рисунок]».
                    message.mosaic == nil ? message.withText(text) : message
                }
                await send(.translatedThere(translated))
            } catch is CancellationError {
                // Экран закрыли — переводить некому.
            } catch let failure as DigestFailure {
                await send(.translateFailed(failure))
            } catch {
                Logger.digest.error("Translation failed: \(error, privacy: .public)")
                await send(.translateFailed(
                    DigestFailure(message: String(localized: "Перевод на устройстве не получился."))
                ))
            }
        }
    }

    /// Вторая ступень: готовый пересказ — обратно на язык переписки.
    /// Одной пачкой, а не по разделу: переводчик поднимается один раз.
    static func translateBack(_ environment: DigestEnvironment,
                              digest: Digest,
                              source: Locale.Language,
                              pivot: Locale.Language) -> Effect {
        Effect { send in
            let translator = environment.digester.translator(from: pivot, to: source)
            do {
                let returned = try await translator.translate(digest.texts)
                await send(.backTranslated(.success(digest.replacingTexts(returned))))
            } catch is CancellationError {
                // Экран закрыли.
            } catch let failure as DigestFailure {
                await send(.backTranslated(.failure(failure)))
            } catch {
                Logger.digest.error("Back-translation failed: \(error, privacy: .public)")
                await send(.backTranslated(.failure(
                    DigestFailure(message: String(localized: "Перевод на устройстве не получился."))
                )))
            }
        }
    }

    /// Ждать, пока языки скачаются, и продолжить пересказ.
    ///
    /// `prepareTranslation` возвращается, когда закрыто системное окно, а
    /// не когда закончилась загрузка: закрыть окно можно и посреди неё, и
    /// качать система продолжит без приложения. Поэтому готовность
    /// проверяется опросом — следующим действием после скачивания будет
    /// обычный `.start`, он переспрашивает план сам.
    static func pollUntilDownloaded(_ environment: DigestEnvironment) -> Effect {
        Effect { send in
            while !Task.isCancelled {
                if case .download = await environment.digester.plan(for: environment.messages) {
                    try? await Task.sleep(for: environment.downloadPollInterval)
                    continue
                }
                await send(.start)
                return
            }
        }
    }
}

private extension Message {
    /// То же сообщение с другим текстом — переведённым.
    func withText(_ text: String) -> Message {
        Message(id: id, text: text, mosaic: mosaic, voice: voice, senderName: senderName, peerAddress: peerAddress,
                isFromMe: isFromMe, timestamp: timestamp, status: status, isRead: isRead)
    }
}
