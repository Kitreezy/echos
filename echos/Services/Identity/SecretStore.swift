//
//  SecretStore.swift
//  echos
//
//  Где лежат секреты.
//
//  Keychain спрятан за протоколом не ради красоты: у него есть состояния,
//  которые в тесте руками не вызвать — заблокированное устройство, дубликат
//  записи, чужие байты под нашим ключом. Настоящая реализация ходит в
//  Security, поддельная в тестах отдаёт что скажут, а политика — что
//  делать в каждом из этих состояний — живёт выше и проверяется без
//  устройства.
//

import Foundation
import Security

protocol SecretStore: Sendable {

    /// `nil` — записи нет. Всё остальное, что мешает прочитать, — ошибка:
    /// отсутствие и недоступность различаются, и путать их нельзя.
    func read(account: String) throws -> Data?

    /// Записать или перезаписать: повторная запись под тем же именем —
    /// это обновление, а не ошибка.
    func write(_ data: Data, account: String) throws

    func delete(account: String) throws
}

enum SecretStoreError: Error, Equatable, LocalizedError {

    /// Устройство ещё не разблокировали после перезагрузки, и до записи
    /// не дотянуться. Пройдёт само.
    case locked

    case failed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .locked:
            return "Keychain недоступен до первой разблокировки"
        case .failed(let status):
            return "Keychain вернул ошибку \(status)"
        }
    }
}

/// Generic password в Keychain этого приложения, под одним service.
struct KeychainSecretStore: SecretStore {

    let service: String

    /// Ключ нужен и в фоне: транспорт переподключается, пока экран
    /// заблокирован, и без этого hello уходить перестанет. А на другое
    /// устройство через резервную копию он уезжать не должен.
    private var accessible: String {
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    }

    func read(account: String) throws -> Data? {
        var query = self.query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw Self.error(for: status)
        }
    }

    func write(_ data: Data, account: String) throws {
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = accessible

        let status = SecItemAdd(item as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Запись есть, а чтение её не показало — так бывает, когда она
            // создана с другой доступностью или её не видно из-за блокировки.
            // Обновить можно, и это лучше, чем уронить всё из-за дубликата.
            try update(data, account: account)
        default:
            throw Self.error(for: status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.error(for: status)
        }
    }

    // MARK: - Private

    private func update(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]
        let status = SecItemUpdate(query(account: account) as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw Self.error(for: status)
        }
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func error(for status: OSStatus) -> SecretStoreError {
        status == errSecInteractionNotAllowed ? .locked : .failed(status)
    }
}
