//
//  DiagnosticsExport.swift
//  echos
//
//  Что уходит, когда человек нажимает «Поделиться диагностикой»: журнал
//  этого запуска и отчёты MetricKit.
//
//  Журнал читается через `OSLogStore` — приложению доступны только его
//  собственные записи и только с текущего запуска. Приватные значения в
//  нём уже скрыты: адреса видны хешами, имена — как `<private>`. Записи
//  уровня `debug` система не хранит, их здесь не будет.
//

import Foundation
import OSLog

enum DiagnosticsExport {

    /// Файлы для листа «Поделиться». Журнал пишется заново при каждом
    /// вызове во временную папку.
    static func files(store: DiagnosticsStore = DiagnosticsStore()) -> [URL] {
        var files: [URL] = []

        do {
            files.append(try writeLog())
        } catch {
            Logger.metrics.error("Журнал не выгружен: \(error, privacy: .public)")
        }

        do {
            files += try store.reports()
        } catch {
            Logger.metrics.error("Отчёты MetricKit не прочитаны: \(error, privacy: .public)")
        }

        return files
    }

    private static func writeLog() throws -> URL {
        let log = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try log.getEntries(matching: NSPredicate(format: "subsystem == %@", Logger.subsystem))

        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
            "\(entry.date.formatted(.iso8601)) [\(entry.category)] \(entry.level.name): \(entry.composedMessage)"
        }

        let url = URL.temporaryDirectory.appending(path: "echos-log.txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private extension OSLogEntryLog.Level {
    var name: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "?"
        }
    }
}
