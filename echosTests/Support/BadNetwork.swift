//
//  BadNetwork.swift
//  echosTests
//
//  Плохая сеть по команде — поверх настоящего сокета к тестовому релею.
//
//  `FakeNetworkMonitor` умеет только две крайности: путь есть или его нет.
//  Плохая сеть — третье: путь есть, а соединение ведёт себя так, будто его
//  нет. Рукопожатие не завершается, отправка не возвращается, pong теряется,
//  соединение открывается и тут же рвётся. Ни одно из этого не случается
//  с релеем на 127.0.0.1, поэтому сбой подмешивается между клиентом и
//  настоящим сокетом.
//

import Foundation
@testable import echos

/// Условия сети, общие для всех сокетов клиента.
///
/// Клиент создаёт новый сокет на каждое подключение, поэтому условия живут
/// отдельно от сокета: их можно поменять посреди теста, и следующее
/// подключение увидит уже новые — так «сеть выздоравливает».
@MainActor
final class BadNetwork {

    /// Рукопожатие не завершается: SYN или ответ сервера потерялись.
    var hangsOnOpen = false

    /// Соединение открывается и рвётся через столько. Лифт, метро, край
    /// зоны покрытия.
    var dropsAfterOpen: Duration?

    /// Отправка не возвращается: буфер сокета полон, данные никуда не идут.
    var stallsSends = false

    /// Ping уходит, pong не приходит: соединение умерло где-то посередине,
    /// а сокет об этом не знает.
    var losesPongs = false

    /// Сколько сокетов создал клиент — то есть сколько было попыток.
    private(set) var attempts = 0

    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func makeSocket() -> any RawWebSocket {
        attempts += 1
        return FlakySocket(wrapping: URLSessionRawSocket(url: url), network: self)
    }
}

/// Настоящий сокет, через который сбои `BadNetwork` пропускаются наружу.
///
/// Зависания сделаны так же, как у настоящего сокета: на отмену задачи они
/// не реагируют и отпускают только при закрытии. Иначе тест проверял бы
/// вежливую сеть, которой не бывает.
@MainActor
private final class FlakySocket: RawWebSocket {

    private let inner: any RawWebSocket
    private let network: BadNetwork
    private let broadcast = AsyncBroadcast<RawWebSocketEvent>()

    private var forwarding: Task<Void, Never>?
    private var dropping: Task<Void, Never>?
    private var stalled: [CheckedContinuation<Void, Error>] = []

    var events: AsyncStream<RawWebSocketEvent> { broadcast.stream }

    init(wrapping inner: any RawWebSocket, network: BadNetwork) {
        self.inner = inner
        self.network = network
    }

    func open() {
        // Сокет к серверу даже не открывается: со стороны клиента это
        // неотличимо от потерянного рукопожатия.
        guard !network.hangsOnOpen else {
            return
        }

        let drop = network.dropsAfterOpen
        forwarding = Task { [weak self] in
            guard let events = self?.inner.events else {
                return
            }
            for await event in events {
                self?.broadcast.yield(event)
                if case .opened = event, let drop {
                    self?.drop(after: drop)
                }
            }
        }
        inner.open()
    }

    func close() {
        forwarding?.cancel()
        dropping?.cancel()
        inner.close()
        releaseStalled()
        broadcast.finish()
    }

    func send(_ data: Data) async throws {
        guard !network.stallsSends else {
            return try await stall()
        }
        try await inner.send(data)
    }

    func ping() async throws {
        guard !network.losesPongs else {
            return try await stall()
        }
        try await inner.ping()
    }

    // MARK: - Private

    private func drop(after delay: Duration) {
        dropping = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else {
                return
            }
            self?.broadcast.yield(.failed("BadNetwork: соединение оборвалось"))
        }
    }

    private func stall() async throws {
        try await withCheckedThrowingContinuation { stalled.append($0) }
    }

    private func releaseStalled() {
        let waiting = stalled
        stalled.removeAll()
        waiting.forEach { $0.resume(throwing: RelayError.notConnected) }
    }
}
