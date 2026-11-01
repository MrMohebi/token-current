#if os(macOS)
import SwiftUI
import TokenCurrentCore

struct MeterPopover: View {
    @Bindable var model: MonitorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var rateSize = 48

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 22) {
                    measurement
                    ThroughputGraph(snapshot: model.snapshot, providers: model.selectedProviders)
                    Picker("Show usage for", selection: $model.filter) {
                        ForEach(SourceFilter.allCases) { filter in Text(filter.title).tag(filter) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if model.mesh.isEnabled { MeshMap(mesh: model.mesh) }
                    providerRows
                    Divider()
                    today
                    if let message = model.displayedError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else if !model.hasMeasurement && !model.snapshot.importing {
                        Text("Start a Claude Code or Codex session. Usage appears when the tool writes its next update. Check source folders in Settings if nothing appears.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .frame(height: model.displayedError != nil || !model.hasMeasurement ? 550 : 520)
            Divider()
            footer
        }
        .frame(width: 360)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
        }
    }

    private var header: some View {
        HStack {
            Label("Token Current", systemImage: "arrow.up.arrow.down")
                .font(.headline)
            Spacer(minLength: 8)
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var measurement: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(TokenFormat.rate(model.rate))
                    .font(.system(size: rateSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("tok/s")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.rate.map { "\(TokenFormat.compact($0)) reported tokens per second" } ?? "No current measurement")
            Text("Reported usage · 10s average")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.rate)
    }

    private var providerRows: some View {
        VStack(spacing: 13) {
            ForEach(model.selectedProviders) { provider in
                ProviderRow(provider: provider, snapshot: model.snapshot)
            }
        }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(model.mesh.isEnabled ? "Today · UTC" : "Today").font(.headline)
                Spacer()
                Text(model.filter.title).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                counter("Input", value: model.totals.input)
                Spacer(minLength: 0)
                counter("Output", value: model.totals.output)
                Spacer(minLength: 0)
                counter("Cached*", value: model.totals.cached)
            }
            Text("*Included in input. Counts come from usage logs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func counter(_ title: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(model.hasTotals ? TokenFormat.compact(Double(value)) : "—")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.hasTotals ? "\(title), \(value.formatted()) tokens today" : "\(title), no measurement")
    }

    private var footer: some View {
        HStack {
            Button(model.isPaused ? "Resume local" : "Pause local", systemImage: model.isPaused ? "play" : "pause") {
                Task { await model.togglePause() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            .keyboardShortcut(",", modifiers: .command)
            Menu("More", systemImage: "ellipsis") {
                Button("Quit Token Current", systemImage: "power") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }
}
#endif
