import CryptoKit
import Foundation
import Security

struct CertificatePinning: Sendable {

    static let defaultRelayPins: Set<Data> = [
        Data(base64Encoded: "8emdl/UmneUm0I4Y/vHzOTQzb9eJwG4voRHtMdNmBPk=")!
    ]

    static func pins(for url: URL) -> Set<Data>? {
        url == UserSettings.defaultRelayURL ? defaultRelayPins : nil
    }

    let publicKeyHashes: Set<Data>

    func evaluate(_ trust: SecTrust) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first,
              let key = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return false
        }

        let hash = Data(SHA256.hash(data: keyData))
        return publicKeyHashes.contains(hash)
    }
}
