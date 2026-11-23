//
//  EnergyPolicy.swift
//  echos
//
//  Все решения об энергопотреблении в одном месте.
//
//  Телефон греется не от одной большой задачи, а от тысяч мелких пробуждений:
//  тик таймера, перерисовка, анимация. Правила здесь сознательно грубые —
//  serious/critical — это уже «система просит остыть», и единственный
//  честный ответ — делать меньше работы, а не умнее.
//

import Foundation

enum EnergyPolicy {

    /// Интервал тиков симуляции RSSI под тепловым режимом. Nominal — как
    /// было; serious/critical — тики реже: на телефоне, который и так горячий,
    /// лишние пробуждения в секунду не нужны.
    static func rssiSimulationInterval(thermal: ProcessInfo.ThermalState) -> Duration {
        switch thermal {
        case .nominal, .fair:
            .seconds(3)
        case .serious:
            .seconds(8)
        case .critical:
            .seconds(15)
        @unknown default:
            .seconds(8)
        }
    }

    /// Фоновые анимации (кольцо радара, точки «печатает») — украшения.
    /// При serious/critical они замерзают: движение на экране не важнее
    /// температуры руки.
    static func allowsAmbientAnimation(_ thermal: ProcessInfo.ThermalState) -> Bool {
        switch thermal {
        case .nominal, .fair:
            true
        case .serious, .critical:
            false
        @unknown default:
            false
        }
    }
}
