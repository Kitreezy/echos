//
//  ConversationCipher.swift
//  echos
//
//  Шифрование переписки между двумя личностями.
//
//  Ключ выводится из общего секрета X25519 через HKDF и одинаков с обеих
//  сторон: ни ключ, ни секрет по сети не ходят. Сообщение запечатывается
//  AES-GCM со случайным nonce, а адреса отправителя и получателя входят в
//  дополнительные данные: конверт, переставленный релеем в другую сторону
//  или отражённый обратно, не откроется.
//
//  Ключ пары статический: пока ключи соглашения у обоих одни и те же, один
//  и тот же. Прямой секретности здесь нет — это отдельный шаг, см. ADR 003.
//

import CryptoKit
import Foundation

/// Что уходит по сети вместо открытого сообщения.
struct SealedPayload: Codable, Sendable, Equatable {
    /// Версия схемы. Чтобы завтрашний формат не открывали вчерашним ключом.
    let version: Int
    /// nonce + шифртекст + тег, как их отдаёт `AES.GCM.SealedBox.combined`.
    let box: Data

    static let currentVersion = 1
}

enum ConversationCipherError: Error, Equatable {
    case unsupportedVersion(Int)
    case sealedBoxMalformed
}

struct ConversationCipher: Sendable {

    private let key: SymmetricKey

    /// Ключ переписки между нами и собеседником.
    ///
    /// Соль и информация фиксированы и симметричны: адреса входят в
    /// отсортированном порядке, чтобы обе стороны вывели один ключ.
    init(identity: DeviceIdentity, peer: PeerIdentity) throws {
        let secret = try identity.sharedSecret(with: peer)
        let pair = [identity.fingerprint, peer.fingerprint].sorted().joined(separator: "|")

        key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("echos/e2e/v1".utf8),
            sharedInfo: Data(pair.utf8),
            outputByteCount: 32
        )
    }

    /// Запечатать что угодно кодируемое — сообщение сегодня, росчерк завтра.
    func seal<T: Encodable>(_ value: T, from sender: String, to recipient: String) throws -> SealedPayload {
        let plaintext = try JSONEncoder().encode(value)
        let box = try AES.GCM.seal(plaintext,
                                   using: key,
                                   authenticating: Self.associatedData(from: sender, to: recipient))

        guard let combined = box.combined else {
            throw ConversationCipherError.sealedBoxMalformed
        }

        return SealedPayload(version: SealedPayload.currentVersion, box: combined)
    }

    func open<T: Decodable>(_ sealed: SealedPayload,
                            as type: T.Type,
                            from sender: String,
                            to recipient: String) throws -> T {
        guard sealed.version == SealedPayload.currentVersion else {
            throw ConversationCipherError.unsupportedVersion(sealed.version)
        }

        let box = try AES.GCM.SealedBox(combined: sealed.box)
        let plaintext = try AES.GCM.open(box,
                                         using: key,
                                         authenticating: Self.associatedData(from: sender, to: recipient))

        return try JSONDecoder().decode(type, from: plaintext)
    }

    /// Направление конверта. Не шифруется — релею адреса нужны, чтобы
    /// доставить, — но подделать его нельзя.
    private static func associatedData(from sender: String, to recipient: String) -> Data {
        Data("echos/message/v1:\(sender)>\(recipient)".utf8)
    }
}
