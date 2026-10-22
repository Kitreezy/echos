//
//  DemoTransport.swift
//  echos
//
//  Транспорт-декорация для UI-тестов: собеседники уже рядом, переписка уже
//  идёт. Ничего не отправляет и ни к чему не подключается.
//
//  Содержимое подобрано так, чтобы у каждого экрана было что проверять:
//  список разговоров, обычные сообщения и мозаика в чате. Только в Debug.
//

#if DEBUG
import Foundation

@MainActor
final class DemoTransport: PeerTransport {

    let myDisplayName = "Тест"
    let myAddress = "demo-me"
    weak var approvalDelegate: PeerConnectionApproving?

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

    static let bob = Peer(address: "demo-bob", displayName: "Боб", status: .connected, rssi: -50, distance: 8)
    static let anna = Peer(address: "demo-anna", displayName: "Аня", status: .connected, rssi: -64, distance: 20)

    private var seeded = false

    func startDeviceDiscovery() {
        peerBroadcast.yield([Self.bob, Self.anna])
        guard !seeded else {
            return
        }
        seeded = true
        // Переписка — чуть позже: модель чата подписывается на поток при
        // запуске, и пришедшее раньше подписки потерялось бы.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.seedConversation()
        }
    }

    private func seedConversation() {
        let heart = Mosaic(columns: 3, rows: 3,
                           cells: ["", "❤️", "", "❤️", "❤️", "❤️", "", "❤️", ""])!
        let incoming: [(Peer, Message)] = [
            (Self.bob, Message(text: "Привет! Ты завтра на фестивале?", isFromMe: false)),
            (Self.bob, Message(text: "Встречаемся у главной сцены в семь", isFromMe: false)),
            (Self.bob, Message(text: heart.text, mosaic: heart, isFromMe: false)),
            (Self.anna, Message(text: "Скинула фото со вчерашнего концерта", isFromMe: false))
        ]
        for (peer, message) in incoming {
            messageBroadcast.yield(Addressed(sender: peer.address,
                                             value: MessagePayload(from: message, senderName: peer.displayName)))
        }
    }

    func stopDeviceDiscovery() {}
    func connectToPeer(address: String) async throws {}
    func disconnect(from address: String) {}
    func disconnectAll() {}
    func sendMessage(_ payload: MessagePayload, to address: String) async throws {}
    func sendTypingEvent(_ event: TypingEvent, to address: String) async throws {}
    func sendStroke(_ stroke: Stroke, to address: String) async throws {}
    func requestWall(from address: String) async throws {}
    func sendWall(_ strokes: [Stroke], to address: String) async throws {}
}
#endif
