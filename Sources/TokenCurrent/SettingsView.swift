#if os(macOS)
import SwiftUI
import ServiceManagement
import TokenCurrentCore

struct SettingsView: View {
    @Bindable var model: MonitorModel
    @State private var confirmsClear = false

    var body: some View {
        TabView {
            general.tabItem { Label("Local", systemImage: "laptopcomputer") }
            MeshSettingsView(mesh: model.mesh).tabItem { Label("Network", systemImage: "network") }
        }.frame(width: 600, height: 730)
    }

    private var general: some View {
        Form {
            Section {
                Picker("Menu bar display", selection: $model.density) {
                    ForEach(DisplayDensity.allCases) { item in Text(item.title).tag(item) }
                }
                Toggle("Launch at login", isOn: $model.wantsLaunchAtLogin)
                if model.needsLoginApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            } header: { Text("General") }

            Section {
                TextField("Claude data folder", text: $model.claudeHome)
                    .textFieldStyle(.roundedBorder)
                TextField("Codex data folder", text: $model.codexHome)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Choose Claude folder…") { chooseFolder(for: .claude) }
                    Button("Choose Codex folder…") { chooseFolder(for: .codex) }
                }
                HStack {
                    Text("Choose the home folder containing projects (Claude), or sessions and archived_sessions (Codex).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Apply folders") { Task { await model.applySources() } }
                        .disabled(model.isApplyingSources)
                }
                ForEach(Provider.allCases) { provider in
                    LabeledContent(provider.name, value: model.localSnapshot.health[provider]?.label ?? "Checking…")
                        .font(.caption)
                }
            } header: { Text("Local sources") }

            Section {
                Text("The meter refreshes each second and averages reported usage over 10 seconds. Logs can arrive in batches. Cached tokens are included in input; reasoning tokens are included in output when reported by the source.")
                    .font(.callout)
                Text("Token Current reads usage metadata locally. It does not retain prompts, responses, AI account credentials, or send telemetry. Optional network mode shares usage with your paired machines or relay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear local usage history…", role: .destructive) { confirmsClear = true }
            } header: { Text("Measurement & privacy") }

            if let error = model.displayedError {
                Section {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    if model.errorMessage != nil { Button("Dismiss") { model.errorMessage = nil } }
                }
            }

            Section {
                LabeledContent("Token Current", value: "1.1.0")
                Button("Quit Token Current") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginStatus()
        }
        .confirmationDialog("Clear local usage history?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { Task { await model.clearHistory() } }
        } message: {
            Text("This clears stored totals and the live graph. File checkpoints remain so previous usage stays cleared. New usage continues to count.")
        }
    }

    private func chooseFolder(for provider: Provider) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose the \(provider.name) data folder."
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: ((provider == .claude ? model.claudeHome : model.codexHome) as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            if provider == .claude { model.claudeHome = url.path }
            else { model.codexHome = url.path }
        }
    }
}
#endif
