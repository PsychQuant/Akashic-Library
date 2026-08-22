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
        // **只攔 `build`／`test`，其餘 pass-through 給真的 swift**（#407 R40）。
        // 先前這支 mock 對任何呼叫都只記錄後回 0，而 pre-push 現在還會用 swift 跑
        // `multiscalar-parity.swift`、以及 `hash-table-drift.sh` 內的表生成器——
        // 它們拿到空輸出就判定漂移，於是**整個 hook exit 1**，本測試的兩個斷言
        // （狀態為 0、swift 呼叫恰為那兩筆）同時紅。本測試要驗的是「環境有沒有被
        // 清乾淨」與「build／test 有沒有帶 -warnings-as-errors」，不是「hook 總共
        // 呼叫幾次 swift」——所以 pass-through 保住原本的斷言不必改。
        let script = """
        #!/bin/sh
        \(checks)
        case "$1" in
          build|test) /usr/bin/printf '%s\\n' "$*" >> "$AKASHIC_PRE_PUSH_PROBE_LOG" ;;
          *) exec /usr/bin/swift "$@" ;;
        esac
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
