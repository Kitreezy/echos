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

    /// Для Instruments и проверки на устройстве: `-echos_seed_messages 5000`
    /// наполняет чат Боба длинной историей, часть сообщений — мозаиками.
    static var requestedMessageCount: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-echos_seed_messages"),
              arguments.count > index + 1,
              let count = Int(arguments[index + 1]) else {
            return nil
        }
        return count
    }

    private var seeded = false

    func startDeviceDiscovery() {
        peerBroadcast.yield([Self.bob, Self.anna])
        guard !seeded, Self.requestedMessageCount == nil else {
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
        for message in Self.demoMessages() {
            guard let peerAddress = message.peerAddress,
                  let peer = [Self.bob, Self.anna].first(where: { $0.address == peerAddress }) else {
                continue
            }
            messageBroadcast.yield(Addressed(sender: peerAddress,
                                             value: MessagePayload(from: message, senderName: peer.displayName)))
        }
    }

    /// Короткая демонстрационная переписка и начало длинной. Адрес стоит в
    /// самих сообщениях: пакетный сценарий пишет их прямо в хранилище, минуя
    /// транспорт, и восстанавливать адрес будет некому.
    static func demoMessages() -> [Message] {
        let heart = Mosaic(columns: 3, rows: 3,
                           cells: ["", "❤️", "", "❤️", "❤️", "❤️", "", "❤️", ""])!
        return [
            Message(text: "Привет! Ты завтра на фестивале?",
                    senderName: bob.displayName,
                    peerAddress: bob.address,
                    isFromMe: false,
                    status: .sent),
            Message(text: "Встречаемся у главной сцены в семь",
                    senderName: bob.displayName,
                    peerAddress: bob.address,
                    isFromMe: false,
                    status: .sent),
            Message(text: heart.text,
                    mosaic: heart,
                    senderName: bob.displayName,
                    peerAddress: bob.address,
                    isFromMe: false,
                    status: .sent),
            Message(text: "Скинула фото со вчерашнего концерта",
                    senderName: anna.displayName,
                    peerAddress: anna.address,
                    isFromMe: false,
                    status: .sent),
        ]
    }

    /// Длинная переписка для Instruments. Разные заполненные сетки: одинаковая
    /// мозаика дала бы кэшу слишком лёгкий сценарий.
    static func longConversationMessages(count: Int) -> [Message] {
        let base = demoMessages()
        let generated = max(0, count - base.count)
        let start = Date().addingTimeInterval(-Double(generated) * 60)
        let brushes = ["❤️", "🟦", "🟨", "🟩", "⭐"]

        let extra = (0..<generated).map { index in
            let timestamp = start.addingTimeInterval(Double(index) * 60)
            if index.isMultiple(of: 10) {
                let cells = (0..<9).map { cell in
                    (cell + index).isMultiple(of: 3) ? brushes[index % brushes.count] : ""
                }
                let mosaic = Mosaic(columns: 3, rows: 3, cells: cells)!
                return Message(text: mosaic.text,
                               mosaic: mosaic,
                               senderName: bob.displayName,
                               peerAddress: bob.address,
                               isFromMe: index.isMultiple(of: 20),
                               timestamp: timestamp,
                               status: .sent)
            }

            return Message(text: "Сообщение \(index + 1) из длинной переписки",
                           senderName: bob.displayName,
                           peerAddress: bob.address,
                           isFromMe: index.isMultiple(of: 2),
                           timestamp: timestamp,
                           status: .sent)
        }
        return base + extra
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
