//
//  DeviceAttestation.swift
//  echos
//
//  Ручательство устройства за ключ личности.
//
//  Подпись под вызовом доказывает релею, что у нас есть ключ. Она не
//  доказывает, что ключ создало наше приложение: скрипт заводит такой же за
//  миллисекунду. App Attest закрывает эту разницу — Secure Enclave создаёт
//  ключ P-256, Apple выписывает на него сертификат, и этим ключом
//  приложение подписывает каждое подключение. Релей проверяет цепочку до
//  корня Apple и знает: с этим Ed25519-ключом говорит настоящий iPhone с
//  настоящим echos.
//
//  Аттестация делается один раз за жизнь ключа и хранится: повторно
//  аттестовать ключ Apple не даёт, а релей между перезапусками не помнит
//  ничего, поэтому объект уходит с каждым hello. Свежесть доказывает
//  assertion под текущим вызовом.
//

import CryptoKit
import DeviceCheck
import Foundation

/// Что уходит в hello, если устройство умеет ручаться.
struct AttestationProof: Sendable, Equatable {
    let keyID: Data
    let attestation: Data
    let challenge: Data
    let assertion: Data
}

protocol DeviceAttesting: Sendable {

    /// Доказательство под этот вызов за этот ключ личности. `nil` — устройство
    /// ручаться не умеет: симулятор, нет entitlement, старая система.
    /// Тогда hello уходит без него, и дальше решает политика релея.
    func proof(answering challenge: Data, for publicKey: Data) async throws -> AttestationProof?
}

/// Устройство, которому ручаться нечем. Симулятор и тесты.
struct NoAttestation: DeviceAttesting {
    func proof(answering challenge: Data, for publicKey: Data) async throws -> AttestationProof? {
        nil
    }
}

/// То, что подписывается assertion'ом: вызов релея и ключ личности вместе.
/// Так устройство ручается не вообще за себя, а за этот ключ в этом
/// подключении — совпадает с `AssertionClientData` на релее.
func assertionClientData(challenge: Data, publicKey: Data) -> Data {
    challenge + publicKey
}

/// App Attest через `DCAppAttestService`.
///
/// Ключ, аттестация и вызов, под который она делалась, лежат в Keychain:
/// ключ сам по себе в Secure Enclave, а его идентификатор и объект
/// аттестации — обычные данные, но терять их нельзя — второй раз ключ не
/// аттестуют.
final class AppAttestService: DeviceAttesting {

    private enum Account {
        static let keyID = "app-attest-key-id"
        static let attestation = "app-attest-attestation"
        static let challenge = "app-attest-challenge"
    }

    /// Синглтон Apple без пометки Sendable; берётся на каждый вызов, а не
    /// хранится, чтобы класс остался честно Sendable.
    private var service: DCAppAttestService { DCAppAttestService.shared }
    private let store: any SecretStore

    init(store: any SecretStore = KeychainSecretStore(service: "com.echos.attest")) {
        self.store = store
    }

    static var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    func proof(answering challenge: Data, for publicKey: Data) async throws -> AttestationProof? {
        guard service.isSupported else {
            return nil
        }

        let attested = try await loadOrAttest(answering: challenge)
        let clientData = assertionClientData(challenge: challenge, publicKey: publicKey)

        do {
            let assertion = try await service.generateAssertion(attested.keyIDString,
                                                                clientDataHash: Data(SHA256.hash(data: clientData)))
            return AttestationProof(keyID: attested.keyID,
                                    attestation: attested.attestation,
                                    challenge: attested.challenge,
                                    assertion: assertion)
        }
        catch DCError.invalidKey {
            // Ключа в Secure Enclave больше нет — так бывает после
            // восстановления из резервной копии. Аттестация к нему тоже
            // бесполезна: заводим всё заново, один раз.
            try reset()
            let fresh = try await loadOrAttest(answering: challenge)
            let assertion = try await service.generateAssertion(fresh.keyIDString,
                                                                clientDataHash: Data(SHA256.hash(data: clientData)))
            return AttestationProof(keyID: fresh.keyID,
                                    attestation: fresh.attestation,
                                    challenge: fresh.challenge,
                                    assertion: assertion)
        }
    }

    // MARK: - Private

    private struct Attested {
        let keyIDString: String
        let keyID: Data
        let attestation: Data
        let challenge: Data
    }

    private func loadOrAttest(answering challenge: Data) async throws -> Attested {
        if let keyID = try store.read(account: Account.keyID),
           let attestation = try store.read(account: Account.attestation),
           let storedChallenge = try store.read(account: Account.challenge) {
            return Attested(keyIDString: keyID.base64EncodedString(),
                            keyID: keyID,
                            attestation: attestation,
                            challenge: storedChallenge)
        }

        // Идентификатор ключа Apple отдаёт строкой base64; релею нужны
        // сами байты — это SHA-256 открытого ключа.
        let keyIDString = try await service.generateKey()
        guard let keyID = Data(base64Encoded: keyIDString) else {
            throw AttestationError.badKeyID
        }
        let attestation = try await service.attestKey(keyIDString,
                                                      clientDataHash: Data(SHA256.hash(data: challenge)))

        try store.write(keyID, account: Account.keyID)
        try store.write(attestation, account: Account.attestation)
        try store.write(challenge, account: Account.challenge)

        return Attested(keyIDString: keyIDString, keyID: keyID, attestation: attestation, challenge: challenge)
    }

    private func reset() throws {
        try store.delete(account: Account.keyID)
        try store.delete(account: Account.attestation)
        try store.delete(account: Account.challenge)
    }
}

enum AttestationError: Error, Equatable {
    case badKeyID
}
