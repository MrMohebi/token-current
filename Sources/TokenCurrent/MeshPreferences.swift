#if os(macOS)
import Foundation

enum MeshMode: String, Codable, CaseIterable, Identifiable {
    case local, tailscale, relay
    var id: String { rawValue }
    var title: String {
        switch self { case .local: "This Mac"; case .tailscale: "Tailscale"; case .relay: "Self-hosted relay" }
    }
}
struct PairedMachine: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var url: String
    var trustsTailscale: Bool? = nil
}
struct MeshPreferences: Codable {
    var mode: MeshMode = .local
    var localID = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    var localName = Host.current().localizedName ?? "This Mac"
    var relayURL = ""
    var relayLocalID: String?
    var peers: [PairedMachine] = []
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "networkPreferences"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "networkPreferences") } }
}
#endif
