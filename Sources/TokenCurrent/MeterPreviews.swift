#if os(macOS)
import SwiftUI
import TokenCurrentCore

/// Illustrative measurements for Xcode's canvas only. Never used by the running application.
@MainActor
private func previewModel() -> MonitorModel {
    let model = MonitorModel(startMonitoring: false)
    let now = Date.now
    let graph = (0..<60).map { index in
        RatePoint(time: now.addingTimeInterval(Double(index - 59)),
                  claude: max(0, sin(Double(index) * 0.2) * 800 + 800),
                  codex: max(0, cos(Double(index) * 0.3) * 400 + 400))
    }
    model.snapshot = MonitorSnapshot(timestamp: now, health: [.claude: .ready, .codex: .ready],
        totals: [.claude: TokenCounts(input: 284_000, output: 32_000, cacheRead: 190_000)],
        rates: [.claude: 1_600, .codex: 800], graph: graph, importing: false)
    return model
}

#Preview("Illustrative data · light") {
    MeterPopover(model: previewModel()).environment(\.colorScheme, .light)
}
#Preview("Illustrative data · dark") {
    MeterPopover(model: previewModel()).environment(\.colorScheme, .dark)
}
#Preview("Waiting for sources") {
    MeterPopover(model: MonitorModel(startMonitoring: false))
}
#endif
