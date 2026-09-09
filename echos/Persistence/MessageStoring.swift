//
//  MessageStoring.swift
//  echos
//
//  Абстракция над хранилищем сообщений.
//
//  Зачем: даёт возможность подменить Core Data в тестах ViewModel
//  (in-memory стор или spy), не таща за собой весь стек.
//

import Foundation

@MainActor
protocol MessageStoring: AnyObject {
    
    func saveMessage(_ message: Message) async throws
    
    func loadMessages() async throws -> [Message]
    func loadMessages(with address: String) async throws -> [Message]
    
    func deleteOldMessages(olderThan days: Int) async throws
    func deleteConverstaion(with address: String) async throws
    func clearAll() async throws
    
    func getMessageStats() async throws -> [String: Int]
}

extension MessageStore: MessageStoring {}
