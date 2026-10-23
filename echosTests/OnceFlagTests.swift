//
//  OnceFlagTests.swift
//  echosTests
//
//  Флажок, на котором держится однократное возобновление continuation.
//

import Testing
@testable import echos

struct OnceFlagTests {

    @Test func firstClaimWins_restLose() {
        let flag = OnceFlag()

        #expect(flag.claim())
        #expect(!flag.claim())
        #expect(!flag.claim())
    }

    @Test func concurrentClaims_exactlyOneWins() async {
        let flag = OnceFlag()

        let winners = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask { flag.claim() }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }

        #expect(winners == 1)
    }
}
