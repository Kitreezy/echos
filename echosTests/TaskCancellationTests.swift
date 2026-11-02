//
//  TaskCancellationTests.swift
//  echosTests
//
//  Unit: задачи отменяются вместе с владельцем, подписки не переживают
//  подписчика.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct TaskCancellationTests {

    /// Регрессия: симуляция RSSI была цепочкой `Task { sleep; simulate() }`
    /// без ручки — не отменялась и обновляла присутствие у выключенного
    /// сервиса.
    @Test func rssiSimulation_stopsWhenStopped() async {
        let service = MultipeerService(identity: nil)
        service.rssiUpdateInterval = .milliseconds(50)

        service.startRSSISimulation()
        let started = await waitUntil { service.rssiSimulationTicks >= 2 }
        #expect(started)

        service.stopRSSISimulation()
        let frozen = service.rssiSimulationTicks
        try? await Task.sleep(for: .milliseconds(200))

        #expect(service.rssiSimulationTicks == frozen, "Тики продолжаются после остановки")
    }

    /// Регрессия: циклы чтения потоков были методами, а запущенный метод
    /// держит модель сильно — она не умирала, и подписки висели вечно.
    /// Модель умерла — все её подписки сняты, и транспорт не держит
    /// мёртвых подписчиков.
    @Test func deallocatedViewModel_releasesAllSubscriptions() async {
        let transport = LoopbackTransport()
        var viewModel: ChatViewModel? = ChatViewModel()
        viewModel?.initialize(transport: transport, store: SpyMessageStore())

        let subscribed = await waitUntil { transport.liveSubscriptions > 0 }
        #expect(subscribed)

        viewModel = nil

        let released = await waitUntil { transport.liveSubscriptions == 0 }
        #expect(released, "Подписки остались после смерти модели: задачи не отменены")
    }
}
