import XCTest
@testable import TokenCurrentCore

final class MeshTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_534_400)
    func machine(_ id: String, rate: Double = 10, input: Int64 = 100) -> NetworkMachine {
        let local = MonitorSnapshot(timestamp: now, health: [.claude: .ready, .codex: .missing], totals: [.claude: TokenCounts(input: input)], rates: [.claude: rate], importing: false)
        return NetworkMachine(snapshot: NetworkSnapshot(id: id, name: id, bootID: "boot-test", sequence: 1, local: local))
    }
    func testCombinesAndDeduplicatesMachineIDs() {
        let a = machine("machine-a"), b = machine("machine-b", rate: 20, input: 300)
        let combined = MeshAccounting.combine([a, a, b], at: now)
        XCTAssertEqual(combined.rate(for: nil), 30)
        XCTAssertEqual(combined.total(for: nil).input, 400)
        XCTAssertEqual(MeshAccounting.combine([a,b], selectedID: b.id, at: now).rate(for: nil), 20)
    }
    func testOfflineRateExcludedButTotalsRetainedAndMidnightResets() {
        let a = machine("machine-a")
        let stale = MeshAccounting.combine([a], at: now.addingTimeInterval(16))
        XCTAssertNil(stale.rate(for: nil)); XCTAssertEqual(stale.total(for: nil).input, 100)
        XCTAssertEqual(MeshAccounting.combine([a], at: now.addingTimeInterval(86400)).total(for: nil), .zero)
    }
    func testRejectsInvalidCountersAndFutureSamples() {
        var a = machine("machine-a")
        a.snapshot?.providers["claude"]?.totals.input = Int64.max
        XCTAssertEqual(MeshAccounting.combine([a], at: now).total(for: nil), .zero)
        a = machine("machine-a"); a.snapshot?.observedAt += 600
        XCTAssertNil(MeshAccounting.combine([a], at: now).rate(for: nil))
    }
    func testImportingAndPausedRemoteSourcesAreNotReportedAsIdle() {
        var a = machine("machine-a")
        a.snapshot?.providers["claude"]?.health = "importing"
        XCTAssertTrue(MeshAccounting.combine([a], at: now).importing)
        XCTAssertNil(MeshAccounting.combine([a], at: now).rate(for: nil))
        a.snapshot?.providers["claude"]?.health = "paused"
        XCTAssertNil(MeshAccounting.combine([a], at: now).rate(for: nil))
        XCTAssertFalse(MeshAccounting.combine([a], at: now).importing)
    }
    func testEndpointTransportRestrictions() {
        for endpoint in ["https://meter.example.com", "http://127.0.0.1:8787", "http://100.100.1.2:8790", "http://[fd7a:115c:a1e0::1]:8790"] {
            XCTAssertNotNil(MeshAPI.endpoint(endpoint), endpoint)
        }
        for endpoint in ["http://example.com", "http://0100.64.0.1", "http://+127.0.0.1", "http://127.0.0.1.example.com", "http://100.64.0.1.example.com", "http://192.168.1.2", "https://user:key@example.com", "https://example.com/path", "https://example.com?token=secret", "file:///tmp/test"] {
            XCTAssertNil(MeshAPI.endpoint(endpoint), endpoint)
        }
    }
}
