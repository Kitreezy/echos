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
import Foundation
import Testing
@testable import echos

@MainActor
@Suite(.tags(.persistence))
final class PersistenceSplitIntegrationTests {

    /// Своя папка на каждый тест — хранилища разных тестов не встречаются.
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "echos-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Модель

    @Test func model_splitsEntitiesBetweenConfigurations() {
        let model = PersistenceController.managedObjectModel

        let cloud = model.entities(forConfigurationName: "Cloud")?.map(\.name) ?? []
        let local = model.entities(forConfigurationName: "Local")?.map(\.name) ?? []

        #expect(Set(cloud) == ["KnownPeerEntity", "StrokeEntity"], "В облако едут знакомые и стена — то, что не зависит от ключа устройства")
        #expect(local == ["MessageEntity"], "Переписка адресована ключу этого устройства и остаётся на нём")
    }

    @Test func model_meetsCloudKitConstraints() {
        // CloudKit не терпит обязательных атрибутов без default и unique
        // constraints; связей у модели нет, а будь они — понадобились бы
        // обратные. Нарушение здесь ловится на симуляторе, а не при
        // первом запуске с iCloud.
        for entity in PersistenceController.managedObjectModel.entities(forConfigurationName: "Cloud") ?? [] {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") с unique constraint в облако не поедет")
            for (name, attribute) in entity.attributesByName {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name ?? "?").\(name) обязателен и без default")
            }
            for (name, relationship) in entity.relationshipsByName {
                #expect(relationship.inverseRelationship != nil, "\(entity.name ?? "?").\(name) без обратной связи")
            }
        }
    }

    // MARK: - Хранилища

    @Test func entitiesLandInTheirOwnStore() throws {
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

        #expect(message.objectID.persistentStore?.configurationName == "Local")
        #expect(peer.objectID.persistentStore?.configurationName == "Cloud")
        #expect(stroke.objectID.persistentStore?.configurationName == "Cloud")

        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "echos.sqlite").path()))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "echos-cloud.sqlite").path()))
    }

    @Test func withoutFlag_noStoreTalksToCloudKit() {
        let controller = PersistenceController(storeDirectory: directory, cloudSync: false)

        for description in controller.container.persistentStoreDescriptions {
            #expect(description.cloudKitContainerOptions == nil, "\(description.configuration ?? "?") без entitlement подключаться к iCloud не должно")
        }
    }

    @Test func withFlag_onlyCloudStoreTalksToCloudKit() {
        // Загрузка с опциями CloudKit без entitlement на симуляторе проходит:
        // контейнер ругается в лог и работает как локальный. Проверяем,
        // что опции навешаны ровно на одно хранилище и с нужным контейнером.
        let controller = PersistenceController(storeDirectory: directory, cloudSync: true)
        let descriptions = controller.container.persistentStoreDescriptions

        let withCloud = descriptions.filter { $0.cloudKitContainerOptions != nil }
        #expect(withCloud.map(\.configuration) == ["Cloud"])
        #expect(withCloud.first?.cloudKitContainerOptions?.containerIdentifier == PersistenceController.cloudContainerIdentifier)
    }

    @Test func inMemory_stillLoadsBothStores() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let peer = KnownPeerEntity(context: context)
        peer.address = "a"
        peer.name = "b"
        let message = MessageEntity(context: context)
        message.text = "c"

        try context.save()

        #expect(controller.container.persistentStoreCoordinator.persistentStores.count == 2)
        #expect(peer.objectID.persistentStore?.configurationName == "Cloud")
        #expect(message.objectID.persistentStore?.configurationName == "Local")
    }

    // MARK: - Старый файл

    @Test func legacySingleStore_isSplitOnFirstLaunch() throws {
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

        #expect(Set(messages.compactMap(\.text)) == ["первое", "второе"], "Сообщения остаются на месте — файл теперь и есть локальное хранилище")
        #expect(peers.map(\.name) == ["Борис"], "Знакомые переехали в облачное хранилище")
        #expect(peers.first?.objectID.persistentStore?.configurationName == "Cloud")
        #expect(strokes.count == 3, "Стена переехала целиком")
        #expect(strokes.first?.objectID.persistentStore?.configurationName == "Cloud")
    }

    @Test func legacySplit_happensOnce() throws {
        try makeLegacyStore(messages: [], peers: ["a": "Анна"], strokes: 0)

        _ = PersistenceController(storeDirectory: directory, cloudSync: false)
        let second = PersistenceController(storeDirectory: directory, cloudSync: false)

        let peers = try second.container.viewContext.fetch(NSFetchRequest<KnownPeerEntity>(entityName: "KnownPeerEntity"))
        #expect(peers.count == 1, "Повторный запуск не должен переносить знакомых второй раз")
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
