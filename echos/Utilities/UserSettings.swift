//
//  UserSettings.swift
//  echos
//
//  Created by Artem Rodionov on 24.02.2026.
//

import Foundation

enum UserSettings {
    
    private static let userNameKey = "echos_user_name"
    private static let relayURLKey = "echos_relay_url"
    private static let demoPeersKey = "echos_demo_peers"
    
    static var userName: String? {
        get {
            UserDefaults.standard.string(forKey: userNameKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userNameKey)
        }
    }
    
    static var hasCompletedOnboarding: Bool {
        userName != nil
    }
    
    /// Адрес WebSocket-релея. Пусто — работаем через MultipeerConnectivity,
    /// то есть только с устройствами рядом. Задан — идём через релей и видим
    /// собеседников из любой сети.
    static var relayURL: URL? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: relayURLKey),
                  !raw.isEmpty else {
                return nil
            }
            return URL(string: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: relayURLKey)
        }
    }
    
    /// Показывать выдуманный список устройств, когда рядом никого нет.
    ///
    /// Нужен, чтобы смотреть вёрстку экрана поиска без второго телефона.
    /// В обычном запуске выключен: на боевом релее четыре несуществующих
    /// собеседника выглядят как поломка, а не как демонстрация.
    ///
    /// Включается аргументом запуска в схеме: `-echos_demo_peers YES`.
    static var showsDemoPeers: Bool {
        UserDefaults.standard.bool(forKey: demoPeersKey)
    }
    
    /// Имя, под которым нас видят остальные.
    ///
    /// Запасного варианта из имени устройства здесь больше нет. С iOS 16
    /// `UIDevice.current.name` возвращает не имя из настроек, а модель —
    /// «iPhone» у всех подряд, и весь список собеседников состоял из
    /// одинаковых строк. Имя спрашивается при первом запуске, до того как
    /// начнётся поиск, так что подставлять сюда нечего.
    static var displayName: String {
        guard let name = userName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "Без имени"
        }

        return name
    }
    /// Сбросить настройки 
    static func rest() {
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: relayURLKey)
        UserDefaults.standard.removeObject(forKey: demoPeersKey)
    }
}
