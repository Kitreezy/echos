//
//  Fuzzer.swift
//  echosTests
//
//  Генератор входов для проверки разбора на мусоре.
//
//  Случайные байты почти всегда отсекаются первой же проверкой — это
//  проверяет только то, что JSON-декодер не падает. Полезнее испорченные
//  настоящие данные: структура почти верная, и разбор доходит до кода
//  приложения — до проверок размера мозаики, ключей, адресов. Поэтому
//  большая часть входов — мутации образцов, а значения в JSON подменяются
//  крайними: огромные числа, отрицательные, длинные строки, лишняя
//  вложенность.
//
//  Генератор с зерном. Падение процесса тест поймать не может, но зерно
//  печатается в начале, и `FUZZ_SEED` повторяет ту же последовательность
//  входов — вплоть до падающего. `FUZZ_ITERATIONS` — сколько входов на
//  тест; по умолчанию столько, чтобы прогон занимал секунды.
//

import Foundation

/// SplitMix64: быстрый и воспроизводимый. Криптостойкость здесь не нужна.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

enum Fuzz {

    static var iterations: Int {
        ProcessInfo.processInfo.environment["FUZZ_ITERATIONS"].flatMap(Int.init) ?? 1000
    }

    static func seed(_ name: String) -> UInt64 {
        if let fixed = ProcessInfo.processInfo.environment["FUZZ_SEED"].flatMap(UInt64.init) {
            return fixed
        }
        let seed = UInt64.random(in: 1...UInt64.max)
        print("[fuzz] \(name): FUZZ_SEED=\(seed)")
        return seed
    }

    /// Самое медленное на одном входе — признак квадратичного разбора или
    /// зависания. Порог щедрый: Debug-сборка на нагруженной машине.
    static let slowInput: Duration = .milliseconds(200)

    struct Report {
        var slowest: Duration = .zero
        var slowestInput = Data()
    }

    /// Прогнать `body` на `iterations` входах. Входы — от `generate`.
    static func run(_ name: String,
                    iterations: Int = Fuzz.iterations,
                    generate: (inout SeededGenerator) -> Data,
                    body: (Data) -> Void) -> Report {
        var generator = SeededGenerator(seed: seed(name))
        var report = Report()
        let clock = ContinuousClock()
        for _ in 0..<iterations {
            let input = generate(&generator)
            let elapsed = clock.measure { body(input) }
            if elapsed > report.slowest {
                report.slowest = elapsed
                report.slowestInput = input
            }
        }
        return report
    }

    // MARK: - Входы

    /// Смесь: немного чистого мусора, остальное — испорченные образцы.
    static func input(from samples: [Data], using generator: inout SeededGenerator) -> Data {
        switch Int.random(in: 0..<10, using: &generator) {
        case 0:
            return randomBytes(using: &generator)
        case 1...4:
            return mutateBytes(samples.randomElement(using: &generator)!, using: &generator)
        default:
            return mutateJSON(samples.randomElement(using: &generator)!, using: &generator)
        }
    }

    static func randomBytes(using generator: inout SeededGenerator) -> Data {
        let count = Int.random(in: 0...256, using: &generator)
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    /// Порча на уровне байтов: перевёрнутые биты, обрезка, вставка, повтор.
    static func mutateBytes(_ data: Data, using generator: inout SeededGenerator) -> Data {
        var bytes = [UInt8](data)
        for _ in 0..<Int.random(in: 1...4, using: &generator) {
            guard !bytes.isEmpty else {
                bytes = [UInt8.random(in: 0...255, using: &generator)]
                continue
            }
            let index = Int.random(in: 0..<bytes.count, using: &generator)
            switch Int.random(in: 0..<5, using: &generator) {
            case 0:
                bytes[index] ^= 1 << UInt8.random(in: 0...7, using: &generator)
            case 1:
                bytes.removeSubrange(index...)
            case 2:
                bytes.insert(UInt8.random(in: 0...255, using: &generator), at: index)
            case 3:
                bytes.remove(at: index)
            default:
                let end = min(bytes.count, index + Int.random(in: 1...32, using: &generator))
                bytes.insert(contentsOf: bytes[index..<end], at: index)
            }
        }
        return Data(bytes)
    }

    /// Порча на уровне значений: JSON остаётся JSON, но одно поле — или
    /// несколько — получает то, чего код не ждёт.
    static func mutateJSON(_ data: Data, using generator: inout SeededGenerator) -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return mutateBytes(data, using: &generator)
        }
        for _ in 0..<Int.random(in: 1...3, using: &generator) {
            root = mutate(root, depth: 0, using: &generator)
        }
        return (try? JSONSerialization.data(withJSONObject: root, options: [.fragmentsAllowed])) ?? data
    }

    private static func mutate(_ value: Any, depth: Int, using generator: inout SeededGenerator) -> Any {
        if var object = value as? [String: Any], !object.isEmpty, Bool.random(using: &generator) {
            let key = object.keys.sorted().randomElement(using: &generator)!
            if Int.random(in: 0..<8, using: &generator) == 0 {
                object[key] = nil  // поле пропало
            } else {
                object[key] = mutate(object[key]!, depth: depth + 1, using: &generator)
            }
            return object
        }
        if var array = value as? [Any], !array.isEmpty, Bool.random(using: &generator) {
            let index = Int.random(in: 0..<array.count, using: &generator)
            switch Int.random(in: 0..<4, using: &generator) {
            case 0: array.remove(at: index)
            case 1: array.append(contentsOf: Array(repeating: array[index], count: Int.random(in: 1...200, using: &generator)))
            default: array[index] = mutate(array[index], depth: depth + 1, using: &generator)
            }
            return array
        }
        return nasty(using: &generator)
    }

    /// Значения, на которых обычно и ломаются.
    static func nasty(using generator: inout SeededGenerator) -> Any {
        let fixed: [Any] = [
            0, -1, Int.max, Int.min, Int32.max, 1e300, -1e300, 0.5, 9, 64, 100_000,
            "", "🟥", "🟥🟦", "👨‍👩‍👧‍👦", String(repeating: "x", count: 100_000), "\u{0}", "\u{FFFD}",
            "not-a-uuid", "00000000-0000-0000-0000-000000000000", "AAAA",
            true, NSNull(), [] as [Any], [:] as [String: Any]
        ]
        switch Int.random(in: 0..<(fixed.count + 2), using: &generator) {
        case fixed.count:
            // Один «знак» из тысяч кодовых точек: буква и комбинирующие ударения.
            return "a" + String(repeating: "\u{0301}", count: Int.random(in: 1...20_000, using: &generator))
        case fixed.count + 1:
            // Глубже не надо: `JSONSerialization` пишет вложенность
            // рекурсией, и на потоке теста с маленьким стеком падает сам
            // генератор. Глубокую вложенность проверяет deepNesting_isRejected
            // — готовой строкой, без записи.
            return nested(Int.random(in: 1...200, using: &generator))
        case let index:
            return fixed[index]
        }
    }

    private static func nested(_ depth: Int) -> Any {
        var value: Any = 0
        for _ in 0..<depth {
            value = [value]
        }
        return value
    }
}
