import Foundation

public struct TokenCounts: Codable, Equatable, Sendable {
    public var input: Int64
    public var output: Int64
    public var cacheRead: Int64
    public var cacheWrite: Int64
    public var total: Int64 { input + output }
    public var cached: Int64 { cacheRead + cacheWrite }
    public static let zero = TokenCounts()

    public init(input: Int64 = 0, output: Int64 = 0, cacheRead: Int64 = 0, cacheWrite: Int64 = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
             cacheRead: lhs.cacheRead + rhs.cacheRead, cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }

    func highWater(against previous: Self) -> Self {
        Self(input: max(input, previous.input), output: max(output, previous.output),
             cacheRead: max(cacheRead, previous.cacheRead), cacheWrite: max(cacheWrite, previous.cacheWrite))
    }

    func increment(after previous: Self) -> Self {
        Self(input: max(0, input - previous.input), output: max(0, output - previous.output),
             cacheRead: max(0, cacheRead - previous.cacheRead), cacheWrite: max(0, cacheWrite - previous.cacheWrite))
    }
}
