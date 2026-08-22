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

    /// `swift build` 失敗時，hook 必須**中止**——不得繼續跑 `swift test` 或後面的守衛。
    ///
    /// 為什麼要有這一項（#407 R42，跨模型審查指名）：上面那項的 mock 對 `build`／`test`
    /// **永遠回 0**，所以它驗得了「有沒有帶 `-warnings-as-errors`」與「環境有沒有清乾淨」，
    /// 卻驗不了**這道閘會不會擋**。一個把 `set -eo pipefail` 拿掉、或把 `swift test` 接進
    /// 沒有 `pipefail` 的管線的回歸（那正是 #129 記過的 bug），會讓上面那項**逐字不變**
    /// 地通過——log 仍是那兩行、狀態仍是 0——而失敗的建置從此推得上去。
    ///
    /// **它抓的是哪一類，誠實界定**：本項證明「`swift build` 失敗 ⇒ hook 中止且不再跑
    /// `swift test`」。它**不**證明 #129 那個管線吞 exit code 的形狀——那需要 hook 把
    /// `swift test` 接進管線，而現在沒有（兩行都是裸呼叫，`set -e` 就足夠）。若日後有人
    /// 加了管線，要另外加一項；本項不會替它把關。
    ///
    /// **判別力來自「與上一項成對」，不是本項自己**（#407 R43，跨模型審查在孤立閱讀下
    /// 指名）：一個「呼叫完 `swift build` 就無條件 `exit 1`」的假實作，**本項會綠**
    /// （exit≠0、log 一行，兩個斷言都滿足）。排除它的是**上一項**——那裡 build 成功而
    /// 斷言 exit 0 ＋ log 兩行，假實作在那裡是紅的。所以這兩項**不可拆**：刪掉或搬走
    /// 任一項，另一項的判別力就消失，而且不會有任何跡象。
    func testHookAbortsWhenSwiftBuildFails() throws {
        let root = repositoryRoot
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".git").path) else {
            throw XCTSkip("這項承重測試需要 Git checkout")
        }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-prepush-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let log = temporary.appendingPathComponent("swift-invocations.log")
        let mockSwift = temporary.appendingPathComponent("swift")
        // `build` 記錄後**以 1 結束**；`test` 若被呼叫也記錄（那正是回歸的證據）。
        let script = """
        #!/bin/sh
        /usr/bin/printf '%s\\n' "$*" >> "$AKASHIC_PRE_PUSH_PROBE_LOG"
        case "$1" in
          build) exit 1 ;;
          test) exit 0 ;;
          *) exec /usr/bin/swift "$@" ;;
        esac
        """
        try script.write(to: mockSwift, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: mockSwift.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent(".githooks/pre-push").path]
        process.currentDirectoryURL = root
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(temporary.path):/usr/bin:/bin"
        environment["AKASHIC_PRE_PUSH_PROBE_LOG"] = log.path
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        XCTAssertNotEqual(
            process.terminationStatus, 0,
            "swift build 失敗時 pre-push 必須以非零結束，否則壞掉的建置推得上去")
        XCTAssertEqual(
            try String(contentsOf: log, encoding: .utf8)
                .split(separator: "\n").map(String.init),
            ["build -Xswiftc -warnings-as-errors"],
            "build 失敗後不得再呼叫 swift test——出現第二行即代表 hook 沒有中止")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
