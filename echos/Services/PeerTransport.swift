//
//  PeerTransport.swift
//  echos
//
//  Абстракция над транспортом для обмена с соседними устройствами.
//
//  Зачем: у транспорта две реализации — `MultipeerService` (устройства рядом,
//  через MultipeerConnectivity) и `WebSocketTransport` (через релей, из любой
//  сети). ViewModel не должна знать, какой из них подключён.
//
//  В тестах в этот же шов подставляется `LoopbackTransport`.
//

import Foundation

/// Подтверждение входящего подключения пользователем.
@MainActor
protocol PeerConnectionApproving: AnyObject {
    /// Показать UI для подтверждения подключения.
    /// - Returns: true если пользователь принял, false если отклонил
    func shouldAcceptConnection(from peerName: String) async -> Bool
}

/// Входящее вместе с адресом отправителя.
///
/// Адрес здесь — тот, что подтвердил транспорт, а не тот, который отправитель
/// написал о себе внутри payload. Разница принципиальная: имя в `MessagePayload`
/// заполняет сам отправитель, и назваться там можно кем угодно. Раскладывать
/// переписку по такому имени значит верить на слово.
struct Addressed<Value> {
    let sender: String
    let value: Value
}

extension Addressed: Sendable where Value: Sendable {}

/// Состояние связи транспорта — в терминах, одинаковых для Multipeer и релея.
enum TransportConnectionState: Sendable, Equatable {
    case offline
    case connecting
    /// Сети нет. Отдельно от `connecting`: попыток сейчас не идёт,
    /// и пользователю честнее сказать «нет сети», а не «подключаемся».
    case waitingForNetwork
    case online
}

@MainActor
protocol PeerTransport: AnyObject {
    
    // MARK: - Identity
    
    var myDisplayName: String { get }

    /// Собственный адрес — то, что собеседники увидят как отправителя.
    var myAddress: String { get }
    
    // MARK: - Delegation
    
    var approvalDelegate: PeerConnectionApproving? { get set }
    
    // MARK: - Streams
    
    /// Потоки мультикастовые: каждое обращение отдаёт НОВЫЙ независимый
    /// `AsyncStream`, и все подписчики получают одни и те же события.
    /// Реализация обязана держать по одному continuation на подписчика,
    /// иначе два `for await` начнут делить события
    /// между собой вместо того чтобы каждый получил все.
    
    var peerStream: AsyncStream<[Peer]> { get }
    var messageStream: AsyncStream<Addressed<MessagePayload>> { get }
    var typingStream: AsyncStream<Addressed<TypingEvent>> { get }
    var strokeStream: AsyncStream<Addressed<Stroke>> { get }

    /// Адреса тех, кто просит показать свою стену.
    var wallRequestStream: AsyncStream<String> { get }

    /// Чужая стена целиком, как она есть у владельца.
    var wallStateStream: AsyncStream<Addressed<[Stroke]>> { get }
    
    /// Состояние связи. Транспорту, у которого нет единого соединения
    /// (Multipeer), сообщать нечего — для него работает пустая реализация
    /// по умолчанию.
    var connectionStateUpdates: AsyncStream<TransportConnectionState> { get }
    
    // MARK: - Discovery
    
    func startDeviceDiscovery()
    func stopDeviceDiscovery()
    func connectToPeer(address: String) async throws
    
    // MARK: - Connection Management
    
    /// Пир адресуется адресом, а не транспортным идентификатором.
    /// Было `getPeerID(for:) -> MCPeerID?` плюс `disconnect(from: MCPeerID)` —
    /// связка, из-за которой тип из MultipeerConnectivity протекал и в
    /// протокол, и во все вызывающие места.
    func disconnect(from address: String)
    func disconnectAll()
    
    // MARK: - Messaging
    
    /// Всё адресное: переписка один на один и есть один на один, а не
    /// рассылка всем, кто оказался рядом.
    func sendMessage(_ payload: MessagePayload, to address: String) async throws
    func sendTypingEvent(_ event: TypingEvent, to address: String) async throws
    /// Росчерк адресный: он предназначен владельцу стены, а не всем вокруг.
    func sendStroke(_ stroke: Stroke, to address: String) async throws

    /// Попросить показать стену. Владелец — источник правды: росчерк,
    /// отправленный ему в офлайне, до него не дошёл, и узнать об этом можно
    /// только спросив.
    func requestWall(from address: String) async throws

    /// Отдать свою стену тому, кто попросил.
    func sendWall(_ strokes: [Stroke], to address: String) async throws
}

extension PeerTransport {

    /// Транспорту, у которого нет собственного адресного пространства,
    /// адресом служит имя: у MultipeerConnectivity ничего другого и нет,
    /// `MCPeerID` за пределы устройства не выходит.
    var myAddress: String { myDisplayName }

    /// У Multipeer нет одного соединения, состояние которого можно показать:
    /// связь устанавливается с каждым устройством отдельно и уже отражена
    /// в статусах пиров.
    var connectionStateUpdates: AsyncStream<TransportConnectionState> {
        AsyncStream { $0.finish() }
    }
}

extension MultipeerService: PeerTransport {}

// MARK: - Factory

/// Каким способом держать связь.
enum TransportKind: Equatable {
    /// Только те, кто рядом: MultipeerConnectivity, без интернета.
    case nearby
    /// Через сервер: видно собеседников из любой сети.
    case relay(URL)
}

enum PeerTransportFactory {

    /// Что выбрать при таких настройках.
    ///
    /// Отдельно от сборки транспорта, потому что решение стоит проверять, а
    /// поднимать ради этого MultipeerConnectivity в тесте — значит просить
    /// разрешение на локальную сеть у тестового процесса.
    static func kind(usesRelay: Bool, customURL: URL?) -> TransportKind {
        // Свой адрес задают аргументом запуска и только ради проверки на
        // поднятом рядом сервере. Считаем это явной просьбой идти через него,
        // иначе переключатель в приложении пришлось бы трогать каждый раз.
        if let customURL {
            return .relay(customURL)
        }

        return usesRelay ? .relay(UserSettings.defaultRelayURL) : .nearby
    }

    @MainActor
    static func make() -> any PeerTransport {
        switch kind(usesRelay: UserSettings.usesRelay, customURL: UserSettings.relayURL) {
        case .relay(let url):
            print("[PeerTransportFactory] Relay transport: \(url)")
            return WebSocketTransport(url: url)

        case .nearby:
            print("[PeerTransportFactory] Multipeer transport")
            return MultipeerService()
        }
    }
}
