//
//  BackgroundLeaseTests.swift
//  echosTests
//
//  Отсрочка в фоне: истекает один раз, а если вернулись раньше — не
//  истекает вовсе.
//

import XCTest
@testable import echos

@MainActor
final class BackgroundLeaseTests: XCTestCase {

    func test_expires_once_afterDuration() async {
        let lease = BackgroundLease(duration: .milliseconds(50))
        var expired = 0
        lease.begin { expired += 1 }

        let fired = await waitUntil { expired == 1 }
        XCTAssertTrue(fired)

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(expired, 1, "Второго раза не бывает")
    }

    func test_endingEarly_preventsExpiry() async {
        let lease = BackgroundLease(duration: .milliseconds(50))
        var expired = 0
        lease.begin { expired += 1 }
        lease.end()

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(expired, 0, "Вернулись раньше — отключаться незачем")
    }
}
