//
//  FingerprintTests.swift
//  echosTests
//

import Foundation
import Testing
@testable import echos

struct FingerprintTests {

    @Test func fingerprint_isGroupedByFour() {
        #expect(Fingerprint.display("93f440ee4f07d563") == "93f4 40ee 4f07 d563")
    }

    @Test func realFingerprint_isGrouped() {
        let identity = DeviceIdentity()
        let shown = Fingerprint.display(identity.fingerprint)

        #expect(shown.count == 19)
        #expect(shown.replacingOccurrences(of: " ", with: "") == identity.fingerprint, "Разбиение ничего не теряет и не меняет")
    }

    /// Не отпечаток — оставить как есть. Каждый вход — отдельный случай:
    /// упадёт один — в отчёте видно, какой.
    @Test(arguments: [
        "bob-address",
        "Борис",
        "",
        "93f440ee4f07d56",   // пятнадцать знаков — не отпечаток
        "93f440ee4f07d56g"   // g — не hex
    ])
    func somethingElse_isLeftAlone(_ address: String) {
        #expect(Fingerprint.display(address) == address)
    }
}
