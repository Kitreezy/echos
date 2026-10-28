//
//  ProfilingScenarioTests.swift
//  echosUITests
//
//  Сценарий для Instruments, а не проверка: ходит по экранам туда и обратно,
//  чтобы профилировщику было что записать. Утечка видна только после того,
//  как с экрана ушли, а блокировка главного потока — только когда по
//  экранам ходят.
//
//  Запускается планом Profiling через scripts/profile.sh, который к нему и
//  подключает xctrace. В остальных планах пропускается: проверять тут
//  нечего, а идёт он минуту.
//

import XCTest

@MainActor
final class ProfilingScenarioTests: XCTestCase {

    /// Сколько раз пройти круг. Утечка одного экрана за круг растёт
    /// линейно, и на шести кругах её уже не спутать с кэшем.
    private static let rounds = 6

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ECHOS_PROFILING"] == "1",
                          "Сценарий для Instruments — только в плане Profiling")
    }

    func test_screensRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITests", "-echos_user_name", "Тест"]
        app.launch()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 15), "Разговоров нет — демо не сработало")

        // Профилировщик подключается к уже запущенному приложению — даём
        // ему время, прежде чем начать ходить.
        sleep(warmup)

        let mosaic = app.buttons["Мозаика"]
        for _ in 0..<Self.rounds {
            try roundTrip(into: app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Боб'")).firstMatch,
                          until: app.textFields.firstMatch, in: app) {
                // Палитра из закрытой клавиатуры и вместо открытой — у
                // ChatViewController для этого разные пути.
                for keyboardUp in [false, true] {
                    if keyboardUp {
                        try self.tap(app.textFields.firstMatch)
                    }
                    try self.tap(mosaic)
                    XCTAssertEqual(mosaic.value as? String, "палитра открыта")
                    try self.tap(mosaic)
                }
            }
            try roundTrip(into: app.buttons["моя стена"], until: app.navigationBars.firstMatch, in: app)
        }

        // Пауза в конце: Leaks снимает память раз в несколько секунд, и
        // последний снимок должен прийти, когда все экраны уже закрыты.
        sleep(warmup)
    }

    // MARK: - Private

    private var warmup: UInt32 {
        UInt32(ProcessInfo.processInfo.environment["ECHOS_PROFILING_WARMUP"] ?? "") ?? 8
    }

    private func roundTrip(into entry: XCUIElement,
                           until marker: XCUIElement,
                           in app: XCUIApplication,
                           while inside: () throws -> Void = {}) throws {
        try tap(entry)
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        try inside()
        try tap(app.navigationBars.buttons["Назад"])
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
    }

    /// Всегда через `waitForExistence`, хоть он и стоит секунду: `exists`
    /// отвечает «да» посреди анимации перехода, и касание уходит в никуда.
    private func tap(_ element: XCUIElement) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Нет элемента: \(element)")
        element.tap()
    }
}
