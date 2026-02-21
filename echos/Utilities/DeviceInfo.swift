//
//  DeviceInfo.swift
//  echos
//
//  Created by Artem Rodionov on 21.02.2026.
//

import UIKit
/// Использовать не получится, требует специальный entitlement с iOS 16+.
enum DeviceInfo {
    
    /// Получить полное имя устройства из настроек.
    /// Возвращает имя типа "iPhone (имя)" вместо просто.
    static var deviceName: String {
        UIDevice.current.name
    }
    
    /// Альтернатива: возвращает только "iPhone",
    static var hostName: String {
        ProcessInfo.processInfo.hostName
    }
}
