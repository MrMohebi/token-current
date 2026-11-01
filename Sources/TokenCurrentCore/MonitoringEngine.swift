import Foundation

public actor MonitoringEngine {
    private let storage: SQLiteStore
    private var configuration: SourceConfiguration
    private var files: [Provider: [URL]] = [:]
    private var directories: [URL] = []
    private var health: [Provider: SourceHealth] = [:]
    private var meter = RateMeter()
    private var nextDiscovery = Date.distantPast
    private var initialScan = true
    private var backfilling: Set<String> = []
    private var paused = false
    private var suppressLive = true
    private var lastTick: Date?
    private var dayStart = Date.distantPast

    public init(databasePath: String, configuration: SourceConfiguration = SourceConfiguration()) throws {
        self.storage = try SQLiteStore(path: databasePath)
        self.configuration = configuration
    }

    public func configure(_ value: SourceConfiguration) {
        configuration = value
        files.removeAll()
        health.removeAll()
        initialScan = true
        backfilling.removeAll()
        meter.reset()
        suppressLive = true
        nextDiscovery = .distantPast
    }

    public func setPaused(_ value: Bool) {
        paused = value
        meter.reset()
        suppressLive = true
    }

    public func clearHistory() throws {
        try storage.clearHistory()
        meter.reset()
    }

    public func requestDiscovery() { nextDiscovery = .distantPast }
    public func watchedDirectories() -> [URL] { directories }

    public func tick(at now: Date = .now, calendar: Calendar = .current) throws -> MonitorSnapshot {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        if start != dayStart {
            dayStart = start
            nextDiscovery = .distantPast
            try storage.pruneHistory(before: start)
        }
        // Sleep/wake and large clock changes must not replay accumulated usage as live throughput.
        if let lastTick, now.timeIntervalSince(lastTick) > 5 || now < lastTick {
            suppressLive = true
            meter.reset()
        }
        lastTick = now
        if !paused {
            if now >= nextDiscovery {
                try discover(since: start)
                nextDiscovery = now.addingTimeInterval(30)
            }
            for provider in Provider.allCases {
                for url in files[provider] ?? [] {
                    do {
                        try consume(url, provider: provider, now: now, dayStart: start)
                    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                        health[provider] = .permissionDenied
                    } catch let error as StorageError {
                        throw error
                    } catch {
                        health[provider] = .failed("Could not read a log. Check the source folder.")
                        nextDiscovery = .distantPast
                    }
                }
            }
            initialScan = false
            suppressLive = false
        }
        var totals: [Provider: TokenCounts] = [:]
        var rates: [Provider: Double] = [:]
        for provider in Provider.allCases {
            totals[provider] = try storage.totals(provider: provider, from: start, to: end)
            rates[provider] = meter.rate(provider: provider, at: now)
        }
        return MonitorSnapshot(timestamp: now, health: health, totals: totals, rates: rates,
                               graph: meter.graph(at: now), paused: paused,
                               importing: initialScan || !backfilling.isEmpty)
    }

    private func consume(_ url: URL, provider: Provider, now: Date, dayStart: Date) throws {
        let saved = try storage.checkpoint(path: url.path)
        var batch = try FileTailer().read(url, checkpoint: saved)
        if initialScan || suppressLive { backfilling.insert(url.path) }
        let live = !suppressLive && !backfilling.contains(url.path)
        var reported = TokenCounts.zero
        if batch.checkpoint != saved || !batch.lines.isEmpty { try storage.transaction {
            for line in batch.lines {
                switch LogParser().parse(line, provider: provider, fileID: url.path, context: &batch.checkpoint.context) {
                case .observation(let observation):
                    batch.checkpoint.recognized = true
                    batch.checkpoint.unsupported = false
                    let delta = try storage.apply(observation, since: dayStart)
                    if live { reported = reported + delta }
                case .unsupported, .malformed:
                    batch.checkpoint.unsupported = true
                case .ignored, .metadata: break
                }
            }
            try storage.save(batch.checkpoint, path: url.path)
        } }
        if !batch.hasMore { backfilling.remove(url.path) }
        if health[provider] != .permissionDenied {
            if batch.checkpoint.unsupported { health[provider] = .unsupported }
            else if batch.checkpoint.recognized { health[provider] = .ready }
        }
        if live { meter.record(reported.total, provider: provider, at: now) }
    }

    private func discover(since dayStart: Date) throws {
        let manager = FileManager.default
        directories = []
        for provider in Provider.allCases {
            files[provider] = []
            var foundRoot = false
            var accessDenied = false
            let knownUsage = try storage.hasUsage(provider: provider)
            health[provider] = knownUsage ? .ready : .waiting
            for root in configuration.roots(for: provider) {
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    // Watch an existing ancestor so installing a client wakes discovery promptly.
                    var ancestor = root.deletingLastPathComponent()
                    while !manager.fileExists(atPath: ancestor.path), ancestor.path != "/" {
                        ancestor.deleteLastPathComponent()
                    }
                    directories.append(ancestor)
                    continue
                }
                foundRoot = true
                guard manager.isReadableFile(atPath: root.path) else { accessDenied = true; continue }
                directories.append(root)
                guard let enumerator = manager.enumerator(at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles], errorHandler: { _, _ in accessDenied = true; return true }) else {
                    accessDenied = true
                    continue
                }
                for case let url as URL in enumerator {
                    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey]) else { continue }
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if values.isDirectory == true { directories.append(url); continue }
                    if values.isRegularFile == true, url.pathExtension == "jsonl",
                       (values.contentModificationDate ?? .distantPast) >= dayStart {
                        files[provider, default: []].append(url)
                    }
                }
            }
            if !foundRoot { health[provider] = .missing }
            else if accessDenied { health[provider] = .permissionDenied }
            files[provider]?.sort { $0.path < $1.path }
        }
        directories = Array(Set(directories)).sorted { $0.path < $1.path }
    }
}
