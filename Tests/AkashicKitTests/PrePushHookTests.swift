import Foundation
import XCTest

final class PrePushHookTests: XCTestCase {
    func testHookScrubsRepositoryLocalGitEnvironmentAndRunsWarningsAsErrors() throws {
        let root = repositoryRoot
        let gitDirectory = root.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDirectory.path) else {
            throw XCTSkip("這項承重測試需要 Git checkout")
        }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-pre-push-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let log = temporary.appendingPathComponent("swift-invocations.log")
        let mockSwift = temporary.appendingPathComponent("swift")
        let poisonedNames = [
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX",
            "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
        ]
        let checks = poisonedNames.map {
            "if /usr/bin/env | /usr/bin/grep -q '^\($0)='; then exit 91; fi"
        }.joined(separator: "\n")
        let script = """
        #!/bin/sh
        \(checks)
        /usr/bin/printf '%s\\n' "$*" >> "$AKASHIC_PRE_PUSH_PROBE_LOG"
        """
        try script.write(to: mockSwift, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: mockSwift.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent(".githooks/pre-push").path]
        process.currentDirectoryURL = root
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(temporary.path):/usr/bin:/bin"
        environment["AKASHIC_PRE_PUSH_PROBE_LOG"] = log.path
        environment["GIT_DIR"] = gitDirectory.path
        environment["GIT_WORK_TREE"] = root.path
        environment["GIT_INDEX_FILE"] = gitDirectory.appendingPathComponent("index").path
        environment["GIT_PREFIX"] = "poisoned-prefix/"
        environment["GIT_COMMON_DIR"] = gitDirectory.path
        environment["GIT_OBJECT_DIRECTORY"] = gitDirectory
            .appendingPathComponent("objects").path
        process.environment = environment

        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(
            try String(contentsOf: log, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init),
            [
                "build -Xswiftc -warnings-as-errors",
                "test -Xswiftc -warnings-as-errors",
            ]
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
