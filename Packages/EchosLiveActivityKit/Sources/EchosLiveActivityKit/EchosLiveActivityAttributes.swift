//
//  EchosLiveActivityAttributes.swift
//  EchosLiveActivityKit
//
//  Общая модель Live Activity между приложением и расширением виджета.
//  Модуль должен быть один: ActivityKit сопоставляет активность по типу
//  атрибутов, а две одинаковые декларации в разных модулях — разные типы.
//

import ActivityKit
import Foundation

public struct EchosLiveActivityAttributes: ActivityAttributes {

    /// То, что меняется локально: состояние связи и отправки. Пушей нет —
    /// приложение само обновляет это состояние через `Activity.update`.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Имя — состояние, а не атрибут: человек может переименоваться, и
        /// активность должна обновиться без пересоздания.
        public var peerName: String
        public var connectionText: String
        public var isEncrypted: Bool
        public var sendingCount: Int
        public var failedCount: Int

        public init(peerName: String,
                    connectionText: String,
                    isEncrypted: Bool,
                    sendingCount: Int,
                    failedCount: Int) {
            self.peerName = peerName
            self.connectionText = connectionText
            self.isEncrypted = isEncrypted
            self.sendingCount = sendingCount
            self.failedCount = failedCount
        }
    }

    /// Адрес фиксируется при старте активности: он стабилен и однозначно
    /// определяет собеседника. На экране показываем имя из состояния.
    public var peerAddress: String

    public init(peerAddress: String) {
        self.peerAddress = peerAddress
    }
}
