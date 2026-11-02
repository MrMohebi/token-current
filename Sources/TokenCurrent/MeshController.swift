#if os(macOS)
import SwiftUI
import TokenCurrentCore

@Observable @MainActor
final class MeshController {
    private var settings: MeshPreferences
    private var task: Task<Void, Never>?
    private var generation = 0
    private let bootID = UUID().uuidString
    private var sequence: UInt64 = 0
    private var local: NetworkSnapshot?
    private var remote: [NetworkMachine] = []
    private var graph: [RatePoint] = []
    private var graphSelection = ""
    var mode: MeshMode { didSet { settings.mode = mode; changed() } }
    var selectedID = "all"
    var relayURL: String
    var localName: String { didSet { settings.localName = localName; settings.save() } }
    var peers: [PairedMachine] { settings.peers }
    var machines: [NetworkMachine] = []
    var discovered: [TailnetPeer] = []
    var error: String?
    var busy = false
    var issuedToken: String?
    var isEnabled: Bool { mode != .local }
    var relayMachines: [NetworkMachine] { remote }
    var isPublishing: Bool { settings.relayLocalID != nil }

    init() {
        let p = MeshPreferences.load()
        settings = p; mode = p.mode; relayURL = p.relayURL; localName = p.localName
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    private func changed() {
        generation += 1; remote = []; machines = []; graph = []; selectedID = "all"
        settings.save(); error = nil; issuedToken = nil
    }
    func connectRelay(token: String) {
        do {
            _ = try MeshAPI(origin: relayURL, token: token)
            let origin = MeshAPI.endpoint(relayURL)!.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if settings.relayURL != origin {
                settings.relayLocalID = nil; PairingKeychain.remove("publisher")
            }
            try PairingKeychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines), account: "relay")
            settings.relayURL = origin; relayURL = origin; changed()
        } catch { self.error = error.localizedDescription }
    }
    func pair(name: String, url: String, token: String) {
        do {
            guard settings.peers.count < 32 else { throw MeshAPIError.invalid }
            let key = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let api = try MeshAPI(origin: url, token: key)
            let origin = api.origin.absoluteString
            let id = settings.peers.first(where: { $0.url == origin })?.id ?? UUID().uuidString
            try PairingKeychain.save(key, account: id)
            settings.peers.removeAll { $0.id == id }
            settings.peers.append(PairedMachine(id: id, name: name.isEmpty ? api.origin.host() ?? "Machine" : name, url: origin))
            changed()
        } catch { self.error = error.localizedDescription }
    }
    func connectTailscale(name: String, address: String) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let version = generation
        do {
            guard let origin = MeshAPI.tailscaleOrigin(address) else {
                error = "Enter the server’s Tailscale IP, such as 100.64.0.10."
                return
            }
            let api = try MeshAPI(origin: origin, trustTailscale: true)
            let mesh = try await api.mesh()
            guard mesh.machines.count == 1, let machine = mesh.machines.first else { throw MeshAPIError.invalid }
            guard version == generation else { return }
            guard settings.peers.count < 32 || settings.peers.contains(where: { $0.url == origin }) else { throw MeshAPIError.invalid }
            var aliases: Set<String> = [api.origin.host() ?? ""]
            for peer in discovered where peer.url == origin {
                aliases.formUnion(peer.TailscaleIPs)
                aliases.insert(peer.DNSName.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            let replaced = settings.peers.filter { peer in
                aliases.contains(URL(string: peer.url)?.host()?.lowercased() ?? "")
            }
            let id = replaced.first?.id ?? UUID().uuidString
            let replacedIDs = Set(replaced.map(\.id))
            settings.peers.removeAll { replacedIDs.contains($0.id) }
            settings.peers.append(PairedMachine(id: id, name: name.isEmpty ? machine.name : name, url: origin, trustsTailscale: true))
            changed()
            remote = [machine]
        } catch let failure as MeshAPIError {
            if case .rejected(401) = failure { error = "This agent still requires a token. Update it and run token-current-agent tailscale, then restart its service." }
            else { error = failure.localizedDescription }
        } catch {
            self.error = "Cannot reach the agent at \(address). Run token-current-agent tailscale on that server, then restart its service. \(error.localizedDescription)"
        }
    }
    func unpair(_ id: String) {
        let usedToken = settings.peers.first(where: { $0.id == id })?.trustsTailscale != true
        settings.peers.removeAll { $0.id == id }
        if usedToken { PairingKeychain.remove(id) }
        changed()
    }
    func discover() async {
        busy = true; defer { busy = false }
        do { discovered = try await TailscaleDiscovery.discover(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func relayAPI() throws -> MeshAPI {
        try MeshAPI(origin: settings.relayURL, token: PairingKeychain.read("relay") ?? "")
    }
    func enroll(name: String, platform: String = "", thisMac: Bool = false) async {
        busy = true; defer { busy = false }
        let version = generation
        do {
            let enrollment = try await relayAPI().enroll(name: name, platform: platform)
            guard version == generation else { return }
            if thisMac {
                try PairingKeychain.save(enrollment.token, account: "publisher")
                settings.relayLocalID = enrollment.id; settings.save()
            } else { issuedToken = enrollment.token }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ id: String) async {
        do {
            try await relayAPI().remove(id: id)
            remote.removeAll { $0.id == id }
            if selectedID == id { selectedID = "all" }
            if settings.relayLocalID == id { settings.relayLocalID = nil; PairingKeychain.remove("publisher"); settings.save() }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func rotate(_ id: String) async {
        do {
            let enrollment = try await relayAPI().rotate(id: id)
            if settings.relayLocalID == id { try PairingKeychain.save(enrollment.token, account: "publisher") }
            else { issuedToken = enrollment.token }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func update(local snapshot: MonitorSnapshot, available: Bool) -> MonitorSnapshot {
        sequence += 1
        let id = mode == .relay ? settings.relayLocalID ?? settings.localID : settings.localID
        let sample = NetworkSnapshot(id: id, name: localName, bootID: bootID, sequence: sequence, local: snapshot)
        local = available ? sample : nil
        var result: [NetworkMachine] = []
        if available { result.append(NetworkMachine(snapshot: sample)) }
        var seen = Set(result.map(\.id))
        for machine in remote where seen.insert(machine.id).inserted { result.append(machine) }
        machines = result
        var combined = MeshAccounting.combine(result, selectedID: selectedID, at: snapshot.timestamp)
        let selection = "\(mode.rawValue):\(selectedID)"
        if selection != graphSelection { graph = []; graphSelection = selection }
        graph.removeAll { snapshot.timestamp.timeIntervalSince($0.time) >= 60 || $0.time >= snapshot.timestamp }
        graph.append(RatePoint(time: snapshot.timestamp, claude: combined.rates[.claude] ?? 0, codex: combined.rates[.codex] ?? 0))
        combined.graph = graph
        return combined
    }
    private func poll() async {
        guard isEnabled else { return }
        let version = generation
        if mode == .relay {
            do {
                let api = try relayAPI()
                var publishError: String?
                if let local, settings.relayLocalID != nil, let token = PairingKeychain.read("publisher") {
                    do { try await MeshAPI(origin: settings.relayURL, token: token).publish(local) }
                    catch { publishError = "This Mac could not publish. Rotate its token or check the relay connection." }
                }
                let mesh = try await api.mesh()
                guard version == generation else { return }
                remote = Array(mesh.machines.prefix(128)); error = publishError
            } catch { if version == generation { self.error = error.localizedDescription } }
        } else {
            let connections = settings.peers.compactMap { peer -> (PairedMachine, String)? in
                if peer.trustsTailscale == true { return (peer, "") }
                return PairingKeychain.read(peer.id).map { (peer, $0) }
            }
            let results = await withTaskGroup(of: (String, NetworkMachine?, String?).self) { group in
                for (peer, token) in connections {
                    group.addTask {
                        do {
                            let mesh = try await MeshAPI(origin: peer.url, token: token, trustTailscale: peer.trustsTailscale == true).mesh()
                            guard mesh.machines.count == 1, let machine = mesh.machines.first else { throw MeshAPIError.invalid }
                            return (peer.id, machine, nil)
                        } catch { return (peer.id, nil, "\(peer.name): \(error.localizedDescription). Check that its agent service is running.") }
                    }
                }
                var collected: [(String, NetworkMachine?, String?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            guard version == generation else { return }
            // Retain last known totals on transient failures; freshness gates live rates.
            for (_, machine, _) in results {
                if let machine { remote.removeAll { $0.id == machine.id }; remote.append(machine) }
            }
            error = results.compactMap { $0.2 }.first
        }
    }
}
#endif
