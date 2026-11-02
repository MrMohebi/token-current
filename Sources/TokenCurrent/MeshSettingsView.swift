#if os(macOS)
import SwiftUI
import TokenCurrentCore

struct MeshSettingsView: View {
    @Bindable var mesh: MeshController
    @State private var relayToken = ""
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var newMachineName = ""
    @State private var pendingRemoval: NetworkMachine?
    @State private var pendingRotation: NetworkMachine?
    var body: some View {
        Form {
            Section {
                Picker("Connection", selection: $mesh.mode) {
                    ForEach(MeshMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                TextField("This Mac’s name", text: $mesh.localName)
                Text("Direct mode reads each paired machine over your tailnet. Relay mode publishes usage to your own server. Network totals use UTC; local-only mode uses your Mac’s day.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Your machines, one meter") }
            if mesh.mode == .tailscale {
                Section {
                    Button("Find machines") { Task { await mesh.discover() } }.disabled(mesh.busy)
                    ForEach(mesh.discovered) { peer in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(peer.HostName)
                                Text(peer.Online ? "Online" : "Offline").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let address = peer.url {
                                if mesh.peers.contains(where: { $0.url == address }) {
                                    Label("Connected", systemImage: "checkmark.circle").font(.caption)
                                } else {
                                    Button("Connect") { Task { await mesh.connectTailscale(name: peer.HostName, address: address) } }
                                        .disabled(mesh.busy || !peer.Online)
                                }
                            }
                        }
                    }
                    Text("Your tailnet handles access. Connect a machine running the agent. No pairing token, certificates, or relay needed.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Server Tailscale IP", text: $url, prompt: Text("100.x.y.z"))
                        Button(mesh.busy ? "Connecting…" : "Connect") {
                            Task {
                                await mesh.connectTailscale(name: "", address: url)
                                if mesh.error == nil { url = "" }
                            }
                        }.disabled(mesh.busy || url.isEmpty)
                    }
                    DisclosureGroup("Advanced: older agents with tokens") {
                        TextField("Machine name", text: $name)
                        TextField("Legacy agent URL", text: $url)
                        SecureField("Pairing token", text: $token)
                        Button("Pair with token") {
                            mesh.pair(name: name, url: url, token: token)
                            if mesh.error == nil { name = ""; url = ""; token = "" }
                        }.disabled(url.isEmpty || token.isEmpty)
                    }
                    ForEach(mesh.peers) { peer in
                        HStack {
                            VStack(alignment: .leading) { Text(peer.name); Text(peer.url).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Unpair", role: .destructive) { mesh.unpair(peer.id) }
                        }
                    }
                    Link("Agent installation & Tailscale setup", destination: URL(string: "https://github.com/MrMohebi/token-current/blob/main/docs/NETWORK.md#direct-tailscale-mode")!)
                } header: { Text("Tailscale connections") }
            }
            if mesh.mode == .relay {
                Section {
                    TextField("Relay URL", text: $mesh.relayURL, prompt: Text("https://tokens.example.com"))
                    SecureField("Management token", text: $relayToken)
                    Button("Save relay connection") {
                        mesh.connectRelay(token: relayToken)
                        if mesh.error == nil { relayToken = "" }
                    }.disabled(relayToken.isEmpty)
                    if !mesh.isPublishing {
                        Button("Add this Mac to relay") { Task { await mesh.enroll(name: mesh.localName, platform: "darwin", thisMac: true) } }
                            .disabled(mesh.busy)
                    } else {
                        Label("This Mac publishes to the relay", systemImage: "checkmark.circle")
                    }
                    HStack {
                        TextField("New machine name", text: $newMachineName)
                        Button("Create device token") { Task { await mesh.enroll(name: newMachineName) } }
                            .disabled(mesh.busy || newMachineName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Paste the device token into token-current-agent configure on that machine. The management token stays in your Mac’s Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(mesh.relayMachines) { machine in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(machine.name)
                                Text(machine.isOnline(at: .now) ? "Online" : "Waiting or offline").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu("Manage") {
                                Button("Rotate device token…") { pendingRotation = machine }
                                Button("Remove machine…", role: .destructive) { pendingRemoval = machine }
                            }.fixedSize()
                        }
                    }
                    Link("Open browser dashboard", destination: MeshAPI.endpoint(mesh.relayURL) ?? URL(string: "https://github.com/MrMohebi/token-current")!)
                } header: { Text("Self-hosted relay") }
            }
            if let issued = mesh.issuedToken {
                Section {
                    Text("Copy this device token now. It is shown once and grants publishing access to one machine.").font(.caption)
                    Text(issued).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button("Copy token") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(issued, forType: .string) }
                        Button("Done") { mesh.issuedToken = nil }
                    }
                } header: { Text("Device token") }
            }
            if let error = mesh.error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
            Section {
                Text("Only machine names, source status, token counts, and rates travel over the network. Prompts, responses, and AI account credentials stay on each machine. Pause in the meter pauses this Mac’s collection; remote agents keep running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: mesh.mode) {
            if mesh.mode == .tailscale && mesh.discovered.isEmpty { await mesh.discover() }
        }
        .confirmationDialog("Remove \(pendingRemoval?.name ?? "machine")?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove and revoke token", role: .destructive) { if let m = pendingRemoval { Task { await mesh.remove(m.id) } }; pendingRemoval = nil }
        }
        .confirmationDialog("Rotate \(pendingRotation?.name ?? "machine")’s token?", isPresented: Binding(get: { pendingRotation != nil }, set: { if !$0 { pendingRotation = nil } }), titleVisibility: .visible) {
            Button("Rotate token") { if let m = pendingRotation { Task { await mesh.rotate(m.id) } }; pendingRotation = nil }
        } message: { Text("The existing token stops working immediately. Configure the agent with its replacement.") }
    }
}
#endif
