//
//  AppDelegate.swift
//  echos
//
//  Created by Artem Rodionov on 16.02.2026.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        LaunchTrace.applicationDidFinishLaunching()
        MetricsCollector.shared.start()

        // Фоновая сессия сама знает о живых задачах. Запуск без прерванной
        // очереди не должен платить за getTasks на каждом холодном старте.
        if BackgroundDownloadService.shared.hasPendingDownloads() {
            BackgroundDownloadService.shared.restorePendingDownloads()
        }
        return true
    }

    /// Фоновая сессия дожила до событий: система подняла приложение, чтобы
    /// отдать их делегату. Сервис пересоздаёт потерянные задачи и сообщает
    /// системе, когда все события обработаны.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundDownloadService.sessionIdentifier else {
            completionHandler()
            return
        }

        // UIKit отдаёт closure без пометки Sendable; вызвать её может только
        // система, поэтому через границу изоляции несётся явная расписка.
        let completion = UncheckedSendableBox(completionHandler)
        BackgroundDownloadService.shared.handleBackgroundEvents {
            completion.value()
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
