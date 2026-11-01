import Foundation

public struct SourceConfiguration: Codable, Equatable, Sendable {
    public var claudeHome: String
    public var codexHome: String

    public init(claudeHome: String = "~/.claude", codexHome: String = "~/.codex") {
        self.claudeHome = claudeHome
        self.codexHome = codexHome
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
