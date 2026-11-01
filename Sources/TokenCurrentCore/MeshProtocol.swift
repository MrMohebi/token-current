import Foundation

public struct NetworkProvider: Codable, Sendable {
    public var health: String
    public var rate: Double
    public var totals: TokenCounts
    public init(health: String, rate: Double, totals: TokenCounts) {
        self.health = health; self.rate = rate; self.totals = totals
    }
}

public struct NetworkSnapshot: Codable, Sendable {
    public var id: String
    public var name: String
    public var platform: String
    public var bootID: String
    public var sequence: UInt64
    public var day: String
    public var observedAt: Double
    public var providers: [String: NetworkProvider]

    public init(id: String, name: String, bootID: String, sequence: UInt64, local: MonitorSnapshot) {
        self.id = id; self.name = name.isEmpty ? "This Mac" : String(name.prefix(80)); platform = "darwin"
        while self.name.utf8.count > 80 { self.name.removeLast() }
        self.bootID = bootID; self.sequence = sequence
        observedAt = local.timestamp.timeIntervalSince1970
        day = Self.utcDay(local.timestamp)
        providers = Dictionary(uniqueKeysWithValues: Provider.allCases.map { p in
            let health = local.paused && local.health[p] == .ready ? "paused" : local.importing ? "importing" : Self.wireHealth(local.health[p])
            return (p.rawValue, NetworkProvider(health: health, rate: local.rate(for: p) ?? 0, totals: local.totals[p] ?? .zero))
        })
    }

    public static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public func isValid(at now: Date) -> Bool {
        guard id.count >= 8, id.count <= 80, name.count <= 80, !name.isEmpty,
              observedAt.isFinite, observedAt > 0, observedAt <= now.timeIntervalSince1970 + 300,
              day == Self.utcDay(Date(timeIntervalSince1970: observedAt)), providers.count == 2 else { return false }
        return Provider.allCases.allSatisfy { p in
            guard let v = providers[p.rawValue] else { return false }
            let c = v.totals
            return v.rate.isFinite && v.rate >= 0 && v.rate <= 1e12 &&
                [c.input, c.output, c.cacheRead, c.cacheWrite].allSatisfy { $0 >= 0 && $0 <= 1_000_000_000_000_000 } &&
                c.cacheRead + c.cacheWrite <= c.input
        }
    }

    private static func wireHealth(_ health: SourceHealth?) -> String {
        switch health {
        case .ready: "ready"
        case .missing: "missing"
        case .unsupported: "unsupported"
        case .permissionDenied: "permissionDenied"
        case .failed: "unsupported"
        default: "waiting"
        }
    }
}

public struct NetworkMachine: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var platform: String
    public var receivedAt: Double
    public var online: Bool
    public var snapshot: NetworkSnapshot?
    public init(snapshot: NetworkSnapshot) {
        id = snapshot.id; name = snapshot.name; platform = snapshot.platform
        receivedAt = snapshot.observedAt; online = true; self.snapshot = snapshot
    }
    public func isOnline(at now: Date) -> Bool {
        guard online, let snapshot, snapshot.isValid(at: now) else { return false }
        let t = now.timeIntervalSince1970
        return t - receivedAt < 15 && t - snapshot.observedAt < 15
    }
}

public struct NetworkMesh: Codable, Sendable {
    public var serverTime: Double
    public var machines: [NetworkMachine]
}

public struct NetworkEnrollment: Codable, Sendable {
    public var id: String
    public var token: String
}

public enum MeshAccounting {
    public static func combine(_ machines: [NetworkMachine], selectedID: String = "all", at now: Date) -> MonitorSnapshot {
        var result = MonitorSnapshot(timestamp: now, importing: false)
        var seen: Set<String> = []
        var importing = false
        for machine in machines.prefix(128) where selectedID == "all" || machine.id == selectedID {
            guard seen.insert(machine.id).inserted, let s = machine.snapshot,
                  s.id == machine.id, s.isValid(at: now), s.day == NetworkSnapshot.utcDay(now) else { continue }
            for p in Provider.allCases {
                guard let value = s.providers[p.rawValue] else { continue }
                if machine.isOnline(at: now) && value.health == "importing" { importing = true }
                result.totals[p] = (result.totals[p] ?? .zero) + value.totals
                if machine.isOnline(at: now) && value.health == "ready" {
                    result.health[p] = .ready
                    result.rates[p, default: 0] += value.rate
                } else if result.health[p] != .ready {
                    result.health[p] = value.health == "unsupported" ? .unsupported : .waiting
                }
            }
        }
        result.importing = importing && !result.health.values.contains(.ready)
        return result
    }
}
