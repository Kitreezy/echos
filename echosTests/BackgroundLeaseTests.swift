//
//  BackgroundLeaseTests.swift
//  echosTests
//
//  Отсрочка в фоне: истекает один раз, а если вернулись раньше — не
//  истекает вовсе.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct BackgroundLeaseTests {

    @Test func expires_once_afterDuration() async {
        let lease = BackgroundLease(duration: .milliseconds(50))
        var expired = 0
        lease.begin { expired += 1 }

        let fired = await waitUntil { expired == 1 }
        #expect(fired)

        try? await Task.sleep(for: .milliseconds(80))
        #expect(expired == 1, "Второго раза не бывает")
    }

    @Test func endingEarly_preventsExpiry() async {
        let lease = BackgroundLease(duration: .milliseconds(50))
        var expired = 0
        lease.begin { expired += 1 }
        lease.end()

        try? await Task.sleep(for: .milliseconds(100))
        #expect(expired == 0, "Вернулись раньше — отключаться незачем")
    }
}
