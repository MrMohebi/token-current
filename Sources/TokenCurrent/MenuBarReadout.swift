#if os(macOS)
import SwiftUI

struct MenuBarReadout: View {
    let model: MonitorModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: model.isPaused ? "pause" : "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .medium))
            if model.density != .icon {
                Text(TokenFormat.rate(model.rate))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 47, alignment: .trailing)
                if model.density == .standard {
                    Text("tok/s").font(.system(size: 10))
                }
            }
        }
        .frame(width: model.density == .icon ? 18 : model.density == .compact ? 68 : 101)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token Current, \(model.status), \(model.rate.map { "\(TokenFormat.compact($0)) reported tokens per second" } ?? "no current measurement")")
        .help("Token Current · \(model.filter.title) · \(model.status)")
    }
}
#endif
