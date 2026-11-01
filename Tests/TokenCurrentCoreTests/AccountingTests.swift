import Foundation
import XCTest
@testable import TokenCurrentCore

final class AccountingTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1_790_000_000)

    func testClaudeCacheAndRevisedMessagesAreCountedOnce() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        let first = try observation(claude(input: 5, output: 2, read: 100, write: 20), provider: .claude, context: &context)
        XCTAssertEqual(first.counts, TokenCounts(input: 125, output: 2, cacheRead: 100, cacheWrite: 20))
        XCTAssertEqual(try store.apply(first, since: .distantPast).total, 127)
        XCTAssertEqual(try store.apply(first, since: .distantPast).total, 0)
        let revised = try observation(claude(input: 5, output: 50, read: 100, write: 20), provider: .claude, context: &context)
        XCTAssertEqual(try store.apply(revised, since: .distantPast).total, 48)
        XCTAssertEqual(try store.apply(first, since: .distantPast).total, 0)
        let total = try store.totals(provider: .claude, from: .distantPast, to: .distantFuture)
        XCTAssertEqual(total.total, 175)
        XCTAssertEqual(total.cached, 120)
    }

    func testMissingRequestIDAndCopiedTranscriptStillDeduplicate() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        let sample = try observation(claude(input: 10, output: 20), provider: .claude, context: &context)
        XCTAssertEqual(try store.apply(sample, since: .distantPast).total, 30)
        let copied = try observation(claude(input: 10, output: 20), provider: .claude, fileID: "copied.jsonl", context: &context)
        XCTAssertEqual(try store.apply(copied, since: .distantPast).total, 0)
    }

    func testCodexCumulativeSnapshotsAndReasoningAreNotDoubleCounted() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        _ = LogParser().parse(Data(#"{"type":"session_meta","payload":{"id":"session-a"}}"#.utf8), provider: .codex, fileID: "file", context: &context)
        let first = try observation(codex(input: 1_000, output: 50, cached: 900), provider: .codex, context: &context)
        XCTAssertEqual(try store.apply(first, since: .distantPast).total, 1_050)
        XCTAssertEqual(try store.apply(first, since: .distantPast).total, 0)
        let second = try observation(codex(input: 2_000, output: 100, cached: 1_800), provider: .codex, context: &context)
        XCTAssertEqual(try store.apply(second, since: .distantPast).total, 1_050)
        // Stale / decreasing snapshots cannot generate negative or duplicate consumption.
        XCTAssertEqual(try store.apply(first, since: .distantPast).total, 0)
        XCTAssertEqual(try store.totals(provider: .codex, from: .distantPast, to: .distantFuture).total, 2_100)
    }

    func testHistoricalCumulativeBaselineDoesNotInflateToday() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        let first = try observation(codex(input: 1_000, output: 100), provider: .codex, context: &context)
        XCTAssertEqual(try store.apply(first, since: time.addingTimeInterval(1)).total, 0)
        let next = UsageObservation(provider: .codex, identity: first.identity,
                                    timestamp: time.addingTimeInterval(2), counts: TokenCounts(input: 1_200, output: 150))
        XCTAssertEqual(try store.apply(next, since: time.addingTimeInterval(1)).total, 250)
    }

    func testForkedCodexInheritedCountersEstablishBaseline() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        let meta = """
        {"type":"session_meta","timestamp":"\(time.ISO8601Format())","payload":{"id":"child","forked_from_id":"parent"}}
        """
        _ = LogParser().parse(Data(meta.utf8), provider: .codex, fileID: "file", context: &context)
        let baseline = try observation(codex(input: 1_000, output: 100), provider: .codex, context: &context)
        XCTAssertTrue(baseline.isBaseline)
        XCTAssertEqual(try store.apply(baseline, since: .distantPast).total, 0)
        let own = try observation(codex(input: 1_200, output: 150), provider: .codex, context: &context)
        XCTAssertFalse(own.isBaseline)
        XCTAssertEqual(try store.apply(own, since: .distantPast).total, 250)
    }

    func testTransactionRollbackDoesNotLoseUsage() throws {
        let store = try SQLiteStore(path: ":memory:")
        let event = UsageObservation(provider: .claude, identity: "a", timestamp: time, counts: TokenCounts(input: 10))
        enum Failure: Error { case simulated }
        XCTAssertThrowsError(try store.transaction {
            try store.apply(event, since: .distantPast)
            throw Failure.simulated
        })
        XCTAssertEqual(try store.apply(event, since: .distantPast).total, 10)
    }

    func testModernCodexRecordsAndLegacySnapshotsShareOneLedger() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        context.sessionID = "thread-a"
        let record = """
        {"type":"token_usage_record","timestamp":"\(time.ISO8601Format())","payload":{"thread_id":"thread-a","response_id":"response-a","usage":{"input_tokens":100,"output_tokens":10},"thread_token_usage":{"input_tokens":100,"output_tokens":10,"cached_input_tokens":60,"cache_write_input_tokens":20}}}
        """
        let modern = try observation(record, provider: .codex, context: &context)
        XCTAssertEqual(try store.apply(modern, since: .distantPast).total, 110)
        XCTAssertEqual(modern.counts.cached, 80)
        let legacy = try observation(codex(input: 100, output: 10, cached: 60), provider: .codex, context: &context)
        XCTAssertEqual(try store.apply(legacy, since: .distantPast).total, 0)
    }

    func testNewSubagentIsNotMistakenForInheritedForkHistory() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        let meta = #"{"type":"session_meta","payload":{"id":"agent","parent_thread_id":"parent"}}"#
        _ = LogParser().parse(Data(meta.utf8), provider: .codex, fileID: "file", context: &context)
        let own = try observation(codex(input: 100, output: 10), provider: .codex, context: &context)
        XCTAssertFalse(own.isBaseline)
        XCTAssertEqual(try store.apply(own, since: .distantPast).total, 110)
    }

    func testFirstOwnForkResponseUsesLastUsageToExcludeInheritedCounters() throws {
        let store = try SQLiteStore(path: ":memory:")
        var context = LogContext()
        context.sessionID = "child"
        context.forked = true
        context.startedAt = time
        let json = """
        {"type":"event_msg","timestamp":"\(time.ISO8601Format())","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1100,"output_tokens":110},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
        """
        let own = try observation(json, provider: .codex, context: &context)
        XCTAssertEqual(try store.apply(own, since: .distantPast).total, 110)
        XCTAssertEqual(try store.apply(own, since: .distantPast).total, 0)
    }

    func testLateCacheBreakdownDoesNotAddTotalTokensAgain() throws {
        let store = try SQLiteStore(path: ":memory:")
        let first = UsageObservation(provider: .codex, identity: "a", timestamp: time,
                                     counts: TokenCounts(input: 100, output: 10, cacheRead: 60))
        let revised = UsageObservation(provider: .codex, identity: "a", timestamp: time,
                                       counts: TokenCounts(input: 100, output: 10, cacheRead: 60, cacheWrite: 20))
        try store.apply(first, since: .distantPast)
        XCTAssertEqual(try store.apply(revised, since: .distantPast).total, 0)
        let totals = try store.totals(provider: .codex, from: .distantPast, to: .distantFuture)
        XCTAssertEqual(totals.total, 110)
        XCTAssertEqual(totals.cached, 80)
    }

    func testMalformedAndUnsupportedValuesDoNotCrashOrAddTokens() {
        var context = LogContext()
        guard case .malformed = LogParser().parse(Data("{".utf8), provider: .claude, fileID: "x", context: &context) else { return XCTFail() }
        guard case .unsupported = LogParser().parse(Data(claude(input: -1, output: 5).utf8), provider: .claude, fileID: "x", context: &context) else { return XCTFail() }
        let limits = #"{"type":"event_msg","payload":{"type":"token_count","info":null}}"#
        guard case .ignored = LogParser().parse(Data(limits.utf8), provider: .codex, fileID: "x", context: &context) else { return XCTFail() }
    }

    func observation(_ json: String, provider: Provider, fileID: String = "file", context: inout LogContext) throws -> UsageObservation {
        guard case .observation(let value) = LogParser().parse(Data(json.utf8), provider: provider, fileID: fileID, context: &context) else {
            throw StorageError(message: "Expected a usage observation")
        }
        return value
    }

    func claude(input: Int, output: Int, read: Int = 0, write: Int = 0) -> String {
        """
        {"type":"assistant","timestamp":"\(time.ISO8601Format())","message":{"id":"msg-a","content":[{"text":"not retained"}],"usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(write)}}}
        """
    }

    func codex(input: Int, output: Int, cached: Int = 0) -> String {
        """
        {"type":"event_msg","timestamp":"\(time.ISO8601Format())","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"output_tokens":\(output),"cached_input_tokens":\(cached),"reasoning_output_tokens":20}}}}
        """
    }
}
