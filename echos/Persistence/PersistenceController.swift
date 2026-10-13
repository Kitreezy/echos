//
//  PersistenceController.swift
//  echos
//
//  Created by Artem Rodionov on 26.02.2026.
//

import CoreData

/// Стек Core Data живёт на главном акторе: наружу отдаётся только
/// `container.viewContext` (main-queue контекст), поэтому изоляция
/// на `@MainActor` — самое честное описание того, как класс уже используется.
/// Это же снимает предупреждения strict concurrency про глобальное
/// изменяемое состояние в `shared` / `preview` / `managedObjectModel`.
///
/// Хранилищ два, и делит их не техника, а смысл. Личность в echos — ключ
/// устройства: переписка адресована ему и на другом телефоне была бы чужой.
/// Поэтому сообщения лежат в локальном хранилище и никуда не уезжают.
/// Знакомые и стена от ключа не зависят — они в облачном, и при включённой
/// синхронизации ходят через iCloud на все устройства владельца.
@MainActor
final class PersistenceController {
    
    static let shared = PersistenceController()
    
    let container: NSPersistentCloudKitContainer

    /// Контейнер CloudKit. Появляется в App Store Connect сам, когда в
    /// проект добавлен entitlement iCloud с этим идентификатором.
    static let cloudContainerIdentifier = "iCloud.com.kitreezy.echos"

    /// Синхронизация включается ключом `EchosCloudSync` в Info.plist, а не
    /// просто наличием кода: без entitlement iCloud контейнер не загрузится,
    /// а entitlement выдаётся только платному аккаунту разработчика.
    /// Пока его нет, оба хранилища — обычные локальные SQLite.
    static var isCloudSyncEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "EchosCloudSync") as? Bool ?? false
    }

    /// Прилетело из iCloud: другое устройство что-то записало. `viewContext`
    /// изменения уже подхватил, но списки, собранные вручную через fetch,
    /// об этом не знают — им нужно перечитать.
    static let remoteChangesNotification = Notification.Name("PersistenceController.remoteChanges")

    private var remoteChangesTask: Task<Void, Never>?
    
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        
        let viewContext = controller.container.viewContext
        
        for i in 0..<10 {
            let message = MessageEntity(context: viewContext)
            message.id = UUID()
            message.text = "Test message \(i)"
            message.isFromMe = i % 2 == 0
            message.timestamp = Date()
            message.status = 1
        }
        
        try? viewContext.save()
        return controller
    }()
    
    /// Модель грузится из бандла ОДИН раз на процесс.
    ///
    /// `NSPersistentContainer(name:)` при каждом вызове создаёт новый
    /// `NSManagedObjectModel`. В приложении контроллер один, и это незаметно,
    /// но в тестах стеков много — и Core Data начинает ругаться
    /// «Failed to find a unique match for an NSEntityDescription».
    static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: PersistenceController.self).url(forResource: "echos", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("CoreData: не найдена модель echos.momd")
        }
        return model
    }()

    // MARK: - Init
    
    convenience init(inMemory: Bool = false) {
        if inMemory {
            self.init(storeDirectory: nil, cloudSync: false)
        } else {
            self.init(storeDirectory: NSPersistentContainer.defaultDirectoryURL(),
                      cloudSync: Self.isCloudSyncEnabled)
        }
    }

    /// - Parameters:
    ///   - storeDirectory: где лежат файлы. `nil` — временный стек: настоящий
    ///     SQLite (с batch-запросами, которых хранилище в памяти не умеет)
    ///     в папке под `tmp`. Сам контроллер её не удаляет: контейнер
    ///     нередко живёт дольше него, а `tmp` система чистит сама.
    ///   - cloudSync: вешать ли на облачное хранилище CloudKit. Имеет смысл
    ///     только с entitlement; в тестах всегда `false`.
    init(storeDirectory: URL?, cloudSync: Bool) {
        let directory = storeDirectory ?? FileManager.default.temporaryDirectory
            .appending(path: "echos-ephemeral-\(UUID().uuidString)", directoryHint: .isDirectory)
        if storeDirectory == nil {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // `NSPersistentCloudKitContainer` без `cloudKitContainerOptions`
        // ведёт себя ровно как `NSPersistentContainer`, поэтому класс один
        // на оба случая — меняется только описание облачного хранилища.
        container = NSPersistentCloudKitContainer(name: "echos",
                                                  managedObjectModel: Self.managedObjectModel)

        let local = Self.storeDescription(configuration: "Local",
                                          file: "echos.sqlite",
                                          in: directory)
        let cloud = Self.storeDescription(configuration: "Cloud",
                                          file: "echos-cloud.sqlite",
                                          in: directory)
        if cloudSync {
            cloud.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudContainerIdentifier
            )
        }
        container.persistentStoreDescriptions = [local, cloud]

        // До этой версии всё лежало в одном файле echos.sqlite. Проверять
        // надо до загрузки: она создаст облачный файл, и признак пропадёт.
        let needsSplit = Self.legacyStoreNeedsSplit(in: directory)
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("CoreData failed to load \(description.configuration ?? "?"): \(error.localizedDescription)")
            }
        }
        
        // Правка в памяти важнее того, что успело прийти из облака:
        // иначе набранное здесь имя знакомого перетёрлось бы импортом
        // с другого устройства, который случился между чтением и записью.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        if needsSplit {
            moveLegacyRows(from: directory.appending(path: "echos.sqlite"))
        }

        observeRemoteChanges()
    }

    // MARK: - Store descriptions

    /// Оба хранилища с историей изменений: облачному она обязательна —
    /// по ней CloudKit понимает, что отправлять, — а локальному не мешает
    /// и пригодится, когда сообщения тоже поедут куда-нибудь.
    private static func storeDescription(configuration: String,
                                         file: String,
                                         in directory: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: directory.appending(path: file))
        description.configuration = configuration
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    // MARK: - Legacy store

    private static func legacyStoreNeedsSplit(in directory: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appending(path: "echos.sqlite").path())
            && !fm.fileExists(atPath: directory.appending(path: "echos-cloud.sqlite").path())
    }

    /// Старый файл остаётся локальным хранилищем — сообщения из него никуда
    /// не переезжают. А знакомых и стену конфигурация `Local` больше не
    /// видит, поэтому их надо перенести в облачное руками: открыть тот же
    /// файл полной моделью, только для чтения, и переписать строки.
    /// Старые копии остаются в файле мёртвым грузом — Core Data их не
    /// покажет, а удалять из хранилища, которое уже открыто как `Local`,
    /// дороже, чем они весят.
    private func moveLegacyRows(from url: URL) {
        let description = NSPersistentStoreDescription(url: url)
        description.isReadOnly = true

        let legacy = NSPersistentContainer(name: "echos-legacy",
                                           managedObjectModel: Self.managedObjectModel)
        legacy.persistentStoreDescriptions = [description]

        var loadError: Error?
        legacy.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            print("[Persistence] Старое хранилище не открылось, знакомые и стена не перенесены: \(loadError)")
            return
        }

        let source = legacy.viewContext
        let target = container.viewContext

        do {
            for entity in ["KnownPeerEntity", "StrokeEntity"] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                for object in try source.fetch(request) {
                    let copy = NSEntityDescription.insertNewObject(forEntityName: entity, into: target)
                    for key in object.entity.attributesByName.keys {
                        copy.setValue(object.value(forKey: key), forKey: key)
                    }
                }
            }
            if target.hasChanges {
                try target.save()
            }
        } catch {
            print("[Persistence] Перенос знакомых и стены не удался: \(error)")
        }
    }

    // MARK: - Remote changes

    /// Уведомление приходит с фоновой очереди и для каждого хранилища
    /// отдельно; наружу оно уходит одно и на главном акторе.
    private func observeRemoteChanges() {
        let coordinator = container.persistentStoreCoordinator
        remoteChangesTask = Task { @MainActor in
            let changes = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange,
                                                                   object: coordinator)
            for await _ in changes {
                NotificationCenter.default.post(name: Self.remoteChangesNotification, object: nil)
            }
        }
    }

    deinit {
        remoteChangesTask?.cancel()
    }
}
