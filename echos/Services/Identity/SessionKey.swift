//
//  SessionKey.swift
//  echos
//
//  Ключ на одну сессию.
//
//  Зачем: ключ переписки, выведенный только из статических ключей, один и
//  тот же, пока живут сами ключи. Утечка закрытого ключа открывала бы всё,
//  что было записано. Эфемерная пара создаётся на каждую сессию и после неё
//  забывается: записанное прошлое остаётся закрытым, даже если долгие ключи
//  однажды утекут.
//
//  Сессия — это одно подключение: у Multipeer — сессия с устройством, на
//  релее — одно соединение с сервером. Ключ подписывается личностью, чтобы
//  подменить его посредник не мог.
//

import CryptoKit
import Foundation

struct SessionKey: Sendable {

    /// Открытая часть — уходит собеседникам.
    let publicKey: Data

    /// Подпись под `bindingMessage(for: publicKey)` подписывающим ключом.
    let proof: Data

    private let privateKey: Curve25519.KeyAgreement.PrivateKey

    /// Свежая пара, подписанная личностью.
    init(signedBy identity: DeviceIdentity) throws {
        privateKey = Curve25519.KeyAgreement.PrivateKey()
        publicKey = privateKey.publicKey.rawRepresentation
        proof = try identity.signature(for: Self.bindingMessage(for: publicKey))
    }

    /// Пара вокруг готового ключа — для тестов и вектора совместимости.
    init(privateKey: Curve25519.KeyAgreement.PrivateKey, signedBy identity: DeviceIdentity) throws {
        self.privateKey = privateKey
        publicKey = privateKey.publicKey.rawRepresentation
        proof = try identity.signature(for: Self.bindingMessage(for: publicKey))
    }

    /// Свой префикс, отличный и от вызова, и от привязки статического ключа:
    /// три вида подписей одним ключом не должны сходить друг за друга.
    static func bindingMessage(for publicKey: Data) -> Data {
        Data("echos/session-key/v1:".utf8) + publicKey
    }

    /// Эфемерная часть общего секрета.
    func sharedSecret(with peer: PeerIdentity) throws -> SharedSecret {
        let theirKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer.sessionKey)
        return try privateKey.sharedSecretFromKeyAgreement(with: theirKey)
    }
}
