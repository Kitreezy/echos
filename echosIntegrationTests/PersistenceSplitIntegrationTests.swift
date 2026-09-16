//
//  PersistenceSplitIntegrationTests.swift
//  echosIntegrationTests
//
//  Два хранилища вместо одного: сообщения остаются на устройстве, знакомые
//  и стена уезжают в облако. Проверяется всё, что можно проверить без
//  entitlement iCloud — куда ложится каждая сущность, что без флага CloudKit
//  не подключается и что старый единый файл переживает разделение.
//

import CoreData
import XCTest
@testable import echos

@MainActor
final class PersistenceSplitIntegrationTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "echos-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Модель

    func test_model_splitsEntitiesBetweenConfigurations() {
        let model = PersistenceController.managedObjectModel

        let cloud = model.entities(forConfigurationName: "Cloud")?.map(\.name) ?? []
        let local = model.entities(forConfigurationName: "Local")?.map(\.name) ?? []

        XCTAssertEqual(Set(cloud), ["KnownPeerEntity", "StrokeEntity"],
                       "В облако едут знакомые и стена — то, что не зависит от ключа устройства")
        XCTAssertEqual(local, ["MessageEntity"],
                       "Переписка адресована ключу этого устройства и остаётся на нём")
    }

    func test_model_meetsCloudKitConstraints() {
        // CloudKit не терпит обязательных атрибутов без default и unique
        // constraints; связей у модели нет, а будь они — понадобились бы
        // обратные. Нарушение здесь ловится на симуляторе, а не при
        // первом запуске с iCloud.
        for entity in PersistenceController.managedObjectModel.entities(forConfigurationName: "Cloud") ?? [] {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") с unique constraint в облако не поедет")
            for (name, attribute) in entity.attributesByName {
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil,
                              "\(entity.name ?? "?").\(name) обязателен и без default")
            }
            for (name, relationship) in entity.relationshipsByName {
                XCTAssertNotNil(relationship.inverseRelationship, "\(entity.name ?? "?").\(name) без обратной связи")
            }
        }
    }

    // MARK: - Хранилища

    func test_entitiesLandInTheirOwnStore() throws {
        let controller = PersistenceController(storeDirectory: directory, cloudSync: false)
        let context = controller.container.viewContext

        let message = MessageEntity(context: context)
        message.id = UUID()
        message.text = "привет"

        let peer = KnownPeerEntity(context: context)
        peer.address = "9f86d081884c7d65"
        peer.name = "Борис"

        let stroke = StrokeEntity(context: context)
        stroke.id = UUID()

        try context.save()

        XCTAssertEqual(message.objectID.persistentStore?.configurationName, "Local")
        XCTAssertEqual(peer.objectID.persistentStore?.configurationName, "Cloud")
        XCTAssertEqual(stroke.objectID.persistentStore?.configurationName, "Cloud")

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "echos.sqlite").path()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "echos-cloud.sqlite").path()))
    }

    func test_withoutFlag_noStoreTalksToCloudKit() {
        let controller = PersistenceController(storeDirectory: directory, cloudSync: false)

        for description in controller.container.persistentStoreDescriptions {
            XCTAssertNil(description.cloudKitContainerOptions,
                         "\(description.configuration ?? "?") без entitlement подключаться к iCloud не должно")
        }
    }

    func test_withFlag_onlyCloudStoreTalksToCloudKit() {
        // Загрузка с опциями CloudKit без entitlement на симуляторе проходит:
        // контейнер ругается в лог и работает как локальный. Проверяем,
        // что опции навешаны ровно на одно хранилище и с нужным контейнером.
        let controller = PersistenceController(storeDirectory: directory, cloudSync: true)
        let descriptions = controller.container.persistentStoreDescriptions

        let withCloud = descriptions.filter { $0.cloudKitContainerOptions != nil }
        XCTAssertEqual(withCloud.map(\.configuration), ["Cloud"])
        XCTAssertEqual(withCloud.first?.cloudKitContainerOptions?.containerIdentifier,
                       PersistenceController.cloudContainerIdentifier)
    }

    func test_inMemory_stillLoadsBothStores() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let peer = KnownPeerEntity(context: context)
        peer.address = "a"
        peer.name = "b"
        let message = MessageEntity(context: context)
        message.text = "c"

        try context.save()

        XCTAssertEqual(controller.container.persistentStoreCoordinator.persistentStores.count, 2)
        XCTAssertEqual(peer.objectID.persistentStore?.configurationName, "Cloud")
        XCTAssertEqual(message.objectID.persistentStore?.configurationName, "Local")
    }

    // MARK: - Старый файл

    func test_legacySingleStore_isSplitOnFirstLaunch() throws {
        // До разделения всё лежало в одном echos.sqlite. Собираем такой файл
        // полной моделью, потом открываем новым контроллером.
        try makeLegacyStore(messages: ["первое", "второе"],
                            peers: ["9f86d081884c7d65": "Борис"],
                            strokes: 3)

        let controller = PersistenceController(storeDirectory: directory, cloudSync: false)
        let context = controller.container.viewContext

        let messages = try context.fetch(NSFetchRequest<MessageEntity>(entityName: "MessageEntity"))
        let peers = try context.fetch(NSFetchRequest<KnownPeerEntity>(entityName: "KnownPeerEntity"))
        let strokes = try context.fetch(NSFetchRequest<StrokeEntity>(entityName: "StrokeEntity"))

        XCTAssertEqual(Set(messages.compactMap(\.text)), ["первое", "второе"],
                       "Сообщения остаются на месте — файл теперь и есть локальное хранилище")
        XCTAssertEqual(peers.map(\.name), ["Борис"], "Знакомые переехали в облачное хранилище")
        XCTAssertEqual(peers.first?.objectID.persistentStore?.configurationName, "Cloud")
        XCTAssertEqual(strokes.count, 3, "Стена переехала целиком")
        XCTAssertEqual(strokes.first?.objectID.persistentStore?.configurationName, "Cloud")
    }

    func test_legacySplit_happensOnce() throws {
        try makeLegacyStore(messages: [], peers: ["a": "Анна"], strokes: 0)

        _ = PersistenceController(storeDirectory: directory, cloudSync: false)
        let second = PersistenceController(storeDirectory: directory, cloudSync: false)

        let peers = try second.container.viewContext.fetch(NSFetchRequest<KnownPeerEntity>(entityName: "KnownPeerEntity"))
        XCTAssertEqual(peers.count, 1, "Повторный запуск не должен переносить знакомых второй раз")
    }

    // MARK: - Support

    private func makeLegacyStore(messages: [String], peers: [String: String], strokes: Int) throws {
        let legacy = NSPersistentContainer(name: "echos",
                                           managedObjectModel: PersistenceController.managedObjectModel)
        legacy.persistentStoreDescriptions = [
            NSPersistentStoreDescription(url: directory.appending(path: "echos.sqlite"))
        ]
        var loadError: Error?
        legacy.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let context = legacy.viewContext
        for text in messages {
            let message = MessageEntity(context: context)
            message.id = UUID()
            message.text = text
            message.timestamp = Date()
        }
        for (address, name) in peers {
            let peer = KnownPeerEntity(context: context)
            peer.address = address
            peer.name = name
            peer.firstSeen = Date()
            peer.lastSeen = Date()
        }
        for _ in 0..<strokes {
            let stroke = StrokeEntity(context: context)
            stroke.id = UUID()
            stroke.createdAt = Date()
        }
        try context.save()

        // Закрыть файл, иначе новый стек откроет его поверх незакрытого.
        for store in legacy.persistentStoreCoordinator.persistentStores {
            try legacy.persistentStoreCoordinator.remove(store)
        }
    }
}
