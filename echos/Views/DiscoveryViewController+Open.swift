//
//  DiscoveryViewController+Open.swift
//  echos
//
//  Переход в чат извне главного экрана: из уведомления о сообщении и из
//  системного поиска.
//

import UIKit

extension DiscoveryViewController {

    /// Открыть то, что нашли поиском: чат, а если нашли сообщение — то и
    /// само сообщение в нём.
    func open(_ target: SpotlightItems.Target) {
        guard isStarted else {
            pendingSearchTarget = target
            return
        }
        switch target {
        case let .conversation(address):
            open(conversationWith: address, named: nil)
        case let .message(id, address):
            open(conversationWith: address, named: nil, focusing: id)
        }
    }

    /// Открыть чат с человеком, откуда бы ни нажали: назад к корню и в чат.
    func open(conversationWith address: String, named name: String?, focusing messageID: UUID? = nil) {
        guard let navigation = navigationController else {
            return
        }
        navigation.popToRootViewController(animated: false)

        Task {
            await viewModel.switchToConversation(with: address, named: name)
            let chat = ChatViewController(viewModel: viewModel)
            chat.focusedMessageID = messageID
            navigation.pushViewController(chat, animated: true)
        }
    }
}
