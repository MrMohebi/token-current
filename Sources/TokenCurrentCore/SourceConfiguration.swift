import Foundation

public struct SourceConfiguration: Codable, Equatable, Sendable {
    public var claudeHome: String
    public var codexHome: String

    public init(claudeHome: String = "~/.claude", codexHome: String = "~/.codex") {
        self.claudeHome = claudeHome
        self.codexHome = codexHome
    }

    /// First-launch discovery only. Explicitly saved source selections always take precedence.
    public static func autodetected(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Self {
        let manager = FileManager.default
        func expanded(_ value: String) -> URL {
            if value == "~" { return homeDirectory }
            if value.hasPrefix("~/") { return homeDirectory.appending(path: String(value.dropFirst(2))) }
            return URL(fileURLWithPath: value).standardizedFileURL
        }
        func override(_ key: String, child: String) -> URL? {
            let candidates = (environment[key] ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map(expanded)
                .map { $0.lastPathComponent == child ? $0.deletingLastPathComponent() : $0 }
            return candidates.first { manager.fileExists(atPath: $0.appending(path: child).path) } ?? candidates.first
        }
        let traditional = homeDirectory.appending(path: ".claude")
        let xdg = environment["XDG_CONFIG_HOME"].map(expanded) ?? homeDirectory.appending(path: ".config")
        let alternative = xdg.appending(path: "claude")
        let claude = override("CLAUDE_CONFIG_DIR", child: "projects") ??
            ([traditional, alternative].first { manager.fileExists(atPath: $0.appending(path: "projects").path) } ?? traditional)
        let codex = override("CODEX_HOME", child: "sessions") ?? homeDirectory.appending(path: ".codex")
        return Self(claudeHome: claude.path, codexHome: codex.path)
    }

    public func home(for provider: Provider) -> URL {
        let path = provider == .claude ? claudeHome : codexHome
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    public func roots(for provider: Provider) -> [URL] {
        let home = home(for: provider)
        return provider == .claude ? [home.appending(path: "projects")] :
            [home.appending(path: "sessions"), home.appending(path: "archived_sessions")]
    }
}
