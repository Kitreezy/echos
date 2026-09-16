//
//  WebSocketTransportTests.swift
//  echosTests
//
//  Вторая реализация `PeerTransport` против настоящего релея: два «устройства»
//  в одном процессе видят друг друга и обмениваются сообщениями.
//

import XCTest
@testable import echos

@MainActor
final class WebSocketTransportTests: XCTestCase {

    private var server: RelayServer!
    private var monitor: FakeNetworkMonitor!

    override func setUp() async throws {
        try await super.setUp()
        server = RelayServer()
        try await server.start()
        monitor = FakeNetworkMonitor()
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
        monitor = nil
        try await super.tearDown()
    }

    /// У каждого транспорта свой ключ: на одном устройстве их два, а для
    /// релея это должны быть двое разных людей.
    private func makeTransport(named name: String) -> WebSocketTransport {
        WebSocketTransport(url: server.url,
                           displayName: name,
                           identity: DeviceIdentity(),
                           networkMonitor: monitor)
    }

    /// Поднимает оба транспорта и ждёт, пока сервер увидит обоих.
    private func makePair() async -> (alice: WebSocketTransport, bob: WebSocketTransport) {
        let alice = makeTransport(named: "Alice")
        let bob = makeTransport(named: "Bob")

        alice.startDeviceDiscovery()
        bob.startDeviceDiscovery()

        _ = await waitUntil { self.server.connectedClientCount == 2 }

        return (alice, bob)
    }

    // MARK: - Присутствие

    func test_twoTransports_seeEachOtherInPeerStream() async {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        // Сервер насчитал двоих раньше, чем клиент перевёл своё состояние:
        // ждём его, а не утверждаем с ходу.
        let connected = await waitUntil { alice.connectionState == .connected }
        XCTAssertTrue(connected)

        // Ждём именно появления собеседника: до этого поток успевает отдать
        // пустой список — присутствие с одной лишь Alice.
        let peers = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            !$0.isEmpty
        }

        XCTAssertEqual(peers?.map(\.displayName), ["Bob"],
                       "Себя в списке собеседников быть не должно")
        XCTAssertEqual(peers?.first?.status, .connected)
    }

    func test_peerIdentifiers_areStableAcrossPresenceUpdates() async {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let first = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            $0.contains { $0.displayName == "Bob" }
        }?.first?.id

        // Третий участник вызывает новую рассылку присутствия.
        let carol = makeTransport(named: "Carol")
        carol.startDeviceDiscovery()
        defer { carol.stopDeviceDiscovery() }

        let updated = await waitUntil(timeout: .seconds(5)) {
            self.server.connectedClientCount == 3
        }
        XCTAssertTrue(updated)

        let second = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            $0.count == 2
        }?.first { $0.displayName == "Bob" }?.id

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second, "Идентификатор пира не должен меняться от обновления к обновлению")
    }

    // MARK: - Обмен

    func test_message_isDeliveredToTheOtherTransport() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let incoming = bob.messageStream
        // Слать можно только тому, чей ключ уже пришёл с присутствием.
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }

        let payload = MessagePayload(from: Message(text: "привет из сети", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: bob.myAddress)

        let received = await collect(incoming, count: 1, timeout: .seconds(5))

        XCTAssertEqual(received.first?.value.text, "привет из сети")
        XCTAssertEqual(received.first?.value.senderName, "Alice")
        XCTAssertEqual(received.first?.sender, alice.myAddress,
                       "Отправителя проставляет релей, из ключа")
    }

    /// Ради этого всё и затевалось: релей сообщение переносит, но прочитать
    /// не может.
    func test_relay_doesNotSeeTheText() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let incoming = bob.messageStream
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }

        let payload = MessagePayload(from: Message(text: "только для Боба", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: bob.myAddress)

        let received = await collect(incoming, count: 1, timeout: .seconds(5))
        XCTAssertEqual(received.first?.value.text, "только для Боба", "До Боба текст дошёл")

        let passedThrough = server.received.filter { $0.kind == .message }
        XCTAssertEqual(passedThrough.count, 1)
        for envelope in passedThrough {
            let wire = String(decoding: try envelope.encoded(), as: UTF8.self)
            XCTAssertFalse(wire.contains("только для Боба"), "Текст виден серверу")
            XCTAssertFalse(wire.contains(payload.id), "Идентификатор сообщения тоже под замком")
        }
    }

    /// Релей, который ключи не пересылает (старая сборка сервера), даёт
    /// пустой список: писать этим людям нечем.
    func test_relayWithoutKeys_listsNobody() async {
        server.forwardsKeys = false
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let stream = alice.peerStream
        let lists = await collect(stream, count: 1, timeout: .seconds(3))

        XCTAssertTrue(lists.allSatisfy(\.isEmpty))

        do {
            let payload = MessagePayload(from: Message(text: "в никуда", isFromMe: true),
                                         senderName: "Alice")
            try await alice.sendMessage(payload, to: bob.myAddress)
            XCTFail("Без ключа собеседника отправлять нечем")
        } catch let error as RelayError {
            XCTAssertEqual(error, .noCipher(bob.myAddress))
        } catch {
            XCTFail("Не та ошибка: \(error)")
        }
    }

    /// Конверт, которого Алиса не отправляла: релей (или кто-то за ним)
    /// подделал сообщение от её имени. Не откроется — и не дойдёт.
    func test_forgedMessage_isDropped() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let incoming = bob.messageStream
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }

        // Мэллори притворяется Алисой: подписаться на релее её ключом
        // не может, поэтому шлёт от себя — сервер проставит её адрес,
        // а Боб такого адреса не знает. Проверяем и второй путь: конверт
        // с адресом Алисы, но чужим содержимым.
        let forged = SealedPayload(version: 1, box: Data(repeating: 0x42, count: 60))
        try await alice.sendSealed(forged, to: bob.myAddress)

        let received = await collect(incoming, count: 1, timeout: .seconds(2))
        XCTAssertTrue(received.isEmpty, "Подделка не должна пройти")
    }

    func test_typingEvent_isDeliveredToTheOtherTransport() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let incoming = bob.typingStream

        try await alice.sendTypingEvent(TypingEvent(type: .start, peerName: "Alice"), to: bob.myAddress)

        let received = await collect(incoming, count: 1, timeout: .seconds(5))

        XCTAssertEqual(received.first?.value.type, .start)
        XCTAssertEqual(received.first?.value.peerName, "Alice")
        XCTAssertEqual(received.first?.sender, alice.myAddress)
    }

    /// Отправитель не должен получать собственное сообщение обратно.
    func test_sender_doesNotReceiveItsOwnMessage() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let echoed = alice.messageStream

        let payload = MessagePayload(from: Message(text: "эхо", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: bob.myAddress)

        _ = await collect(bob.messageStream, count: 1, timeout: .seconds(5))
        let ownMessages = await collect(echoed, count: 1, timeout: .milliseconds(300))

        XCTAssertTrue(ownMessages.isEmpty)
    }

    // MARK: - Восстановление сессии

    /// После перезапуска сервера транспорт обязан не только переподключиться,
    /// но и заново представиться — иначе он будет «онлайн», но невидим.
    func test_afterServerRestart_transportReannouncesItself() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        // Считаем только то, что придёт после обрыва.
        server.clearReceived()
        try await server.restart()

        let reannounced = await waitUntil(timeout: .seconds(15)) {
            self.server.received.filter { $0.kind == .hello }.count >= 2
        }

        XCTAssertTrue(reannounced, "После реконнекта hello должен уйти повторно")
    }

    // MARK: - Смена сессионного ключа

    /// Сессионные ключи: те, что ушли в hello до обрыва, и те, что после.
    private func sessionKeys(in hellos: [RelayEnvelope]) -> [Data] {
        hellos.compactMap { envelope in
            guard let payload = envelope.payload,
                  let hello = try? JSONDecoder().decode(HelloPayload.self, from: payload) else {
                return nil
            }
            return hello.sessionKey
        }
    }

    /// После переподключения у обоих новые сессионные ключи — и переписка
    /// продолжается: шифры пересобрались из свежего присутствия.
    func test_afterReconnect_sessionKeysChangeAndMessagesStillFlow() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }
        let before = sessionKeys(in: server.received.filter { $0.kind == .hello })

        server.clearReceived()
        try await server.restart()
        _ = await waitUntil(timeout: .seconds(15)) {
            self.server.received.filter { $0.kind == .hello }.count >= 2
        }
        let after = sessionKeys(in: server.received.filter { $0.kind == .hello })

        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(after.count, 2)
        XCTAssertTrue(Set(before).isDisjoint(with: Set(after)), "Сессионные ключи после обрыва — новые")

        // Оба должны получить присутствие с новыми ключами, прежде чем слать.
        _ = await waitUntil(timeout: .seconds(5)) {
            self.server.received.filter { $0.kind == .hello }.count >= 2
        }
        try await Task.sleep(for: .milliseconds(300))

        let incoming = bob.messageStream
        let payload = MessagePayload(from: Message(text: "после обрыва", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: bob.myAddress)

        let received = await collect(incoming, count: 1, timeout: .seconds(5))
        XCTAssertEqual(received.first?.value.text, "после обрыва")
    }

    /// Сообщение, написанное без сети: запечатано ключом прошлой сессии,
    /// встало в очередь, ушло после переподключения. Боб всё это время на
    /// связи; наши новые ключи доходят до него присутствием раньше, чем
    /// конверт из очереди, — и он открывает конверт прошлым шифром.
    func test_messageQueuedOffline_opensAfterKeysRotated() async throws {
        // У Алисы своя сеть: только она и уйдёт в офлайн.
        let aliceNetwork = FakeNetworkMonitor()
        let alice = WebSocketTransport(url: server.url,
                                       displayName: "Alice",
                                       identity: DeviceIdentity(),
                                       networkMonitor: aliceNetwork)
        let bob = makeTransport(named: "Bob")
        alice.startDeviceDiscovery()
        bob.startDeviceDiscovery()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }
        let incoming = bob.messageStream

        aliceNetwork.goOffline()
        _ = await waitUntil { self.server.connectedClientCount == 1 }
        XCTAssertFalse(alice.ciphersAreEmpty, "Обрыв шифры не стирает — иначе без сети не написать")

        let payload = MessagePayload(from: Message(text: "из очереди", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: bob.myAddress)

        server.clearReceived()
        aliceNetwork.goOnline()

        let received = await collect(incoming, count: 1, timeout: .seconds(15))
        XCTAssertEqual(received.first?.value.text, "из очереди",
                       "Конверт из прошлой сессии должен открыться прошлым шифром")

        // И это действительно была смена ключа, а не тот же самый.
        let hellos = server.received.filter { $0.kind == .hello }
        XCTAssertEqual(hellos.count, 1, "Переподключилась только Алиса")
        XCTAssertEqual(server.received.first?.kind, .hello, "hello уходит раньше очереди")
    }

    /// Собеседник переподключился, а мы — нет. Его ключ сменился, наш
    /// остался; шифр с ним пересобирается, и переписка идёт в обе стороны.
    func test_whenOnlyPeerReconnects_cipherIsRebuilt() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }

        // Только Боб уходит и возвращается.
        bob.stopDeviceDiscovery()
        _ = await waitUntil { self.server.connectedClientCount == 1 }
        server.clearReceived()
        bob.startDeviceDiscovery()
        _ = await waitUntil(timeout: .seconds(10)) {
            self.server.received.filter { $0.kind == .hello }.count == 1
        }
        try await Task.sleep(for: .milliseconds(300))

        let toBob = bob.messageStream
        let toAlice = alice.messageStream

        try await alice.sendMessage(MessagePayload(from: Message(text: "к новому Бобу", isFromMe: true),
                                                   senderName: "Alice"), to: bob.myAddress)
        try await bob.sendMessage(MessagePayload(from: Message(text: "к прежней Алисе", isFromMe: true),
                                                 senderName: "Bob"), to: alice.myAddress)

        let bobGot = await collect(toBob, count: 1, timeout: .seconds(5))
        let aliceGot = await collect(toAlice, count: 1, timeout: .seconds(5))

        XCTAssertEqual(bobGot.first?.value.text, "к новому Бобу")
        XCTAssertEqual(aliceGot.first?.value.text, "к прежней Алисе")
    }

    // MARK: - Ограничения релея

    func test_connectToUnknownPeer_throws() async {
        let alice = makeTransport(named: "Alice")
        alice.startDeviceDiscovery()
        defer { alice.stopDeviceDiscovery() }

        _ = await waitUntil { self.server.connectedClientCount == 1 }

        do {
            try await alice.connectToPeer(address: "никого-нет")
            XCTFail("Подключение к отсутствующему собеседнику должно падать")
        }
        catch {
            XCTAssertTrue(error is RelayError)
        }
    }
}
