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
    var approvalDelegate: PeerConnectionApproving?

    // MARK: - Streams

    /// Те же броадкастеры, что и в проде, — иначе тест не проверял бы
    /// мультикаст, который и является предметом проверки.
    private let peerBroadcast = AsyncBroadcast<[Peer]>(replaysLatest: true)
    private let messageBroadcast = AsyncBroadcast<MessagePayload>()
    private let typingBroadcast = AsyncBroadcast<TypingEvent>()

    /// Сколько раз у потоков запрашивали подписку. Тесту нужно дождаться, пока
    /// конвейер ViewModel действительно встанет на потоки: события, отправленные
    /// до подписки, теряются (кроме реплея последнего списка пиров).
    private(set) var subscriptionsCreated = 0

    var peerStream: AsyncStream<[Peer]> {
        subscriptionsCreated += 1
        return peerBroadcast.stream
    }

    var messageStream: AsyncStream<MessagePayload> {
        subscriptionsCreated += 1
        return messageBroadcast.stream
    }

    var typingStream: AsyncStream<TypingEvent> {
        subscriptionsCreated += 1
        return typingBroadcast.stream
    }

    /// Один вызов `consumeTransportEvents()` подписывается на все три потока.
    var pipelinesConnected: Int {
        subscriptionsCreated / 3
    }

    // MARK: - Recorded output

    private(set) var sentMessages: [MessagePayload] = []
    private(set) var sentTypingEvents: [TypingEvent] = []
    private(set) var isDiscovering = false

    var sentTypingTypes: [TypingEventType] {
        sentTypingEvents.map(\.type)
    }

    // MARK: - Test input

    func emit(peers: [Peer]) {
        peerBroadcast.yield(peers)
    }

    func emit(message: MessagePayload) {
        messageBroadcast.yield(message)
    }

    func emit(typing: TypingEvent) {
        typingBroadcast.yield(typing)
    }

    // MARK: - PeerTransport

    func startDeviceDiscovery() {
        isDiscovering = true
    }

    func stopDeviceDiscovery() {
        isDiscovering = false
    }

    func connectToPeer(displayName: String) async throws {}

    private(set) var disconnectedPeers: [String] = []

    func disconnect(from displayName: String) {
        disconnectedPeers.append(displayName)
    }

    func disconnectAll() {}

    func sendMessage(_ payload: MessagePayload) async throws {
        sentMessages.append(payload)
    }

    func sendTypingEvent(_ event: TypingEvent) async throws {
        sentTypingEvents.append(event)
    }
}
