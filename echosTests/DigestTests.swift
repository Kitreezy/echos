//
//  DigestTests.swift
//  echosTests
//
//  Пересказ пропущенного: что модель читает, как длинное режется под её
//  окно, что видит человек и когда ему вообще предлагают пересказ.
//
//  Модель здесь подменена: на CI её нет, а логика вокруг неё — нарезка,
//  состояния экрана, момент, когда запоминается пропущенное, — от модели
//  не зависит. Живой прогон — в OnDeviceDigesterLiveTests.
//

import XCTest
@testable import echos

// MARK: - Текст для модели

final class DigestTranscriptTests: XCTestCase {

    /// Один токен на символ — так части легко пересчитать в уме.
    private func perCharacter(_ text: String) -> Int { text.count }

    func test_lines_nameTheAuthorAndCollapseLineBreaks() {
        let messages = [
            Message(text: "привет,\nкак ты?", isFromMe: false),
            Message(text: "норм", isFromMe: true)
        ]

        XCTAssertEqual(DigestTranscript.lines(of: messages, with: "Боб"),
                       ["Боб: привет, как ты?", "Я: норм"],
                       "Продолжение сообщения с новой строки не должно выглядеть репликой без автора")
    }

    func test_mosaic_isNotSpelledOutCellByCell() {
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!
        let message = Message(text: mosaic.text, mosaic: mosaic, isFromMe: false)

        XCTAssertEqual(DigestTranscript.lines(of: [message], with: "Боб"), ["Боб: [рисунок]"])
    }

    func test_shortConversation_isOneChunk() async {
        let chunks = await DigestTranscript.chunks(of: ["aaa", "bbb"], budget: 100, measure: perCharacter)

        XCTAssertEqual(chunks, [["aaa", "bbb"]])
    }

    func test_longConversation_splitsInOrderWithoutBreakingLines() async {
        // Каждая строка стоит 4 + 1 за перевод строки: в бюджет 10 входят две.
        let lines = ["aaaa", "bbbb", "cccc", "dddd", "eeee"]

        let chunks = await DigestTranscript.chunks(of: lines, budget: 10, measure: perCharacter)

        XCTAssertEqual(chunks, [["aaaa", "bbbb"], ["cccc", "dddd"], ["eeee"]])
    }

    func test_lineLongerThanTheWindow_isCutNotDropped() async {
        let huge = String(repeating: "x", count: 50)

        let chunks = await DigestTranscript.chunks(of: ["a", huge, "b"], budget: 10, measure: perCharacter)

        let cut = chunks.flatMap { $0 }.first { $0.hasPrefix("x") }
        XCTAssertNotNil(cut, "Длинное сообщение — тоже часть переписки")
        XCTAssertLessThanOrEqual(cut!.count + 1, 10)
        XCTAssertTrue(cut!.hasSuffix("…"), "Обрезанное видно как обрезанное")
        XCTAssertEqual(chunks.flatMap { $0 }.last, "b")
    }

    func test_nothingToRead_noChunks() async {
        let chunks = await DigestTranscript.chunks(of: [], budget: 10, measure: perCharacter)

        XCTAssertTrue(chunks.isEmpty)
    }

    func test_language_isRecognizedOnTheWholeConversation() {
        let russian = ["ок", "Привет! Завтра созвон в десять", "не забудь логи"]
        let english = ["ok", "Hi! Standup is at ten tomorrow", "bring the logs"]

        XCTAssertEqual(DigestTranscript.dominantLanguage(of: russian.map { Message(text: $0, isFromMe: false) })?.languageCode, "ru")
        XCTAssertEqual(DigestTranscript.dominantLanguage(of: english.map { Message(text: $0, isFromMe: false) })?.languageCode, "en")
    }

    func test_onlyMosaics_languageUnknown() {
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!

        XCTAssertNil(DigestTranscript.dominantLanguage(of: [Message(text: mosaic.text, mosaic: mosaic, isFromMe: false)]))
    }

    func test_estimate_errsOnTheGenerousSide() {
        // Кириллица в токенизаторах дробится мельче латиницы: оценка
        // «символ в два» должна давать не меньше, чем реальный счёт
        // слов, — иначе окно переполнится.
        let text = "Завтра в десять созвон по релизу"

        XCTAssertGreaterThan(DigestTranscript.estimatedTokens(text),
                             text.split(separator: " ").count * 2)
    }
}

// MARK: - Экран пересказа

@MainActor
final class DigestViewModelTests: XCTestCase {

    private func makeViewModel(_ digester: StubDigester) -> DigestViewModel {
        DigestViewModel(messages: [Message(text: "привет", isFromMe: false)],
                        peerName: "Боб",
                        digester: digester)
    }

    func test_draftsArrive_thenTheLastOneIsTheResult() async {
        let digester = StubDigester()
        let final = Digest(points: ["Боб зовёт в кино"], questions: ["Пойдёшь?"], plans: ["Суббота, 19:00"])
        digester.script = [
            .reading(part: 1, of: 2),
            .reading(part: 2, of: 2),
            .draft(Digest(points: ["Боб зовёт"])),
            .draft(final)
        ]
        let viewModel = makeViewModel(digester)

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .done(final))
    }

    func test_modelFailure_isShownInItsOwnWords() async {
        let digester = StubDigester()
        digester.failure = DigestFailure(message: "Модель на устройстве не работает с языком этой переписки")
        let viewModel = makeViewModel(digester)

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .failed("Модель на устройстве не работает с языком этой переписки"))
    }

    func test_modelNotReady_explainsWithoutCallingIt() async {
        let digester = StubDigester()
        digester.availability = .notNow("Включите Apple Intelligence")
        let viewModel = makeViewModel(digester)

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .failed("Включите Apple Intelligence"))
        XCTAssertTrue(digester.digested.isEmpty)
    }

    func test_unreadableLanguage_explainedWithoutCallingTheModel() async {
        let digester = StubDigester()
        digester.plan = .impossible("Ни модель, ни переводчик не знают языка")
        let viewModel = makeViewModel(digester)

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .failed("Ни модель, ни переводчик не знают языка"))
        XCTAssertTrue(digester.digested.isEmpty, "Отказ известен заранее — звать модель незачем")
    }

    func test_emptyAnswer_isNotPresentedAsASummary() async {
        let digester = StubDigester()
        digester.script = [.draft(Digest())]
        let viewModel = makeViewModel(digester)

        await viewModel.start()

        guard case .failed = viewModel.state else {
            return XCTFail("Пустой пересказ — не пересказ: \(viewModel.state)")
        }
    }
}

// MARK: - Когда предлагать

@MainActor
final class MissedMessagesTests: XCTestCase {

    private func makeViewModel(unread: Int, read: Int = 0,
                               availability: DigestAvailability = .ready) async -> (ChatViewModel, StubDigester) {
        let store = SpyMessageStore()
        let timestamps = (0..<(read + unread)).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        for (index, timestamp) in timestamps.enumerated() {
            try? await store.saveMessage(Message(text: "сообщение \(index)",
                                                 senderName: "bob",
                                                 peerAddress: "bob",
                                                 isFromMe: false,
                                                 timestamp: timestamp,
                                                 status: .sent,
                                                 isRead: index < read))
        }
        let digester = StubDigester()
        digester.availability = availability
        let viewModel = ChatViewModel()
        viewModel.messageStore = store
        viewModel.digester = digester
        viewModel.unreadCounts["bob"] = unread
        return (viewModel, digester)
    }

    func test_openingAChat_remembersWhatWasMissedBeforeMarkingItRead() async {
        let (viewModel, digester) = await makeViewModel(unread: 6, read: 3)

        await viewModel.switchToConversation(with: "bob")

        XCTAssertNil(viewModel.unreadCounts["bob"], "Чат открыт — значит, прочитан")
        XCTAssertEqual(viewModel.missedMessages.map(\.text),
                       (3..<9).map { "сообщение \($0)" },
                       "Пересказывается пропущенное, а не вся история")
        XCTAssertTrue(viewModel.canDigest)
        XCTAssertEqual(digester.preparedCount, 1, "Модель греется, пока человек читает чат")
    }

    func test_fewMissed_noOffer() async {
        let (viewModel, digester) = await makeViewModel(unread: ChatViewModel.digestThreshold - 1)

        await viewModel.switchToConversation(with: "bob")

        XCTAssertFalse(viewModel.canDigest, "Пару сообщений быстрее прочитать, чем ждать модель")
        XCTAssertEqual(digester.preparedCount, 0)
    }

    func test_noModelOnThisDevice_noOffer() async {
        let (viewModel, _) = await makeViewModel(unread: 10, availability: .never)

        await viewModel.switchToConversation(with: "bob")

        XCTAssertFalse(viewModel.canDigest)
    }

    func test_modelNotReadyYet_stillOffered() async {
        let (viewModel, _) = await makeViewModel(unread: 10, availability: .notNow("загружается"))

        await viewModel.switchToConversation(with: "bob")

        XCTAssertTrue(viewModel.canDigest, "Кнопка остаётся — с объяснением, что сделать")
    }

    func test_unreadableLanguage_offeredButModelNotWarmed() async {
        let (viewModel, digester) = await makeViewModel(unread: 10)
        digester.plan = .impossible("не тот язык")

        await viewModel.switchToConversation(with: "bob")

        XCTAssertTrue(viewModel.canDigest, "Кнопка объяснит, почему нет, — лучше, чем молча пропасть")
        XCTAssertEqual(digester.preparedCount, 0, "Греть модель ради языка, которого она не знает, незачем")
    }

    func test_translatableLanguage_modelWarmed() async {
        let (viewModel, digester) = await makeViewModel(unread: 10)
        digester.plan = .translate(from: .init(identifier: "ru"), via: .init(identifier: "en"))

        await viewModel.switchToConversation(with: "bob")

        XCTAssertEqual(digester.preparedCount, 1, "Через перевод модель всё равно понадобится")
    }

    func test_languagesNotDownloaded_modelNotWarmedYet() async {
        let (viewModel, digester) = await makeViewModel(unread: 10)
        digester.plan = .download(from: .init(identifier: "ru"), via: .init(identifier: "en"))

        await viewModel.switchToConversation(with: "bob")

        XCTAssertEqual(digester.preparedCount, 0, "Сначала вопрос о скачивании, и человек может отказаться")
    }

    func test_clearingTheChat_forgetsWhatWasMissed() async throws {
        let (viewModel, _) = await makeViewModel(unread: 10)
        await viewModel.switchToConversation(with: "bob")

        try await viewModel.clearCurrentConversation()

        XCTAssertTrue(viewModel.missedMessages.isEmpty)
        XCTAssertFalse(viewModel.canDigest)
    }
}

// MARK: - Цепочка через перевод

@MainActor
final class TranslatedDigestTests: XCTestCase {

    private let russian = Locale.Language(identifier: "ru")
    private let english = Locale.Language(identifier: "en")

    private func makeViewModel(_ digester: StubDigester, messages: [Message]) -> DigestViewModel {
        DigestViewModel(messages: messages, peerName: "Боб", digester: digester)
    }

    func test_conversationGoesThereAndTheDigestComesBack() async {
        let digester = StubDigester()
        digester.plan = .translate(from: russian, via: english)
        digester.script = [
            .draft(Digest(points: ["Bob"])),
            .draft(Digest(points: ["Bob invites to the cinema"], questions: ["Are you coming?"], plans: ["Saturday 7pm"]))
        ]
        let viewModel = makeViewModel(digester, messages: [
            Message(text: "пойдём в кино?", isFromMe: false),
            Message(text: "в субботу в семь", isFromMe: false)
        ])

        await viewModel.start()

        XCTAssertEqual(digester.digested.first?.map(\.text), ["[en] пойдём в кино?", "[en] в субботу в семь"],
                       "Модель читает переведённое")
        XCTAssertEqual(viewModel.state, .done(Digest(points: ["[ru] Bob invites to the cinema"],
                                                     questions: ["[ru] Are you coming?"],
                                                     plans: ["[ru] Saturday 7pm"])),
                       "Пересказ возвращается на язык переписки, разделы не перепутаны")
        XCTAssertNotNil(viewModel.translatedVia, "Под пересказом сказано, что он шёл через перевод")
    }

    func test_backTranslation_isOneBatch() async {
        let digester = StubDigester()
        digester.plan = .translate(from: russian, via: english)
        digester.script = [.draft(Digest(points: ["a", "b"], questions: ["c"], plans: ["d"]))]
        let viewModel = makeViewModel(digester, messages: [Message(text: "x", isFromMe: false)])

        await viewModel.start()

        XCTAssertEqual(digester.translators.map(\.received.count), [1, 1],
                       "Туда и обратно — по одной пачке: переводчик поднимается один раз")
    }

    func test_mosaic_isNotTranslated() async {
        let digester = StubDigester()
        digester.plan = .translate(from: russian, via: english)
        digester.script = [.draft(Digest(points: ["a"]))]
        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!
        let viewModel = makeViewModel(digester, messages: [
            Message(text: "смотри", isFromMe: false),
            Message(text: mosaic.text, mosaic: mosaic, isFromMe: false)
        ])

        await viewModel.start()

        XCTAssertEqual(digester.digested.first?.last?.text, mosaic.text)
        XCTAssertEqual(digester.digested.first?.last?.mosaic, mosaic)
    }

    func test_englishDraftsAreNotShown() async {
        let digester = StubDigester()
        digester.plan = .translate(from: russian, via: english)
        digester.script = [.draft(Digest(points: ["Bob"]))]
        let viewModel = makeViewModel(digester, messages: [Message(text: "x", isFromMe: false)])

        await viewModel.start()

        // Черновик на языке-посреднике человеку не показывается: по ходу
        // было бы видно английский текст, который потом сменится русским.
        guard case .done = viewModel.state else {
            return XCTFail("\(viewModel.state)")
        }
    }

    func test_translationFailure_isExplained() async {
        let digester = StubDigester()
        digester.plan = .translate(from: russian, via: english)
        digester.translationFailure = URLError(.unknown)
        let viewModel = makeViewModel(digester, messages: [Message(text: "x", isFromMe: false)])

        await viewModel.start()

        XCTAssertEqual(viewModel.state, .failed("Перевод на устройстве не получился."))
        XCTAssertTrue(digester.digested.isEmpty)
    }

    func test_languagesNotDownloaded_askFirst() async {
        let digester = StubDigester()
        digester.plan = .download(from: russian, via: english)
        let viewModel = makeViewModel(digester, messages: [Message(text: "x", isFromMe: false)])

        await viewModel.start()

        guard case .needsDownload = viewModel.state else {
            return XCTFail("\(viewModel.state)")
        }
        XCTAssertEqual(viewModel.pendingDownload?.source, russian)
        XCTAssertEqual(viewModel.pendingDownload?.target, english)
        XCTAssertTrue(digester.digested.isEmpty)
    }

    func test_tappingDownload_showsThatItIsGoing() async {
        let digester = StubDigester()
        digester.plan = .download(from: russian, via: english)
        let viewModel = makeViewModel(digester, messages: [Message(text: "x", isFromMe: false)])
        await viewModel.start()

        viewModel.beginDownload()

        guard case .downloading = viewModel.state else {
            return XCTFail("После нажатия экран не должен выглядеть нетронутым: \(viewModel.state)")
        }
    }

    /// Системное окно закрылось, а загрузка ещё идёт: пересказ должен
    /// дождаться её и начаться сам.
    func test_languagesArriveLater_digestStartsByItself() async {
        let digester = StubDigester()
        digester.plan = .download(from: russian, via: english)
        digester.script = [.draft(Digest(points: ["a"]))]
        let viewModel = makeViewModel(digester, messages: [Message(text: "x", isFromMe: false)])
        viewModel.downloadPollInterval = .milliseconds(5)
        await viewModel.start()

        let notYet = DigestPlan.download(from: russian, via: english)
        digester.upcomingPlans = [notYet, notYet]
        digester.plan = .translate(from: russian, via: english)
        await viewModel.waitForLanguages()

        XCTAssertEqual(viewModel.state, .done(Digest(points: ["[ru] a"])))
    }

    func test_downloadRefused_isExplained() async {
        let digester = StubDigester()
        digester.plan = .download(from: russian, via: english)
        let viewModel = makeViewModel(digester, messages: [Message(text: "x", isFromMe: false)])
        await viewModel.start()

        viewModel.downloadFailed()

        guard case .failed = viewModel.state else {
            return XCTFail("\(viewModel.state)")
        }
    }
}
