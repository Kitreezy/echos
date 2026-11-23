//
//  CompositionRoot.swift
//  echos
//
//  Корень композиции: единственное место, где собирается граф объектов
//  приложения. Без фреймворка — обычные инициализаторы и явные параметры;
//  кто что получает, видно здесь, а не размазано по синглтонам с дефолтными
//  аргументами.
//
//  Фабрика — не Service Locator: корень создаёт экземпляры один раз и
//  передаёт дальше по ссылке. Тесты собирают тот же граф сами и подменяют
//  любое звено, ничего глобально не трогая.
//

import Foundation

/// Где запущено приложение. Решения об окружении принимает корень, а не
/// фабрики в глубине — тест может собрать граф для любого окружения явно.
enum AppEnvironment: Equatable {
    /// Обычный запуск: транспорт по настройкам приложения.
    case production
    /// UI-тесты: собеседники и переписка — декорация, см. UITestMode.
    case uiTests

    static func current() -> AppEnvironment {
        UITestMode.isActive ? .uiTests : .production
    }
}

/// Собранный граф. SceneDelegate берёт отсюда координатор; экраны дальше
/// получают зависимости через инициализаторы.
@MainActor
final class CompositionRoot {

    let environment: AppEnvironment

    /// Общий для экранов владелец состояния.
    let viewModel: ChatViewModel

    /// Кэш отрисованных мозаик. Один на граф — общий для чата и ячеек.
    let mosaicCache: MosaicChatImageCache

    let coordinator: AppCoordinator

    init(environment: AppEnvironment) {
        self.environment = environment

        let cache = MosaicChatImageCache()
        self.mosaicCache = cache

        let viewModel = ChatViewModel()
        self.viewModel = viewModel

        // Транспорт решает корень: VM просит фабрику у владельца, а не
        // читает окружение сама. Так uiTests-тест получает DemoTransport,
        // не подменяя глобальное состояние.
        viewModel.makeTransport = { [environment] in
            switch environment {
            case .production:
                PeerTransportFactory.make()
            case .uiTests:
                DemoTransport()
            }
        }

        self.coordinator = AppCoordinator(viewModel: viewModel, mosaicCache: cache)
    }
}
