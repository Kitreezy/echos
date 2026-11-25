//
//  SecretRotation.swift
//  echos
//
//  Ротация секретов устройства: перезапись ключей личности в Keychain.
//  «Ротация» без сервера — это не смена ключей (адрес привязан к ключу,
//  менять его в фоне нельзя), а их перетасовка: запись пересоздаётся
//  с актуальным классом защиты, проверяется, что байты по-прежнему
//  собираются в ключ, а случайный мусор вместо ключа чинится сразу, пока
//  человек не обнаружил, что hello не уходит.
//

import CryptoKit
import Foundation
import OSLog

/// Итог одного прохода ротации.
struct SecretRotationResult: Equatable, Sendable {
    /// Сколько существующих записей переписано заново.
    var rotated = 0
    /// Сколько записей было потеряно или повреждено и воссоздано.
    var healed = 0
    /// Keychain заперт до первой разблокировки: ничего не делали, придём
    /// в следующий раз. Это не неудача.
    var skippedLocked = false
}

/// Ротация ключей личности. Ключи не меняются — меняется их обёртка.
struct SecretRotation: Sendable {

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
    }

    /// Перезаписать обе записи личности. Личность после ротации — та же:
    /// адрес устройства не смещается, переписки и знакомые на месте.
    func rotate() throws -> SecretRotationResult {
        var result = SecretRotationResult()

        do {
            result.rotated += try rotateSigningKey(result: &result)
            result.rotated += try rotateAgreementKey(result: &result)
        } catch SecretStoreError.locked {
            result.skippedLocked = true
        }
        return result
    }

    // MARK: - Private

    /// Ключ Curve25519: если записи нет или байты не собираются в ключ —
    /// создаём новый (это и есть починка), иначе переписываем те же байты.
    /// Возвращает 1, если запись переписана.
    private func rotateSigningKey(result: inout SecretRotationResult) throws -> Int {
        try rotate(account: IdentityStore.signingAccount,
                   make: Curve25519.Signing.PrivateKey.init,
                   parse: Curve25519.Signing.PrivateKey.init(rawRepresentation:),
                   raw: \.rawRepresentation,
                   result: &result)
    }

    private func rotateAgreementKey(result: inout SecretRotationResult) throws -> Int {
        try rotate(account: IdentityStore.agreementAccount,
                   make: Curve25519.KeyAgreement.PrivateKey.init,
                   parse: Curve25519.KeyAgreement.PrivateKey.init(rawRepresentation:),
                   raw: \.rawRepresentation,
                   result: &result)
    }

    private func rotate<Key>(account: String,
                             make: () -> Key,
                             parse: (Data) throws -> Key,
                             raw: (Key) -> Data,
                             result: inout SecretRotationResult) throws -> Int {
        let bytes = try store.read(account: account)
        if let bytes {
            if let key = try? parse(bytes) {
                // Перезапись теми же байтами: обновляется класс защиты
                // записи, ключ остаётся прежним.
                try store.write(raw(key), account: account)
                return 1
            }
            // Байты есть, а ключ из них не собирается — как в IdentityStore,
            // но в фоне, до того как кто-то пострадал.
            Logger.identity.fault("Ротация: ключ \(account, privacy: .public) повреждён, создаётся новый")
            result.healed += 1
        } else {
            // Записи нет вообще — лечим дырку сразу.
            result.healed += 1
        }

        let key = make()
        try store.write(raw(key), account: account)
        return 0
    }
}
