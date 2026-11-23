//
//  AccessibilityAuditTests.swift
//  echosUITests
//
//  Аудит доступности каждого экрана: VoiceOver-подписи, контраст, Dynamic
//  Type, обрезанный текст, области нажатия.
//
//  Проверяет системный `performAccessibilityAudit` — тот же, что в
//  Accessibility Inspector, — и тест падает на любой находке, кроме
//  исключений, записанных ниже с причиной. Каждый экран — дважды: при
//  обычном размере текста и при самом крупном из специальных возможностей:
//  там вылезает текст, который обрезается.
//
//  Псевдолокализация — те же экраны с удвоенными строками и с вёрсткой
//  справа налево. Удвоение — грубая модель немецкого и финского: строки
//  там в полтора-два раза длиннее русских, и обрезанное видно сразу.
//  Проверяется только обрезанный текст, остальное уже проверено выше;
//  снимки экранов остаются в отчёте — посмотреть глазами.
//
//  UI-тесты — на XCTest: Swift Testing управлять интерфейсом не умеет.
//  Приложение запускается с `-UITests`: собеседники и переписка — декорация
//  (DemoTransport), хранилище — в памяти.
//

import XCTest

@MainActor
final class AccessibilityAuditTests: XCTestCase {

    /// Самый крупный размер текста в специальных возможностях.
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() async throws {
        continueAfterFailure = true
    }

    // MARK: - Экраны

    func test_home() throws { try audit(.home, size: nil) }
    func test_home_largestText() throws { try audit(.home, size: Self.largest) }

    func test_nearby() throws { try audit(.nearby, size: nil) }
    func test_nearby_largestText() throws { try audit(.nearby, size: Self.largest) }

    func test_wall() throws { try audit(.wall, size: nil) }
    func test_wall_largestText() throws { try audit(.wall, size: Self.largest) }

    func test_chat() throws { try audit(.chat, size: nil) }
    func test_chat_largestText() throws { try audit(.chat, size: Self.largest) }

    func test_mosaicPalette() throws { try audit(.palette, size: nil) }
    func test_mosaicPalette_largestText() throws { try audit(.palette, size: Self.largest) }

    // MARK: - Псевдолокализация

    func test_home_doubleLength() throws { try audit(.home, pseudo: .doubleLength) }
    func test_nearby_doubleLength() throws { try audit(.nearby, pseudo: .doubleLength) }
    func test_wall_doubleLength() throws { try audit(.wall, pseudo: .doubleLength) }
    func test_chat_doubleLength() throws { try audit(.chat, pseudo: .doubleLength) }
    func test_mosaicPalette_doubleLength() throws { try audit(.palette, pseudo: .doubleLength) }

    func test_home_rightToLeft() throws { try audit(.home, pseudo: .rightToLeft) }
    func test_chat_rightToLeft() throws { try audit(.chat, pseudo: .rightToLeft) }
    func test_mosaicPalette_rightToLeft() throws { try audit(.palette, pseudo: .rightToLeft) }

    /// Псевдоязыки Xcode — это аргументы запуска Foundation и UIKit.
    enum Pseudo: String {
        case doubleLength = "удвоенные строки"
        case rightToLeft = "справа налево"

        var arguments: [String] {
            switch self {
            case .doubleLength: ["-NSDoubleLocalizedStrings", "YES"]
            case .rightToLeft: ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
            }
        }
    }

    private func audit(_ screen: Screen, pseudo: Pseudo) throws {
        let app = launch(size: nil, extra: pseudo.arguments)
        try open(screen, in: app)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(screen.rawValue), \(pseudo.rawValue)"
        shot.lifetime = .keepAlways
        add(shot)

        try app.performAccessibilityAudit(for: .textClipped) { issue in
            // Плейсхолдер поля ввода аудит под удвоением считает обрезанным,
            // хотя «Сообщение Сообщение» занимает 190 pt из 292 — видно на
            // снимке. Без удвоения находки нет, обрезки на снимке нет и с ним.
            // Похоже на ложное срабатывание на плейсхолдере `UITextField`;
            // само поле однострочное, и длинный текст в нём прокручивается.
            if issue.element?.elementType == .textField {
                return true
            }
            let element = issue.element.map { "«\($0.label)» \($0.elementType) \($0.frame)" } ?? "без элемента"
            XCTFail("\(screen.rawValue), \(pseudo.rawValue): \(issue.compactDescription) — \(element)")
            return true
        }
    }

    // MARK: - Как дойти до экрана

    enum Screen: String {
        case home = "главный", nearby = "рядом", wall = "стена", chat = "чат", palette = "палитра"
    }

    private func audit(_ screen: Screen, size: String?) throws {
        let app = launch(size: size)
        try open(screen, in: app)
        try app.performAccessibilityAudit { issue in
            if Self.isKnownException(issue) {
                return true
            }
            // Тип и место — чтобы найти элемент без подписи: у таких label пустой.
            let element = issue.element.map { "«\($0.label)» \($0.elementType) \($0.frame)" } ?? "без элемента"
            XCTFail("\(screen.rawValue)\(size == nil ? "" : ", крупный текст"): \(issue.compactDescription) — \(element). \(issue.detailedDescription)")
            return true
        }
    }

    private func launch(size: String?, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Имя — аргументом: попадает в UserDefaults, и знакомство пропускается.
        app.launchArguments = ["-UITests", "-echos_user_name", "Тест"] + extra
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        // Переписка приходит от DemoTransport через полсекунды и ложится в
        // хранилище пачкой — ждём, пока разговоры появятся в списке.
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 15), "Разговоров нет — демо не сработало")
        return app
    }

    private func open(_ screen: Screen, in app: XCUIApplication) throws {
        switch screen {
        case .home:
            break
        case .nearby:
            try tap(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Рядом'")).firstMatch)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        case .wall:
            try tap(app.buttons.matching(Self.starts("моя стена")).firstMatch)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        case .chat:
            try tap(app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Боб'")).firstMatch)
            XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        case .palette:
            try open(.chat, in: app)
            let mosaic = app.buttons.matching(Self.starts("Мозаика")).firstMatch
            try tap(mosaic)
            XCTAssertTrue((mosaic.value as? String)?.hasPrefix("палитра открыта") == true)
        }
        // Переходы с анимацией: аудит посреди неё видит полупрозрачное.
        sleep(1)
    }

    /// Элементы ищутся по началу подписи: при удвоенных строках «моя стена»
    /// становится «моя стена моя стена», а начало у неё то же.
    private static func starts(_ prefix: String) -> NSPredicate {
        NSPredicate(format: "label BEGINSWITH %@", prefix)
    }

    private func tap(_ element: XCUIElement) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Нет элемента: \(element)")
        element.tap()
    }

    // MARK: - Исключения

    /// Что аудит находит, но что проблемой не является. Каждое — с причиной;
    /// пополнять — только так же.
    static func isKnownException(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        // Краски палитры мозаики — ⬛, 🟫, ▪️ — это материал рисунка, а не
        // текст: тёмный квадрат на тёмном фоне так и выглядит. Аудит меряет
        // контраст эмодзи как текста.
        if issue.auditType == .contrast, let label = issue.element?.label, isEmojiOnly(label) {
            return true
        }
        return false
    }

    private static func isEmojiOnly(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            $0.properties.isEmoji || $0.properties.isVariationSelector || $0.value == 0x200D
        }
    }
}
