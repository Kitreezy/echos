//
//  DiagnosticsStoreTests.swift
//  echosTests
//
//  Отчёты MetricKit на диске: новые первыми, лишние удаляются, в резервную
//  копию не попадают. Сами отчёты в тестах не создать — у MetricKit нет
//  открытых инициализаторов, — поэтому хранилище принимает готовый JSON.
//

import Foundation
import OSLog
import Testing
@testable import echos

struct DiagnosticsStoreTests {

    private let store = DiagnosticsStore(
        directory: URL.temporaryDirectory.appending(path: "Diagnostics-\(UUID().uuidString)"),
        limit: 3)

    private func json(_ value: Int) -> Data {
        Data(#"{"n":\#(value)}"#.utf8)
    }

    @Test func reports_newestFirst() throws {
        defer { try? store.removeAll() }
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        try store.save(json(1), kind: .metrics, receivedAt: start)
        try store.save(json(2), kind: .diagnostics, receivedAt: start.addingTimeInterval(60))

        let reports = try store.reports().map { try Data(contentsOf: $0) }
        #expect(reports == [json(2), json(1)],
                "Вид в начале имени не должен влиять на порядок")
    }

    @Test func overLimit_dropsOldest() throws {
        defer { try? store.removeAll() }
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        for day in 0..<5 {
            try store.save(json(day), kind: .metrics, receivedAt: start.addingTimeInterval(Double(day) * 86_400))
        }

        let kept = try store.reports().map { try Data(contentsOf: $0) }
        #expect(kept == [json(4), json(3), json(2)])
    }

    @Test func sameMoment_keepsBoth() throws {
        defer { try? store.removeAll() }
        let now = Date.now

        try store.save(json(1), kind: .diagnostics, receivedAt: now)
        try store.save(json(2), kind: .diagnostics, receivedAt: now)

        #expect(try store.reports().count == 2, "Два отчёта из одной пачки — два файла")
    }

    @Test func directory_excludedFromBackup() throws {
        defer { try? store.removeAll() }
        try store.save(json(1), kind: .metrics)

        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func empty_whenNothingSaved() throws {
        #expect(try store.reports().isEmpty)
    }

    /// Журнал читается через `OSLogStore` — тестовый процесс и есть
    /// приложение, так что запись отсюда должна оказаться в выгрузке.
    @Test func export_containsLogAndReports() throws {
        defer { try? store.removeAll() }
        try store.save(json(1), kind: .diagnostics)
        let marker = UUID().uuidString
        Logger.metrics.notice("Метка выгрузки \(marker, privacy: .public)")

        let files = DiagnosticsExport.files(store: store)

        let log = try #require(files.first { $0.lastPathComponent == "echos-log.txt" })
        #expect(try String(contentsOf: log, encoding: .utf8).contains(marker))
        #expect(files.count == 2, "Журнал и один отчёт")
    }
}
