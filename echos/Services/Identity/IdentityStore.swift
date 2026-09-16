//
//  IdentityStore.swift
//  echos
//
//  Ключи личности: прочитать, а при первом обращении — создать.
//
//  Здесь живёт политика, а не Keychain. Что считать «ключа нет», что —
//  «ключ есть, но не достать», что делать с байтами, из которых ключ не
//  собирается. Ошибиться легко в обе стороны: создать новый ключ там, где
//  старый просто не читался, — значит сменить адрес и потерять переписки;
//  а отказаться работать из-за мусора в Keychain — значит сломать
//  приложение навсегда.
//

import CryptoKit
import Foundation

/// Отдельный тип нужен из-за кэша: обращаться в Keychain на каждое
/// переподключение незачем, а кэш переживает потоки, поэтому под замком.
final class IdentityStore: @unchecked Sendable {

    static let signingAccount = "device-signing-key"
    static let agreementAccount = "device-agreement-key"

    private let store: any SecretStore
    private let lock = NSLock()
    private var cached: DeviceIdentity?

    init(store: any SecretStore) {
        self.store = store
    }

    /// Личность устройства. Бросает только тогда, когда её сейчас не достать
    /// и создавать новую нельзя; после успеха — из кэша.
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

    /// Забыть личность. Следующее обращение создаст новую — с другим адресом.
    func reset() throws {
        lock.lock()
        defer { lock.unlock() }

        try store.delete(account: Self.signingAccount)
        try store.delete(account: Self.agreementAccount)
        cached = nil
    }

    // MARK: - Private

    /// Ключи читаются и создаются по отдельности: у того, кто обновился,
    /// подписывающий ключ уже есть, и адрес менять из-за появления второго
    /// нельзя — к адресу привязаны переписки и знакомые.
    private func loadOrCreate() throws -> DeviceIdentity {
        let signing = try loadOrCreate(account: Self.signingAccount,
                                       make: Curve25519.Signing.PrivateKey.init,
                                       parse: Curve25519.Signing.PrivateKey.init(rawRepresentation:),
                                       raw: \.rawRepresentation)
        let agreement = try loadOrCreate(account: Self.agreementAccount,
                                         make: Curve25519.KeyAgreement.PrivateKey.init,
                                         parse: Curve25519.KeyAgreement.PrivateKey.init(rawRepresentation:),
                                         raw: \.rawRepresentation)
        return DeviceIdentity(privateKey: signing, agreementKey: agreement)
    }

    /// Три исхода чтения, и у каждого своя судьба.
    ///
    /// Записи нет — создаём: это первый запуск. Прочитать нельзя — бросаем
    /// как есть: ключ на месте, просто устройство ещё заперто, и новый
    /// сейчас сделать — значит потерять адрес. Байты есть, но ключ из них
    /// не собирается — создаём новый и перезаписываем: старый всё равно
    /// потерян, а без ключа приложение не работает. Адрес при этом
    /// меняется, и это единственный случай, когда так можно.
    private func loadOrCreate<Key>(account: String,
                                   make: () -> Key,
                                   parse: (Data) throws -> Key,
                                   raw: (Key) -> Data) throws -> Key {
        if let raw = try store.read(account: account) {
            if let key = try? parse(raw) {
                return key
            }
            print("[IdentityStore] Ключ \(account) в Keychain повреждён, создаётся новый")
        }

        let key = make()
        try store.write(raw(key), account: account)
        return key
    }
}
