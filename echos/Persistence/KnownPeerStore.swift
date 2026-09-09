//
//  KnownPeerStore.swift
//  echos
//
//  Кого мы уже знаем.
//
//  Доверие с первого разговора: адрес попадает сюда, когда вы этому человеку
//  написали. Не когда увидели рядом — иначе знакомыми стали бы все, кто
//  когда-либо оказался в списке, и отличать тёзку было бы не от кого.
//

import CoreData
import Foundation

@MainActor
final class KnownPeerStore {

    private let container: NSPersistentContainer

    private var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
    }

    // MARK: - Read

    func loadKnownPeers() async throws -> [KnownPeer] {
        let request = NSFetchRequest<KnownPeerEntity>(entityName: "KnownPeerEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]

        return try viewContext.fetch(request).compactMap { entity in
            guard let address = entity.address, let name = entity.name else {
                return nil
            }

            return KnownPeer(address: address,
                             name: name,
                             firstSeen: entity.firstSeen ?? Date(),
                             lastSeen: entity.lastSeen ?? Date())
        }
    }

    // MARK: - Write

    func remember(address: String, name: String) async throws {
        let request = NSFetchRequest<KnownPeerEntity>(entityName: "KnownPeerEntity")
        request.predicate = NSPredicate(format: "address == %@", address)
        request.fetchLimit = 1

        let now = Date()

        if let existing = try viewContext.fetch(request).first {
            existing.name = name
            existing.lastSeen = now
        } else {
            let entity = KnownPeerEntity(context: viewContext)
            entity.address = address
            entity.name = name
            entity.firstSeen = now
            entity.lastSeen = now
        }

        try viewContext.save()
    }

    func forgetAll() async throws {
        let request: NSFetchRequest<NSFetchRequestResult> =
            NSFetchRequest(entityName: "KnownPeerEntity")

        let batchDelete = NSBatchDeleteRequest(fetchRequest: request)
        batchDelete.resultType = .resultTypeObjectIDs

        let result = try viewContext.execute(batchDelete) as? NSBatchDeleteResult

        // Пакетное удаление идёт мимо контекста, и без слияния он остался бы
        // с объектами, которых в базе уже нет.
        if let ids = result?.result as? [NSManagedObjectID] {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                into: [viewContext]
            )
        }

        try viewContext.save()
    }
}
