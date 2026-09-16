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
//  Ключей два. Подписывающий (Ed25519) — это и есть личность: его отпечаток
//  служит адресом, им подтверждается право на имя. Ключ соглашения (X25519)
//  нужен для переписки: из него и чужого выводится общий секрет, которым
//  шифруются сообщения. Подписью первого второй привязан к личности — иначе
//  релей мог бы подсунуть собеседнику свой.
//
//  Ключи лежат в Keychain, а не в UserDefaults: переустановку они переживать
//  не обязаны, а вот резервную копию чужого устройства — не должны.
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
        Self.fingerprint(of: publicKey)
    }

    /// Отпечаток чужого ключа — тот же, что считает релей.
    static func fingerprint(of publicKey: Data) -> String {
        SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Открытая часть ключа соглашения. Вместе с `publicKey` и подписью
    /// под ней образует `KeyBundle` — то, чем представляемся собеседникам.
    let agreementKey: Data

    private let privateKey: Curve25519.Signing.PrivateKey
    private let agreementPrivateKey: Curve25519.KeyAgreement.PrivateKey

    /// Личность вокруг готовых ключей. Обычный путь — `current()`, а здесь
    /// заходят тесты, которым Keychain не нужен.
    init(privateKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey(),
         agreementKey: Curve25519.KeyAgreement.PrivateKey = Curve25519.KeyAgreement.PrivateKey()) {
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey.rawRepresentation
        self.agreementPrivateKey = agreementKey
        self.agreementKey = agreementKey.publicKey.rawRepresentation
    }

    /// Подписать вызов сервера.
    func signature(for challenge: Data) throws -> Data {
        try privateKey.signature(for: challenge)
    }

    /// Чем представляемся в этой сессии: открытые ключи и доказательства,
    /// что ключи соглашения принадлежат этой же личности.
    ///
    /// Подписывается не голый ключ, а строка с префиксом: вызовы, которые мы
    /// подписываем для кого угодно, — тоже 32 случайных байта, и без префикса
    /// чужой «вызов» мог бы оказаться чужим ключом соглашения с нашей
    /// подписью под ним.
    func keyBundle(session: SessionKey) throws -> KeyBundle {
        KeyBundle(publicKey: publicKey,
                  agreementKey: agreementKey,
                  agreementProof: try privateKey.signature(for: KeyBundle.bindingMessage(for: agreementKey)),
                  sessionKey: session.publicKey,
                  sessionProof: session.proof)
    }

    /// Статическая часть общего секрета — сырая, до вывода ключа шифрования.
    func sharedSecret(with peer: PeerIdentity) throws -> SharedSecret {
        let theirKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer.agreementKey)
        return try agreementPrivateKey.sharedSecretFromKeyAgreement(with: theirKey)
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
    private let signingAccount = "device-signing-key"
    private let agreementAccount = "device-agreement-key"

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

    /// Ключи читаются и создаются по отдельности: у того, кто обновился,
    /// подписывающий ключ уже есть, и адрес менять из-за появления второго
    /// нельзя — к адресу привязаны переписки и знакомые.
    private func loadOrCreate() throws -> DeviceIdentity {
        let signing: Curve25519.Signing.PrivateKey
        if let raw = try read(account: signingAccount) {
            signing = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } else {
            signing = Curve25519.Signing.PrivateKey()
            try write(signing.rawRepresentation, account: signingAccount)
        }

        let agreement: Curve25519.KeyAgreement.PrivateKey
        if let raw = try read(account: agreementAccount) {
            agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
        } else {
            agreement = Curve25519.KeyAgreement.PrivateKey()
            try write(agreement.rawRepresentation, account: agreementAccount)
        }

        return DeviceIdentity(privateKey: signing, agreementKey: agreement)
    }

    // MARK: - Keychain

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func read(account: String) throws -> Data? {
        var query = self.query(account: account)
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

    private func write(_ data: Data, account: String) throws {
        var item = query(account: account)
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
