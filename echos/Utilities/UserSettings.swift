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
    
    @MainActor
    static var displayName: String {
        if let customName = userName, !customName.isEmpty {
            return customName
        }
        
        return DeviceInfo.deviceName
    }
    /// Сбросить настройки 
    static func rest() {
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: relayURLKey)
    }
}
