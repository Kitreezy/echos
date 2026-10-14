//
//  OnDeviceDigesterLiveTests.swift
//  echosTests
//
//  Живая модель: что она на самом деле отвечает.
//
//  Модели нет на CI и на машинах без Apple Intelligence — там тесты
//  пропускаются, а не падают. Где она есть (симулятор берёт модель у Mac),
//  пересказ печатается в лог: ответ модели — не то, что сверяется до
//  буквы, его надо читать глазами.
//

import XCTest
@testable import echos

@MainActor
final class OnDeviceDigesterLiveTests: XCTestCase {

    private func liveDigester() throws -> any Digesting {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("FoundationModels — с iOS 26")
        }
        let digester = OnDeviceDigester()
        guard digester.availability == .ready else {
            throw XCTSkip("Модель недоступна: \(digester.availability)")
        }
        return digester
    }

    private func digest(_ texts: [String], with digester: any Digesting) async throws -> Digest {
        let messages = texts.map { Message(text: $0, isFromMe: false) }
        var latest = Digest()
        do {
            for try await progress in digester.digest(of: messages, with: "Bob") {
                if case let .draft(digest) = progress {
                    latest = digest
                }
            }
        } catch let failure as DigestFailure where failure.message.contains("не ответила") {
            // Симулятор берёт модель у Mac и называет её доступной, даже
            // если на Mac Apple Intelligence выключен, — падает уже вызов.
            // Это не поведение модели, а её отсутствие.
            throw XCTSkip(failure.message)
        }
        print("[live] points: \(latest.points)\n[live] questions: \(latest.questions)\n[live] plans: \(latest.plans)")
        return latest
    }

    func test_english_findsTheQuestionAndThePlan() async throws {
        let digester = try liveDigester()

        let digest = try await digest([
            "Hey, the release build is broken again",
            "Crash on launch on iOS 18, logs are in the ticket",
            "Can you look at it before Friday?",
            "Also, standup moved to 10:30 tomorrow",
            "And Anna wants the design review on Thursday at 3pm"
        ], with: digester)

        XCTAssertFalse(digest.points.isEmpty)
        XCTAssertFalse(digest.questions.isEmpty, "Вопрос к человеку в переписке есть")
        XCTAssertFalse(digest.plans.isEmpty, "Время в переписке есть")
    }

    /// Знает ли модель язык, решает сам фреймворк, а не модель: проверка
    /// работает и там, где модели нет. Поэтому без `liveDigester()`.
    func test_russian_goesThroughTranslation_englishDirect() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("FoundationModels — с iOS 26")
        }
        let russian = ["Привет! Сборка опять сломалась", "Посмотришь до пятницы?"]
            .map { Message(text: $0, isFromMe: false) }
        let english = ["Hey, the build is broken again", "Can you look before Friday?"]
            .map { Message(text: $0, isFromMe: false) }

        let plan = await OnDeviceDigester().plan(for: russian)
        print("[live] русский: \(plan)")

        XCTAssertNotEqual(plan, .direct, "Русского среди языков модели нет")
        let englishPlan = await OnDeviceDigester().plan(for: english)
        XCTAssertEqual(englishPlan, .direct)
    }

    /// Вся цепочка живьём: перевод, пересказ, перевод обратно. Нужны
    /// модель и скачанные языки — без них пропускается.
    func test_russian_fullChain() async throws {
        let digester = try liveDigester()
        let messages = [
            "Привет! Сборка опять сломалась",
            "Падает на запуске на iOS 18, логи в задаче",
            "Посмотришь до пятницы?",
            "И созвон завтра перенесли на 10:30",
            "Аня хочет дизайн-ревью в четверг в 15:00"
        ].map { Message(text: $0, isFromMe: false) }
        guard case .translate = await digester.plan(for: messages) else {
            throw XCTSkip("Языки для перевода не скачаны или недоступны")
        }

        let viewModel = DigestViewModel(messages: messages, peerName: "Боб", digester: digester)
        await viewModel.start()

        print("[live] цепочка: \(viewModel.state)")
        guard case let .done(digest) = viewModel.state else {
            return XCTFail("\(viewModel.state)")
        }
        XCTAssertFalse(digest.points.isEmpty)
    }

    /// Русского среди языков модели нет. Тест не утверждает, что пересказ
    /// получится, — он фиксирует, что происходит: ответ или понятный отказ.
    func test_russian_eitherSummarizesOrSaysWhyNot() async throws {
        let digester = try liveDigester()

        do {
            let digest = try await digest([
                "Привет! Сборка опять сломалась",
                "Падает на запуске на iOS 18, логи в задаче",
                "Посмотришь до пятницы?",
                "И созвон завтра перенесли на 10:30",
                "Аня хочет дизайн-ревью в четверг в 15:00"
            ], with: digester)
            XCTAssertFalse(digest.isEmpty)
        } catch let failure as DigestFailure {
            print("[live] отказ: \(failure.message)")
        }
    }
}
