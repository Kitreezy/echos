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

/// Личность устройства: пара подписывающего ключа Ed25519 и ключа соглашения
/// X25519. Хранение личности — ответственность приложения; пакет оперирует
/// уже загруженными ключами.
public struct DeviceIdentity: Sendable {

    /// Открытая часть ключа. Уходит релею при каждом подключении: проверить
    /// подпись по отпечатку нельзя, а хранить ключи между запусками релею
    /// негде.
    public let publicKey: Data

    /// Короткое представление ключа — то же, что считает релей.
    ///
    /// Само по себе ничего не защищает, но по нему видно, что «Bob» сегодня
    /// и «Bob» вчера — один человек.
    public var fingerprint: String {
        Self.fingerprint(of: publicKey)
    }

    /// Отпечаток чужого ключа — тот же, что считает релей.
    public static func fingerprint(of publicKey: Data) -> String {
        SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Открытая часть ключа соглашения. Вместе с `publicKey` и подписью
    /// под ней образует `KeyBundle` — то, чем представляемся собеседникам.
    public let agreementKey: Data

    private let privateKey: Curve25519.Signing.PrivateKey
    private let agreementPrivateKey: Curve25519.KeyAgreement.PrivateKey

    /// Личность вокруг готовых ключей. Закрытые части пакет наружу не
    /// отдаёт — только подписи и общие секреты.
    public init(privateKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey(),
                agreementKey: Curve25519.KeyAgreement.PrivateKey = Curve25519.KeyAgreement.PrivateKey()) {
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey.rawRepresentation
        self.agreementPrivateKey = agreementKey
        self.agreementKey = agreementKey.publicKey.rawRepresentation
    }

    /// Подписать вызов сервера.
    public func signature(for challenge: Data) throws -> Data {
        try privateKey.signature(for: challenge)
    }

    /// Чем представляемся в этой сессии: открытые ключи и доказательства,
    /// что ключи соглашения принадлежат этой же личности.
    ///
    /// Подписывается не голый ключ, а строка с префиксом: вызовы, которые мы
    /// подписываем для кого угодно, — тоже 32 случайных байта, и без префикса
    /// чужой «вызов» мог бы оказаться чужим ключом соглашения с нашей
    /// подписью под ним.
    public func keyBundle(session: SessionKey) throws -> KeyBundle {
        KeyBundle(publicKey: publicKey,
                  agreementKey: agreementKey,
                  agreementProof: try privateKey.signature(for: KeyBundle.bindingMessage(for: agreementKey)),
                  sessionKey: session.publicKey,
                  sessionProof: session.proof)
    }

    /// Статическая часть общего секрета — сырая, до вывода ключа шифрования.
    public func sharedSecret(with peer: PeerIdentity) throws -> SharedSecret {
        let theirKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer.agreementKey)
        return try agreementPrivateKey.sharedSecretFromKeyAgreement(with: theirKey)
    }
}
