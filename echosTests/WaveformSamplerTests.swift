//
//  WaveformSamplerTests.swift
//  echosTests
//
//  Unit: звуковой файл → амплитуды баров. Синтетический WAV: значения
//  известны заранее, проверяем нормализацию и размер.
//

import Foundation
import Testing
@testable import echos

struct WaveformSamplerTests {

    @Test func sineWave_producesNormalizedBars() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "waveform-test-\(UUID().uuidString).wav")
        try TestAudio.writeWav(to: url, seconds: 1.5, amplitude: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try WaveformSampler.samples(from: url, barCount: 48)

        #expect(samples.count == 48)
        #expect(samples.allSatisfy { (0...1).contains($0) })
        #expect(samples.max() == 1, "Пик должен растянуться к 1")
        #expect(samples.filter { $0 > 0.1 }.count > 40, "Ровный синус не должен давать пустых вёдер")
    }

    @Test func missingFile_throws() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "waveform-missing-\(UUID().uuidString).wav")
        #expect(throws: WaveformSampler.SamplerError.self) {
            try WaveformSampler.samples(from: url, barCount: 48)
        }
    }

    @Test func quietAndLoud_haveSameShape() throws {
        // Громкость не должна менять форму волны: нормализация к пику.
        func shape(_ amplitude: Float) throws -> [Float] {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "waveform-shape-\(UUID().uuidString).wav")
            try TestAudio.writeWav(to: url, seconds: 1, amplitude: amplitude)
            defer { try? FileManager.default.removeItem(at: url) }
            return try WaveformSampler.samples(from: url, barCount: 48)
        }
        let quiet = try shape(0.1)
        let loud = try shape(0.9)
        for (q, l) in zip(quiet, loud) {
            #expect(abs(q - l) < 0.01)
        }
    }
}
