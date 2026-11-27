//
//  WaveformSampler.swift
//  echos
//
//  Звуковой файл → амплитуды баров волны.
//
//  Открытие файла и декодирование — одноразовая работа на запись: волна
//  кладётся в сообщение готовой и рисуется потом без AVAudioFile.
//  Каналы перемножаем в моно, файл режем на barCount вёдер, из каждого
//  берём среднеквадратичную — так громкие всплески не съедают тихий фон.
//

import AVFoundation
import Foundation

enum WaveformSampler {

    enum SamplerError: Error {
        /// Файла нет или декодер его не знает.
        case unreadable
    }

    /// Амплитуды по `barCount` барам, 0...1.
    static func samples(from url: URL, barCount: Int) throws -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw SamplerError.unreadable
        }
        let frameCount = Int(file.length)
        guard frameCount > 0, barCount > 0 else {
            return []
        }

        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw SamplerError.unreadable
        }
        try file.read(into: buffer)

        let channels = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData else {
            throw SamplerError.unreadable
        }

        var buckets = [Float](repeating: 0, count: barCount)
        var counts = [Int](repeating: 0, count: barCount)

        for frame in 0..<frameCount {
            var mono: Float = 0
            for channel in 0..<channels {
                mono += channelData[channel][frame]
            }
            mono /= Float(channels)
            let bucket = min(barCount - 1, frame * barCount / frameCount)
            buckets[bucket] += mono * mono
            counts[bucket] += 1
        }

        // RMS по вёдрам → нормализация к максимуму: масштаб волны не
        // должен зависеть от того, громко ли говорили в микрофон.
        var peaks = buckets.indices.map { index -> Float in
            guard counts[index] > 0 else {
                return 0
            }
            return sqrt(buckets[index] / Float(counts[index]))
        }
        if let max = peaks.max(), max > 0 {
            peaks = peaks.map { $0 / max }
        }
        return peaks
    }
}
