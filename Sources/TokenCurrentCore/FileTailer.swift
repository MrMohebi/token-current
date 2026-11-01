import Foundation

public struct FileCheckpoint: Codable, Equatable, Sendable {
    public var offset: UInt64 = 0
    public var fileIdentity: String = ""
    public var prefixHash: String = ""
    public var prefixLength: Int = 0
    public var discardingLongLine = false
    public var context = LogContext()
    public var recognized = false
    public var unsupported = false
    public init() {}
}

public struct TailBatch: Sendable {
    public let lines: [Data]
    public var checkpoint: FileCheckpoint
    public let hasMore: Bool
}

public struct FileTailer: Sendable {
    public init() {}

    /// Bounded reads; unfinished JSON is retried on the next tick, never checkpointed as consumed.
    public func read(_ url: URL, checkpoint saved: FileCheckpoint?, limit: Int = 2_097_152) throws -> TailBatch {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let identity = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var checkpoint = saved ?? FileCheckpoint()
        let checkLength = checkpoint.prefixLength > 0 ? checkpoint.prefixLength : min(256, Int(size))
        let prefix = try file.read(upToCount: checkLength) ?? Data()
        let hash = fingerprint(prefix)
        if checkpoint.fileIdentity != identity || size < checkpoint.offset ||
            (checkpoint.prefixLength > 0 && hash != checkpoint.prefixHash) {
            checkpoint = FileCheckpoint()
        }
        checkpoint.fileIdentity = identity
        checkpoint.prefixLength = prefix.count
        checkpoint.prefixHash = hash
        try file.seek(toOffset: checkpoint.offset)
        let bytes = try file.read(upToCount: limit) ?? Data()
        var lines: [Data] = []
        var beginning = bytes.startIndex
        for end in bytes.indices where bytes[end] == 10 {
            if checkpoint.discardingLongLine {
                checkpoint.discardingLongLine = false
            } else if end > beginning {
                lines.append(bytes.subdata(in: beginning..<end))
            }
            beginning = end + 1
        }
        checkpoint.offset += UInt64(beginning)
        if beginning == bytes.startIndex && bytes.count == limit {
            // A huge content line cannot stall a watcher indefinitely. Usage lines fit this bound.
            checkpoint.offset += UInt64(bytes.count)
            checkpoint.discardingLongLine = true
        }
        return TailBatch(lines: lines, checkpoint: checkpoint, hasMore: checkpoint.offset < size && bytes.count == limit)
    }

    private func fingerprint(_ bytes: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}
