//
//  LaunchTrace.swift
//  echos
//
//  Signpost-интервалы холодного запуска. Pre-main tail помечается в
//  LaunchTrace.m ещё до main; здесь — всё, что приложение делает от
//  didFinishLaunching до первого активного кадра.
//

import MetricKit
import OSLog

@MainActor
enum LaunchTrace {

    private static let signposter = OSSignposter(
        logHandle: MXMetricManager.makeLogHandle(category: "launch")
    )

    private static var launchState: OSSignpostIntervalState?
    private static var sceneState: OSSignpostIntervalState?

    /// Начало main-фазы. Вызывается из AppDelegate как можно раньше: всё до
    /// sceneDidBecomeActive — бюджет, который пользователь видит как «приложение
    /// запускается».
    static func applicationDidFinishLaunching() {
        guard launchState == nil else {
            return
        }
        launchState = signposter.beginInterval("Launch main phase")
    }

    /// Синхронное создание окна и корневого экрана. Отдельным интервалом:
    /// именно здесь легко случайно поднять Core Data или сеть до первого кадра.
    static func sceneWillConnect() {
        guard sceneState == nil else {
            return
        }
        sceneState = signposter.beginInterval("Scene creation")
    }

    static func sceneDidCreateWindow() {
        guard let sceneState else {
            return
        }
        self.sceneState = nil
        signposter.endInterval("Scene creation", sceneState)
    }

    /// Первый активный кадр — приложение отвечает на касания. Здесь
    /// закрывается и общий интервал холодного запуска.
    static func sceneDidBecomeActive() {
        sceneDidCreateWindow()

        guard let launchState else {
            return
        }
        self.launchState = nil
        signposter.endInterval("Launch main phase", launchState)
    }
}
