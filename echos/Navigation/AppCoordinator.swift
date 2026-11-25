//
//  AppCoordinator.swift
//  echos
//
//  Владелец навигации. Экраны просят открыть маршрут, координатор решает,
//  как именно: к чему возвращаться, что создавать и когда.
//
//  Раньше каждый ViewController толкал следующий сам и сам помнил о входящих
//  (ссылка, поиск, баннер), которые пришли до готовности. Теперь переходы —
//  снаружи экранов, и ровно один исполнитель умеет отменять недоехавший
//  переход, когда пришёл следующий.
//
//  Экраны по-прежнему владеют своими локальными листами и алертами: это не
//  навигация, а часть самого экрана.
//

import UIKit
import SwiftUI

/// Куда можно пойти из приложения. Маршрутов нарочно мало — каждый новый
/// это ещё один внешний контракт вроде `DeepLink`.
enum AppRoute: Equatable {
    /// Открыть чат с адресом. `focus` — сообщение, на которое нажали в поиске.
    case conversation(address: String, name: String?, focus: UUID?)
    /// Экран тех, кто рядом.
    case nearby
    /// Своя стена.
    case ownWall

    /// Ссылка echos:// — всегда чат.
    init(_ link: DeepLink) {
        switch link {
        case .chat(let address):
            self = .conversation(address: address, name: nil, focus: nil)
        }
    }

    /// Результат системного поиска: запись о собеседнике ведёт в чат, запись
    /// о сообщении — в чат с фокусом на нём.
    init(_ target: SpotlightItems.Target) {
        switch target {
        case .conversation(let address):
            self = .conversation(address: address, name: nil, focus: nil)
        case .message(let id, let address):
            self = .conversation(address: address, name: nil, focus: id)
        }
    }
}

/// Единственный, кто двигает корневой стек навигации.
@MainActor
final class AppCoordinator {

    /// Лениво: создаётся после передачи `self` в корневой экран, иначе
    /// пришлось бы протаскивать частично инициализированный координатор.
    private(set) lazy var navigationController = UINavigationController(
        rootViewController: root
    )

    /// Модель живёт здесь, а не в главном экране: она нужна и соседним
    /// экранам (чат, рядом, стена), и переходам извне, которые приходят,
    /// пока главный экран ещё не создан.
    let viewModel: ChatViewModel

    private let root: DiscoveryViewController

    /// Кэш отрисованных мозаик общий с чатом: prefetch и ячейки готовят и
    /// берут одни и те же картинки.
    let mosaicCache: MosaicChatImageCache

    /// Маршрут, пришедший раньше готовности: хранилища подключаются в
    /// `startDiscovery()`, а ссылка или нажатие в поиске может прийти раньше.
    /// Ждёт здесь, а не в экране, — экран про pending больше не знает.
    private var pendingRoute: AppRoute?

    /// Хранилища подключены, модель прогрета — маршруты можно выполнять.
    private var isReady = false

    /// Последний запрошенный переход в чат. Поиск, ссылка, баннер и список
    /// могут прийти почти одновременно; без отмены два перехода открыли бы
    /// два чата поверх друг друга.
    private var openConversationTask: Task<Void, Never>?

    init(viewModel: ChatViewModel, mosaicCache: MosaicChatImageCache) {
        self.viewModel = viewModel
        self.mosaicCache = mosaicCache
        root = DiscoveryViewController(viewModel: viewModel)
        root.coordinator = self
    }

    deinit {
        openConversationTask?.cancel()
    }

    /// Модель готова принимать маршруты. Вызывается из `startDiscovery()`
    /// в тот момент, где раньше проверялся `isStarted`.
    func markReady() {
        isReady = true
        guard let route = pendingRoute else {
            return
        }
        pendingRoute = nil
        open(route)
    }

    /// Единая точка входа для всех просьб открыть экран: ссылка, поиск,
    /// баннер, список разговоров. Рано — встанет в очередь.
    func route(_ route: AppRoute) {
        guard isReady else {
            pendingRoute = route
            return
        }
        open(route)
    }

    // MARK: - Маршруты

    private func open(_ route: AppRoute) {
        switch route {
        case let .conversation(address, name, focus):
            openConversation(address: address, named: name, focusing: focus)
        case .nearby:
            let nearby = NearbyView(viewModel: viewModel) { [weak self] peer in
                self?.route(.conversation(address: peer.address,
                                          name: peer.displayName,
                                          focus: nil))
            }
            navigationController.pushViewController(NearbyHostingController(rootView: nearby),
                                                    animated: true)
        case .ownWall:
            openOwnWall()
        }
    }

    /// Открыть чат с адресом, откуда бы ни пришли: назад к корню и в чат.
    private func openConversation(address: String, named name: String?, focusing messageID: UUID?) {
        navigationController.popToRootViewController(animated: false)

        openConversationTask?.cancel()
        openConversationTask = Task { [weak self] in
            guard let self else {
                return
            }
            await viewModel.switchToConversation(with: address, named: name)
            guard !Task.isCancelled else {
                return
            }

            let chat = ChatViewController(viewModel: viewModel, cache: mosaicCache)
            chat.focusedMessageID = messageID
            navigationController.pushViewController(chat, animated: true)
            openConversationTask = nil
        }
    }

    private func openOwnWall() {
        guard let transport = viewModel.multipeerService else {
            return
        }

        let wall = WallView(
            viewModel: WallViewModel(owner: nil, transport: transport),
            ownAddress: transport.myAddress
        )

        // Радар прячет панель навигации, и стена без этой строки открывалась
        // бы без кнопки «назад». При возврате радар спрячет её снова сам.
        navigationController.setNavigationBarHidden(false, animated: true)
        navigationController.pushViewController(UIHostingController(rootView: wall),
                                                animated: true)
    }
}
