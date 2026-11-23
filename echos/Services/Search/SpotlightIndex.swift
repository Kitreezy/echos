//
//  SpotlightIndex.swift
//  echos
//
//  Индекс echos в системном поиске.
//
//  Индекс свой, а не общий `CSSearchableIndex.default()`, ради класса защиты
//  `.complete`: пока телефон заблокирован, записи зашифрованы и прочитать
//  их не может никто, включая сам поиск. Переписка в echos шифруется в пути;
//  было бы странно, если бы она лежала открытой на устройстве.
//
//  Индекс живёт только на телефоне: Spotlight не отправляет его ни в
//  iCloud, ни на другие устройства. Если человек не хочет видеть переписку в
//  поиске, он выключает это в меню чата — индекс стирается целиком.
//

import CoreSpotlight
import OSLog

/// Шов между хранилищами и поиском. Тесты подставляют запись вызовов.
@MainActor
protocol SearchIndexing: AnyObject {
    func index(_ message: Message) async
    func remember(name: String, for address: String) async
    /// Убрать собеседника из поиска, не трогая переписку с ним.
    func forget(address: String) async
    func remove(_ messages: [Message]) async
    func removeConversation(with address: String) async
    func removeAll() async
}

@MainActor
final class SpotlightIndex: SearchIndexing {

    static let shared = SpotlightIndex()

    /// Поднимается, когда меняется то, что попадает в индекс. Тогда при
    /// следующем запуске индекс пересобирается из истории.
    static let version = 1

    private let index = CSSearchableIndex(name: "echos", protectionClass: .complete)

    /// Имена собеседников по адресу. У своего сообщения имени собеседника
    /// нет — оно берётся отсюда.
    private var names: [String: String] = [:]

    private var isEnabled: Bool {
        UserSettings.showsInSearch && !UITestMode.isActive
    }

    func index(_ message: Message) async {
        if !message.isFromMe, let address = message.peerAddress, let name = message.senderName,
           names[address] == nil {
            names[address] = name
        }
        guard isEnabled,
              let item = SpotlightItems.message(message, peerName: message.peerAddress.flatMap { names[$0] }) else {
            return
        }
        await perform("index message") { $0.indexSearchableItems([item], completionHandler: $1) }
    }

    func remember(name: String, for address: String) async {
        names[address] = name
        guard isEnabled else {
            return
        }
        let item = SpotlightItems.person(address: address, name: name)
        await perform("index person") { $0.indexSearchableItems([item], completionHandler: $1) }
    }

    func forget(address: String) async {
        names[address] = nil
        let id = SpotlightItems.identifier(for: .conversation(address: address))
        await perform("forget person") { $0.deleteSearchableItems(withIdentifiers: [id], completionHandler: $1) }
    }

    func remove(_ messages: [Message]) async {
        let ids = messages.compactMap { message in
            message.peerAddress.map { SpotlightItems.identifier(for: .message(id: message.id, address: $0)) }
        }
        guard !ids.isEmpty else {
            return
        }
        await perform("remove messages") { $0.deleteSearchableItems(withIdentifiers: ids, completionHandler: $1) }
    }

    func removeConversation(with address: String) async {
        let domain = SpotlightItems.domain(of: address)
        await perform("remove conversation") {
            $0.deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: $1)
        }
    }

    func removeAll() async {
        await perform("remove all") { $0.deleteAllSearchableItems(completionHandler: $1) }
    }

    /// Собрать индекс заново из истории: при первом запуске с поиском, после
    /// смены `version` и когда человек снова включил поиск.
    func rebuild(messages: any MessageStoring, people: any KnownPeerStoring) async {
        guard isEnabled else {
            return
        }
        do {
            let known = try await people.loadKnownPeers()
            for peer in known {
                names[peer.address] = peer.name
            }
            let history = try await messages.loadMessages()

            let items = known.map { SpotlightItems.person(address: $0.address, name: $0.name) }
                + history.compactMap { message in
                    SpotlightItems.message(message, peerName: message.peerAddress.flatMap { names[$0] })
                }

            await removeAll()
            await perform("rebuild") { $0.indexSearchableItems(items, completionHandler: $1) }
            UserSettings.searchIndexVersion = Self.version
            Logger.search.notice("Индекс пересобран: \(known.count) собеседников, \(history.count) сообщений")
        } catch {
            Logger.search.error("Индекс не пересобран: \(error)")
        }
    }

    /// Пересобрать, если индекс собран старой версией или не собирался.
    func rebuildIfNeeded(messages: any MessageStoring, people: any KnownPeerStoring) async {
        guard UserSettings.searchIndexVersion != Self.version else {
            return
        }
        await rebuild(messages: messages, people: people)
    }

    /// Ошибка индекса не должна ломать сохранение сообщения: поиск —
    /// удобство, история — главное. Поэтому здесь только запись в журнал.
    ///
    /// Вызовы — с completion handler, а не `async`: `CSSearchableIndex` не
    /// `Sendable`, и Swift 6 не даёт отдать его неизолированному async-методу.
    /// Так индекс не покидает главный актор, через границу идёт только ответ.
    private func perform(_ action: String,
                         _ body: (CSSearchableIndex, @escaping @Sendable (Error?) -> Void) -> Void) async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                body(index) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            Logger.search.error("Spotlight, \(action, privacy: .public): \(error, privacy: .public)")
        }
    }
}
