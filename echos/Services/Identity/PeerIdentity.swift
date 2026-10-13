//
//  PeerIdentity.swift
//  echos
//
//  Чем собеседник представляется и что из этого можно считать проверенным.
//
//  `KeyBundle` — то, что ходит по сети: открытые ключи и подписи,
//  связывающие их с личностью. `PeerIdentity` — то, что остаётся после
//  проверки: адрес и ключи, которыми можно пользоваться. Разделение
//  намеренное: ключ из непроверенного bundle применять нельзя, а тип не
//  даёт этого сделать случайно.
//
//  Ключей в связке два: статический ключ соглашения, живущий с личностью,
//  и сессионный, свежий на каждое подключение. Из обоих выводится ключ
//  переписки, см. `ConversationCipher`.
//

import CryptoKit
import Foundation

/// Открытые ключи собеседника и доказательства, что они от одной личности.
struct KeyBundle: Codable, Sendable, Equatable {

    /// Подписывающий ключ. Его отпечаток — адрес.
    let publicKey: Data

    /// Статический ключ соглашения. Живёт с личностью.
    let agreementKey: Data

    /// Подпись под `bindingMessage(for: agreementKey)` подписывающим ключом.
    ///
    /// Без неё релей мог бы подменить ключ соглашения своим и читать
    /// переписку, оставаясь для обоих концов невидимым.
    let agreementProof: Data

    /// Сессионный ключ соглашения. Свой на каждое подключение.
    let sessionKey: Data

    /// Подпись под `SessionKey.bindingMessage(for: sessionKey)`.
    let sessionProof: Data

    /// Что именно подписывается. Префикс отделяет привязку ключа от всего
    /// остального, что подписывается тем же ключом: вызовы тоже
    /// 32 случайных байта, и ключ соглашения с ними спутать нельзя.
    static func bindingMessage(for agreementKey: Data) -> Data {
        Data("echos/agreement-key/v1:".utf8) + agreementKey
    }

    /// Проверить и получить личность. `nil`, если ключи не разбираются
    /// или хоть одна подпись не сходится.
    func verified() -> PeerIdentity? {
        guard let signingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: agreementKey)) != nil,
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: sessionKey)) != nil else {
            return nil
        }

        guard signingKey.isValidSignature(agreementProof,
                                          for: Self.bindingMessage(for: agreementKey)),
              signingKey.isValidSignature(sessionProof,
                                          for: SessionKey.bindingMessage(for: sessionKey)) else {
            return nil
        }

        return PeerIdentity(fingerprint: DeviceIdentity.fingerprint(of: publicKey),
                            agreementKey: agreementKey,
                            sessionKey: sessionKey)
    }
}

/// Собеседник, чьи ключи проверены, — в рамках одной его сессии.
///
/// Создаётся только из `KeyBundle.verified()`: другого пути нет намеренно.
struct PeerIdentity: Sendable, Equatable {
    let fingerprint: String
    let agreementKey: Data
    let sessionKey: Data

    fileprivate init(fingerprint: String, agreementKey: Data, sessionKey: Data) {
        self.fingerprint = fingerprint
        self.agreementKey = agreementKey
        self.sessionKey = sessionKey
    }
}
