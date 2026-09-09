//
//  RelayHandshake.swift
//  echosTests
//
//  Рукопожатие с релеем для тестов, которые заняты не им.
//
//  Проверки переподключения и heartbeat работают с голым `WebSocketClient`,
//  но представиться серверу всё равно надо: иначе он не станет обслуживать
//  соединение, и тест провалится не по своей теме. Логика та же, что в
//  `WebSocketTransport`: дождаться вызова, подписать, отправить.
//

import Foundation
@testable import echos

@MainActor
enum RelayHandshake {

    /// Повесить рукопожатие на каждое подключение клиента.
    ///
    /// - Parameter identity: чем подписываться. Тесту, которому нужен адрес
    ///   собеседника, ключ приходится завести самому — отпечаток берётся
    ///   оттуда же.
    static func install(on client: WebSocketClient,
                        as name: String,
                        using identity: DeviceIdentity = DeviceIdentity()) {
        let inbox = ChallengeInbox(messages: client.incomingMessages)

        // Замыкание держит `inbox` — вызывающему хранить его не нужно.
        client.onConnected = { [weak client] in
            guard let challenge = await inbox.next() else {
                return
            }

            guard let hello = try? RelayEnvelope.hello(from: name,
                                                       answering: challenge,
                                                       as: identity).encoded() else {
                return
            }

            await client?.send(hello)
        }
    }
}

/// Ловит вызовы сервера.
///
/// Подписка на входящие оформляется сразу, а не в момент ожидания: вызов
/// приходит вплотную к установке соединения и может опередить того, кто его
/// ждёт.
@MainActor
private final class ChallengeInbox {

    private var pending: Data?
    private var waiter: CheckedContinuation<Data?, Never>?
    private var task: Task<Void, Never>?

    init(messages: AsyncStream<Data>) {
        task = Task { [weak self] in
            for await data in messages {
                guard let envelope = try? RelayEnvelope.decode(from: data),
                      envelope.kind == .challenge,
                      let challenge = try? envelope.decodeChallenge() else {
                    continue
                }

                self?.resume(with: challenge)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    func next() async -> Data? {
        if let pending {
            self.pending = nil
            return pending
        }

        return await withCheckedContinuation { continuation in
            waiter = continuation

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.resume(with: nil)
            }
        }
    }

    private func resume(with challenge: Data?) {
        guard let waiter else {
            pending = challenge
            return
        }

        self.waiter = nil
        waiter.resume(returning: challenge)
    }
}
