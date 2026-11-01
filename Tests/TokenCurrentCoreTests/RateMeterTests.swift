import Foundation
import XCTest
@testable import TokenCurrentCore

final class RateMeterTests: XCTestCase {
    func testRollingWindowAndProviderIsolation() {
        let time = Date(timeIntervalSince1970: 100)
        var meter = RateMeter()
        meter.record(1_000, provider: .claude, at: time)
        meter.record(500, provider: .codex, at: time.addingTimeInterval(1))
        XCTAssertEqual(meter.rate(provider: .claude, at: time), 100)
        XCTAssertEqual(meter.rate(provider: .codex, at: time), 0)
        XCTAssertEqual(meter.rate(provider: .codex, at: time.addingTimeInterval(1)), 50)
        XCTAssertEqual(meter.rate(provider: .claude, at: time.addingTimeInterval(10)), 0)
        XCTAssertEqual(meter.graph(at: time).count, 60)
        meter.reset()
        XCTAssertEqual(meter.rate(provider: .claude, at: time), 0)
    }

    func testUnavailableIsDifferentFromIdleAndPartialData() {
        var snapshot = MonitorSnapshot(health: [.claude: .ready, .codex: .missing],
                                       rates: [.claude: 0], importing: false)
        XCTAssertEqual(snapshot.rate(for: nil), 0)
        XCTAssertNil(snapshot.rate(for: .codex))
        snapshot.paused = true
        XCTAssertNil(snapshot.rate(for: nil))
        snapshot.paused = false
        snapshot.importing = true
        XCTAssertNil(snapshot.rate(for: nil))
    }
}
