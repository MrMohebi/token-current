#if os(macOS)
import SwiftUI
import TokenCurrentCore

struct ProviderRow: View {
    let provider: Provider
    let snapshot: MonitorSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: provider == .claude ? "circle.fill" : "diamond.fill")
                .font(.system(size: 7))
                .foregroundStyle(InstrumentPalette.color(for: provider, scheme: scheme))
                .accessibilityHidden(true)
            Text(provider.name).font(.callout)
            Spacer(minLength: 8)
            if let rate = snapshot.rate(for: provider) {
                Text("\(TokenFormat.compact(rate))/s")
                    .font(.system(.callout, design: .monospaced))
            } else {
                Text(snapshot.paused ? "Paused" : snapshot.health[provider]?.label ?? "Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
