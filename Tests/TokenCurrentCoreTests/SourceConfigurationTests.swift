import Foundation
import XCTest
@testable import TokenCurrentCore

final class SourceConfigurationTests: XCTestCase {
    func testFirstLaunchFindsXDGClaudeAndCodexEnvironmentHome() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let xdg = root.appending(path: "config")
        try FileManager.default.createDirectory(at: xdg.appending(path: "claude/projects"), withIntermediateDirectories: true)
        let detected = SourceConfiguration.autodetected(
            environment: ["XDG_CONFIG_HOME": xdg.path, "CODEX_HOME": root.appending(path: "custom-codex").path],
            homeDirectory: root)
        XCTAssertEqual(detected.claudeHome, xdg.appending(path: "claude").path)
        XCTAssertEqual(detected.codexHome, root.appending(path: "custom-codex").path)
    }

    func testClaudeOverrideAcceptsProjectsFolderAndPrefersExistingCandidate() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appending(path: "custom/projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let detected = SourceConfiguration.autodetected(
            environment: ["CLAUDE_CONFIG_DIR": "~/missing, \(projects.path)"], homeDirectory: root)
        XCTAssertEqual(detected.claudeHome, root.appending(path: "custom").path)
        XCTAssertEqual(detected.codexHome, root.appending(path: ".codex").path)
    }

    func testSavedExplicitSelectionsDoNotInvokeAutodiscovery() throws {
        let configuration = SourceConfiguration(claudeHome: "/chosen/claude", codexHome: "/chosen/codex")
        let saved = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(SourceConfiguration.self, from: saved), configuration)
        XCTAssertEqual(configuration.roots(for: .claude), [URL(fileURLWithPath: "/chosen/claude/projects")])
    }
}
