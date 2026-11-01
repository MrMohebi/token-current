#if os(macOS)
import SwiftUI
import Charts
import TokenCurrentCore

struct ThroughputGraph: View {
    let snapshot: MonitorSnapshot
    let providers: [Provider]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleProviders: [Provider] {
        providers.filter { snapshot.health[$0]?.isMeasurable == true }
    }

    var body: some View {
        VStack(spacing: 8) {
            Chart {
                ForEach(visibleProviders) { provider in
                    ForEach(snapshot.graph) { point in
                        LineMark(x: .value("Time", point.time),
                                 y: .value("Reported tokens per second", point.rate(for: provider)),
                                 series: .value("Provider", provider.name))
                        .foregroundStyle(InstrumentPalette.color(for: provider, scheme: scheme))
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round,
                                               dash: provider == .codex ? [4, 3] : []))
                        .interpolationMethod(.linear)
                    }
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.quaternary)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: 0...max(1, peak))
            .chartXScale(domain: snapshot.timestamp.addingTimeInterval(-59)...snapshot.timestamp)
            .frame(height: 100)
            .opacity(snapshot.paused ? 0.4 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: snapshot.timestamp)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reported token usage over the last 60 seconds. Solid line: Claude. Dashed line: Codex. Peak \(TokenFormat.compact(peak)) tokens per second.")
            HStack {
                Text("60 seconds")
                Spacer()
                Text(snapshot.paused ? "Paused" : "Now")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var peak: Double {
        snapshot.graph.flatMap { point in visibleProviders.map { point.rate(for: $0) } }.max() ?? 0
    }
}
#endif
