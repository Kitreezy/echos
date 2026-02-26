//
//  MessageStore.swift
//  echos
//
//  Created by Artem Rodionov on 26.02.2026.
//

import CoreData

@MainActor
final class MessageStore {
    
    private let viewContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }
    
    // MARK: - Save
    
    func saveMessage(_ message: Message) async throws {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", message.id as CVarArg)
        
        let existing = try viewContext.fetch(fetchRequest)
        
        if existing.isEmpty {
            let entity = MessageEntity(context: viewContext)
            entity.id = message.id
            entity.text = message.text
            entity.isFromMe = message.isFromMe
            entity.timestamp = message.timestamp
            entity.status = Int16(message.status.rawValue)
            
            try viewContext.save()
            print("[MessageStore] Saved: \(message.text)")
        } else {
            if let entity = existing.first {
                entity.status = Int16(message.status.rawValue)
                try viewContext.save()
                print("[MessageStore] Update status for: \(message.id)")
            }
        }
    }
    
    // MARK: - Load
    
    func loadMessages() async throws -> [Message] {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        let entities = try viewContext.fetch(fetchRequest)
        
        let messages = entities.map { entity in
            Message(id: entity.id ?? UUID(),
                    text: entity.text ?? "",
                    isFromMe: entity.isFromMe,
                    timestamp: entity.timestamp ?? Date(),
                    status: MessageStatus(rawValue: Int(entity.status)) ?? .sent)
        }
        print("[MessageStore] Loaded \(messages.count) messages")
        return messages
    }
    
    // MARK: - DeleteOld
    
    func deleteOldMessages(olderThan days: Int) async throws {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return
        }
        
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as CVarArg)
        
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try viewContext.execute(batchDelete)
        try viewContext.save()
        
        print("[MessageStore] Deleted messages older than \(days) days")
    }
    
    // MARK: - Clear All
    
    func clearAll() async throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        try viewContext.execute(batchDelete)
        try viewContext.save()
        
        print("[MessageStore] Cleared all messages")
    }
}
