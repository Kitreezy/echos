//
//  FakeAttestation.swift
//  echosTests
//
//  Устройство, которое ручается чем скажут.
//
//  Настоящий App Attest на симуляторе не работает, а без entitlement — и на
//  устройстве. Здесь важно не то, что внутри доказательства, а то, за что
//  и под какой вызов его попросили.
//

import Foundation
@testable import echos

final class FakeAttestation: DeviceAttesting, @unchecked Sendable {

    struct Request: Equatable {
        let challenge: Data
        let publicKey: Data
    }

    private let lock = NSLock()
    private var requests: [Request] = []

    let proof: AttestationProof

    init(proof: AttestationProof = AttestationProof(keyID: Data("key-id".utf8),
                                                    attestation: Data("attestation".utf8),
                                                    challenge: Data("first challenge".utf8),
                                                    assertion: Data("assertion".utf8))) {
        self.proof = proof
    }

    var asked: [Request] {
        lock.withLock { requests }
    }

    func proof(answering challenge: Data, for publicKey: Data) async throws -> AttestationProof? {
        lock.withLock { requests.append(Request(challenge: challenge, publicKey: publicKey)) }
        return proof
    }
}
