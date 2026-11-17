//
//  BackgroundDownloadServiceTests.swift
//  echosTests
//
//  Фоновые загрузки: конфигурация сессии, персистентность очереди,
//  перемещение готового файла и сохранение resume-data для докачки.
//

import Foundation
import Synchronization
import Testing
@testable import echos

@MainActor
@Suite(.serialized)
final class BackgroundDownloadServiceTests {

    private let root: URL
    private let storeDirectory: URL
    private let downloadsDirectory: URL
    private let store: BackgroundDownloadStore

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "echos-background-downloads-\(UUID().uuidString)", directoryHint: .isDirectory)
        storeDirectory = root.appending(path: "store", directoryHint: .isDirectory)
        downloadsDirectory = root.appending(path: "downloads", directoryHint: .isDirectory)
        store = BackgroundDownloadStore(directory: storeDirectory)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService(configuration: URLSessionConfiguration = .ephemeral) -> BackgroundDownloadService {
        BackgroundDownloadService(store: store,
                                  destinationDirectory: downloadsDirectory,
                                  configuration: configuration)
    }

    // MARK: - Конфигурация

    @Test func backgroundConfiguration_usesBackgroundIdentifierAndLaunchEvents() {
        let configuration = BackgroundDownloadService.backgroundConfiguration()

        #expect(configuration.identifier == BackgroundDownloadService.sessionIdentifier)
        #expect(configuration.sessionSendsLaunchEvents)
        #expect(!configuration.isDiscretionary)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    // MARK: - Хранилище

    @Test func store_keepsDownloadAndResumeData() throws {
        var download = PersistedBackgroundDownload(
            id: UUID(),
            url: URL(string: "https://example.com/file.bin")!,
            storedFileName: "file.bin",
            resumeFileName: nil
        )

        try store.save([download])
        #expect(try store.load() == [download])

        let resume = Data([1, 2, 3, 4])
        download.resumeFileName = try store.saveResumeData(resume, for: download.id)
        try store.save([download])

        #expect(try store.resumeData(for: download) == resume)

        store.removeResumeData(for: download)
        #expect(try store.resumeData(for: download) == nil)
    }

    // MARK: - Очередь

    @Test func enqueue_persistsDownloadBeforeTaskStarts() throws {
        let service = makeService()
        defer { service.cancelAll() }

        let id = try service.enqueueDownload(
            from: URL(string: "https://127.0.0.1:1/file.bin")!,
            saveAs: "../file.bin"
        ) { _ in }

        let pending = try store.load()
        #expect(pending.map(\.id) == [id])
        #expect(pending[0].storedFileName.contains("-file.bin"))
        #expect(!pending[0].storedFileName.contains(".."))
        #expect(service.activeTasks[id] != nil)
    }

    @Test func completedDownload_movesFileAndRemovesPendingRecord() async throws {
        let service = makeService()

        let received = Mutex<Result<URL, BackgroundDownloadFailure>?>(nil)
        let id = try service.enqueueDownload(
            from: URL(string: "https://127.0.0.1:1/file.bin")!,
            saveAs: "file.bin"
        ) { result in
            received.withLock { $0 = result }
        }

        let source = root.appending(path: "incoming.bin")
        try Data("готово".utf8).write(to: source)
        service.completeDownload(id: id, temporaryFile: source)

        _ = await waitUntil { received.withLock { $0 } != nil }
        let result = received.withLock { $0 }
        guard case let .success(url)? = result else {
            Issue.record("ожидался готовый файл, получено: \(String(describing: result))")
            return
        }

        #expect(url.deletingLastPathComponent() == downloadsDirectory)
        #expect(try String(contentsOf: url, encoding: .utf8) == "готово")
        #expect(try store.load().isEmpty)
        #expect(service.activeTasks.isEmpty)
    }

    @Test func failedDownload_withResumeData_keepsRecordForNextLaunch() async throws {
        let service = makeService()
        defer { service.cancelAll() }

        let received = Mutex<Result<URL, BackgroundDownloadFailure>?>(nil)
        let id = try service.enqueueDownload(
            from: URL(string: "https://127.0.0.1:1/file.bin")!,
            saveAs: "file.bin"
        ) { result in
            received.withLock { $0 = result }
        }

        service.failDownload(id: id,
                             error: CocoaError(.coderReadCorrupt),
                             resumeData: Data([9, 8, 7]))

        _ = await waitUntil { received.withLock { $0 } != nil }
        let result = received.withLock { $0 }
        guard case let .failure(failure)? = result else {
            Issue.record("ожидалась ошибка, получено: \(String(describing: result))")
            return
        }

        #expect(failure.canResume)
        let pending = try store.load()
        #expect(pending.count == 1)
        #expect(pending[0].resumeFileName != nil)
        #expect(try store.resumeData(for: pending[0]) == Data([9, 8, 7]))

        // Подставные байты — ещё не валидный resume-data для URLSession,
        // поэтому факт пересоздания задачи проверяется отдельным тестом без
        // resume-файла. Здесь важно, что запись и файл пережили сбой.
    }

    @Test func restorePendingDownloads_recreatesTaskFromPersistedRecord() async throws {
        let id = UUID()
        try store.save([
            PersistedBackgroundDownload(id: id,
                                        url: URL(string: "https://127.0.0.1:1/file.bin")!,
                                        storedFileName: "file.bin",
                                        resumeFileName: nil)
        ])

        let relaunched = makeService()
        defer { relaunched.cancelAll() }
        relaunched.restorePendingDownloads()

        let restored = await waitUntil { relaunched.activeTasks[id] != nil }
        #expect(restored, "После перезапуска сохранённая загрузка должна снова появиться в сессии")
    }

    @Test func failedDownload_withoutResumeData_removesPendingRecord() async throws {
        let service = makeService()

        let received = Mutex<Result<URL, BackgroundDownloadFailure>?>(nil)
        let id = try service.enqueueDownload(
            from: URL(string: "https://127.0.0.1:1/file.bin")!,
            saveAs: "file.bin"
        ) { result in
            received.withLock { $0 = result }
        }

        service.failDownload(id: id,
                             error: CocoaError(.coderReadCorrupt),
                             resumeData: nil)

        _ = await waitUntil { received.withLock { $0 } != nil }
        let result = received.withLock { $0 }
        guard case let .failure(failure)? = result else {
            Issue.record("ожидалась ошибка, получено: \(String(describing: result))")
            return
        }

        #expect(!failure.canResume)
        #expect(try store.load().isEmpty)
        #expect(service.activeTasks.isEmpty)
    }

    @Test func backgroundEvents_finishWhenNoPendingDownloadsRemain() async {
        let service = makeService()
        let finished = Mutex(false)

        service.handleBackgroundEvents {
            finished.withLock { $0 = true }
        }

        let didFinish = await waitUntil { finished.withLock { $0 } }
        #expect(didFinish)
    }
}
