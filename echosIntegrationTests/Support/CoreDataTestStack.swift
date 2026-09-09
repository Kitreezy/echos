//
//  CoreDataTestStack.swift
//  echosIntegrationTests
//
//  Изолированный Core Data стек на каждый тест.
//
//  Ключевая мысль: интеграционный тест работает с НАСТОЯЩИМ SQLite-стеком
//  (со всей его семантикой: предикаты, sort descriptors, batch delete),
//  но пишет в /dev/null — база живёт только в памяти процесса и умирает
//  вместе с тестом. Никакого общего состояния между тестами,
//  никакого `PersistenceController.shared`.
//

import CoreData
@testable import echos

enum CoreDataTestStack {
    
    /// Свежий пустой стек. Вызывать в `setUp`, а не в `class` scope.
    @MainActor
    static func makeInMemory() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
    
    /// Хелпер: сообщение с фиксированным временем, чтобы тесты
    /// не зависели от порядка выполнения и скорости машины.
    static func message(_ text: String,
                        from senderName: String? = nil,
                        isFromMe: Bool = false,
                        daysAgo: Int = 0,
                        status: MessageStatus = .sent) -> Message {
        let timestamp = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return Message(text: text,
                       senderName: senderName,
                       isFromMe: isFromMe,
                       timestamp: timestamp,
                       status: status)
    }
}
