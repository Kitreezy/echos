//
//  ChatViewModelStreamTests.swift
//  echosTests
//
//  Unit: как ViewModel читает потоки транспорта после перехода на операторы.
//

import XCTest
@testable import echos

@MainActor
final class ChatViewModelStreamTests: XCTestCase {

    /// Интервалы в проде — сотни миллисекунд и секунды; в тестах их укорачиваем,
    /// иначе каждая проверка стоила бы несколько секунд ожидания.
    private func makeViewModel(
        transport: LoopbackTransport,
        store: SpyMessageStore = SpyMessageStore(),
        knownPeers: SpyKnownPeerStore = SpyKnownPeerStore()
    ) async -> ChatViewModel {
        let viewModel = ChatViewModel()
        viewModel.typingStartDelay = .milliseconds(50)
        viewModel.typingIdleTimeout = .milliseconds(250)
        viewModel.persistenceFlushInterval = .milliseconds(50)
        viewModel.knownPeerStore = knownPeers
        viewModel.initialize(transport: transport, store: store)

        // Подписка встаёт внутри Task, а не синхронно в initialize().
        _ = await waitUntil { transport.pipelinesConnected >= 1 }

        return viewModel
    }

    /// Отправка адресная, поэтому собеседник должен быть выбран.
    /// Раньше сообщения уходили всем подряд, и тестам это было не нужно.
    private func makeViewModelInConversation(
        transport: LoopbackTransport,
        store: SpyMessageStore = SpyMessageStore(),
        knownPeers: SpyKnownPeerStore = SpyKnownPeerStore(),
        with peer: String = "Bob",
        named name: String? = nil
    ) async -> ChatViewModel {
        let viewModel = await makeViewModel(transport: transport,
                                            store: store,
                                            knownPeers: knownPeers)
        viewModel.currentConversationPeer = peer
        viewModel.currentConversationName = name
        return viewModel
    }

    private func payload(_ text: String, from sender: String = "Alice") -> MessagePayload {
        MessagePayload(from: Message(text: text, isFromMe: false), senderName: sender)
    }

    // MARK: - Слияние потоков

    func test_mergedLoop_handlesAllThreeStreams() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(message: payload("привет"))
        transport.emit(typing: TypingEvent(type: .start, peerName: "Alice"))
        transport.emit(peers: [Peer(displayName: "Alice")])

        let gotMessage = await waitUntil { viewModel.messages.count == 1 }
        let gotTyping = await waitUntil { viewModel.typingPeerName == "Alice" }
        let gotPeers = await waitUntil { viewModel.peers.count == 1 }

        XCTAssertTrue(gotMessage)
        XCTAssertTrue(gotTyping)
        XCTAssertTrue(gotPeers)
    }

    /// Регрессия: `initialize()` вызывается повторно (возврат из фона, смена
    /// экрана). Раньше каждый вызов добавлял ещё три подписки, и одно входящее
    /// сообщение попадало в список несколько раз.
    func test_repeatedInitialize_doesNotDuplicateIncomingMessages() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        viewModel.initialize(transport: transport, store: SpyMessageStore())
        viewModel.initialize(transport: transport, store: SpyMessageStore())

        let reconnected = await waitUntil { transport.pipelinesConnected == 3 }
        XCTAssertTrue(reconnected)

        transport.emit(message: payload("однажды"))

        _ = await waitUntil { viewModel.messages.count == 1 }
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(viewModel.messages.count, 1)
    }

    // MARK: - Дедупликация пиров

    func test_duplicatePeerUpdates_areAppliedOnce() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        let id = UUID()
        func snapshot(status: PeerStatus) -> [Peer] {
            [Peer(id: id, displayName: "Alice", status: status, lastSeen: Date(), rssi: -50)]
        }

        transport.emit(peers: snapshot(status: .notConnected))
        let applied = await waitUntil { viewModel.appliedPeerUpdates == 1 }
        XCTAssertTrue(applied)

        // Повтор отличается только временем последнего обнаружения.
        transport.emit(peers: snapshot(status: .notConnected))
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(viewModel.appliedPeerUpdates, 1, "Содержательный дубликат не должен доходить до UI")

        // Реальное изменение статуса пройти обязано.
        transport.emit(peers: snapshot(status: .connected))
        let secondApplied = await waitUntil { viewModel.appliedPeerUpdates == 2 }

        XCTAssertTrue(secondApplied)
        XCTAssertEqual(viewModel.peers.first?.status, .connected)
    }

    // MARK: - Индикатор набора

    func test_burstOfKeystrokes_sendsSingleTypingStart() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport)

        for _ in 0..<10 {
            viewModel.startTyping()
            try? await Task.sleep(for: .milliseconds(10))
        }

        let started = await waitUntil { transport.sentTypingTypes.contains(.start) }

        XCTAssertTrue(started)
        XCTAssertEqual(transport.sentTypingTypes.filter { $0 == .start }.count, 1,
                       "Серия нажатий должна давать ровно один start")
    }

    func test_pauseAfterTyping_sendsStop() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport)

        viewModel.startTyping()

        let started = await waitUntil { transport.sentTypingTypes.contains(.start) }
        XCTAssertTrue(started)

        let stopped = await waitUntil { transport.sentTypingTypes.contains(.stop) }

        XCTAssertTrue(stopped, "После паузы дольше typingIdleTimeout должен уйти stop")
        XCTAssertEqual(transport.sentTypingTypes, [.start, .stop])
    }

    func test_explicitStopTyping_doesNotSendStopTwice() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport)

        viewModel.startTyping()
        _ = await waitUntil { transport.sentTypingTypes.contains(.start) }

        viewModel.stopTyping()
        _ = await waitUntil { transport.sentTypingTypes.contains(.stop) }

        // Ждём, пока сработает и отложенный stop по таймауту бездействия.
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(transport.sentTypingTypes.filter { $0 == .stop }.count, 1)
    }

    // MARK: - Очередь записи

    func test_incomingMessages_arePersistedInOrder() async {
        let transport = LoopbackTransport()
        let store = SpyMessageStore()
        let viewModel = await makeViewModel(transport: transport, store: store)

        transport.emit(message: payload("раз"))
        transport.emit(message: payload("два"))
        transport.emit(message: payload("три"))

        let persisted = await waitUntil { store.saved.count == 3 }

        XCTAssertTrue(persisted)
        XCTAssertEqual(store.savedTexts, ["раз", "два", "три"])
        XCTAssertEqual(viewModel.messages.count, 3)
    }

    func test_sentMessage_isPersistedWithFinalStatus() async {
        let transport = LoopbackTransport()
        let store = SpyMessageStore()
        let viewModel = await makeViewModelInConversation(transport: transport, store: store)

        await viewModel.sendMessage("исходящее")

        let persisted = await waitUntil { store.saved.contains { $0.text == "исходящее" } }

        XCTAssertTrue(persisted)
        XCTAssertEqual(store.saved.last?.status, .sent)
        XCTAssertEqual(transport.sentMessages.count, 1)
        XCTAssertEqual(transport.sentMessages.first?.recipient, "Bob",
                       "Переписка один на один и есть один на один")
    }

    /// Без выбранного собеседника отправлять некому. Раньше сообщение
    /// уходило всем на релее, теперь помечается непосланным.
    func test_messageWithoutConversation_isMarkedFailed() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)
        viewModel.currentConversationPeer = nil

        await viewModel.sendMessage("в никуда")

        XCTAssertTrue(transport.sentMessages.isEmpty)
        XCTAssertEqual(viewModel.messages.last?.status, .failed)
    }

    // MARK: - Адресация

    /// Ради этого вся адресация по ключу и затевалась.
    func test_messageFromANamesake_doesNotEnterTheOpenConversation() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport, with: "bob-address")

        _ = await waitUntil { transport.pipelinesConnected >= 1 }

        // Самозванец подписывается именем Bob, но приходит с другого адреса.
        transport.emit(message: payload("я Bob, честно", from: "Bob"),
                       from: "impostor-address")

        let leaked = await waitUntil(timeout: .milliseconds(300)) {
            viewModel.messages.contains { $0.text == "я Bob, честно" }
        }

        XCTAssertFalse(leaked, "В открытую переписку попадает только то, что пришло с её адреса")
    }

    func test_messageFromTheConversationAddress_isShown() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport, with: "bob-address")

        _ = await waitUntil { transport.pipelinesConnected >= 1 }

        transport.emit(message: payload("настоящий Bob", from: "Bob"), from: "bob-address")

        let shown = await waitUntil {
            viewModel.messages.contains { $0.text == "настоящий Bob" }
        }

        XCTAssertTrue(shown)
    }

    /// Индикатор набора гасит тот же, кто его зажёг.
    func test_typingStopFromAnotherAddress_doesNotClearTheIndicator() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        _ = await waitUntil { transport.pipelinesConnected >= 1 }

        transport.emit(typing: TypingEvent(type: .start, peerName: "Bob"), from: "bob-address")
        _ = await waitUntil { viewModel.typingPeerName == "Bob" }

        transport.emit(typing: TypingEvent(type: .stop, peerName: "Bob"), from: "impostor-address")

        let cleared = await waitUntil(timeout: .milliseconds(300)) {
            viewModel.typingPeerName == nil
        }

        XCTAssertFalse(cleared, "Погасить чужой индикатор, назвавшись тем же именем, нельзя")
    }

    // MARK: - Узнавание

    /// Знакомство заводится разговором, а не встречей: иначе знакомыми стали
    /// бы все, кто попал в список, и отличать тёзку было бы не от кого.
    func test_seeingAPeer_doesNotMakeItKnown() async {
        let transport = LoopbackTransport()
        let knownPeers = SpyKnownPeerStore()
        let viewModel = await makeViewModel(transport: transport, knownPeers: knownPeers)

        transport.emit(peers: [Peer(address: "bob-address", displayName: "Bob")])
        _ = await waitUntil { !viewModel.peers.isEmpty }

        XCTAssertTrue(knownPeers.remembered.isEmpty)
    }

    func test_sendingAMessage_remembersTheRecipient() async {
        let transport = LoopbackTransport()
        let knownPeers = SpyKnownPeerStore()
        let viewModel = await makeViewModelInConversation(transport: transport,
                                                          knownPeers: knownPeers,
                                                          with: "bob-address",
                                                          named: "Bob")

        await viewModel.sendMessage("привет")

        XCTAssertEqual(knownPeers.remembered.map(\.address), ["bob-address"])
        XCTAssertEqual(knownPeers.remembered.map(\.name), ["Bob"])
    }

    func test_afterTalking_thePeerIsRecognized() async {
        let transport = LoopbackTransport()
        let knownPeers = SpyKnownPeerStore()
        let viewModel = await makeViewModelInConversation(transport: transport,
                                                          knownPeers: knownPeers,
                                                          with: "bob-address",
                                                          named: "Bob")

        await viewModel.sendMessage("привет")

        let bob = Peer(address: "bob-address", displayName: "Bob")
        let namesake = Peer(address: "someone-else", displayName: "Bob")

        XCTAssertEqual(viewModel.recognition(for: bob), .known)
        XCTAssertEqual(viewModel.recognition(for: namesake), .namesake)
    }

    /// Список знакомых поднимается до первого присутствия, иначе первые
    /// доли секунды все выглядели бы незнакомцами.
    func test_startingDiscovery_loadsKnownPeersFirst() async {
        let transport = LoopbackTransport()
        let knownPeers = SpyKnownPeerStore()
        knownPeers.preloaded = [KnownPeer(address: "bob-address",
                                          name: "Bob",
                                          firstSeen: Date(),
                                          lastSeen: Date())]

        let viewModel = await makeViewModel(transport: transport, knownPeers: knownPeers)
        await viewModel.startDeviceDiscovery()

        let bob = Peer(address: "bob-address", displayName: "Bob")
        XCTAssertEqual(viewModel.recognition(for: bob), .known)
    }

    // MARK: - Строка под заголовком

    private func peer(_ address: String,
                      _ name: String,
                      _ status: PeerStatus = .connected) -> Peer {
        Peer(address: address, displayName: name, status: status)
    }

    func test_reachablePeer_saysNothing() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport,
                                                          with: "bob-address",
                                                          named: "Bob")

        transport.emit(peers: [peer("bob-address", "Bob")])
        _ = await waitUntil { !viewModel.peers.isEmpty }

        XCTAssertEqual(viewModel.connectionStatus, "",
                       "Имя собеседника уже стоит в заголовке")
    }

    func test_peerNotInTheRoom_saysSo() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport,
                                                          with: "bob-address",
                                                          named: "Bob")

        transport.emit(peers: [peer("someone-else", "Carol")])
        _ = await waitUntil { !viewModel.peers.isEmpty }

        XCTAssertEqual(viewModel.connectionStatus, "не на связи")
    }

    /// Раньше строка перечисляла всех, кто на связи, и с тёзками читалась
    /// буквально как «Bob, Bob».
    func test_namesakeInTheRoom_doesNotLeakIntoTheSubtitle() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport,
                                                          with: "bob-address",
                                                          named: "Bob")

        transport.emit(peers: [peer("bob-address", "Bob"),
                               peer("impostor-address", "Bob")])
        _ = await waitUntil { viewModel.peers.count == 2 }

        XCTAssertEqual(viewModel.connectionStatus, "")
    }

    /// Вне чата сказать можно только сколько рядом: перечислять имена
    /// там некому и незачем.
    func test_withoutAConversation_countsInstead() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(peers: [peer("a", "Bob", .notConnected),
                               peer("b", "Carol", .notConnected)])
        _ = await waitUntil { viewModel.peers.count == 2 }

        XCTAssertEqual(viewModel.connectionStatus, "Рядом: 2")
    }

    // MARK: - Список собеседников

    /// Двое, подключившиеся почти одновременно, попадали в одно окно
    /// `_throttle(latest:)`, и последнее значение придерживалось до следующего
    /// события — которого могло не быть. Список оставался отстающим на одно
    /// обновление: на экране «рядом 1», на релее двое.
    func test_peersArrivingTogether_allReachTheList() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(peers: [peer("bob", "Bob")])
        transport.emit(peers: [peer("bob", "Bob"), peer("carol", "Carol")])

        let both = await waitUntil { viewModel.peers.count == 2 }

        XCTAssertTrue(both, "На экране осталось \(viewModel.peers.count) из двух")
        XCTAssertEqual(viewModel.peers.map(\.address).sorted(), ["bob", "carol"])
    }

    /// Уход последнего собеседника — тоже конец серии, и его тоже теряли.
    func test_lastPeerLeaving_emptiesTheList() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(peers: [peer("bob", "Bob")])
        _ = await waitUntil { !viewModel.peers.isEmpty }

        transport.emit(peers: [])

        let emptied = await waitUntil { viewModel.peers.isEmpty }
        XCTAssertTrue(emptied)
    }

    // MARK: - Автопереход

    /// Раньше очередное присутствие открывало чат с первым подключённым
    /// собеседником поверх уже открытого. Через релей на связи сразу все, и
    /// первым оказывается кто угодно.
    func test_incomingPresence_leavesTheOpenConversationAlone() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModelInConversation(transport: transport,
                                                          with: "bob-address",
                                                          named: "Bob")

        transport.emit(peers: [peer("someone-else", "Carol")])
        _ = await waitUntil { !viewModel.peers.isEmpty }

        XCTAssertEqual(viewModel.currentConversationPeer, "bob-address")
        XCTAssertEqual(viewModel.currentConversationName, "Bob")
    }

    /// Но когда чат не открыт, подключившийся собеседник его открывает —
    /// у Multipeer это момент, когда приглашение приняли.
    func test_withoutAConversation_connectedPeerOpensOne() async {
        let transport = LoopbackTransport()
        let viewModel = await makeViewModel(transport: transport)

        transport.emit(peers: [peer("bob-address", "Bob")])
        _ = await waitUntil { viewModel.currentConversationPeer != nil }

        XCTAssertEqual(viewModel.currentConversationPeer, "bob-address")
        XCTAssertEqual(viewModel.currentConversationName, "Bob")
    }
}
