import XCTest
@testable import TenXAppCore

final class ToolExecutorTests: XCTestCase {
    func testReadFilesRejectsParentTraversalOutsideWorkspace() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executor = ToolExecutor(
            workspaceRoot: root,
            projectName: "Test",
            targetName: "Test",
            currentMode: .build
        )

        let result = await executor.execute(
            toolName: "read_files",
            input: ["paths": ["../outside.txt"]]
        )

        XCTAssertTrue(result.text.contains("outside the readable project workspace"))
    }

    func testReadFilesTruncatesOversizedContent() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bigContent = String(repeating: "abcdefg\n", count: 12_000)
        try bigContent.write(
            to: root.appendingPathComponent("Huge.swift"),
            atomically: true,
            encoding: .utf8
        )

        let executor = ToolExecutor(
            workspaceRoot: root,
            projectName: "Test",
            targetName: "Test",
            currentMode: .build
        )

        let result = await executor.execute(
            toolName: "read_files",
            input: ["paths": ["Huge.swift"]]
        )

        XCTAssertTrue(result.text.contains("<truncated_file"))
        XCTAssertTrue(result.text.contains("file truncated to stay within the model context budget"))
    }
}
