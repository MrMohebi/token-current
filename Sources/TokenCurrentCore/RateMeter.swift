import Foundation

public struct RatePoint: Equatable, Sendable, Identifiable {
    public let time: Date
    public let claude: Double
    public let codex: Double
    public var id: Date { time }
    public init(time: Date, claude: Double, codex: Double) {
        self.time = time
        self.claude = claude
        self.codex = codex
    }
    public func rate(for provider: Provider) -> Double { provider == .claude ? claude : codex }
}

public struct RateMeter: Sendable {
    public static let window: TimeInterval = 10
    private struct Receipt: Sendable { let time: Date; let provider: Provider; let tokens: Int64 }
    private var receipts: [Receipt] = []
    public init() {}

    public mutating func record(_ tokens: Int64, provider: Provider, at time: Date) {
        if tokens > 0 { receipts.append(Receipt(time: time, provider: provider, tokens: tokens)) }
        receipts.removeAll { $0.time <= time.addingTimeInterval(-70) }
    }

    public func rate(provider: Provider, at time: Date) -> Double {
        Double(receipts.filter {
            $0.provider == provider && $0.time > time.addingTimeInterval(-Self.window) && $0.time <= time
        }.reduce(Int64(0)) { $0 + $1.tokens }) / Self.window
    }

    public func graph(at time: Date) -> [RatePoint] {
        (0..<60).map { index in
            let date = time.addingTimeInterval(Double(index - 59))
            return RatePoint(time: date, claude: rate(provider: .claude, at: date), codex: rate(provider: .codex, at: date))
        }
    }

    public mutating func reset() { receipts.removeAll() }
}
