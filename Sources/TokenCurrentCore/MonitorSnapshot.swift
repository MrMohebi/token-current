import Foundation

public struct MonitorSnapshot: Sendable {
    public var timestamp: Date
    public var health: [Provider: SourceHealth]
    public var totals: [Provider: TokenCounts]
    public var rates: [Provider: Double]
    public var graph: [RatePoint]
    public var paused: Bool
    public var importing: Bool

    public init(timestamp: Date = .now, health: [Provider: SourceHealth] = [:],
                totals: [Provider: TokenCounts] = [:], rates: [Provider: Double] = [:],
                graph: [RatePoint] = [], paused: Bool = false, importing: Bool = true) {
        self.timestamp = timestamp
        self.health = health
        self.totals = totals
        self.rates = rates
        self.graph = graph
        self.paused = paused
        self.importing = importing
    }

    public func rate(for provider: Provider?) -> Double? {
        guard !paused, !importing else { return nil }
        let selected = provider.map { [$0] } ?? Provider.allCases
        let available = selected.filter { health[$0]?.isMeasurable == true }
        guard !available.isEmpty else { return nil }
        return available.reduce(0) { $0 + (rates[$1] ?? 0) }
    }

    public func total(for provider: Provider?) -> TokenCounts {
        let selected = provider.map { [$0] } ?? Provider.allCases
        return selected.reduce(.zero) { $0 + (totals[$1] ?? .zero) }
    }
}
