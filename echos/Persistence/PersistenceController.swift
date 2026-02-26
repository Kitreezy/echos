//
//  PersistenceController.swift
//  echos
//
//  Created by Artem Rodionov on 26.02.2026.
//

import CoreData

final class PersistenceController {
    
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    static var preview: PersistenceController = {
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
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "echos")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(filePath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("CoreData failed to load: \(error.localizedDescription)")
            }
            print("Core Data loaded successfully")
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
    }
}
