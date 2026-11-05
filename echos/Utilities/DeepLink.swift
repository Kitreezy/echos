//
//  DeepLink.swift
//  echos
//
//  Разбор ссылок вида echos://chat/<адрес>.
//
//  Своя схема — самый дешёвый способ открыть приложение снаружи: из
//  заметки, письма, терминала (`xcrun simctl openurl`). Ссылка ничего не
//  доказывает и ничего не открывает сама — это просьба показать чат;
//  писать всё равно можно только тому, чей ключ подтверждён рукопожатием.
//

import Foundation

/// Ссылка в приложение. Маршрутов нарочно мало: каждый новый — это
/// внешний API, который придётся поддерживать всегда.
enum DeepLink: Equatable {
    /// Открыть чат с адресом из ссылки.
    case chat(address: String)

    /// Разобрать URL. Не наша схема, неизвестный маршрут, лишние части
    /// адреса — не наше: молча пропускаем, открывать нечего.
    init?(url: URL) {
        // Схема и хост по RFC нечувствительны к регистру, а URL их
        // приводит сам — но только если строку разобрал. Страхуемся.
        guard url.scheme?.lowercased() == "echos",
              url.host()?.lowercased() == "chat" else {
            return nil
        }

        // echos://chat/<адрес>: адрес — ровно один компонент пути.
        // Вложенные маршруты, запросы и фрагменты не несём.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1,
              let address = parts.first,
              !address.isEmpty,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }

        self = .chat(address: address.lowercased())
    }
}
