//
//  VoiceRecorder.swift
//  echos
//
//  Запись голосового: AVAudioRecorder за протоколом.
//
//  Ручка записи спрятана не ради абстракции, а ради состояний: pause на
//  незаписанном, stop дважды, resume после finish — настоящий рекордер
//  на такое отвечает по-своему и не всегда одинаково. Конечный автомат
//  живёт здесь и проверяется на подделке; настоящий AVAudioRecorder в
//  этом классе не тестируется — его верит симулятор и устройство.
//

import AVFoundation
import Foundation
import OSLog

/// Что умеет ручка записи. AVAudioRecorder умеет больше — нам хватает.
protocol AudioRecordingHandle {
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }
    func record() -> Bool
    func pause()
    func stop()
    /// Уровень громкости для живой волны, 0...1.
    func averageLevel() -> Float
}

extension AVAudioRecorder: AudioRecordingHandle {
    func averageLevel() -> Float {
        updateMeters()
        // Метры в dB, диапазон примерно -60...0: растягиваем в 0...1.
        let db = averagePower(forChannel: 0)
        return min(1, max(0, (db + 60) / 60))
    }
}

/// Ошибки записи — своими словами: ошибки AVFoundation человеку ни о чём.
enum VoiceRecorderError: Error, Equatable {
    /// Микрофон не разрешён. Разрешение — Настройки, дальше мы не лезем.
    case permissionDenied
    /// Сессия или ручка не поднялись. Микрофон занят или сломан.
    case engineUnavailable
    /// Слишком короткое: то, что короче секунды, — случайный кашель.
    case tooShort
}

/// Автомат записи: idle → recording ⇄ paused → finished.
@MainActor
final class VoiceRecorder {

    private let makeHandle: @MainActor (URL) throws -> any AudioRecordingHandle
    /// Разрешение на микрофон — отдельной инъекцией: автомат тестируется
    /// без TCC и без микрофона.
    private let requestPermission: @MainActor () async throws -> Void
    private var handle: (any AudioRecordingHandle)?
    private var url: URL?

    /// Сколько секунд считаем минимально осмысленной записью.
    static let minimumDuration: TimeInterval = 1

    init(makeHandle: @escaping @MainActor (URL) throws -> any AudioRecordingHandle = VoiceRecorder.makeRealHandle,
         requestPermission: @escaping @MainActor () async throws -> Void = VoiceRecorder.requestMicrophonePermission) {
        self.makeHandle = makeHandle
        self.requestPermission = requestPermission
    }

    /// Рукоятка идёт к AVAudioRecorder напрямую, без инъекций: создание
    /// — обвязка системной сессией, подменять её в тестах смысла нет,
    /// автомат тестируется на поддельной рукоятке.
    @MainActor
    private static func makeRealHandle(url: URL) throws -> any AudioRecordingHandle {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        do {
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                // Без этого AVAudioRecorder не отдаёт метров для волны.
                AVLinearPCMBitDepthKey: 16,
            ])
            recorder.isMeteringEnabled = true
            return recorder
        } catch {
            Logger.screens.error("Voice recorder unavailable: \(error, privacy: .public)")
            throw VoiceRecorderError.engineUnavailable
        }
    }

    // MARK: - Автомат

    private(set) var state: State = .idle

    enum State: Equatable {
        case idle
        case recording
        case paused
        case finished(TimeInterval)
    }

    /// Начать новую запись. Старое, неотправленное — выброшено:
    //  новая запись старой дорожкой не бывает.
    func start() async throws {
        try await requestPermission()

        let url = FileManager.default.temporaryDirectory
            .appending(path: "voice-\(UUID().uuidString).m4a")
        let handle = try makeHandle(url)

        guard handle.record() else {
            throw VoiceRecorderError.engineUnavailable
        }
        self.handle = handle
        self.url = url
        state = .recording
    }

    /// Уровень для живой волны, 0...1. Вне записи — тишина.
    func level() -> Float {
        guard state == .recording, let handle else {
            return 0
        }
        return handle.averageLevel()
    }
    /// Сколько записано суммарно, с учётом пауз. У AVAudioRecorder
    /// currentTime на паузе не тикает — складывать ничего не нужно.
    var elapsed: TimeInterval {
        handle?.currentTime ?? 0
    }

    func pause() {
        guard state == .recording else {
            return
        }
        handle?.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else {
            return
        }
        handle?.record()
        state = .recording
    }

    /// Закончить и собрать вложение. Файл и волна — результат; короткое
    /// — выброс, чтобы UI не создавал сообщения из случайных щелчков.
    func finish() throws -> VoiceAttachment {
        guard state == .recording || state == .paused, let handle, let url else {
            throw VoiceRecorderError.tooShort
        }
        handle.stop()
        let duration = handle.currentTime
        state = .finished(duration)

        defer {
            self.handle = nil
            self.url = nil
        }
        guard duration >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: url)
            throw VoiceRecorderError.tooShort
        }
        let audio = try Data(contentsOf: url)
        let samples = try WaveformSampler.samples(from: url, barCount: VoiceAttachment.barCount)
        return VoiceAttachment(duration: duration, samples: samples, audio: audio)
    }

    /// Отмена: файл не нужен, состояние — тишина.
    func cancel() {
        handle?.stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        handle = nil
        url = nil
        state = .idle
    }

    // MARK: - Разрешение

    /// Спросить разрешение. Симулятор с устройства без микрофона
    /// (CI) отвечает denied — тесты UI идут через подмену, это честно.
    static func requestMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                throw VoiceRecorderError.permissionDenied
            }
        case .denied:
            throw VoiceRecorderError.permissionDenied
        case .granted:
            return
        @unknown default:
            throw VoiceRecorderError.engineUnavailable
        }
    }
}
