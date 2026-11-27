//
//  VoiceRecorderTests.swift
//  echosTests
//
//  Unit: автомат записи голосового — переходы состояний, пауза и
//  продолжение, короткое выбрасывается, вложение собирается с волной.
//  Рукоятка — поддельная, но пишет настоящий WAV: finish читает файл
//  по-настоящему, и волна тоже.
//

import Foundation
import Testing
@testable import echos

/// Без @MainActor: протокол не изолирован, подделка живёт в тестовом
/// потоке, а обращаются к ней из @MainActor-сьюта — это допустимо.
final class FakeRecordingHandle: AudioRecordingHandle {

    private(set) var isRecording = false
    private(set) var currentTime: TimeInterval = 0

    var levels: [Float] = []
    private var levelIndex = 0

    let url: URL
    private var wroteFile = false

    init(url: URL) {
        self.url = url
    }

    func record() -> Bool {
        if !wroteFile {
            // Дорожку кладем один раз, при самом первом старте: пауза и
            // продолжение её не переписывают.
            try? TestAudio.writeWav(to: url, seconds: 2)
            wroteFile = true
        }
        isRecording = true
        return true
    }

    func pause() {
        isRecording = false
    }

    func stop() {
        isRecording = false
    }

    func averageLevel() -> Float {
        // Сценарий кончился — тишина, а не последнее значение вечным эхом.
        guard levelIndex < levels.count else {
            return 0
        }
        defer { levelIndex += 1 }
        return levels[levelIndex]
    }

    /// Тестовая перемотка: время капает, только пока пишем.
    func advance(_ seconds: TimeInterval) {
        if isRecording {
            currentTime += seconds
        }
    }
}

@MainActor
struct VoiceRecorderTests {

    private func makeRecorder(_ fake: @escaping @MainActor (URL) -> FakeRecordingHandle) -> VoiceRecorder {
        VoiceRecorder(makeHandle: { url in fake(url) },
                      requestPermission: { })
    }

    @Test func start_records_andMeterFlows() async throws {
        var handle: FakeRecordingHandle?
        let recorder = makeRecorder { url in
            let fake = FakeRecordingHandle(url: url)
            fake.levels = [0.2, 0.8]
            handle = fake
            return fake
        }

        try await recorder.start()

        #expect(recorder.state == .recording)
        #expect(recorder.level() == 0.2)
        #expect(recorder.level() == 0.8)
        // Сценарий кончился — тишина, а не последнее значение вечным эхом.
        #expect(recorder.level() == 0)
        #expect(recorder.level() == 0)
        recorder.cancel()
    }

    @Test func pauseAndResume_holdElapsed() async throws {
        var handle: FakeRecordingHandle?
        let recorder = makeRecorder { url in
            let fake = FakeRecordingHandle(url: url)
            handle = fake
            return fake
        }

        try await recorder.start()
        handle?.advance(1)
        recorder.pause()
        #expect(recorder.state == .paused)
        #expect(recorder.elapsed == 1)

        // На паузе время стоит и уровня нет.
        handle?.advance(5)
        #expect(recorder.elapsed == 1)
        #expect(recorder.level() == 0)

        recorder.resume()
        #expect(recorder.state == .recording)
        handle?.advance(1)
        #expect(recorder.elapsed == 2)
        recorder.cancel()
    }

    @Test func guards_ignoreOutOfOrderCalls() async throws {
        let recorder = makeRecorder { FakeRecordingHandle(url: $0) }

        // Не начинали — пауза, продолжение и финиш ни о чём.
        recorder.pause()
        recorder.resume()
        #expect(recorder.state == .idle)

        try await recorder.start()
        recorder.pause()
        recorder.pause()
        #expect(recorder.state == .paused)
        recorder.cancel()
    }

    @Test func finish_underSecond_throwsAndCleansUp() async throws {
        var handle: FakeRecordingHandle?
        var url: URL?
        let recorder = VoiceRecorder { address in
            let fake = FakeRecordingHandle(url: address)
            handle = fake
            url = address
            return fake
        } requestPermission: { }

        try await recorder.start()
        handle?.advance(0.3)
        do {
            _ = try recorder.finish()
            Issue.record("Короткое должно быть выброшено")
        } catch VoiceRecorderError.tooShort {
            // ожидаемо
        }
        #expect(recorder.state == .finished(0.3))
        #expect(url != nil)
        if let url {
            #expect(!FileManager.default.fileExists(atPath: url.path()),
                    "Короткая запись — мусор, файл должен быть удалён")
        }
    }

    @Test func finish_returnsAttachmentWithWaveform() async throws {
        var handle: FakeRecordingHandle?
        let recorder = makeRecorder { url in
            let fake = FakeRecordingHandle(url: url)
            handle = fake
            return fake
        }

        try await recorder.start()
        handle?.advance(2)

        let voice = try recorder.finish()

        #expect(voice.duration == 2)
        #expect(voice.samples.count == VoiceAttachment.barCount)
        #expect(voice.samples.allSatisfy { (0...1).contains($0) })
        #expect(voice.samples.max() == 1, "Волна нормализуется к пику")
        #expect(!voice.audio.isEmpty)

        // После финиша автомат свободен.
        #expect(recorder.state == .finished(2))
    }
}
