//
//  DiagnosticsStore.swift
//  echos
//
//  Папка с отчётами MetricKit на устройстве.
//
//  Сервера для отчётов у echos нет, и отправлять их куда-то без спроса
//  незачем: в отчёте о падении — стек вызовов и версия системы. Поэтому
//  отчёты лежат у человека, а наружу уходят, только когда он сам нажмёт
//  «Поделиться диагностикой».
//
//  Файлы закрыты до первой разблокировки после включения и не попадают в
//  резервную копию: на другом телефоне чужие падения бесполезны. Хранятся
//  последние `limit` отчётов, старые удаляются.
//

import Foundation

struct DiagnosticsStore: Sendable {

    enum Kind: String, Sendable {
        /// Суточная сводка: запуск, отзывчивость, память, энергия.
        case metrics
        /// Падения, зависания, перерасход CPU и диска — со стеками.
        case diagnostics
    }

    let directory: URL
    let limit: Int

    init(directory: URL = DiagnosticsStore.defaultDirectory, limit: Int = 60) {
        self.directory = directory
        self.limit = limit
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    /// Сохранить отчёт. Имя — вид и время получения, так файлы
    /// сортируются по дате и без чтения содержимого.
    @discardableResult
    func save(_ json: Data, kind: Kind, receivedAt date: Date = .now) throws -> URL {
        try prepareDirectory()

        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)
            .timeSeparator(.omitted))
        // Несколько отчётов из одной пачки получают одно и то же время.
        var url = directory.appending(path: "\(kind.rawValue)-\(stamp).json")
        var copy = 1
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = directory.appending(path: "\(kind.rawValue)-\(stamp)-\(copy).json")
            copy += 1
        }
        try json.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        try prune()
        return url
    }

    /// Все отчёты, новые первыми.
    func reports() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.reportDate > $1.reportDate }
    }

    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    private func prune() throws {
        for url in try reports().dropFirst(limit) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

private extension URL {
    /// Время из имени файла: всё после первого дефиса и без расширения.
    /// Вид в начале имени сортировку не сбивает.
    var reportDate: Substring {
        let name = deletingPathExtension().lastPathComponent
        guard let dash = name.firstIndex(of: "-") else { return name[...] }
        return name[name.index(after: dash)...]
    }
}
