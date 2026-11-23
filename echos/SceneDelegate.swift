//
//  SceneDelegate.swift
//  echos
//
//  Created by Artem Rodionov on 16.02.2026.
//

import CoreSpotlight
import UIKit

@MainActor
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// Владелец навигации и модели. Сцена держит его, экраны — слабо.
    /// Граф собирает корень композиции; сцена его только хранит.
    private var coordinator: AppCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        LaunchTrace.sceneWillConnect()
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)

        // Палитра echos тёмная всегда, а системные части интерфейса —
        // алерты, меню, клавиатура, статус-бар — рисуются в оформлении
        // телефона. На светлом телефоне они выходили светлыми поверх тёмного
        // приложения и выглядели чужими. Оформление задаётся окну целиком:
        // ставить его на каждый экран значит однажды забыть.
        window.overrideUserInterfaceStyle = .dark

        let root = CompositionRoot(environment: .current())
        coordinator = root.coordinator
        let navigationController = root.coordinator.navigationController

//        navigationController.setNavigationBarHidden(true, animated: false)

        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.tintColor = UIColor.inkMuted

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.surface
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.ink,
            .font: Typography.scaled(.systemFont(ofSize: 16, weight: .light), as: .headline),
            .kern: Typography.narrow
        ]
        // Полоса под шапкой — тоже рамка. Убираем.
        appearance.shadowColor = .clear

        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance

        navigationController.interactivePopGestureRecognizer?.isEnabled = true

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
        LaunchTrace.sceneDidCreateWindow()

        // Холодный запуск нажатием в поиске: активность приходит здесь, а
        // не в `scene(_:continue:)`.
        connectionOptions.userActivities.forEach(openSearchResult)

        // Холодный запуск ссылкой echos://: контексты приходят здесь,
        // тёплый — в `scene(_:openURLContexts:)`.
        connectionOptions.urlContexts.forEach(openURLContext)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach(openURLContext)
    }

    private func openURLContext(_ context: UIOpenURLContext) {
        guard let link = DeepLink(url: context.url) else {
            return
        }
        coordinator?.route(AppRoute(link))
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        openSearchResult(userActivity)
    }

    private func openSearchResult(_ activity: NSUserActivity) {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let target = SpotlightItems.target(from: identifier) else {
            return
        }
        coordinator?.route(AppRoute(target))
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {
        LaunchTrace.sceneDidBecomeActive()
    }
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
