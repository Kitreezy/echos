//
//  BackgroundDownloadService.swift
//  echos
//
//  Файловые загрузки, которые переживают сворачивание приложения.
//
//  Обычный `URLSession` останавливается вместе с приложением. Фоновая
//  конфигурация продолжает задачу вне процесса, а при запуске система
//  возвращает события через `handleEventsForBackgroundURLSession`. Здесь
//  поверх этого живёт небольшая очередь: метаданные лежат на диске до самого
//  конца, а при обрыве хранится resume-data, чтобы продолжить файл с места
//  обрыва, а не качать заново.
//

import Foundation
import OSLog

/// Скачанный файл или причина, по которой его нет.
struct BackgroundDownloadFailure: Error, Equatable, Sendable {
    var message: String
    /// Сервер отдал resume-data: загрузку можно продолжить после запуска.
    var canResume: Bool
}

typealias BackgroundDownloadCompletion = @Sendable (Result<URL, BackgroundDownloadFailure>) -> Void

/// Загрузка, которая ещё не дошла до финального файла.
struct PersistedBackgroundDownload: Codable, Equatable, Sendable {
    let id: UUID
    let url: URL
    /// Имя файла в папке загрузок. В начале — UUID: коллизий между разными
    /// версиями одного имени не бывает, и подменить путь через `../` нельзя.
    let storedFileName: String
    var resumeFileName: String?
}

/// Индекс незавершённых загрузок и файлы докачки. Отдельно от сервиса,
/// чтобы можно было проверить восстановление без сети и без URLSession.
@MainActor
final class BackgroundDownloadStore {

    static let shared = BackgroundDownloadStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "BackgroundDownloads", directoryHint: .isDirectory))

    private let directory: URL
    private let indexURL: URL
    private let directoryAccessible: Bool

    init(directory: URL) {
        self.directory = directory
        self.indexURL = directory.appending(path: "downloads.json")
        self.directoryAccessible = (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil
    }

    func load() throws -> [PersistedBackgroundDownload] {
        guard directoryAccessible else {
            throw CocoaError(.fileWriteNoPermission)
        }
        guard FileManager.default.fileExists(atPath: indexURL.path(percentEncoded: false)) else {
            return []
        }
        return try JSONDecoder().decode([PersistedBackgroundDownload].self, from: Data(contentsOf: indexURL))
    }

    func save(_ downloads: [PersistedBackgroundDownload]) throws {
        guard directoryAccessible else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let data = try JSONEncoder().encode(downloads)
        try data.write(to: indexURL, options: .atomic)
    }

    func saveResumeData(_ data: Data, for id: UUID) throws -> String {
        guard directoryAccessible else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let name = "\(id.uuidString).resume"
        try data.write(to: directory.appending(path: name), options: .atomic)
        return name
    }

    func resumeData(for download: PersistedBackgroundDownload) throws -> Data? {
        guard let name = download.resumeFileName else {
            return nil
        }
        let file = directory.appending(path: name)
        // Файл мог удалить внешний очиститель или прервавшаяся запись.
        // Для очереди это то же состояние, что «resume-data не сохранилась»:
        // начать файл заново, а не считать запись испорченной.
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            return nil
        }
        return try Data(contentsOf: file)
    }

    func removeResumeData(for download: PersistedBackgroundDownload) {
        guard let name = download.resumeFileName else {
            return
        }
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
}

/// Очередь фоновых загрузок. Сервис синглтонный не ради удобства, а потому
/// что система возвращает события фоновой сессии приложению целиком: второй
/// экземпляр с тем же идентификатором увидел бы чужие задачи.
@MainActor
final class BackgroundDownloadService: NSObject {

    static let shared = BackgroundDownloadService()
    static let sessionIdentifier = "com.kitreezy.echos.background-downloads"

    private let store: BackgroundDownloadStore
    private let destinationDirectory: URL
    /// Делегатом сессии служит сам сервис, поэтому `URLSession` создаётся
    /// только после `super.init()` — отсюда неизбежный implicitly-unwrapped.
    private var session: URLSession!

    private(set) var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var completions: [UUID: BackgroundDownloadCompletion] = [:]
    private var backgroundCompletion: (@Sendable () -> Void)?

    init(store: BackgroundDownloadStore = .shared,
         destinationDirectory: URL = FileManager.default.urls(for: .documentDirectory,
                                                              in: .userDomainMask)[0],
         configuration: URLSessionConfiguration = BackgroundDownloadService.backgroundConfiguration()) {
        self.store = store
        self.destinationDirectory = destinationDirectory
        super.init()
        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        self.session = URLSession(configuration: configuration,
                                  delegate: self,
                                  delegateQueue: .main)
    }

    /// Конфигурация именно background: иначе свёрнутое приложение остановит
    /// задачу вместе с процессом. `sessionSendsLaunchEvents` возвращает
    /// контроль в `AppDelegate.handleEventsForBackgroundURLSession`.
    static func backgroundConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    /// Поставить файл в очередь. Метаданные сохраняются до `resume()`: если
    /// процесс исчезнет между постановкой и стартом, восстановление найдёт
    /// запись и создаст задачу заново.
    @discardableResult
    func enqueueDownload(from url: URL,
                         saveAs fileName: String,
                         completion: @escaping BackgroundDownloadCompletion) throws -> UUID {
        let id = UUID()
        let safeName = "\(id.uuidString)-\(URL(filePath: fileName).lastPathComponent)"
        let download = PersistedBackgroundDownload(id: id,
                                                   url: url,
                                                   storedFileName: safeName,
                                                   resumeFileName: nil)

        var pending = try store.load()
        pending.append(download)
        try store.save(pending)

        completions[id] = completion
        startTask(for: download)
        return id
    }

    /// Есть ли что восстанавливать. Холодный запуск без фоновых загрузок не
    /// должен платить за обращение к сессии: `getTasksWithCompletionHandler`
    /// остаётся только для реально прерванной очереди.
    func hasPendingDownloads() -> Bool {
        (try? store.load())?.isEmpty == false
    }

    /// Восстановить очередь после запуска. Живые задачи сессии не трогаем,
    /// а записи без задачи создаём заново — с resume-data, если она есть.
    func restorePendingDownloads() {
        let pending = (try? store.load()) ?? []

        session.getTasksWithCompletionHandler { [weak self] _, _, downloads in
            Task { @MainActor in
                guard let self else {
                    return
                }

                let liveIDs = Set(downloads.compactMap { task in
                    task.taskDescription.flatMap(UUID.init(uuidString:))
                })

                for download in pending where !liveIDs.contains(download.id) {
                    self.startTask(for: download)
                }

                if pending.isEmpty && downloads.isEmpty {
                    self.finishBackgroundEvents()
                }
            }
        }
    }

    /// Система разбудила приложение ради фоновой сессии. Храним completion
    /// до `urlSessionDidFinishEvents`: системный бюджет на выполнение закроет
    /// его только после того, как все события сессии обработаны.
    func handleBackgroundEvents(completion: @escaping @Sendable () -> Void) {
        backgroundCompletion = completion
        restorePendingDownloads()
    }

    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        completions.removeAll()
    }

    // MARK: - Results

    /// URLSession отдала временный файл. Его надо перенести сразу: система
    /// удалит его после возврата из колбэка.
    func completeDownload(id: UUID, temporaryFile: URL) {
        guard let download = pendingDownload(id: id) else {
            return
        }

        let destination = destinationDirectory.appending(path: download.storedFileName)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryFile, to: destination)
            removePendingDownload(download)
            finish(id: id, result: .success(destination))
        }
        catch {
            failDownload(id: id, error: error, resumeData: nil)
        }
    }

    func failDownload(id: UUID, error: Error, resumeData: Data?) {
        guard var download = pendingDownload(id: id) else {
            return
        }

        if let resumeData, !resumeData.isEmpty {
            download.resumeFileName = try? store.saveResumeData(resumeData, for: id)
            try? store.save(replacing: download)
        } else {
            removePendingDownload(download)
        }

        finish(id: id, result: .failure(BackgroundDownloadFailure(
            message: error.localizedDescription,
            canResume: resumeData != nil && !resumeData!.isEmpty
        )))
    }

    // MARK: - Private

    private func startTask(for download: PersistedBackgroundDownload) {
        let task: URLSessionDownloadTask
        if let resumeData = try? store.resumeData(for: download), !resumeData.isEmpty {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: download.url)
        }

        task.taskDescription = download.id.uuidString
        activeTasks[download.id] = task
        task.resume()
    }

    private func pendingDownload(id: UUID) -> PersistedBackgroundDownload? {
        try? store.load().first { $0.id == id }
    }

    private func removePendingDownload(_ download: PersistedBackgroundDownload) {
        store.removeResumeData(for: download)
        guard var pending = try? store.load() else {
            return
        }
        pending.removeAll { $0.id == download.id }
        try? store.save(pending)
        activeTasks.removeValue(forKey: download.id)
    }

    private func finish(id: UUID, result: Result<URL, BackgroundDownloadFailure>) {
        activeTasks.removeValue(forKey: id)
        let completion = completions.removeValue(forKey: id)
        completion?(result)
    }

    private func finishBackgroundEvents() {
        let completion = backgroundCompletion
        backgroundCompletion = nil
        completion?()
    }
}

private extension BackgroundDownloadStore {
    func save(replacing download: PersistedBackgroundDownload) throws {
        var pending = try load()
        if let index = pending.firstIndex(where: { $0.id == download.id }) {
            pending[index] = download
        } else {
            pending.append(download)
        }
        try save(pending)
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundDownloadService: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else {
            return
        }
        Task { @MainActor in
            self.completeDownload(id: id, temporaryFile: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error,
              let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else {
            return
        }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        Task { @MainActor in
            self.failDownload(id: id, error: error, resumeData: resumeData)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.finishBackgroundEvents()
        }
    }
}
