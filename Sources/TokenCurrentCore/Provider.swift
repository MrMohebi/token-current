import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude, codex
    public var id: String { rawValue }
    public var name: String { self == .claude ? "Claude" : "Codex" }
}

public enum SourceHealth: Equatable, Sendable {
    case missing, waiting, ready, unsupported, permissionDenied, failed(String)

    public var isMeasurable: Bool { self == .ready }
    public var label: String {
        switch self {
        case .missing: "Not found"
        case .waiting: "Waiting for usage"
        case .ready: "Connected"
        case .unsupported: "Unsupported log format"
        case .permissionDenied: "Folder access denied"
        case .failed(let message): message
        }
    }
}
