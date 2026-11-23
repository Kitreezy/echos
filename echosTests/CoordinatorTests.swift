//
//  CoordinatorTests.swift
//  echosTests
//
//  Unit: маршруты — как внешние входы (ссылка, поиск) превращаются в
//  маршруты и как координатор откладывает их до готовности модели.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct CoordinatorTests {

    // MARK: - Разбор внешних входов

    @Test func deepLink_becomesConversationRoute() {
        let link = DeepLink.chat(address: "93f440ee4f07d563")
        #expect(AppRoute(link) == .conversation(address: "93f440ee4f07d563", name: nil, focus: nil))
    }

    @Test func spotlightConversation_becomesConversationRoute() {
        let target = SpotlightItems.Target.conversation(address: "93f440ee4f07d563")
        #expect(AppRoute(target) == .conversation(address: "93f440ee4f07d563", name: nil, focus: nil))
    }

    @Test func spotlightMessage_becomesConversationRouteWithFocus() {
        let id = UUID()
        let target = SpotlightItems.Target.message(id: id, address: "93f440ee4f07d563")
        #expect(AppRoute(target) == .conversation(address: "93f440ee4f07d563", name: nil, focus: id))
    }

    // MARK: - Очередь до готовности

    /// Регрессия pendingDeepLink/pendingSearchTarget: маршрут, пришедший до
    /// `markReady()`, не должен трогать стек — он ждёт и выполняется после.
    @Test func routeBeforeReady_waitsForMarkReady() async {
        let coordinator = AppCoordinator(viewModel: ChatViewModel(), mosaicCache: MosaicChatImageCache())
        #expect(coordinator.navigationController.viewControllers.count == 1)

        coordinator.route(.nearby)
        // До готовности стек не меняется: маршрут в очереди.
        #expect(coordinator.navigationController.viewControllers.count == 1)

        coordinator.markReady()

        let pushed = await waitUntil {
            coordinator.navigationController.viewControllers.count == 2
        }
        #expect(pushed, "Маршрут из очереди не выполнился после markReady()")
        #expect(coordinator.navigationController.viewControllers.last is NearbyViewController)
    }

    /// Маршрут, пришедший после готовности, выполняется сразу.
    @Test func routeAfterReady_executesImmediately() async {
        let coordinator = AppCoordinator(viewModel: ChatViewModel(), mosaicCache: MosaicChatImageCache())
        coordinator.markReady()

        coordinator.route(.nearby)

        let pushed = await waitUntil {
            coordinator.navigationController.viewControllers.count == 2
        }
        #expect(pushed)
        #expect(coordinator.navigationController.viewControllers.last is NearbyViewController)
    }

    /// Стена без транспорта (модель не инициализирована) — тихий пропуск,
    /// как раньше делал guard в самом контроллере.
    @Test func ownWallWithoutTransport_isNoOp() async {
        let coordinator = AppCoordinator(viewModel: ChatViewModel(), mosaicCache: MosaicChatImageCache())
        coordinator.markReady()

        coordinator.route(.ownWall)

        try? await Task.sleep(for: .milliseconds(300))
        #expect(coordinator.navigationController.viewControllers.count == 1)
    }

    /// Последний из серии маршрутов побеждает: два подряд — один чат,
    /// а не два поверх друг друга.
    @Test func secondRouteCancelsFirstConversation() async {
        let coordinator = AppCoordinator(viewModel: ChatViewModel(), mosaicCache: MosaicChatImageCache())
        coordinator.markReady()

        coordinator.route(.conversation(address: "first", name: nil, focus: nil))
        coordinator.route(.conversation(address: "second", name: nil, focus: nil))

        let settled = await waitUntil(timeout: .seconds(3)) {
            coordinator.navigationController.viewControllers.count == 2
        }
        #expect(settled, "После серии маршрутов в стеке должен быть ровно один чат")

        try? await Task.sleep(for: .milliseconds(500))
        #expect(coordinator.navigationController.viewControllers.count == 2,
                "Отменённый первый маршрут дожал стек вторым чатом")
        #expect(coordinator.navigationController.viewControllers.last is ChatViewController)
    }
}
