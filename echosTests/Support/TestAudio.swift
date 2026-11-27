//
//  TestAudio.swift
//  echosTests
//
//  Синтетический звук: WAV, который AVAudioFile точно прочитает.
//  Микрофон в тестах не поднять, файл — честная замена.
//

import Foundation

enum TestAudio {

    /// Моно WAV PCM 16 бит. Синус с заданной амплитудой — волна должна
    /// получиться ровной и нормализованной к 1.
    static func writeWav(to url: URL, sampleRate: Double = 44_100, seconds: Double = 2, amplitude: Float = 0.5) throws {
        let frameCount = Int(sampleRate * seconds)
        let dataSize = frameCount * 2
        var bytes = Data()
        bytes.reserveCapacity(44 + dataSize)

        func append<T>(_ value: T) {
            withUnsafeBytes(of: value) { bytes.append(contentsOf: $0) }
        }
        append(UInt32(0x46464952)) // "RIFF"
        append(UInt32(36 + UInt32(dataSize)))
        append(UInt32(0x45564157)) // "WAVE"
        append(UInt32(0x20746D66)) // "fmt "
        append(UInt32(16))
        append(UInt16(1))          // PCM
        append(UInt16(1))          // mono
        append(UInt32(UInt32(sampleRate)))
        append(UInt32(UInt32(sampleRate) * 2))
        append(UInt16(2))
        append(UInt16(16))
        append(UInt32(0x61746164)) // "data"
        append(UInt32(UInt32(dataSize)))

        for frame in 0..<frameCount {
            let phase = 2 * Float.pi * Float(440) * Float(frame) / Float(sampleRate)
            let sample = Int16(amplitude * sin(phase) * Float(Int16.max))
            append(sample)
        }
        try bytes.write(to: url)
    }
}
