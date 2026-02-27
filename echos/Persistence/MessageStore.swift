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
            entity.senderName = message.senderName
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
    
    // MARK: - Load All
    
    func loadMessages() async throws -> [Message] {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        let entities = try viewContext.fetch(fetchRequest)
        
        let messages = entities.map { entity in
            Message(id: entity.id ?? UUID(),
                    text: entity.text ?? "",
                    senderName: entity.senderName,
                    isFromMe: entity.isFromMe,
                    timestamp: entity.timestamp ?? Date(),
                    status: MessageStatus(rawValue: Int(entity.status)) ?? .sent)
        }
        print("[MessageStore] Loaded \(messages.count) messages")
        return messages
    }
    
    // MARK: - Load Filtered
    
    func loadMessages(with peerName: String) async throws -> [Message] {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "isFromMe == YES"),
            NSPredicate(format: "senderName == %@", peerName)
        ])
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        let entities = try viewContext.fetch(fetchRequest)
        
        let messages = entities.map { entity in
            Message(id: entity.id ?? UUID(),
                    text: entity.text ?? "",
                    senderName: entity.senderName,
                    isFromMe: entity.isFromMe,
                    timestamp: entity.timestamp ?? Date(),
                    status: MessageStatus(rawValue: Int(entity.status)) ?? .sent
            )
        }
        print ("[MessageStore] Loaded \(messages.count) messages with '\(peerName)'")
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
    
    func deleteConverstaion(with peerName: String) async throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "senderName == %@", peerName)
        
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try viewContext.execute(batchDelete)
        try viewContext.save()
        
        print("[MessageStore] Deleted conversation with '\(peerName)'")
    }
    
    // MARK: - Clear All
    
    func clearAll() async throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        try viewContext.execute(batchDelete)
        try viewContext.save()
        
        print("[MessageStore] Cleared all messages")
    }
    
    // MARK: Stats
    
    func getMessageStats() async throws -> [String: Int] {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        let all = try viewContext.fetch(fetchRequest)
        
        var stats: [String: Int] = [:]
        stats["total"] = all.count
        stats["fromMe"] = all.filter { $0.isFromMe }.count
        stats["received"] = all.filter { !$0.isFromMe }.count
        
        let senders = all.compactMap { $0.senderName }
        let uniqueSenders = Set(senders)
        
        for sender in uniqueSenders {
            let count = senders.filter { $0 == sender }.count
            stats[sender] = count
        }
        return stats
    }
}
