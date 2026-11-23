//
//  EnergyPolicyTests.swift
//  echosTests
//
//  Unit: правила энергопотребления — как тепловой режим меняет интервалы
//  и какие анимации замерзают.
//

import Foundation
import Testing
@testable import echos

struct EnergyPolicyTests {

    @Test func rssiInterval_scalesWithThermalState() {
        #expect(EnergyPolicy.rssiSimulationInterval(thermal: .nominal) == .seconds(3))
        #expect(EnergyPolicy.rssiSimulationInterval(thermal: .fair) == .seconds(3))
        #expect(EnergyPolicy.rssiSimulationInterval(thermal: .serious) == .seconds(8))
        #expect(EnergyPolicy.rssiSimulationInterval(thermal: .critical) == .seconds(15))
    }

    @Test func ambientAnimation_allowedOnlyWhenCool() {
        #expect(EnergyPolicy.allowsAmbientAnimation(.nominal))
        #expect(EnergyPolicy.allowsAmbientAnimation(.fair))
        #expect(!EnergyPolicy.allowsAmbientAnimation(.serious))
        #expect(!EnergyPolicy.allowsAmbientAnimation(.critical))
    }

    /// Тепловой режим сервис учитывает на каждом тике: поменялся режим —
    /// следующая пауза уже новая, перезапуск симуляции не нужен.
    @MainActor
    @Test func multipeer_appliesThermalIntervalWithoutRestart() async {
        let service = MultipeerService(identity: nil)
        service.rssiUpdateInterval = .milliseconds(50)

        service.startRSSISimulation()
        let started = await waitUntil { service.rssiSimulationTicks >= 2 }
        #expect(started)

        service.applyThermalState(.serious)
        #expect(service.rssiUpdateInterval == .seconds(8))

        service.applyThermalState(.critical)
        #expect(service.rssiUpdateInterval == .seconds(15))

        // Nominal возвращает исходный интервал: телефон остыл — работаем
        // как раньше.
        service.applyThermalState(.nominal)
        #expect(service.rssiUpdateInterval == .seconds(3))

        service.stopRSSISimulation()
    }

    /// Повторный вызов при том же режиме — ничего не делает.
    @MainActor
    @Test func multipeer_ignoresUnchangedThermalState() {
        let service = MultipeerService(identity: nil)
        service.applyThermalState(.nominal)
        #expect(service.rssiUpdateInterval == .seconds(3))
    }
}
