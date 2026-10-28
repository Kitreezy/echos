//
//  MetricsCollector.swift
//  echos
//
//  Метрики и диагностика с устройств через MetricKit.
//
//  Система сама копит данные о приложении и раз в сутки отдаёт сводку:
//  время запуска, зависания, память, энергию, сеть. Отчёты о падениях и
//  зависаниях со стеками приходят отдельно — начиная с iOS 15 при
//  следующем запуске, а не через сутки. Instruments показывает, что
//  происходит у меня на столе; MetricKit — что случилось у людей.
//
//  На симуляторе MetricKit ничего не присылает. На устройстве отчёт можно
//  получить сразу: Xcode → Debug → Simulate MetricKit Payloads.
//

import MetricKit
import OSLog

final class MetricsCollector: NSObject, MXMetricManagerSubscriber, Sendable {

    static let shared = MetricsCollector()

    /// Интервалы, которые попадут и в Instruments (Points of Interest),
    /// и в суточную сводку MetricKit — в раздел `signpostMetrics`.
    static let signposter = OSSignposter(logHandle: MXMetricManager.makeLogHandle(category: "echos"))

    private let store: DiagnosticsStore

    init(store: DiagnosticsStore = DiagnosticsStore()) {
        self.store = store
    }

    /// Подписаться. Отчёты, накопленные до подписки, система отдаёт сразу.
    func start() {
        MXMetricManager.shared.add(self)
    }

    // Вызываются на фоновой очереди MetricKit.

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            save(payload.jsonRepresentation(), kind: .metrics)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            if crashes + hangs > 0 {
                Logger.metrics.error("Отчёт MetricKit: падений \(crashes), зависаний \(hangs)")
            }
            save(payload.jsonRepresentation(), kind: .diagnostics)
        }
    }

    private func save(_ json: Data, kind: DiagnosticsStore.Kind) {
        do {
            let url = try store.save(json, kind: kind)
            Logger.metrics.notice("Сохранён отчёт MetricKit: \(url.lastPathComponent, privacy: .public)")
        } catch {
            Logger.metrics.error("Отчёт MetricKit не сохранён: \(error, privacy: .public)")
        }
    }
}
