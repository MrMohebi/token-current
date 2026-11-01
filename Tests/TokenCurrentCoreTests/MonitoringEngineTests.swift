import Foundation
import XCTest
@testable import TokenCurrentCore

final class MonitoringEngineTests: XCTestCase, @unchecked Sendable {
    func testBackfillAppendRestartPauseAndClearHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date.now
        try fixture.append(provider: .claude, id: "before-launch", input: 1_000, output: 100, time: now)
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        let first = try await engine.tick(at: now)
        XCTAssertEqual(first.total(for: nil).total, 1_100)
        XCTAssertEqual(first.rate(for: nil), 0)
        XCTAssertEqual(first.health[.codex], .waiting)

        try fixture.append(provider: .claude, id: "live", input: 200, output: 50, time: now.addingTimeInterval(1))
        let live = try await engine.tick(at: now.addingTimeInterval(1))
        XCTAssertEqual(live.rate(for: .claude), 25)
        XCTAssertEqual(live.total(for: .claude).total, 1_350)
        let restarted = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        let restored = try await restarted.tick(at: now.addingTimeInterval(2))
        XCTAssertEqual(restored.total(for: .claude).total, 1_350)
        XCTAssertEqual(restored.rate(for: .claude), 0)

        await restarted.setPaused(true)
        try fixture.append(provider: .claude, id: "paused", input: 80, output: 20, time: now.addingTimeInterval(3))
        let paused = try await restarted.tick(at: now.addingTimeInterval(3))
        XCTAssertNil(paused.rate(for: nil))
        XCTAssertEqual(paused.total(for: nil).total, 1_350)
        await restarted.setPaused(false)
        let resumed = try await restarted.tick(at: now.addingTimeInterval(4))
        XCTAssertEqual(resumed.total(for: nil).total, 1_450)
        XCTAssertEqual(resumed.rate(for: nil), 0)

        try await restarted.clearHistory()
        let cleared = try await restarted.tick(at: now.addingTimeInterval(5))
        XCTAssertEqual(cleared.total(for: nil).total, 0)
        try fixture.append(provider: .claude, id: "after-clear", input: 5, output: 5, time: now.addingTimeInterval(6))
        let afterClear = try await restarted.tick(at: now.addingTimeInterval(6))
        XCTAssertEqual(afterClear.total(for: nil).total, 10)
    }

    func testWakeBacklogIsExcludedFromLiveRate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date.now
        try fixture.append(provider: .claude, id: "first", input: 10, output: 10, time: now)
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        _ = try await engine.tick(at: now)
        try fixture.append(provider: .claude, id: "during-sleep", input: 1_000, output: 100, time: now.addingTimeInterval(20))
        let wake = try await engine.tick(at: now.addingTimeInterval(60))
        XCTAssertEqual(wake.total(for: nil).total, 1_120)
        XCTAssertEqual(wake.rate(for: nil), 0)
    }

    func testNewNestedSessionsDiscoveryAndConcurrentAgents() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date.now
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        _ = try await engine.tick(at: now)
        try fixture.append(provider: .claude, id: "parent", input: 20, output: 10, time: now.addingTimeInterval(1))
        let nested = fixture.root.appending(path: "claude/projects/project/session/subagents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let content = fixture.claudeJSON(id: "child", input: 10, output: 10, time: now.addingTimeInterval(1))
        try Data((content + "\n").utf8).write(to: nested.appending(path: "agent.jsonl"))
        await engine.requestDiscovery()
        let snapshot = try await engine.tick(at: now.addingTimeInterval(1))
        XCTAssertEqual(snapshot.total(for: nil).total, 50)
        XCTAssertEqual(snapshot.rate(for: nil), 5)
    }

    func testMissingAndUnsupportedSources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date.now
        let missing = try MonitoringEngine(databasePath: ":memory:", configuration: SourceConfiguration(claudeHome: "/no-such-claude", codexHome: "/no-such-codex"))
        let absent = try await missing.tick(at: now)
        XCTAssertEqual(absent.health[.claude], .missing)
        XCTAssertNil(absent.rate(for: nil))
        let malformed = fixture.root.appending(path: "claude/projects/session.jsonl")
        try Data("broken json\n".utf8).write(to: malformed)
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        let unsupported = try await engine.tick(at: now)
        XCTAssertEqual(unsupported.health[.claude], .unsupported)
        XCTAssertNil(unsupported.rate(for: .claude))
    }

    func testMidnightUsesLocalCalendarAndDoesNotResetDeduplication() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7_200)!
        let before = calendar.startOfDay(for: .now).addingTimeInterval(86_399)
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        try fixture.append(provider: .claude, id: "yesterday", input: 30, output: 10, time: before)
        _ = try await engine.tick(at: before, calendar: calendar)
        try fixture.append(provider: .claude, id: "today", input: 20, output: 10, time: before.addingTimeInterval(2))
        // Give the fixture's mtime the same virtual day as its events.
        try FileManager.default.setAttributes([.modificationDate: before.addingTimeInterval(2)],
            ofItemAtPath: fixture.root.appending(path: "claude/projects/session.jsonl").path)
        let today = try await engine.tick(at: before.addingTimeInterval(2), calendar: calendar)
        XCTAssertEqual(today.total(for: nil).total, 30)
    }

    func testIdleTickDoesNotWriteUnchangedDatabase() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date.now
        try fixture.append(provider: .claude, id: "first", input: 10, output: 5, time: now)
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        _ = try await engine.tick(at: now)
        let walURL = URL(fileURLWithPath: fixture.database + "-wal")
        let before = try Data(contentsOf: walURL)
        _ = try await engine.tick(at: now.addingTimeInterval(1))
        XCTAssertEqual(try Data(contentsOf: walURL), before)
    }

    func testMultiChunkWakeBacklogDoesNotLeakIntoLiveRate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date.now
        try fixture.append(provider: .claude, id: "first", input: 10, output: 10, time: now)
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        _ = try await engine.tick(at: now)
        let url = fixture.root.appending(path: "claude/projects/session.jsonl")
        let file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
        let ignored = "{\"type\":\"user\",\"padding\":\"" + String(repeating: "x", count: 1_000) + "\"}\n"
        try file.write(contentsOf: Data(String(repeating: ignored, count: 2_100).utf8))
        try file.close()
        try fixture.append(provider: .claude, id: "after-backlog", input: 1_000, output: 100, time: now.addingTimeInterval(30))
        let first = try await engine.tick(at: now.addingTimeInterval(60))
        XCTAssertTrue(first.importing)
        let next = try await engine.tick(at: now.addingTimeInterval(61))
        XCTAssertFalse(next.importing)
        XCTAssertEqual(next.total(for: nil).total, 1_120)
        XCTAssertEqual(next.rate(for: nil), 0)
    }

    func testPermissionDeniedSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appending(path: "claude/projects")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        if FileManager.default.isReadableFile(atPath: url.path) {
            throw XCTSkip("This account bypasses Unix folder permissions; run this test as an unprivileged user.")
        }
        let engine = try MonitoringEngine(databasePath: fixture.database, configuration: fixture.configuration)
        let snapshot = try await engine.tick()
        XCTAssertEqual(snapshot.health[.claude], .permissionDenied)
        XCTAssertNil(snapshot.rate(for: .claude))
    }
}

private struct Fixture {
    let root: URL
    var database: String { root.appending(path: "usage.sqlite").path }
    var configuration: SourceConfiguration {
        SourceConfiguration(claudeHome: root.appending(path: "claude").path,
                            codexHome: root.appending(path: "codex").path)
    }
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "TokenCurrent-\(UUID().uuidString)")
        for subdirectory in ["claude/projects", "codex/sessions"] {
            try FileManager.default.createDirectory(at: root.appending(path: subdirectory), withIntermediateDirectories: true)
        }
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func append(provider: Provider, id: String, input: Int, output: Int, time: Date) throws {
        let url = root.appending(path: provider == .claude ? "claude/projects/session.jsonl" : "codex/sessions/session.jsonl")
        let content = claudeJSON(id: id, input: input, output: output, time: time) + "\n"
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: Data(content.utf8))
    }
    func claudeJSON(id: String, input: Int, output: Int, time: Date) -> String {
        """
        {"type":"assistant","timestamp":"\(time.ISO8601Format())","message":{"id":"\(id)","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
        """
    }
}
