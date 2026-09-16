//
//  ConversationCipher.swift
//  echos
//
//  Шифрование переписки между двумя личностями в рамках сессии.
//
//  Ключ выводится через HKDF из двух общих секретов X25519 и одинаков с
//  обеих сторон: ни ключ, ни секреты по сети не ходят. Сессионный секрет —
//  из эфемерных ключей, свежих на каждое подключение: он даёт прямую
//  секретность, записанное прошлое не откроется даже утёкшими долгими
//  ключами. Статический — из ключей, живущих с личностью: он держит
//  привязку к ней, и посреднику, чтобы встать между двумя людьми, нужен не
//  только подписывающий ключ, но и закрытый ключ соглашения.
//
//  Сообщение запечатывается AES-GCM со случайным nonce, а адреса отправителя
//  и получателя входят в дополнительные данные: конверт, переставленный
//  релеем в другую сторону или отражённый обратно, не откроется.
//

import CryptoKit
import Foundation

/// Что уходит по сети вместо открытого сообщения.
struct SealedPayload: Codable, Sendable, Equatable {
    /// Версия схемы. Чтобы завтрашний формат не открывали вчерашним ключом.
    let version: Int
    /// nonce + шифртекст + тег, как их отдаёт `AES.GCM.SealedBox.combined`.
    let box: Data

    /// 2 — ключ с сессионной частью. Первую версию, без неё, не открываем:
    /// собеседник без сессионного ключа в список и так не попадает.
    static let currentVersion = 2
}

enum ConversationCipherError: Error, Equatable {
    case unsupportedVersion(Int)
    case sealedBoxMalformed
}

struct ConversationCipher: Sendable {

    private let key: SymmetricKey

    /// Ключ переписки между нами и собеседником на эту сессию.
    ///
    /// Оба секрета симметричны сами по себе — X25519 даёт одно и то же с
    /// любой стороны, — поэтому и их порядок фиксирован: сессионный, потом
    /// статический. Адреса входят в отсортированном порядке, чтобы обе
    /// стороны вывели один ключ.
    init(identity: DeviceIdentity, session: SessionKey, peer: PeerIdentity) throws {
        let ephemeral = try session.sharedSecret(with: peer)
        let longTerm = try identity.sharedSecret(with: peer)
        let pair = [identity.fingerprint, peer.fingerprint].sorted().joined(separator: "|")

        // `SharedSecret` наружу байты не отдаёт иначе как через
        // `withUnsafeBytes`; склеиваем оба и ведём через HKDF как один
        // входной материал.
        var material = Data()
        ephemeral.withUnsafeBytes { material.append(contentsOf: $0) }
        longTerm.withUnsafeBytes { material.append(contentsOf: $0) }

        key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            salt: Data("echos/e2e/v2".utf8),
            info: Data(pair.utf8),
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
