//
//  Log.swift
//  echos
//
//  Логгеры приложения — по одному на подсистему.
//
//  `print` пишет в stdout: с устройства его не достать, уровней у него нет,
//  и всё, что в него попало, попадает целиком — адреса, имена, текст
//  сообщений. `Logger` пишет в системный журнал: его видно в Console.app и
//  в sysdiagnose, фильтруется по категории и уровню, а подставленные строки
//  без пометки `.public` в журнале вне отладчика заменяются на `<private>`.
//
//  Договорённость о приватности:
//  - текст сообщений и содержимое стены не пишутся вообще;
//  - адреса — `.private(mask: .hash)`: значение скрыто, но один и тот же
//    адрес даёт один и тот же хеш, и разговор с одним собеседником в
//    журнале можно проследить;
//  - имена устройств — приватные по умолчанию: их выбирает человек;
//  - ошибки сети и числа — публичные, в них нет ничего личного;
//  - ошибки хранилища — приватные: Core Data кладёт в них значения полей.
//
//  Уровни: `debug` — подробности, которые нужны только при отладке (в
//  журнал на устройстве не сохраняются); `info` — заметные шаги;
//  `notice` — смена состояния; `error` — сбой, после которого работа
//  продолжается; `fault` — то, чего не должно быть никогда.
//
//  Смотреть: Console.app, фильтр `subsystem:com.kitreezy.echos`, или
//  `log stream --predicate 'subsystem == "com.kitreezy.echos"' --level debug`.
//

import OSLog

extension Logger {

    static let subsystem = Bundle.main.bundleIdentifier ?? "com.kitreezy.echos"

    /// Создание и уничтожение экранов и сервисов — для поиска утечек.
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let chat = Logger(subsystem: subsystem, category: "chat")
    static let wall = Logger(subsystem: subsystem, category: "wall")
    static let screens = Logger(subsystem: subsystem, category: "screens")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let identity = Logger(subsystem: subsystem, category: "identity")
    /// Multipeer: поиск, приглашения, сессия.
    static let nearby = Logger(subsystem: subsystem, category: "nearby")
    /// Релей: сокет и рукопожатие.
    static let relay = Logger(subsystem: subsystem, category: "relay")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let metrics = Logger(subsystem: subsystem, category: "metrics")
    /// Пересказ пропущенного: модель на устройстве и перевод.
    static let digest = Logger(subsystem: subsystem, category: "digest")
}
