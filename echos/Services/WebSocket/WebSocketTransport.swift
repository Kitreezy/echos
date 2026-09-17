//
//  WebSocketTransport.swift
//  echos
//
//  Вторая реализация `PeerTransport` — через релей вместо Multipeer.
//
//  Отличие в модели связи. У Multipeer соединение устанавливается с каждым
//  устройством отдельно, поэтому там есть приглашения и статусы. Здесь
//  соединение одно — с сервером; все, кто на нём сейчас есть, доступны сразу.
//

import Foundation
import UIKit

@MainActor
final class WebSocketTransport: NSObject {

    // MARK: - Identity

    let myDisplayName: String

    /// Адрес на релее — отпечаток собственного ключа.
    ///
    /// Пусто, если ключ недостать: подключиться в этом случае всё равно не
    /// выйдет, а подставлять сюда имя значило бы делать вид, что адрес есть.
    let myAddress: String

    // MARK: - Delegation

    /// Релей не спрашивает разрешения на подключение: соединение
    /// устанавливается с сервером, а не с конкретным собеседником.
    weak var approvalDelegate: PeerConnectionApproving?

    // MARK: - Streams

    private let peerBroadcast = AsyncBroadcast<[Peer]>(replaysLatest: true)
    private let messageBroadcast = AsyncBroadcast<Addressed<MessagePayload>>()
    private let typingBroadcast = AsyncBroadcast<Addressed<TypingEvent>>()
    private let strokeBroadcast = AsyncBroadcast<Addressed<Stroke>>()
    private let wallRequestBroadcast = AsyncBroadcast<String>()
    private let wallStateBroadcast = AsyncBroadcast<Addressed<[Stroke]>>()

    var peerStream: AsyncStream<[Peer]> { peerBroadcast.stream }
    var messageStream: AsyncStream<Addressed<MessagePayload>> { messageBroadcast.stream }
    var typingStream: AsyncStream<Addressed<TypingEvent>> { typingBroadcast.stream }
    var strokeStream: AsyncStream<Addressed<Stroke>> { strokeBroadcast.stream }
    var wallRequestStream: AsyncStream<String> { wallRequestBroadcast.stream }
    var wallStateStream: AsyncStream<Addressed<[Stroke]>> { wallStateBroadcast.stream }

    /// Состояние соединения с релеем — для индикатора в UI.
    var connectionState: WebSocketClient.State { client.state }

    var connectionStateUpdates: AsyncStream<TransportConnectionState> {
        let states = client.stateUpdates

        return AsyncStream { continuation in
            let task = Task {
                for await state in states {
                    continuation.yield(TransportConnectionState(state))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private let client: WebSocketClient
    private let backgroundLease: BackgroundLease

    /// Ключ, которым подписывается рукопожатие.
    private let identity: DeviceIdentity?

    /// Свой сессионный ключ. Один на соединение: создаётся перед hello и
    /// меняется при каждом переподключении, так что записанное в прошлом
    /// соединении не откроется даже нашими долгими ключами.
    private var session: SessionKey?

    /// Шифр переписки с каждым, кто сейчас на релее. Пересобирается на
    /// каждом присутствии: сессионный ключ собеседника меняется с каждым
    /// его переподключением.
    ///
    /// Обрыв связи шифры не стирает намеренно. Сообщение, написанное без
    /// сети, запечатывается тем ключом, что был, встаёт в очередь и уходит
    /// после переподключения; та сторона откроет его прошлым шифром.
    private var ciphers: [String: ConversationCipher] = [:]

    /// Шифр предыдущей сессии с каждым — на одну смену ключа назад.
    ///
    /// Нужен для конвертов, запечатанных до смены: сообщение из очереди, или
    /// отправленное собеседником, пока к нему ещё не дошло наше новое
    /// присутствие. Глубже одной смены не храним: два переподключения подряд
    /// за время доставки одного сообщения — уже не сеть, а её отсутствие.
    private var previousCiphers: [String: ConversationCipher] = [:]

    /// Из чего собран текущий шифр с каждым: наш и его сессионные ключи.
    /// По этому видно, сменился ли ключ, а не просто пришло ли присутствие.
    private var cipherInputs: [String: (ours: Data, theirs: Data)] = [:]
    private var readerTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    /// Пользователь включил поиск и не выключал. Отличается от «сейчас
    /// подключены»: в фоне соединения нет, но возобновлять его при возврате
    /// надо, а если поиск остановлен явно — не надо.
    private var isActive = false

    /// Адрес → идентификатор. `Peer` требует стабильный `id`, иначе SwiftUI
    /// будет пересоздавать строки списка. Ключ именно адрес, а не имя: имена
    /// могут совпадать, и два человека слились бы в одну строку.
    private var peerIdentifiers: [String: UUID] = [:]
    private var knownAddresses: Set<String> = []

    /// Вызов, пришедший раньше, чем его успели дождаться.
    ///
    /// Порядок здесь не гарантирован: сервер шлёт вызов сразу после
    /// установки соединения, а хук `onConnected` выполняется отдельной
    /// задачей и может опоздать.
    private var pendingChallenge: Data?
    private var challengeWaiter: CheckedContinuation<Data?, Never>?

    // MARK: - Init

    /// - Parameter identity: чем подписываться. По умолчанию — ключ
    ///   устройства. Задаётся снаружи ради тестов: два транспорта в одном
    ///   процессе иначе делили бы одну личность на двоих и оказывались бы
    ///   для релея одним человеком.
    /// - Parameter backgroundGrace: сколько держать соединение после
    ///   сворачивания. По умолчанию — сколько даёт система; тесты ставят
    ///   меньше.
    init(url: URL,
         displayName: String = UserSettings.displayName,
         identity: DeviceIdentity? = nil,
         networkMonitor: any NetworkMonitoring = NetworkMonitor.shared,
         backgroundGrace: Duration = BackgroundLease.duration) {
        self.myDisplayName = displayName
        self.identity = identity ?? (try? DeviceIdentity.current())
        self.myAddress = self.identity?.fingerprint ?? ""
        self.client = WebSocketClient(url: url, networkMonitor: networkMonitor)
        self.backgroundLease = BackgroundLease(duration: backgroundGrace)
        super.init()
        observeAppLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - App Lifecycle

    /// Наблюдатели живут на уровне транспорта, а не экрана.
    ///
    /// Раньше фон обрабатывал только `DiscoveryViewController`, и уход в фон
    /// из чата, минуя радар, оставлял сокет умирать по таймауту. Транспорт же
    /// жив всё время, пока идёт сессия.
    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc
    private func appDidEnterBackground() {
        guard isActive else {
            return
        }

        // Не рвём сразу: полминуты соединение живёт, и сообщение за это
        // время дойдёт — его покажет уведомление. Потом закрываемся штатно,
        // а не ждём, пока соединение умрёт само: так сервер сразу уберёт
        // нас из присутствия, и собеседники не будут видеть призрака.
        backgroundLease.begin { [weak self] in
            self?.client.disconnect()
            self?.clearPeers()
        }
    }

    @objc
    private func appWillEnterForeground() {
        guard isActive else {
            return
        }

        // Вернулись до истечения отсрочки — соединение и не рвалось;
        // `connect()` на живом соединении ничего не делает.
        backgroundLease.end()
        client.connect()
    }

    // MARK: - Discovery

    func startDeviceDiscovery() {
        isActive = true

        guard readerTask == nil else {
            client.connect()
            return
        }

        readerTask = Task { [weak self] in
            guard let messages = self?.client.incomingMessages else {
                return
            }

            for await data in messages {
                self?.handle(data)
            }
        }

        // Представиться надо при каждом подключении, а не только при первом:
        // после реконнекта сервер о нас ничего не помнит. Хук клиента
        // гарантирует, что рукопожатие пройдёт до отложенной очереди.
        client.onConnected = { [weak self] in
            await self?.performHandshake()
        }

        // Пока связи нет, список собеседников недостоверен — чистим его.
        stateTask = Task { [weak self] in
            guard let states = self?.client.stateUpdates else {
                return
            }

            for await state in states where state != .connected {
                self?.clearPeers()
            }
        }

        client.connect()
    }

    func stopDeviceDiscovery() {
        isActive = false

        readerTask?.cancel()
        readerTask = nil

        stateTask?.cancel()
        stateTask = nil

        resumeChallengeWaiter(with: nil)
        pendingChallenge = nil

        client.disconnect()
        clearPeers()
    }

    /// У релея нет пер-пирового подключения: если собеседник в списке
    /// присутствия, ему уже можно писать.
    func connectToPeer(address: String) async throws {
        guard knownAddresses.contains(address) else {
            throw RelayError.notConnected
        }
    }

    // MARK: - Connection Management

    /// Разорвать связь с одним собеседником релей не позволяет — рвётся
    /// только соединение с сервером целиком.
    func disconnect(from address: String) {
        print("[WebSocketTransport] Per-peer disconnect is not supported by the relay")
    }

    func disconnectAll() {
        client.disconnect()
        clearPeers()
    }

    // MARK: - Messaging

    func sendMessage(_ payload: MessagePayload, to address: String) async throws {
        try await sendSealed(try seal(payload, kind: .message, to: address), to: address)
    }

    /// Отправить уже запечатанное. Отдельно от `sendMessage`, чтобы можно
    /// было проверить, что чужой конверт на той стороне не откроется.
    func sendSealed(_ sealed: SealedPayload, to address: String) async throws {
        try await send(.message(sealed, from: myDisplayName, to: address))
    }

    /// Есть ли с кем-нибудь ключ переписки. Тестам нужно дождаться, пока
    /// присутствие с ключами дойдёт, прежде чем слать.
    var ciphersAreEmpty: Bool {
        ciphers.isEmpty
    }

    func sendTypingEvent(_ event: TypingEvent, to address: String) async throws {
        try await send(.typing(event, from: myDisplayName, to: address))
    }

    func sendStroke(_ stroke: Stroke, to address: String) async throws {
        try await send(.stroke(try seal(stroke, kind: .stroke, to: address),
                               from: myDisplayName, to: address))
    }

    func requestWall(from address: String) async throws {
        try await send(.wallRequest(from: myAddress, to: address))
    }

    func sendWall(_ strokes: [Stroke], to address: String) async throws {
        try await send(.wallState(try seal(strokes, kind: .wall, to: address),
                                  from: myAddress, to: address))
    }

    private func send(_ envelope: RelayEnvelope) async throws {
        await client.send(try envelope.encoded())
    }

    // MARK: - Handshake

    /// Дождаться вызова сервера и ответить на него подписью.
    ///
    /// Отправить hello сразу нельзя: подписывать нечего, пока сервер не
    /// прислал свою случайную строку. Зато и подслушанная подпись ничего не
    /// даёт — она годится ровно для одного подключения.
    private func performHandshake() async {
        guard let challenge = await awaitChallenge() else {
            print("[WebSocketTransport] No challenge from the relay, giving up on this connection")
            return
        }

        guard let identity else {
            print("[WebSocketTransport] No device key, cannot introduce myself")
            return
        }

        do {
            // Новое соединение — новый сессионный ключ. Прошлый забывается
            // вместе с ним: его секрет уже вошёл в прошлые шифры, а больше
            // он ни для чего не нужен.
            let session = try SessionKey(signedBy: identity)
            self.session = session

            try await send(.hello(from: myDisplayName,
                                  answering: challenge,
                                  as: identity,
                                  session: session))
        }
        catch {
            print("[WebSocketTransport] Handshake failed: \(error.localizedDescription)")
        }
    }

    private func awaitChallenge() async -> Data? {
        if let challenge = pendingChallenge {
            pendingChallenge = nil
            return challenge
        }

        return await withCheckedContinuation { continuation in
            challengeWaiter = continuation

            // Страховка от вечного ожидания: если вызов не пришёл, соединение
            // всё равно закроется по таймауту на сервере, и клиент попробует
            // снова. Ждать здесь дольше смысла нет.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.resumeChallengeWaiter(with: nil)
            }
        }
    }

    private func resumeChallengeWaiter(with challenge: Data?) {
        guard let waiter = challengeWaiter else {
            pendingChallenge = challenge
            return
        }

        challengeWaiter = nil
        waiter.resume(returning: challenge)
    }

    // MARK: - Incoming

    private func handle(_ data: Data) {
        do {
            let envelope = try RelayEnvelope.decode(from: data)

            switch envelope.kind {
            case .presence:
                updatePeers(try envelope.decodePresence())

            case .message:
                let payload = try open(try envelope.decodeMessage(),
                                       as: MessagePayload.self, kind: .message, from: envelope.sender)
                messageBroadcast.yield(Addressed(sender: envelope.sender, value: payload))

            case .typing:
                typingBroadcast.yield(
                    Addressed(sender: envelope.sender, value: try envelope.decodeTyping()))

            case .stroke:
                let stroke = try open(try envelope.decodeStroke(),
                                      as: Stroke.self, kind: .stroke, from: envelope.sender)
                strokeBroadcast.yield(Addressed(sender: envelope.sender, value: stroke))

            case .challenge:
                resumeChallengeWaiter(with: try envelope.decodeChallenge())

            case .wallRequest:
                wallRequestBroadcast.yield(envelope.sender)

            case .wallState:
                let strokes = try open(try envelope.decodeWallState(),
                                       as: [Stroke].self, kind: .wall, from: envelope.sender)
                wallStateBroadcast.yield(Addressed(sender: envelope.sender, value: strokes))

            case .hello:
                break  // сервер такое не шлёт
            }
        }
        catch {
            print("[WebSocketTransport] Failed to decode envelope: \(error.localizedDescription)")
        }
    }

    /// Запечатать для собеседника — тем шифром, что есть, даже без сети:
    /// конверт встанет в очередь и уйдёт после переподключения.
    private func seal<T: Encodable>(_ value: T, kind: SealedKind, to address: String) throws -> SealedPayload {
        guard let cipher = ciphers[address] else {
            throw RelayError.noCipher(address)
        }
        return try cipher.seal(value, kind: kind, from: myAddress, to: address)
    }

    /// Открыть текущим шифром, а если не вышло — прошлым.
    ///
    /// Не открылось ни тем, ни другим — значит, не от него или не нам.
    /// Открытый текст от старой сборки сюда тоже не пройдёт, и это верно:
    /// принимать его — принимать подделку от кого угодно.
    private func open<T: Decodable>(_ sealed: SealedPayload,
                                    as type: T.Type,
                                    kind: SealedKind,
                                    from sender: String) throws -> T {
        guard let cipher = ciphers[sender] else {
            throw RelayError.noCipher(sender)
        }

        do {
            return try cipher.open(sealed, as: type, kind: kind, from: sender, to: myAddress)
        }
        catch {
            guard let previous = previousCiphers[sender] else {
                throw error
            }
            return try previous.open(sealed, as: type, kind: kind, from: sender, to: myAddress)
        }
    }

    private func updatePeers(_ participants: [RelayParticipant]) {
        // Себя в списке собеседников быть не должно. Отличаем по адресу:
        // тёзка на другом устройстве — это другой человек, и он в списке
        // остаться должен.
        // Без проверенных ключей собеседника нет: писать ему нечем, а
        // показывать в списке того, кому нельзя написать, — обман. Так же
        // отсеивается старая сборка и старый релей, не пересылающий ключи.
        let others = participants
            .filter { $0.id != myAddress }
            .compactMap { participant -> RelayParticipant? in
                guard let identity, let session,
                      let peer = participant.verifiedIdentity else {
                    print("[WebSocketTransport] '\(participant.name)' (\(participant.id)) has no usable keys")
                    return nil
                }

                // Ключ не сменился — шифр тот же, пересобирать незачем, и
                // прошлый трогать нельзя: иначе он бы затёрся копией текущего.
                if let inputs = cipherInputs[participant.id],
                   inputs.ours == session.publicKey, inputs.theirs == peer.sessionKey {
                    return participant
                }

                guard let cipher = try? ConversationCipher(identity: identity, session: session, peer: peer) else {
                    return nil
                }

                if let current = ciphers[participant.id] {
                    previousCiphers[participant.id] = current
                }
                ciphers[participant.id] = cipher
                cipherInputs[participant.id] = (session.publicKey, peer.sessionKey)
                return participant
            }

        knownAddresses = Set(others.map(\.id))

        // Порядок задаёт релей — по отпечатку. Для глаза он произволен,
        // поэтому сортируем по имени, а совпавшие имена разводим адресом.
        let peers = others
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
            .map { participant in
                Peer(id: identifier(for: participant.id),
                     address: participant.id,
                     displayName: participant.name,
                     status: .connected,
                     lastSeen: Date())
            }

        peerBroadcast.yield(peers)
    }

    private func clearPeers() {
        guard !knownAddresses.isEmpty else {
            return
        }

        knownAddresses = []
        peerBroadcast.yield([])
    }

    private func identifier(for address: String) -> UUID {
        if let existing = peerIdentifiers[address] {
            return existing
        }

        let identifier = UUID()
        peerIdentifiers[address] = identifier
        return identifier
    }
}

extension WebSocketTransport: PeerTransport {}

private extension TransportConnectionState {

    init(_ state: WebSocketClient.State) {
        switch state {
        case .disconnected:       self = .offline
        case .connecting:         self = .connecting
        case .waitingForNetwork:  self = .waitingForNetwork
        case .connected:          self = .online
        }
    }
}
