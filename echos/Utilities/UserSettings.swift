//
//  UserSettings.swift
//  echos
//
//  Created by Artem Rodionov on 24.02.2026.
//

import Foundation

enum UserSettings {
    
    private static let userNameKey = "echos_user_name"
    
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
    }
}
