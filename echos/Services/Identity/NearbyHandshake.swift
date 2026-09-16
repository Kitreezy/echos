//
//  NearbyHandshake.swift
//  echos
//
//  Подтверждение личности у тех, кто рядом.
//
//  На релее личность подтверждается подписью, а у MultipeerConnectivity до сих
//  пор не подтверждалась ничем: адресом там служило имя устройства, и назваться
//  чужим именем мог кто угодно. Узнавание собеседника, тёзки, адресная доставка
//  — всё это рядом работало на доверии к имени.
//
//  Порядок тот же, что и с сервером: открытый ключ объявляется при обнаружении,
//  а подтверждается подписью под случайной строкой уже внутри сессии.
//

import CryptoKit
import Foundation

enum NearbyHandshake {

    /// Ключ в объявлении. Короткий намеренно: `discoveryInfo` ходит в
    /// широковещательных пакетах, и место там не бесплатное.
    static let discoveryKey = "key"

    /// Длина случайной строки, которую просим подписать.
    static let nonceSize = 32

    static func newNonce() -> Data {
        Data((0..<nonceSize).map { _ in UInt8.random(in: .min ... .max) })
    }

    /// Проверить ответ и получить адрес собеседника.
    ///
    /// - Parameters:
    ///   - hello: открытый ключ и подпись, пришедшие от собеседника.
    ///   - nonce: строка, которую мы ему выдали.
    ///   - advertised: ключ, которым он представился при обнаружении. `nil`,
    ///     если подключились к нам первыми и объявления мы не видели.
    /// - Returns: отпечаток ключа, если всё сошлось, иначе `nil`.
    ///
    /// Объявленный ключ сверяется с присланным намеренно: иначе собеседник мог
    /// бы показаться в списке одним человеком, а в переписке оказаться другим.
    static func verify(hello: HelloPayload,
                       nonce: Data,
                       advertised: Data?) -> String? {
        guard let key = try? Curve25519.Signing.PublicKey(
            rawRepresentation: hello.publicKey) else {
            return nil
        }

        guard key.isValidSignature(hello.signature, for: nonce) else {
            return nil
        }

        if let advertised, advertised != hello.publicKey {
            return nil
        }

        return DeviceIdentity.fingerprint(of: hello.publicKey)
    }

    /// Ответ на чужой вызов.
    static func answer(to nonce: Data, as identity: DeviceIdentity) throws -> HelloPayload {
        HelloPayload(publicKey: identity.publicKey,
                     signature: try identity.signature(for: nonce))
    }
}
