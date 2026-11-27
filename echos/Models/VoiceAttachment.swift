//
//  VoiceAttachment.swift
//  echos
//
//  Голосовое сообщение: звук и форма волны, что его рисует.
//
//  Форма волны хранится готовой ([Float] по барам), а не вычисляется
//  из звука на лету: открыть чат и декодировать все голосовые подряд —
//  не работа для главного потока. Сэмплы — 0...1, нормализованные,
//  порядок не важен, размер фиксирован.
//

import Foundation

/// Вложение голосового сообщения.
struct VoiceAttachment: Codable, Equatable, Sendable {

    /// Сколько секунд звука. 0 — пустышка, отправлять незачем.
    let duration: TimeInterval
    /// Амплитуды по барам волны, 0...1. Размер — `barCount`.
    let samples: [Float]
    /// Звук, m4a (AAC). Бинарь едет в payload base64: Multipeer и релей
    /// его проглатывают, шифрование поверх — байт-независимое.
    let audio: Data

    /// Сколько баров рисуем в ячейке и кладём в payload.
    static let barCount = 48

    /// "0:07" — минуты, секунды с ведущим нулём: подпись в сообщении,
    /// ячейке и списках — одна.
    static func format(duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

/// Транспортная форма вложения. Зеркало VoiceAttachment: менять вместе.
struct VoicePayload: Codable, Equatable, Sendable {
    let duration: TimeInterval
    let samples: [Float]
    let audio: String // base64

    init(duration: TimeInterval, samples: [Float], audio: String) {
        self.duration = duration
        self.samples = samples
        self.audio = audio
    }

    init(from attachment: VoiceAttachment) {
        duration = attachment.duration
        samples = attachment.samples
        audio = attachment.audio.base64EncodedString()
    }

    /// Байты, из которых база64 не собрался, — не вложение, а текст:
    /// payload валиден, а голосового в нём просто нет.
    var attachment: VoiceAttachment? {
        guard let data = Data(base64Encoded: audio) else {
            return nil
        }
        return VoiceAttachment(duration: duration, samples: samples, audio: data)
    }
}
