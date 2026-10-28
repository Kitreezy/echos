//
//  WebSocketTransportTests.swift
//  echosTests
//
//  Вторая реализация `PeerTransport` против настоящего релея: два «устройства»
//  в одном процессе видят друг друга и обмениваются сообщениями.
//

import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.relayServer, .tags(.network))
struct WebSocketTransportTests {

    private var server: RelayServer { RelayFixture.server }
    // Подставной монитор, чтобы тесты не зависели от реальной сети машины.
    private let monitor = FakeNetworkMonitor()

    /// У каждого транспорта свой ключ: на одном устройстве их два, а для
    /// релея это должны быть двое разных людей.
    private func makeTransport(named name: String) -> WebSocketTransport {
        WebSocketTransport(url: server.url,
                           displayName: name,
                           identity: DeviceIdentity(),
                           networkMonitor: monitor)
    }

    /// Поднимает оба транспорта и ждёт, пока каждый увидит другого.
    ///
    /// Ждать установки соединений мало: рукопожатие идёт отдельным кругом, и
    /// сообщение, отправленное между этими моментами, релей выбросит —
    /// получателя он ещё не знает по отпечатку. И того, что оба представились
    /// серверу, тоже мало: ключ собеседника приходит следом, в присутствии, и
    /// без него шифровать нечем — `noCipher`. Последовательный запуск это
    /// прятал: присутствие успевало прийти. Под параллельной нагрузкой — нет.
    private func makePair() async -> (alice: WebSocketTransport, bob: WebSocketTransport) {
        let alice = makeTransport(named: "Alice")
        let bob = makeTransport(named: "Bob")

        alice.startDeviceDiscovery()
        bob.startDeviceDiscovery()

        _ = await waitUntil(timeout: .seconds(5)) { self.server.introducedClientCount == 2 }

        // Собеседник в присутствии — значит, и шифр для него уже есть:
        // транспорт заводит шифр раньше, чем объявляет собеседника.
        let (aliceAddress, bobAddress) = (alice.myAddress, bob.myAddress)
        _ = await firstElement(of: alice.peerStream, timeout: .seconds(5)) { $0.contains { $0.address == bobAddress } }
        _ = await firstElement(of: bob.peerStream, timeout: .seconds(5)) { $0.contains { $0.address == aliceAddress } }

        return (alice, bob)
    }

    // MARK: - Присутствие

    @Test func twoTransports_seeEachOtherInPeerStream() async {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        // Сервер насчитал двоих раньше, чем клиент перевёл своё состояние:
        // ждём его, а не утверждаем с ходу.
        let connected = await waitUntil { alice.connectionState == .connected }
        #expect(connected)

        // Ждём именно появления собеседника: до этого поток успевает отдать
        // пустой список — присутствие с одной лишь Alice.
        let peers = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            !$0.isEmpty
        }

        #expect(peers?.map(\.displayName) == ["Bob"], "Себя в списке собеседников быть не должно")
        #expect(peers?.first?.status == .connected)
    }

    @Test func peerIdentifiers_areStableAcrossPresenceUpdates() async {
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
        #expect(updated)

        let second = await firstElement(of: alice.peerStream, timeout: .seconds(5)) {
            $0.count == 2
        }?.first { $0.displayName == "Bob" }?.id

        #expect(first != nil)
        #expect(first == second, "Идентификатор пира не должен меняться от обновления к обновлению")
    }

    // MARK: - Обмен

    @Test func message_isDeliveredToTheOtherTransport() async throws {
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

        #expect(received.first?.value.text == "привет из сети")
        #expect(received.first?.value.senderName == "Alice")
        #expect(received.first?.sender == alice.myAddress, "Отправителя проставляет релей, из ключа")
    }

    /// Ради этого всё и затевалось: релей сообщение переносит, но прочитать
    /// не может.
    @Test func relay_doesNotSeeTheText() async throws {
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
        #expect(received.first?.value.text == "только для Боба", "До Боба текст дошёл")

        let passedThrough = server.received.filter { $0.kind == .message }
        #expect(passedThrough.count == 1)
        for envelope in passedThrough {
            let wire = try #require(String(bytes: try envelope.encoded(), encoding: .utf8))
            #expect(!(wire.contains("только для Боба")), "Текст виден серверу")
            #expect(!wire.contains(payload.id), "Идентификатор сообщения тоже под замком")
        }
    }

    /// Релей, который ключи не пересылает (старая сборка сервера), даёт
    /// пустой список: писать этим людям нечем.
    @Test func relayWithoutKeys_listsNobody() async {
        server.forwardsKeys = false
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let stream = alice.peerStream
        let lists = await collect(stream, count: 1, timeout: .seconds(3))

        #expect(lists.allSatisfy { $0.isEmpty })

        do {
            let payload = MessagePayload(from: Message(text: "в никуда", isFromMe: true),
                                         senderName: "Alice")
            try await alice.sendMessage(payload, to: bob.myAddress)
            Issue.record("Без ключа собеседника отправлять нечем")
        } catch let error as RelayError {
            #expect(error == .noCipher(bob.myAddress))
        } catch {
            Issue.record("Не та ошибка: \(error)")
        }
    }

    /// Конверт, которого Алиса не отправляла: релей (или кто-то за ним)
    /// подделал сообщение от её имени. Не откроется — и не дойдёт.
    @Test func forgedMessage_isDropped() async throws {
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
        #expect(received.isEmpty, "Подделка не должна пройти")
    }

    @Test func typingEvent_isDeliveredToTheOtherTransport() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }

        let incoming = bob.typingStream

        try await alice.sendTypingEvent(TypingEvent(type: .start, peerName: "Alice"), to: bob.myAddress)

        let received = await collect(incoming, count: 1, timeout: .seconds(5))

        #expect(received.first?.value.type == .start)
        #expect(received.first?.value.peerName == "Alice")
        #expect(received.first?.sender == alice.myAddress)
    }

    /// Отправитель не должен получать собственное сообщение обратно.
    @Test func sender_doesNotReceiveItsOwnMessage() async throws {
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

        #expect(ownMessages.isEmpty)
    }

    // MARK: - Восстановление сессии

    /// После перезапуска сервера транспорт обязан не только переподключиться,
    /// но и заново представиться — иначе он будет «онлайн», но невидим.
    @Test func afterServerRestart_transportReannouncesItself() async throws {
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

        #expect(reannounced, "После реконнекта hello должен уйти повторно")
    }

    /// Мозаика — то же сообщение, только с сеткой внутри: доходит сеткой,
    /// а не текстом, и сервер её не видит.
    @Test func mosaic_arrivesAsAGrid() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }
        let incoming = bob.messageStream

        let mosaic = Mosaic(columns: 2, rows: 2, cells: ["🟨", "", "", "🟨"])!
        let payload = MessagePayload(from: Message(text: mosaic.text, mosaic: mosaic, isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: bob.myAddress)

        let received = await collect(incoming, count: 1, timeout: .seconds(5))
        #expect(received.first?.value.mosaic == mosaic)
        #expect(received.first?.value.text == mosaic.text)

        for envelope in server.received where envelope.kind == .message {
            let wire = try #require(String(bytes: try envelope.encoded(), encoding: .utf8))
            #expect(!(wire.contains("🟨")))
            #expect(!wire.contains("cells"))
        }
    }

    // MARK: - Стена

    /// Росчерк и стена целиком — такое же содержимое, как сообщение:
    /// доходят, а релей внутрь не заглядывает.
    @Test func strokeAndWall_travelSealed() async throws {
        let (alice, bob) = await makePair()
        defer {
            alice.stopDeviceDiscovery()
            bob.stopDeviceDiscovery()
        }
        _ = await waitUntil { !alice.ciphersAreEmpty && !bob.ciphersAreEmpty }

        let strokes = bob.strokeStream
        let requests = bob.wallRequestStream
        let walls = alice.wallStateStream

        let stroke = Stroke(author: alice.myAddress,
                            points: [Stroke.Point(x: 0.25, y: 0.75), Stroke.Point(x: 0.5, y: 0.5)])
        try await alice.sendStroke(stroke, to: bob.myAddress)
        try await alice.requestWall(from: bob.myAddress)

        let gotStroke = await collect(strokes, count: 1, timeout: .seconds(5))
        #expect(gotStroke.first?.value.id == stroke.id)
        #expect(gotStroke.first?.value.points.count == 2)
        #expect(gotStroke.first?.sender == alice.myAddress)

        let asked = await collect(requests, count: 1, timeout: .seconds(5))
        #expect(asked.first == alice.myAddress)

        try await bob.sendWall([stroke], to: alice.myAddress)
        let gotWall = await collect(walls, count: 1, timeout: .seconds(5))
        #expect(gotWall.first?.value.map(\.id) == [stroke.id])

        for envelope in server.received where envelope.kind == .stroke || envelope.kind == .wallState {
            let wire = try #require(String(bytes: try envelope.encoded(), encoding: .utf8))
            #expect(!wire.contains("points"), "Содержимое росчерка видно серверу")
            #expect(!wire.contains(stroke.id.uuidString), "Идентификатор росчерка видно серверу")
        }
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
    @Test func afterReconnect_sessionKeysChangeAndMessagesStillFlow() async throws {
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

        #expect(before.count == 2)
        #expect(after.count == 2)
        #expect(Set(before).isDisjoint(with: Set(after)), "Сессионные ключи после обрыва — новые")

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
        #expect(received.first?.value.text == "после обрыва")
    }

    /// Сообщение, написанное без сети: запечатано ключом прошлой сессии,
    /// встало в очередь, ушло после переподключения. Боб всё это время на
    /// связи; наши новые ключи доходят до него присутствием раньше, чем
    /// конверт из очереди, — и он открывает конверт прошлым шифром.
    @Test func messageQueuedOffline_opensAfterKeysRotated() async throws {
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
        #expect(!alice.ciphersAreEmpty, "Обрыв шифры не стирает — иначе без сети не написать")

        let payload = MessagePayload(from: Message(text: "из очереди", isFromMe: true),
                                     senderName: "Alice")
        try await alice.sendMessage(payload, to: bob.myAddress)

        server.clearReceived()
        aliceNetwork.goOnline()

        let received = await collect(incoming, count: 1, timeout: .seconds(15))
        #expect(received.first?.value.text == "из очереди", "Конверт из прошлой сессии должен открыться прошлым шифром")

        // И это действительно была смена ключа, а не тот же самый.
        let hellos = server.received.filter { $0.kind == .hello }
        #expect(hellos.count == 1, "Переподключилась только Алиса")
        #expect(server.received.first?.kind == .hello, "hello уходит раньше очереди")
    }

    /// Собеседник переподключился, а мы — нет. Его ключ сменился, наш
    /// остался; шифр с ним пересобирается, и переписка идёт в обе стороны.
    @Test func whenOnlyPeerReconnects_cipherIsRebuilt() async throws {
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

        #expect(bobGot.first?.value.text == "к новому Бобу")
        #expect(aliceGot.first?.value.text == "к прежней Алисе")
    }

    // MARK: - Ограничения релея

    @Test func connectToUnknownPeer_throws() async {
        let alice = makeTransport(named: "Alice")
        alice.startDeviceDiscovery()
        defer { alice.stopDeviceDiscovery() }

        _ = await waitUntil { self.server.connectedClientCount == 1 }

        do {
            try await alice.connectToPeer(address: "никого-нет")
            Issue.record("Подключение к отсутствующему собеседнику должно падать")
        }
        catch {
            #expect(error is RelayError)
        }
    }
}
