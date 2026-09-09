//
//  DeviceIdentity.swift
//  echos
//
//  Кто мы такие с точки зрения релея.
//
//  Аккаунтов в приложении нет, и заводить их ради одного релея не хочется.
//  Но личность и не обязана приходить снаружи: пары ключей, созданной при
//  первом запуске, достаточно. Имя — это ярлык, который человек выбрал сам,
//  а доказательством права на имя служит подпись.
//
//  Ключ лежит в Keychain, а не в UserDefaults: переустановку он переживать
//  не обязан, а вот резервную копию чужого устройства — не должен.
//

import CryptoKit
import Foundation
import Security

struct DeviceIdentity: Sendable {

    /// Открытая часть ключа. Уходит релею при каждом подключении: проверить
    /// подпись по отпечатку нельзя, а хранить ключи между запусками релею
    /// негде.
    let publicKey: Data

    /// Короткое представление ключа — то же, что считает релей.
    ///
    /// Само по себе ничего не защищает, но по нему видно, что «Bob» сегодня
    /// и «Bob» вчера — один человек.
    var fingerprint: String {
        let digest = SHA256.hash(data: publicKey)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private let privateKey: Curve25519.Signing.PrivateKey

    /// Личность вокруг готового ключа. Обычный путь — `current()`, а здесь
    /// заходят тесты, которым Keychain не нужен.
    init(privateKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey()) {
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey.rawRepresentation
    }

    /// Подписать вызов сервера.
    func signature(for challenge: Data) throws -> Data {
        try privateKey.signature(for: challenge)
    }

    // MARK: - Access

    /// Личность этого устройства: из Keychain, а при первом обращении —
    /// созданная и сразу туда записанная.
    static func current() throws -> DeviceIdentity {
        try store.identity()
    }

    private static let store = IdentityStore()
}

/// Хранилище ключа.
///
/// Отдельный тип нужен из-за кэша: обращаться в Keychain на каждое
/// переподключение незачем, а кэш переживает потоки, поэтому под замком.
private final class IdentityStore: @unchecked Sendable {

    private let lock = NSLock()
    private var cached: DeviceIdentity?

    private let service = "com.echos.identity"
    private let account = "device-signing-key"

    func identity() throws -> DeviceIdentity {
        lock.lock()
        defer { lock.unlock() }

        if let cached {
            return cached
        }

        let identity = try loadOrCreate()
        cached = identity
        return identity
    }

    private func loadOrCreate() throws -> DeviceIdentity {
        if let raw = try read() {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
            return DeviceIdentity(privateKey: key)
        }

        let key = Curve25519.Signing.PrivateKey()
        try write(key.rawRepresentation)
        return DeviceIdentity(privateKey: key)
    }

    // MARK: - Keychain

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func read() throws -> Data? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:    return result as? Data
        case errSecItemNotFound: return nil
        default:               throw DeviceIdentityError.keychainFailed(status)
        }
    }

    private func write(_ data: Data) throws {
        var item = query
        item[kSecValueData as String] = data

        // Ключ нужен и в фоне: транспорт переподключается, пока экран
        // заблокирован, и без этого hello уходить перестанет.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainFailed(status)
        }
    }
}

enum DeviceIdentityError: Error, LocalizedError, Equatable {
    case keychainFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainFailed(let status):
            return "Keychain вернул ошибку \(status)"
        }
    }
}
