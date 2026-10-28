//
//  LaunchPerformanceTests.swift
//  echosUITests
//
//  Время запуска — числом, а не на глаз. Шаблон App Launch в Instruments
//  на симуляторе не работает, а XCTApplicationLaunchMetric работает: пять
//  запусков, первый не в счёт, в отчёте среднее и разброс.
//
//  Как и сценарий для Instruments, идёт только в плане Profiling: десяток
//  запусков приложения в обычном прогоне — лишняя минута ради числа,
//  которое на симуляторе всё равно меряют не для порога, а для сравнения
//  «до» и «после».
//

import XCTest

@MainActor
final class LaunchPerformanceTests: XCTestCase {

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ECHOS_PROFILING"] == "1",
                          "Замер запуска — только в плане Profiling")
    }

    /// До первого кадра, на котором приложение отвечает на касания.
    func test_launch() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITests", "-echos_user_name", "Тест"]

        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
            app.terminate()
        }
    }
}
