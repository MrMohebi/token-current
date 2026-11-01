import Foundation
import XCTest
@testable import TokenCurrentCore

final class FileTailerTests: XCTestCase {
    func testPartialWritesAreRetriedAndNewlinesAreCheckpointed() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("one\n{\"partial\":".utf8).write(to: url)
        let first = try FileTailer().read(url, checkpoint: nil)
        XCTAssertEqual(first.lines, [Data("one".utf8)])
        XCTAssertEqual(first.checkpoint.offset, 4)
        let file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
        try file.write(contentsOf: Data("true}\n".utf8))
        try file.close()
        let second = try FileTailer().read(url, checkpoint: first.checkpoint)
        XCTAssertEqual(second.lines, [Data(#"{"partial":true}"#.utf8)])
        XCTAssertEqual(try FileTailer().read(url, checkpoint: second.checkpoint).lines, [])
    }

    func testReplacementAndCopyTruncationResetOffsetAndContext() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old first\nold second\n".utf8).write(to: url)
        var first = try FileTailer().read(url, checkpoint: nil)
        first.checkpoint.context.sessionID = "old-session"
        // Rewriting the same inode to a longer file is detected by prefix verification.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("new first\nnew second\nnew third\n".utf8))
        try handle.close()
        let rewritten = try FileTailer().read(url, checkpoint: first.checkpoint)
        XCTAssertEqual(rewritten.lines.count, 3)
        XCTAssertNil(rewritten.checkpoint.context.sessionID)
        try FileManager.default.removeItem(at: url)
        try Data("replacement\n".utf8).write(to: url)
        XCTAssertEqual(try FileTailer().read(url, checkpoint: rewritten.checkpoint).lines, [Data("replacement".utf8)])
    }

    func testHugeNonUsageLinesCannotStallTailer() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data((String(repeating: "x", count: 100) + "\nusage\n").utf8).write(to: url)
        var checkpoint: FileCheckpoint?
        var lines: [Data] = []
        for _ in 0..<10 {
            let batch = try FileTailer().read(url, checkpoint: checkpoint, limit: 32)
            checkpoint = batch.checkpoint
            lines += batch.lines
        }
        XCTAssertEqual(lines, [Data("usage".utf8)])
    }

    func testUnreadablePathThrows() {
        XCTAssertThrowsError(try FileTailer().read(URL(fileURLWithPath: "/no-such-token-current-file"), checkpoint: nil))
    }
}
