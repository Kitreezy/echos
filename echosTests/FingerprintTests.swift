//
//  FingerprintTests.swift
//  echosTests
//

import XCTest
@testable import echos

final class FingerprintTests: XCTestCase {

    func test_fingerprint_isGroupedByFour() {
        XCTAssertEqual(Fingerprint.display("93f440ee4f07d563"), "93f4 40ee 4f07 d563")
    }

    func test_realFingerprint_isGrouped() {
        let identity = DeviceIdentity()
        let shown = Fingerprint.display(identity.fingerprint)

        XCTAssertEqual(shown.count, 19)
        XCTAssertEqual(shown.replacingOccurrences(of: " ", with: ""), identity.fingerprint,
                       "Разбиение ничего не теряет и не меняет")
    }

    func test_somethingElse_isLeftAlone() {
        XCTAssertEqual(Fingerprint.display("bob-address"), "bob-address")
        XCTAssertEqual(Fingerprint.display("Борис"), "Борис")
        XCTAssertEqual(Fingerprint.display(""), "")
        XCTAssertEqual(Fingerprint.display("93f440ee4f07d56"), "93f440ee4f07d56", "Пятнадцать знаков — не отпечаток")
        XCTAssertEqual(Fingerprint.display("93f440ee4f07d56g"), "93f440ee4f07d56g", "g — не hex")
    }
}
