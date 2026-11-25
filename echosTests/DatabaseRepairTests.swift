//
//  DatabaseRepairTests.swift
//  echosTests
//
//  Unit: профилактика базы — считает сообщения, пересобирает поисковый
//  индекс только при рассинхроне версий, честно сдаётся, если база
//  не открывается.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct DatabaseRepairTests {

    @Test func healthyDatabase_countsWithoutReindex() async {
        var reindexCalls = 0
        let repair = DatabaseRepair(
            countMessages: { 42 },
            reindexIfNeeded: {
                reindexCalls += 1
                return false
            }
        )

        let result = await repair.repair()

        #expect(result.messageCount == 42)
        #expect(!result.reindexed)
        #expect(reindexCalls == 1)
    }

    @Test func versionMismatch_rebuildsIndex() async {
        let repair = DatabaseRepair(
            countMessages: { 7 },
            reindexIfNeeded: { true }
        )

        let result = await repair.repair()

        #expect(result.messageCount == 7)
        #expect(result.reindexed)
    }

    @Test func unreadableDatabase_failsWithoutReindex() async {
        var reindexCalls = 0
        struct Broken: Error {}
        let repair = DatabaseRepair(
            countMessages: { throw Broken() },
            reindexIfNeeded: {
                reindexCalls += 1
                return true
            }
        )

        let result = await repair.repair()

        #expect(result.messageCount == nil)
        #expect(!result.reindexed)
        #expect(reindexCalls == 0, "Мёртвой базе индекс не пересобираем")
    }
}
