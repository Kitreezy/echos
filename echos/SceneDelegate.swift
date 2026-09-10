//
//  SceneDelegate.swift
//  echos
//
//  Created by Artem Rodionov on 16.02.2026.
//

import UIKit
 
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
 
    var window: UIWindow?
 
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)

        // Палитра echos тёмная всегда, а системные части интерфейса —
        // алерты, меню, клавиатура, статус-бар — рисуются в оформлении
        // телефона. На светлом телефоне они выходили светлыми поверх тёмного
        // приложения и выглядели чужими. Оформление задаётся окну целиком:
        // ставить его на каждый экран значит однажды забыть.
        window.overrideUserInterfaceStyle = .dark
        
        let discoveryVC = DiscoveryViewController()
        let navigationController = UINavigationController(rootViewController: discoveryVC)
        
//        navigationController.setNavigationBarHidden(true, animated: false)
        
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.tintColor = UIColor.inkMuted
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.surface
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.ink,
            .font: UIFont.systemFont(ofSize: 16, weight: .light),
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
    }
 
    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}

