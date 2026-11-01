import Foundation
import CSQLite

public struct StorageError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Owned by MonitoringEngine's actor; never shared with views or other executors.
public final class SQLiteStore {
    private var database: OpaquePointer?

    public init(path: String) throws {
        if path != ":memory:" {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            let error = failure()
            sqlite3_close(database)
            database = nil
            throw error
        }
        if path != ":memory:" { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        sqlite3_busy_timeout(database, 3_000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        try execute("""
            CREATE TABLE IF NOT EXISTS records (
                identity TEXT PRIMARY KEY, provider TEXT NOT NULL,
                input INTEGER NOT NULL, output INTEGER NOT NULL,
                cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY, provider TEXT NOT NULL, time REAL NOT NULL,
                input INTEGER NOT NULL, output INTEGER NOT NULL,
                cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS event_time ON events(time, provider);
            CREATE TABLE IF NOT EXISTS checkpoints (path TEXT PRIMARY KEY, value BLOB NOT NULL);
            PRAGMA user_version=1;
            """)
    }

    deinit { sqlite3_close(database) }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Persists high-water counters even for historical baselines. Only the increment enters totals.
    @discardableResult
    public func apply(_ observation: UsageObservation, since dayStart: Date) throws -> TokenCounts {
        let persisted = try record(observation.identity)
        let old = persisted == .zero ? observation.initialBaseline ?? .zero : persisted
        let high = observation.counts.highWater(against: old)
        let delta = high.increment(after: old)
        guard high != persisted else { return .zero }
        try statement("INSERT OR REPLACE INTO records VALUES (?, ?, ?, ?, ?, ?)") { query in
            bind(observation.identity, at: 1, to: query)
            bind(observation.provider.rawValue, at: 2, to: query)
            bind(high, start: 3, to: query)
            try step(query)
        }
        guard !observation.isBaseline, observation.timestamp >= dayStart, delta != .zero else { return .zero }
        try statement("INSERT INTO events(provider,time,input,output,cache_read,cache_write) VALUES (?,?,?,?,?,?)") { query in
            bind(observation.provider.rawValue, at: 1, to: query)
            sqlite3_bind_double(query, 2, observation.timestamp.timeIntervalSince1970)
            bind(delta, start: 3, to: query)
            try step(query)
        }
        return delta
    }

    public func totals(provider: Provider, from start: Date, to end: Date) throws -> TokenCounts {
        try statement("SELECT coalesce(sum(input),0),coalesce(sum(output),0),coalesce(sum(cache_read),0),coalesce(sum(cache_write),0) FROM events WHERE provider=? AND time>=? AND time<?") { query in
            bind(provider.rawValue, at: 1, to: query)
            sqlite3_bind_double(query, 2, start.timeIntervalSince1970)
            sqlite3_bind_double(query, 3, end.timeIntervalSince1970)
            guard sqlite3_step(query) == SQLITE_ROW else { throw failure() }
            return counts(query)
        }
    }

    public func hasUsage(provider: Provider) throws -> Bool {
        try statement("SELECT 1 FROM records WHERE provider=? LIMIT 1") { query in
            bind(provider.rawValue, at: 1, to: query)
            let result = sqlite3_step(query)
            guard result == SQLITE_ROW || result == SQLITE_DONE else { throw failure() }
            return result == SQLITE_ROW
        }
    }

    public func checkpoint(path: String) throws -> FileCheckpoint? {
        try statement("SELECT value FROM checkpoints WHERE path=?") { query in
            bind(path, at: 1, to: query)
            let result = sqlite3_step(query)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(query, 0) else { throw failure() }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
            return try JSONDecoder().decode(FileCheckpoint.self, from: data)
        }
    }

    public func save(_ checkpoint: FileCheckpoint, path: String) throws {
        let data = try JSONEncoder().encode(checkpoint)
        try statement("INSERT OR REPLACE INTO checkpoints VALUES (?,?)") { query in
            bind(path, at: 1, to: query)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(query, 2, bytes.baseAddress, Int32(bytes.count), transient)
            }
            try step(query)
        }
    }

    /// Retain checkpoints and deduplication counters so cleared history is not imported again.
    public func clearHistory() throws { try execute("DELETE FROM events;") }

    public func pruneHistory(before date: Date) throws {
        try statement("DELETE FROM events WHERE time<?") { query in
            sqlite3_bind_double(query, 1, date.timeIntervalSince1970)
            try step(query)
        }
    }

    private func record(_ identity: String) throws -> TokenCounts {
        try statement("SELECT input,output,cache_read,cache_write FROM records WHERE identity=?") { query in
            bind(identity, at: 1, to: query)
            let result = sqlite3_step(query)
            if result == SQLITE_DONE { return .zero }
            guard result == SQLITE_ROW else { throw failure() }
            return counts(query)
        }
    }

    private func counts(_ query: OpaquePointer) -> TokenCounts {
        TokenCounts(input: sqlite3_column_int64(query, 0), output: sqlite3_column_int64(query, 1),
                    cacheRead: sqlite3_column_int64(query, 2), cacheWrite: sqlite3_column_int64(query, 3))
    }

    private var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }
    private func bind(_ string: String, at position: Int32, to query: OpaquePointer) {
        _ = string.withCString { sqlite3_bind_text(query, position, $0, -1, transient) }
    }
    private func bind(_ value: TokenCounts, start: Int32, to query: OpaquePointer) {
        sqlite3_bind_int64(query, start, value.input)
        sqlite3_bind_int64(query, start + 1, value.output)
        sqlite3_bind_int64(query, start + 2, value.cacheRead)
        sqlite3_bind_int64(query, start + 3, value.cacheWrite)
    }
    private func step(_ query: OpaquePointer) throws {
        guard sqlite3_step(query) == SQLITE_DONE else { throw failure() }
    }
    private func statement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &query, nil) == SQLITE_OK, let query else { throw failure() }
        defer { sqlite3_finalize(query) }
        return try body(query)
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> StorageError {
        StorageError(message: database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open local usage storage.")
    }
}
