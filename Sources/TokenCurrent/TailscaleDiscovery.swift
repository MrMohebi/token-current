#if os(macOS)
import Foundation
import TokenCurrentCore

struct TailnetPeer: Decodable, Identifiable, Sendable {
    var id: String { TailscaleIPs.first ?? DNSName }
    var HostName: String
    var DNSName: String
    var TailscaleIPs: [String]
    var Online: Bool
    var OS: String
    var url: String? { TailscaleIPs.compactMap { MeshAPI.tailscaleOrigin($0) }.first }
    private enum CodingKeys: String, CodingKey { case HostName, DNSName, TailscaleIPs, Online, OS }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        HostName = try c.decodeIfPresent(String.self, forKey: .HostName) ?? "Machine"
        DNSName = try c.decodeIfPresent(String.self, forKey: .DNSName) ?? ""
        TailscaleIPs = try c.decodeIfPresent([String].self, forKey: .TailscaleIPs) ?? []
        Online = try c.decodeIfPresent(Bool.self, forKey: .Online) ?? false
        OS = try c.decodeIfPresent(String.self, forKey: .OS) ?? ""
    }
}
enum TailscaleDiscovery {
    static func discover() async throws -> [TailnetPeer] {
        try await Task.detached {
            struct Status: Decodable { var BackendState: String; var Peer: [String: TailnetPeer]? }
            let candidates = ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
            guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw DiscoveryError.unavailable }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["status", "--json"]
            let pipe = Pipe()
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            try process.run()
            // Bound the subprocess, including disconnected client installations.
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); timeout.cancel()
            guard process.terminationStatus == 0 else { throw DiscoveryError.unavailable }
            let status = try JSONDecoder().decode(Status.self, from: data)
            guard status.BackendState == "Running" else { throw DiscoveryError.unavailable }
            return (status.Peer ?? [:]).values.filter { $0.url != nil }.sorted { $0.HostName < $1.HostName }
        }.value
    }
    enum DiscoveryError: Error, LocalizedError {
        case unavailable
        var errorDescription: String? { "Open Tailscale, sign in, and install its CLI. You can also paste a machine URL manually." }
    }
}
#endif
