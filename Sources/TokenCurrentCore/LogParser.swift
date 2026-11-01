import Foundation

/// A narrow decoder: conversation content and authentication fields have no representation here.
public struct LogParser: Sendable {
    public init() {}

    public func parse(_ data: Data, provider: Provider, fileID: String, context: inout LogContext) -> ParseResult {
        guard let row = try? JSONDecoder().decode(Envelope.self, from: data) else { return .malformed }
        if provider == .claude { return claude(row, context: context) }
        return codex(row, fileID: fileID, context: &context)
    }

    private func claude(_ row: Envelope, context: LogContext) -> ParseResult {
        guard row.type == "assistant" else { return .ignored }
        guard let usage = row.message?.usage else { return .ignored }
        guard let message = row.message?.id, let time = date(row.timestamp),
              let input = usage.input_tokens, let output = usage.output_tokens,
              valid([input, output, usage.cache_read_input_tokens ?? 0, usage.cache_creation_input_tokens ?? 0])
        else { return .unsupported }
        let read = usage.cache_read_input_tokens ?? 0
        let write = usage.cache_creation_input_tokens ?? 0
        let counts = TokenCounts(input: input + read + write, output: output, cacheRead: read, cacheWrite: write)
        // Message IDs survive copied/forked transcripts. A missing request ID still deduplicates.
        return .observation(UsageObservation(provider: .claude,
            identity: "claude:\(message):\(row.requestId ?? "")", timestamp: time, counts: counts))
    }

    private func codex(_ row: Envelope, fileID: String, context: inout LogContext) -> ParseResult {
        if row.type == "session_meta" {
            context.sessionID = row.payload?.id ?? context.sessionID
            context.startedAt = date(row.payload?.timestamp ?? row.timestamp)
            context.forked = row.payload?.forked_from_id != nil
            return .metadata
        }
        guard row.payload?.type == "token_count" || row.type == "token_usage_record" else { return .ignored }
        // Rate-limit-only updates are normal and do not constitute unsupported usage.
        guard let usage = row.payload?.info?.total_token_usage ?? row.payload?.thread_token_usage else {
            return row.type == "token_usage_record" ? .unsupported : .ignored
        }
        guard let input = usage.input_tokens, let output = usage.output_tokens,
              let time = date(row.timestamp),
              valid([input, output, usage.cached_input_tokens ?? 0, usage.cache_write_input_tokens ?? 0]),
              (usage.cached_input_tokens ?? 0) + (usage.cache_write_input_tokens ?? 0) <= input else { return .unsupported }
        let session = row.payload?.thread_id ?? context.sessionID ?? fileID
        let counts = TokenCounts(input: input, output: output, cacheRead: usage.cached_input_tokens ?? 0,
                                 cacheWrite: usage.cache_write_input_tokens ?? 0)
        // Copied history in forked rollouts is baseline data, not newly consumed tokens.
        let inherited = context.forked && (context.startedAt.map { time < $0 } ?? false)
        if inherited, let thread = row.payload?.thread_id, thread != context.sessionID { return .ignored }
        let firstForkSnapshot = context.forked && !context.baselineSeen
        let last = row.payload?.info?.last_token_usage ?? row.payload?.usage
        var baseline: TokenCounts?
        if firstForkSnapshot && !inherited, let lastInput = last?.input_tokens, let lastOutput = last?.output_tokens,
           lastInput >= 0, lastInput <= input, lastOutput >= 0, lastOutput <= output {
            baseline = TokenCounts(input: input - lastInput, output: output - lastOutput,
                cacheRead: max(0, counts.cacheRead - (last?.cached_input_tokens ?? 0)),
                cacheWrite: max(0, counts.cacheWrite - (last?.cache_write_input_tokens ?? 0)))
        }
        context.baselineSeen = true
        return .observation(UsageObservation(provider: .codex, identity: "codex:\(session)",
            timestamp: time, counts: counts, isBaseline: inherited || (firstForkSnapshot && baseline == nil),
            initialBaseline: baseline))
    }

    private func valid(_ values: [Int64]) -> Bool { values.allSatisfy { $0 >= 0 && $0 <= 1_000_000_000_000_000 } }

    private func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct Envelope: Decodable {
    var type: String?
    var timestamp: String?
    var requestId: String?
    var message: Message?
    var payload: Payload?
}
private struct Message: Decodable { var id: String?; var usage: Usage? }
private struct Payload: Decodable {
    var id: String?
    var type: String?
    var timestamp: String?
    var forked_from_id: String?
    var parent_thread_id: String?
    var thread_id: String?
    var usage: Usage?
    var thread_token_usage: Usage?
    var info: UsageInfo?
}
private struct UsageInfo: Decodable { var total_token_usage: Usage?; var last_token_usage: Usage? }
private struct Usage: Decodable {
    var input_tokens: Int64?
    var output_tokens: Int64?
    var cached_input_tokens: Int64?
    var cache_write_input_tokens: Int64?
    var cache_read_input_tokens: Int64?
    var cache_creation_input_tokens: Int64?
}
