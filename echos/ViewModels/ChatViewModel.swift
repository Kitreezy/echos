//
//  ChatViewModel.swift
//  echos
//
//  Created by Artem Rodionov on 17.02.2026.
//

import AsyncAlgorithms
import Foundation
import Observation

/// Три потока транспорта сводятся к одному типу события, чтобы их можно было
/// слить оператором `merge` и читать одним циклом.
enum TransportEvent: Sendable {
    case peers([Peer])
    case message(Addressed<MessagePayload>)
    case typing(Addressed<TypingEvent>)
    case stroke(Addressed<Stroke>)
}

@Observable
@MainActor
final class ChatViewModel {
    
    // MARK: - State (автоматически наблюдаемое)
    
    var messages: [Message] = []
    var peers: [Peer] = []
    var connectionStatus: String = "Не подключён"
    var isDiscovering: Bool = false
    var typingPeerName: String? = nil  // nil - никто не печатает

    /// Адрес того, кто печатает. Отдельно от имени: гасить индикатор надо по
    /// тому же адресу, с которого он зажёгся, а имена могут совпадать.
    private var typingPeer: String? = nil
    
    /// Адрес собеседника, чей чат открыт.
    ///
    /// Именно адрес, а не имя: тёзка — это другой человек, и его сообщения
    /// не должны попадать в чужую переписку.
    var currentConversationPeer: String? = nil

    /// Имя собеседника для заголовка. Держится отдельно, потому что адрес
    /// показывать человеку незачем, а имени в адресе нет.
    var currentConversationName: String? = nil
    
    // MARK: - Services
    
    /// Тип — протокол, а не конкретный класс: в тестах сюда подставляется фейк.
    var multipeerService: (any PeerTransport)?
    var messageStore: (any MessageStoring)?
    
    /// Своя стена. Живёт здесь, а не на экране: росчерки приходят и тогда,
    /// когда стена закрыта.
    var strokeStore: any StrokeStoring = StrokeStore()

    /// Кого мы уже знаем.
    var knownPeerStore: any KnownPeerStoring = KnownPeerStore()

    /// Сопоставление того, кого видим, с теми, с кем разговаривали.
    /// Пересобирается при каждом изменении списка знакомых.
    private(set) var recognizer = PeerRecognizer(known: [])
    
    // MARK: - Typing State
    
    /// Пауза, после которой считаем, что пользователь действительно печатает.
    var typingStartDelay: Duration = .milliseconds(300)
    
    /// Пауза, после которой считаем, что печатать перестали.
    var typingIdleTimeout: Duration = .seconds(3)
    
    private var isCurrentlyTyping = false
    
    /// Поток нажатий. `startTyping()` только кладёт сюда событие — всё
    /// остальное делают операторы в `observeTyping()`.
    private let keystrokes: AsyncStream<Void>
    private let keystrokeContinuation: AsyncStream<Void>.Continuation
    
    // MARK: - Pipeline
    
    /// Как часто сбрасывать накопленные сообщения в хранилище.
    /// Меняется до `initialize()` — конвейер собирается один раз.
    var persistenceFlushInterval: Duration = .seconds(1)
    
    /// Очередь на запись. `AsyncChannel` (в отличие от `AsyncStream`) даёт
    /// backpressure: отправитель ждёт, пока получатель заберёт элемент, —
    /// поэтому очередь не может распухнуть неограниченно.
    private let messagesToPersist = AsyncChannel<Message>()
    
    /// Буфер перед каналом. Нужен, чтобы зафиксировать порядок синхронно —
    /// см. `persist(_:)`.
    private var pendingPersistence: [Message] = []
    private var persistencePump: Task<Void, Never>?
    
    /// Состояние связи транспорта. Для Multipeer остаётся `.offline` —
    /// у него нет единого соединения, и статус там формируют сами пиры.
    private(set) var transportState: TransportConnectionState = .offline

    private var transportTask: Task<Void, Never>?
    private var connectionStateTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    
    /// Как часто ViewModel применяла обновление списка пиров. Диагностика для
    /// тестов: показывает, что `removeDuplicates` действительно схлопывает
    /// повторы, а не просто «работает».
    private(set) var appliedPeerUpdates = 0
    
    // MARK: - Init
    
    init() {
        (keystrokes, keystrokeContinuation) = AsyncStream.makeStream(of: Void.self)
        print("[lifecycle] ChatViewModel init")
    }

    deinit {
        print("[lifecycle] ChatViewModel deinit")
    }
    
    // MARK: - Setup
    
    /// Точка внедрения зависимостей.
    /// Прод вызывает без аргументов и получает реальные Multipeer + Core Data,
    /// тест передаёт свои реализации.
    func initialize(transport: (any PeerTransport)? = nil,
                    store: (any MessageStoring)? = nil,
                    strokes: (any StrokeStoring)? = nil) {
        if let strokes {
            strokeStore = strokes
        }
        // `initialize()` вызывается повторно (возврат из фона, смена экрана),
        // поэтому старые подписки снимаются явно. Раньше каждый вызов добавлял
        // ещё три несфотменяемые Task.
        transportTask?.cancel()
        typingTask?.cancel()
        connectionStateTask?.cancel()
        
        multipeerService = transport ?? PeerTransportFactory.make()
        messageStore = store ?? MessageStore()
        
        transportTask = Task { [weak self] in
            await self?.consumeTransportEvents()
        }
        
        typingTask = Task { [weak self] in
            await self?.observeTyping()
        }
        
        connectionStateTask = Task { [weak self] in
            await self?.observeConnectionState()
        }
        
        // Конвейер записи переживает переподключения: он не привязан к
        // конкретному транспорту и не должен терять накопленную пачку.
        if persistenceTask == nil {
            persistenceTask = Task { [weak self] in
                await self?.consumePersistenceQueue()
            }
        }
    }
    
    // MARK: - Persistence
    
    func switchToConversation(with address: String, named name: String? = nil) async {
        guard let messageStore = messageStore else {
            return
        }
        do {
            let filtered = try await messageStore.loadMessages(with: address)
            messages = filtered
            currentConversationPeer = address
            // Имя ищем по порядку: что передали, кто сейчас на связи, что
            // осталось в истории. Собеседника может не быть рядом, а чат
            // всё равно открывается.
            currentConversationName = name
                ?? peers.first { $0.address == address }?.displayName
                ?? filtered.last { !$0.isFromMe }?.senderName
            print("[ChatViewModel] Showing conversation with \(address): \(filtered.count) messages")
        }
        catch {
            print("[ChatViewModel] Failed to switch: \(error)")
        }
    }
    
    func getAllConversations() async -> [ConversationSummary] {
        guard let messageStore = messageStore else {
            return []
        }
        do {
            let allMessages = try await messageStore.loadMessages()
            var conversations: [String: [Message]] = [:]
            
            // Группируем по адресу, а не по имени: у двух тёзок переписки
            // разные, и сливать их в одну нельзя.
            for message in allMessages {
                if let address = message.peerAddress {
                    conversations[address, default: []].append(message)
                }
            }
            let summaries = conversations.map { address, messages in
                let lastMessage = messages.max(by: { $0.timestamp < $1.timestamp })
                let unreadCount = 0

                // Имя берём то, под которым собеседник известен сейчас, а
                // если его нет рядом — то, под которым он писал в последний раз.
                let name = peers.first { $0.address == address }?.displayName
                    ?? messages.last { !$0.isFromMe }?.senderName
                    ?? address

                return ConversationSummary(peerAddress: address,
                                           peerName: name,
                                           lastMessage: lastMessage?.text ?? "",
                                           lastMessageTime: lastMessage?.timestamp ?? Date(),
                                           messageCount: messages.count,
                                           unreadCount: unreadCount,
                                           isActive: peers.contains { $0.address == address && $0.status == .connected })
                
            }
            return summaries.sorted { $0.lastMessageTime > $1.lastMessageTime }
        }
        catch {
            print("[ChatViewModel] Failed to get conversations: \(error)")
            return []
        }
    }
    
    func clearCurrentConversation() async throws {
        guard let messageStore = messageStore,
              let address = currentConversationPeer else {
            return
        }
        try await messageStore.deleteConverstaion(with: address)
        messages = []
        currentConversationPeer = nil
        currentConversationName = nil
        print("[ChatViewModel] Cleared conversation with \(address)")
    }
    
    func clearAllMessages() async throws {
        guard let messageStore = messageStore else {
            return
        }
        
        try await messageStore.clearAll()
        messages = []
        print("[ChatViewModel] Cleared all messages")
    }
    
    // MARK: - Connection Management
    
    func disconnectFromCurrentPeer() {
        guard let multipeerService = multipeerService,
              let address = currentConversationPeer else {
            return
        }
        
        multipeerService.disconnect(from: address)
        messages = []
        currentConversationPeer = nil
        currentConversationName = nil
        print("[ChatViewModel] Disconnected from \(address)")
    }
    
    func showAllMessages() async {
        guard let messageStore = messageStore else {
            return
        }
        do {
            let all = try await messageStore.loadMessages()
            messages = all
            currentConversationPeer = nil
            print("[ChatViewModel] Showing all messages: \(all.count)")
        }
        catch {
            print("[ChatViewModel] Failed to load all: \(error)")
        }
    }
    
    // MARK: - Recognition

    /// Узнаём ли мы этого собеседника.
    func recognition(for peer: Peer) -> PeerRecognition {
        recognizer.recognize(peer)
    }

    func loadKnownPeers() async {
        do {
            recognizer = PeerRecognizer(known: try await knownPeerStore.loadKnownPeers())
        }
        catch {
            print("[ChatViewModel] Failed to load known peers: \(error)")
        }
    }

    /// Запомнить собеседника.
    ///
    /// Вызывается, когда вы ему написали, а не когда увидели рядом: иначе
    /// знакомыми стали бы все, кто когда-либо попал в список, и отличать
    /// тёзку было бы не от кого.
    private func remember(address: String, name: String?) async {
        do {
            try await knownPeerStore.remember(address: address, name: name ?? address)
            await loadKnownPeers()
        }
        catch {
            print("[ChatViewModel] Failed to remember \(address): \(error)")
        }
    }

    // MARK: - Listening
    
    /// Один цикл на три потока.
    ///
    /// Было: три независимые `Task`, каждая со своим `for await`. Стало: потоки
    /// приводятся к общему типу события и сливаются `merge`. Плюсы — одна точка
    /// отмены, один `switch` и гарантированный порядок обработки внутри цикла.
    private func consumeTransportEvents() async {
        guard let multipeerService = multipeerService else {
            return
        }
        
        let peers = multipeerService.peerStream
            // Список пиров пересобирается на каждый чих, включая периодическую
            // симуляцию RSSI. Отсекаем содержательные повторы...
            .removeDuplicates { $0.hasSameState(as: $1) }
            // ...и ограничиваем частоту перерисовки, оставляя последнее
            // значение в окне. `_throttle` в 1.1.5 всё ещё с подчёркиванием —
            // API помечен как экспериментальный.
            ._throttle(for: .milliseconds(300), latest: true)
            .map(TransportEvent.peers)
        
        let messages = multipeerService.messageStream.map(TransportEvent.message)
        let typing = multipeerService.typingStream.map(TransportEvent.typing)
        let strokes = multipeerService.strokeStream.map(TransportEvent.stroke)
        
        for await event in merge(merge(peers, messages), typing, strokes) {
            switch event {
            case .peers(let discoveredPeers):
                await handlePeers(discoveredPeers)
                
            case .message(let incoming):
                handleIncomingMessage(incoming)
                
            case .typing(let incoming):
                handleTypingEvent(incoming)
                
            case .stroke(let incoming):
                await handleIncomingStroke(incoming)
            }
        }
    }
    
    /// Росчерки принимает приложение, а не экран стены.
    ///
    /// Иначе рисунок, сделанный пока вы смотрите в другое место, пропадал бы
    /// бесследно — а стена нужна ровно для обратного: чтобы след оставался,
    /// когда вас нет.
    private func handleIncomingStroke(_ incoming: Addressed<Stroke>) async {
        // Автора берём у транспорта, а не из росчерка: внутри он от
        // отправителя, и подписаться там можно кем угодно.
        let stroke = incoming.value.by(incoming.sender)

        do {
            try await strokeStore.saveStroke(stroke, wallOwner: nil)
            print("[ChatViewModel] Stroke from \(stroke.author) saved to own wall")
        }
        catch {
            print("[ChatViewModel] Failed to save stroke: \(error)")
        }
    }
    
    private func handleIncomingMessage(_ incoming: Addressed<MessagePayload>) {
        let message = incoming.value.toMessage(from: incoming.sender)
        
        // Сравниваем адреса. По имени было нельзя: тёзка попадал бы в чужую
        // переписку, а при адресации по ключу — и вовсе кто угодно, назвавшись
        // как надо.
        if currentConversationPeer == nil || incoming.sender == currentConversationPeer {
            messages.append(message)
            print("[ChatViewModel] Received from \(incoming.sender): \(message.text.prefix(20))...")
        } else {
            print("[ChatViewModel] Silently saved message from \(incoming.sender) (different conversation)")
        }
        
        persist(message)
    }
    
    private func handlePeers(_ discoveredPeers: [Peer]) async {
        peers = discoveredPeers
        appliedPeerUpdates += 1
        
        if let connected = discoveredPeers.first(where: { $0.status == .connected }) {
            if currentConversationPeer != connected.address {
                await switchToConversation(with: connected.address,
                                           named: connected.displayName)
            }
        }
        
        // Строго после switchToConversation: статус смотрит на то, чей чат
        // открыт, а до переключения это значение ещё старое.
        updateConnectionStatus()
    }
    
    func handleTypingEvent(_ incoming: Addressed<TypingEvent>) {
        // Печатает тот, от кого пришло событие. Имя внутри — только для показа.
        let sender = incoming.sender
        let name = peers.first { $0.address == sender }?.displayName
            ?? incoming.value.peerName

        switch incoming.value.type {
        case .start:
            typingPeer = sender
            typingPeerName = name
            print("[ChatViewModel] \(sender) started typing...")
            
        case .stop:
            if typingPeer == sender {
                typingPeer = nil
                typingPeerName = nil
                print("[ChatViewModel] \(sender) stopped typing")
            }
        }
    }
    
    // MARK: - Persistence pipeline
    
    /// Кладёт сообщение в очередь на запись.
    ///
    /// Порядок фиксируется здесь, синхронно, а в канал сообщения перекладывает
    /// одна-единственная задача-насос. Заводить `Task` на каждое сообщение
    /// нельзя: порядок их запуска планировщиком не определён, и сообщения
    /// приезжают в хранилище вперемешку — что и ловил тест на порядок записи.
    private func persist(_ message: Message) {
        pendingPersistence.append(message)
        
        guard persistencePump == nil else {
            return
        }
        
        persistencePump = Task { [weak self] in
            while let next = self?.takeNextPending() {
                await self?.messagesToPersist.send(next)
            }
            self?.persistencePump = nil
        }
    }
    
    private func takeNextPending() -> Message? {
        pendingPersistence.isEmpty ? nil : pendingPersistence.removeFirst()
    }
    
    /// Пишет накопленное пачками.
    ///
    /// Было: `Task { try? await store.saveMessage(message) }` на каждое
    /// сообщение — незаказанные конкурентные записи в Core Data без гарантии
    /// порядка. Стало: один потребитель, `chunked(by:)` собирает всё
    /// пришедшее за интервал в массив, записи идут последовательно.
    private func consumePersistenceQueue() async {
        let batches = messagesToPersist.chunked(
            by: AsyncTimerSequence.repeating(every: persistenceFlushInterval)
        )
        
        for await batch in batches {
            guard let messageStore = messageStore else {
                continue
            }
            
            for message in batch {
                do {
                    try await messageStore.saveMessage(message)
                }
                catch {
                    print("[ChatViewModel] Failed to save message: \(error)")
                }
            }
        }
    }
    
    // MARK: - Discovery
    
    /// Запуск обнаружения устройств
    func startDeviceDiscovery() async {
        guard let multipeerService = multipeerService else {
            return
        }
        isDiscovering = true
        connectionStatus = "Ищем устройства..."

        // Список знакомых нужен до того, как придёт первое присутствие:
        // иначе первые пол-секунды все выглядят незнакомцами.
        await loadKnownPeers()
        
        multipeerService.startDeviceDiscovery()
    }
    
    func stopDeviceDiscovery() {
        guard let multipeerService = multipeerService else {
            return
        }
        isDiscovering = false
        multipeerService.stopDeviceDiscovery()
        connectionStatus = "Поиск остановлен"
        
        stopTyping()
    }
    
    /// Состояние связи важнее числа найденных устройств: если сети нет,
    /// «Нет устройств рядом» вводит в заблуждение.
    private func observeConnectionState() async {
        guard let multipeerService = multipeerService else {
            return
        }
        
        for await state in multipeerService.connectionStateUpdates {
            transportState = state
            updateConnectionStatus()
        }
    }
    
    private func updateConnectionStatus() {
        switch transportState {
        case .waitingForNetwork:
            connectionStatus = "Нет сети"
            return
            
        case .connecting:
            connectionStatus = "Переподключаемся..."
            return
            
        case .offline, .online:
            break
        }
        
        // Строка под заголовком чата относится к собеседнику, а не ко всей
        // комнате. Раньше она перечисляла всех, кто на связи, — через релей,
        // где «на связи» сразу все, это превращалось в список имён, а с
        // тёзками читалось буквально как «Bob, Bob».
        if let address = currentConversationPeer {
            let isReachable = peers.contains {
                $0.address == address && $0.status == .connected
            }

            // Имя собеседника уже стоит в заголовке — повторять его незачем.
            // Сказать есть что, только когда его нет рядом.
            connectionStatus = isReachable ? "" : "не на связи"
            return
        }
        
        connectionStatus = peers.isEmpty ? "" : "Рядом: \(peers.count)"
    }
    
    // MARK: - Messaging
    
    /// Отправка сообщения
    func sendMessage(_ text: String) async {
        guard let multipeerService = multipeerService else {
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        // Адрес проставляется сразу: без него сообщение не принадлежит ни
        // одной переписке и в чате собеседника не покажется.
        let message = Message(text: trimmed,
                              senderName: nil,
                              peerAddress: currentConversationPeer,
                              isFromMe: true,
                              status: .sending)
        messages.append(message)
        
        stopTyping()
        
        // Сообщение адресное, и без собеседника отправлять его некому.
        // Раньше в этом случае оно уходило всем подряд.
        guard let address = currentConversationPeer else {
            updateStatus(.failed, for: message.id)
            print("[ChatViewModel] No conversation selected, message not sent")
            return
        }
        
        let playLoad = MessagePayload(from: message, senderName: multipeerService.myDisplayName)
        
        do {
            try await multipeerService.sendMessage(playLoad, to: address)
            
            updateStatus(.sent, for: message.id)
            await remember(address: address, name: currentConversationName)
            print("[ChatViewModel] Message sent successfully")
        } catch {
            updateStatus(.failed, for: message.id)
            print("[ChatViewModel] Failed to send message: \(error)")
        }
    }
    
    // MARK: - Typing indication
    
    /// Вызывается на каждое нажатие клавиши. Никакой логики — только событие
    /// в поток; решение «печатает / перестал» принимают операторы.
    func startTyping() {
        keystrokeContinuation.yield()
    }
    
    /// Два потребителя одного потока нажатий с разными интервалами.
    ///
    /// Было: `typingDebounceTimer` и `typingTimer` — две задачи с `Task.sleep`,
    /// которые надо было руками отменять в четырёх местах. Стало: тот же
    /// поток нажатий, размноженный `share()`, и два `debounce` с разными
    /// интервалами. `share()` здесь обязателен — без него второй `for await`
    /// начал бы отбирать нажатия у первого.
    private func observeTyping() async {
        let shared = keystrokes.share()
        let startDelay = typingStartDelay
        let idleTimeout = typingIdleTimeout
        
        await withTaskGroup(of: Void.self) { group in
            // Короткая пауза после нажатия — пользователь печатает.
            group.addTask { [weak self] in
                for await _ in shared.debounce(for: startDelay) {
                    await self?.sendTypingStart()
                }
            }
            
            // Длинная пауза — печатать перестали.
            group.addTask { [weak self] in
                for await _ in shared.debounce(for: idleTimeout) {
                    await self?.sendTypingStop()
                }
            }
        }
    }
    
    /// Явная остановка: отправка сообщения, уход с экрана, остановка поиска.
    /// Пауза в 3 секунды тут не нужна — событие шлём сразу.
    func stopTyping() {
        Task { [weak self] in
            await self?.sendTypingStop()
        }
    }
    
    private func sendTypingStart() async {
        guard let multipeerService = multipeerService,
              let address = currentConversationPeer,
              !isCurrentlyTyping else {
            return
        }
        
        isCurrentlyTyping = true
        
        let event = TypingEvent(type: .start, peerName: multipeerService.myDisplayName)
        try? await multipeerService.sendTypingEvent(event, to: address)
        print("[ChatViewModel] Sent typing start from '\(multipeerService.myDisplayName)'")
    }
    
    private func sendTypingStop() async {
        guard let multipeerService = multipeerService,
              let address = currentConversationPeer,
              isCurrentlyTyping else {
            return
        }
        
        isCurrentlyTyping = false
        
        let event = TypingEvent(type: .stop, peerName: multipeerService.myDisplayName)
        try? await multipeerService.sendTypingEvent(event, to: address)
        print("[ChatViewModel] Sent typing stop from '\(multipeerService.myDisplayName)'")
    }
    
    // MARK: - Helpers
    
    private func updateStatus(_ status: MessageStatus, for id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        messages[idx].status = status
        persist(messages[idx])
    }
}
