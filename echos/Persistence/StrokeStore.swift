//
//  StrokeStore.swift
//  echos
//

import CoreData
import Foundation

/// Хранилище росчерков.
///
/// Точки лежат одним двоичным полем, а не отдельными сущностями: у одного
/// росчерка их сотни, и заводить на каждую строку в базе — верный способ
/// получить тормоза на пустом месте. Читаются они всегда целиком.
@MainActor
final class StrokeStore {

    private let container: NSPersistentContainer

    private var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
    }

    // MARK: - Read

    func loadStrokes(wallOwner: String?) async throws -> [Stroke] {
        let request = NSFetchRequest<StrokeEntity>(entityName: "StrokeEntity")
        request.predicate = wallOwner.map { NSPredicate(format: "wallOwner == %@", $0) }
            ?? NSPredicate(format: "wallOwner == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        return try viewContext.fetch(request).compactMap(Stroke.init)
    }

    // MARK: - Write

    func saveStroke(_ stroke: Stroke, wallOwner: String?) async throws {
        // Тот же росчерк может прийти повторно после реконнекта — проверяем.
        let existing = NSFetchRequest<StrokeEntity>(entityName: "StrokeEntity")
        existing.predicate = NSPredicate(format: "id == %@", stroke.id as CVarArg)
        existing.fetchLimit = 1

        guard try viewContext.fetch(existing).isEmpty else {
            return
        }

        let entity = StrokeEntity(context: viewContext)
        entity.id = stroke.id
        entity.author = stroke.author
        entity.createdAt = stroke.createdAt
        entity.wallOwner = wallOwner
        entity.points = try JSONEncoder().encode(stroke.points)

        try viewContext.save()
    }

    func clearWall(_ wallOwner: String?) async throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "StrokeEntity")
        request.predicate = wallOwner.map { NSPredicate(format: "wallOwner == %@", $0) }
            ?? NSPredicate(format: "wallOwner == nil")

        let delete = NSBatchDeleteRequest(fetchRequest: request)
        delete.resultType = .resultTypeObjectIDs

        let result = try viewContext.execute(delete) as? NSBatchDeleteResult

        // Пакетное удаление идёт мимо контекста — иначе он продолжит отдавать
        // уже удалённые объекты.
        if let ids = result?.result as? [NSManagedObjectID] {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                into: [viewContext]
            )
        }
    }
}

private extension Stroke {

    init?(_ entity: StrokeEntity) {
        guard let id = entity.id,
              let author = entity.author,
              let data = entity.points,
              let points = try? JSONDecoder().decode([Stroke.Point].self, from: data) else {
            return nil
        }

        self.init(id: id,
                  author: author,
                  points: points,
                  createdAt: entity.createdAt ?? Date())
    }
}
