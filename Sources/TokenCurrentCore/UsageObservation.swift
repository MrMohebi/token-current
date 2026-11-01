import Foundation

public struct UsageObservation: Equatable, Sendable {
    public let provider: Provider
    public let identity: String
    public let timestamp: Date
    public let counts: TokenCounts
    public let isBaseline: Bool
    public let initialBaseline: TokenCounts?

    public init(provider: Provider, identity: String, timestamp: Date, counts: TokenCounts,
                isBaseline: Bool = false, initialBaseline: TokenCounts? = nil) {
        self.provider = provider
        self.identity = identity
        self.timestamp = timestamp
        self.counts = counts
        self.isBaseline = isBaseline
        self.initialBaseline = initialBaseline
    }
}

public struct LogContext: Codable, Equatable, Sendable {
    public var sessionID: String?
    public var startedAt: Date?
    public var forked: Bool = false
    public var baselineSeen: Bool = false
    public init() {}
}

public enum ParseResult: Sendable {
    case observation(UsageObservation), metadata, ignored, unsupported, malformed
}
