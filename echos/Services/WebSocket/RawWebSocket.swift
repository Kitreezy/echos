//
//  RawWebSocket.swift
//  echos
//
//  Граница между «транспортом» и «всем остальным».
//
//  Ровно эту часть и заменяет готовая библиотека вроде Starscream: открыть
//  соединение, отправить кадр, получить кадр, пропинговать, закрыть.
//  Реконнект, backoff, heartbeat-политика, очередь исходящих и реакция на
//  состояние сети живут этажом выше и от выбора библиотеки не зависят.
//
//  Протокол существует, чтобы это утверждение можно было проверить, а не
//  постулировать: обе реализации гоняются одним и тем же набором тестов.
//

import Foundation

enum RawWebSocketEvent: Sendable {
    /// Handshake завершён, соединение готово.
    case opened
    case message(Data)
    /// Собеседник закрыл соединение штатно.
    case closed(code: Int, reason: String?)
    /// Оборвалось. Текстом, а не `Error`: наверх нужна только диагностика.
    case failed(String)
}

@MainActor
protocol RawWebSocket: AnyObject {

    /// События соединения. Один поток на сокет — сокет одноразовый,
    /// на переподключение создаётся новый.
    var events: AsyncStream<RawWebSocketEvent> { get }

    func open()
    func close()

    func send(_ data: Data) async throws

    /// Отправляет ping и ждёт pong. Таймаут накладывает вызывающий —
    /// политика живучести не дело транспорта.
    func ping() async throws
}
