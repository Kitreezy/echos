import CoreData
import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.tags(.persistence))
final class CoreDataMigrationIntegrationTests {

    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "echos-migration-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func oldStore_openedByNewModel_keepsMessagesAndGainsNewField() throws {
        try createStoreWithFirstModelVersion()

        let controller = PersistenceController(storeDirectory: directory, cloudSync: false)
        let context = controller.container.viewContext

        let request = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "text", ascending: true)]
        let messages = try context.fetch(request)

        #expect(Set(messages.compactMap(\.text)) == ["первое", "второе"])
        #expect(messages.allSatisfy { $0.deliveryReceiptAt == nil })

        let message = messages[0]
        message.deliveryReceiptAt = Date()
        try context.save()

        for store in controller.container.persistentStoreCoordinator.persistentStores {
            try controller.container.persistentStoreCoordinator.remove(store)
        }

        // После повторного открытия значение нового поля тоже должно быть
        // на месте — миграция создала колонку, а не только «пропустила» файл.
        let reopened = PersistenceController(storeDirectory: directory, cloudSync: false)
        let saved = try reopened.container.viewContext.fetch(request)
        #expect(saved.compactMap(\.deliveryReceiptAt).count == 1)
    }

    @Test func currentModel_isSecondVersionWithReceiptField() {
        let message = PersistenceController.managedObjectModel.entitiesByName["MessageEntity"]

        #expect(message?.attributesByName["deliveryReceiptAt"]?.attributeType == .dateAttributeType)
    }

    private func createStoreWithFirstModelVersion() throws {
        let bundle = Bundle(for: PersistenceController.self)
        guard let momd = bundle.url(forResource: "echos", withExtension: "momd") else {
            Issue.record("Не найден echos.momd в тестовом бандле")
            return
        }
        // Первой версией модели считается файл, скомпилированный из
        // echos.xcdatamodel — по нему и создаём «старый» файл.
        let firstVersion = NSManagedObjectModel(contentsOf: momd.appending(path: "echos.mom"))
        let container = NSPersistentContainer(name: "echos-first-version",
                                              managedObjectModel: try #require(firstVersion))
        container.persistentStoreDescriptions = [
            NSPersistentStoreDescription(url: directory.appending(path: "echos.sqlite"))
        ]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let context = container.viewContext
        for text in ["первое", "второе"] {
            let message = NSEntityDescription.insertNewObject(forEntityName: "MessageEntity", into: context)
            message.setValue(UUID(), forKey: "id")
            message.setValue(text, forKey: "text")
            message.setValue(Date(), forKey: "timestamp")
        }
        try context.save()

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
