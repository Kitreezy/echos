//
//  PeerIdentity.swift
//  echos
//
//  Чем собеседник представляется и что из этого можно считать проверенным.
//
//  `KeyBundle` — то, что ходит по сети: оба открытых ключа и подпись,
//  связывающая их. `PeerIdentity` — то, что остаётся после проверки: адрес
//  и ключ соглашения, которым можно пользоваться. Разделение намеренное:
//  ключ из непроверенного bundle применять нельзя, а тип не даёт этого
//  сделать случайно.
//

import CryptoKit
import Foundation

/// Открытые ключи собеседника и доказательство, что они от одной личности.
struct KeyBundle: Codable, Sendable, Equatable {

    /// Подписывающий ключ. Его отпечаток — адрес.
    let publicKey: Data

    /// Ключ соглашения, из которого выводится ключ переписки.
    let agreementKey: Data

    /// Подпись под `bindingMessage(for: agreementKey)` подписывающим ключом.
    ///
    /// Без неё релей мог бы подменить ключ соглашения своим и читать
    /// переписку, оставаясь для обоих концов невидимым.
    let agreementProof: Data

    /// Что именно подписывается. Префикс отделяет привязку ключа от всего
    /// остального, что подписывается тем же ключом: вызовы тоже
    /// 32 случайных байта, и ключ соглашения с ними спутать нельзя.
    static func bindingMessage(for agreementKey: Data) -> Data {
        Data("echos/agreement-key/v1:".utf8) + agreementKey
    }

    /// Проверить и получить личность. `nil`, если ключи не разбираются
    /// или подпись не сходится.
    func verified() -> PeerIdentity? {
        guard let signingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: agreementKey)) != nil else {
            return nil
        }

        guard signingKey.isValidSignature(agreementProof,
                                          for: Self.bindingMessage(for: agreementKey)) else {
            return nil
        }

        return PeerIdentity(fingerprint: DeviceIdentity.fingerprint(of: publicKey),
                            agreementKey: agreementKey)
    }
}

/// Собеседник, чьи ключи проверены.
///
/// Создаётся только из `KeyBundle.verified()`: другого пути нет намеренно.
struct PeerIdentity: Sendable, Equatable {
    let fingerprint: String
    let agreementKey: Data

    fileprivate init(fingerprint: String, agreementKey: Data) {
        self.fingerprint = fingerprint
        self.agreementKey = agreementKey
    }
}
