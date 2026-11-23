import CryptoKit
import Foundation
import Security
import Testing
@testable import echos

@MainActor
@Suite(.tags(.network, .crypto))
struct CertificatePinningTests {

    @Test func matchingPublicKeyPin_allowsTLSConnection() async throws {
        let identity = try loadIdentity(named: "relay-identity")
        let pins: Set<Data> = [try publicKeyHash(of: identity)]
        let server = RelayServer()
        try await server.start(identity: identity)
        do {
            let client = WebSocketClient(url: server.url,
                                         publicKeyPins: pins,
                                         networkMonitor: FakeNetworkMonitor())
            client.connect()
            let connected = await waitUntil { client.state == .connected }
            client.disconnect()
            #expect(connected)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    @Test func substitutedCertificate_isRejectedBeforeWebSocketOpens() async throws {
        let expectedIdentity = try loadIdentity(named: "relay-identity")
        let substitutedIdentity = try loadIdentity(named: "substituted-identity")
        let pins: Set<Data> = [try publicKeyHash(of: expectedIdentity)]
        let server = RelayServer()
        try await server.start(identity: substitutedIdentity)
        do {
            let socket = URLSessionRawSocket(url: server.url, publicKeyPins: pins)
            socket.open()
            let failure = await firstElement(of: socket.events, timeout: .seconds(5)) { event in
                if case .failed = event { return true }
                return false
            }
            socket.close()
            #expect(failure != nil)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    private func loadIdentity(named name: String) throws -> SecIdentity {
        let url = try #require(Bundle(for: BundleLocator.self).url(forResource: name, withExtension: "p12"))
        let data = try Data(contentsOf: url)
        var items: CFArray?
        let status = SecPKCS12Import(data as NSData, [kSecImportExportPassphrase: "echos"] as NSDictionary, &items)
        try #require(status == errSecSuccess)
        let dictionary = try #require((items as? [[String: Any]])?.first)
        return try #require(dictionary[kSecImportItemIdentity as String] as! SecIdentity?)
    }

    private func publicKeyHash(of identity: SecIdentity) throws -> Data {
        var certificate: SecCertificate?
        try #require(SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess)
        let key = try #require(certificate.flatMap(SecCertificateCopyKey))
        let data = try #require(SecKeyCopyExternalRepresentation(key, nil) as Data?)
        return Data(SHA256.hash(data: data))
    }
}

private final class BundleLocator {}
