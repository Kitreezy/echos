//
//  LoopbackTransport.swift
//  echosTests
//
//  Подставной транспорт: даёт руками подать события в потоки и посмотреть,
//  что ViewModel отправила в ответ. Реальный `MultipeerService` требует двух
//  устройств и разрешения на локальную сеть — в тестах его не поднять.
//

import Foundation
@testable import echos

@MainActor
final class LoopbackTransport: PeerTransport {

    // MARK: - Identity

    var myDisplayName: String = "Tester"

    /// По умолчанию совпадает с именем — так тесты, которым адресация
    /// безразлична, читаются как раньше. Где важна разница между именем и
    /// адресом, тест выставляет его сам.
    var myAddress: String = "Tester"
    var approvalDelegate: PeerConnectionApproving?

    // MARK: - Streams

    /// Те же броадкастеры, что и в проде, — иначе тест не проверял бы
    /// мультикаст, который и является предметом проверки.
    private let peerBroadcast = AsyncBroadcast<[Peer]>(replaysLatest: true)
    private let messageBroadcast = AsyncBroadcast<Addressed<MessagePayload>>()
    private let typingBroadcast = AsyncBroadcast<Addressed<TypingEvent>>()
    private let strokeBroadcast = AsyncBroadcast<Addressed<Stroke>>()
    private let wallRequestBroadcast = AsyncBroadcast<String>()
    private let wallStateBroadcast = AsyncBroadcast<Addressed<[Stroke]>>()

    /// Сколько раз у потоков запрашивали подписку. Тесту нужно дождаться, пока
    /// конвейер ViewModel действительно встанет на потоки: события, отправленные
    /// до подписки, теряются (кроме реплея последнего списка пиров).
    private(set) var subscriptionsCreated = 0

    var peerStream: AsyncStream<[Peer]> {
        subscriptionsCreated += 1
        return peerBroadcast.stream
    }

    var messageStream: AsyncStream<Addressed<MessagePayload>> {
        subscriptionsCreated += 1
        return messageBroadcast.stream
    }

    var typingStream: AsyncStream<Addressed<TypingEvent>> {
        subscriptionsCreated += 1
        return typingBroadcast.stream
    }

    var strokeStream: AsyncStream<Addressed<Stroke>> {
        strokeBroadcast.stream
    }

    var wallRequestStream: AsyncStream<String> {
        subscriptionsCreated += 1
        return wallRequestBroadcast.stream
    }

    var wallStateStream: AsyncStream<Addressed<[Stroke]>> {
        wallStateBroadcast.stream
    }

    /// Сколько подписчиков сейчас читают росчерки. Тест ждёт по нему, а не
    /// по времени: событие, отправленное до подписки, теряется.
    var strokeSubscriberCount: Int {
        strokeBroadcast.subscriberCount
    }

    /// Один вызов `consumeTransportEvents()` подписывается на четыре потока.
    var pipelinesConnected: Int {
        subscriptionsCreated / 4
    }

    // MARK: - Recorded output

    private(set) var sentMessages: [(payload: MessagePayload, recipient: String)] = []
    private(set) var sentTypingEvents: [(event: TypingEvent, recipient: String)] = []
    private(set) var sentStrokes: [(stroke: Stroke, recipient: String)] = []
    private(set) var isDiscovering = false

    var sentTypingTypes: [TypingEventType] {
        sentTypingEvents.map(\.event.type)
    }

    // MARK: - Test input

    func emit(peers: [Peer]) {
        peerBroadcast.yield(peers)
    }

    /// Отправитель по умолчанию — имя внутри события. Так тесты, писавшиеся
    /// до появления адресов, продолжают означать ровно то же самое.
    func emit(message: MessagePayload, from sender: String? = nil) {
        messageBroadcast.yield(Addressed(sender: sender ?? message.senderName,
                                         value: message))
    }

    func emit(typing: TypingEvent, from sender: String? = nil) {
        typingBroadcast.yield(Addressed(sender: sender ?? typing.peerName, value: typing))
    }

    func emit(stroke: Stroke, from sender: String? = nil) {
        strokeBroadcast.yield(Addressed(sender: sender ?? stroke.author, value: stroke))
    }

    func emit(wallRequestFrom asker: String) {
        wallRequestBroadcast.yield(asker)
    }

    func emit(wall strokes: [Stroke], from owner: String) {
        wallStateBroadcast.yield(Addressed(sender: owner, value: strokes))
    }

    // MARK: - PeerTransport

    func startDeviceDiscovery() {
        isDiscovering = true
    }

    func stopDeviceDiscovery() {
        isDiscovering = false
    }

    func connectToPeer(address: String) async throws {}

    private(set) var disconnectedPeers: [String] = []

    func disconnect(from address: String) {
        disconnectedPeers.append(address)
    }

    func disconnectAll() {}

    func sendMessage(_ payload: MessagePayload, to address: String) async throws {
        sentMessages.append((payload, address))
    }

    func sendTypingEvent(_ event: TypingEvent, to address: String) async throws {
        sentTypingEvents.append((event, address))
    }

    func sendStroke(_ stroke: Stroke, to address: String) async throws {
        sentStrokes.append((stroke, address))
    }

    /// Владелец, до которого не дотянуться. Нужен, чтобы проверить, что
    /// открытая стена переживает его отсутствие.
    var unreachableOwners: Set<String> = []

    private(set) var wallRequests: [String] = []
    private(set) var sentWalls: [(strokes: [Stroke], recipient: String)] = []

    /// Забыть отправленные росчерки: сведение проверяется отдельно от
    /// рисования, и штрих, ушедший при рисовании, здесь только мешает.
    func clearSentStrokes() {
        sentStrokes.removeAll()
    }

    func requestWall(from address: String) async throws {
        guard !unreachableOwners.contains(address) else {
            throw MultipeerError.peerNotFound
        }

        wallRequests.append(address)
    }

    func sendWall(_ strokes: [Stroke], to address: String) async throws {
        sentWalls.append((strokes, address))
    }
}
