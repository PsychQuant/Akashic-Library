import Foundation
import XCTest

final class PrePushHookTests: XCTestCase {

    /// 只推 tag 且其 commit 已在遠端 → 跳過驗證（#434）。
    ///
    /// **兩個負向 case 是這支測試的重點**。正向那個（真的跳過）只證明早退存在；
    /// 負向那兩個才證明它**沒有跳太多**——而跳太多的失敗是安靜的：push 成功、
    /// 驗證沒跑、沒有任何訊息說它沒跑。
    func testTagOnlyPushSkipsVerificationButOnlyWhenTheCommitIsAlreadyRemote() throws {
        let root = repositoryRoot
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
        else { throw XCTSkip("這項承重測試需要 Git checkout") }

        /// 真 repo 上一個**確定已在遠端**的 commit。取不到就跳過——它是本測試的前提，
        /// 而前提不成立時謊報通過比跳過更糟。
        func remoteCommit() -> String? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", root.path, "rev-parse", "origin/main"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            return s?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let onRemote = remoteCommit(), !onRemote.isEmpty else {
            throw XCTSkip("拿不到 origin/main——本測試的前提不成立")
        }

        /// 餵 stdin 跑 hook，回 (exit code, 是否呼叫過 swift)。
        ///
        /// `AKASHIC_PRE_PUSH_STAGES=build` 讓非早退的路徑只跑第一階段——本測試問的是
        /// 「有沒有早退」，不是「後面幾階段對不對」。mock 的 swift 只記錄不執行。
        func run(stdin: String) throws -> (Int32, Bool) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("akashic-tagonly-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let log = tmp.appendingPathComponent("swift.log")
            let mock = tmp.appendingPathComponent("swift")
            try "#!/bin/sh\n/usr/bin/printf '%s\\n' \"$*\" >> \"$AKASHIC_PRE_PUSH_PROBE_LOG\"\n"
                .write(to: mock, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: mock.path)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [root.appendingPathComponent(".githooks/pre-push").path]
            proc.currentDirectoryURL = root
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(tmp.path):/usr/bin:/bin"
            env["AKASHIC_PRE_PUSH_PROBE_LOG"] = log.path
            env["AKASHIC_PRE_PUSH_STAGES"] = "build"
            proc.environment = env
            let input = Pipe()
            proc.standardInput = input
            proc.standardOutput = Pipe(); proc.standardError = Pipe()
            try proc.run()
            input.fileHandleForWriting.write(stdin.data(using: .utf8)!)
            try? input.fileHandleForWriting.close()
            proc.waitUntilExit()
            let called = FileManager.default.fileExists(atPath: log.path)
                && ((try? String(contentsOf: log, encoding: .utf8))?.isEmpty == false)
            return (proc.terminationStatus, called)
        }

        // ① 正向：只推 tag，commit 已在遠端 → 早退，一次 swift 都不呼叫
        let tagOnly = try run(
            stdin: "refs/tags/v9.9.9 \(onRemote) refs/tags/v9.9.9 " + String(repeating: "0", count: 40))
        XCTAssertEqual(tagOnly.0, 0, "只推已在遠端的 tag 應該直接通過")
        XCTAssertFalse(tagOnly.1, "早退之後不該呼叫 swift——跑了就表示沒有真的跳過")

        // ② 負向：推 branch → 照常驗證
        let branchPush = try run(
            stdin: "refs/heads/main \(onRemote) refs/heads/main " + String(repeating: "0", count: 40))
        XCTAssertTrue(branchPush.1,
                      "推 branch 必須照常跑驗證——早退若吃掉這個情形，失敗是安靜的")

        // ③ 負向：tag 指向**不在遠端**的 commit → 照常驗證
        //
        // `git push origin v1.0` 可以推一個指向本地獨有 commit 的 tag，那次 push 會把
        // 那個 commit 一起帶上去。那時樹是新的，驗證不能跳。
        let orphanTag = try run(
            stdin: "refs/tags/v9.9.9 \(String(repeating: "f", count: 40)) refs/tags/v9.9.9 "
                + String(repeating: "0", count: 40))
        XCTAssertTrue(orphanTag.1,
                      "tag 指向遠端沒有的 commit 時，那次 push 會帶上新程式碼——不能跳")
    }
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
        // **只跑前兩階段**（#432）。本測試斷言的是「`GIT_*` 有沒有被清乾淨」與
        // 「swift 有沒有帶 `-Xswiftc -warnings-as-errors`」——**兩者都在前兩階段**。
        //
        // 先前它會連守衛一起跑（實測 **43 分鐘**），而外層 hook 兩分鐘後跑同一批、
        // 讀同一個工作樹、得同一個結果。內層那次的覆蓋是外層的真子集,純浪費。
        environment["AKASHIC_PRE_PUSH_STAGES"] = "build,test"
        environment["GIT_DIR"] = gitDirectory.path
        environment["GIT_WORK_TREE"] = root.path
        environment["GIT_INDEX_FILE"] = gitDirectory.appendingPathComponent("index").path
        environment["GIT_PREFIX"] = "poisoned-prefix/"
        environment["GIT_COMMON_DIR"] = gitDirectory.path
        environment["GIT_OBJECT_DIRECTORY"] = gitDirectory
            .appendingPathComponent("objects").path
        process.environment = environment

        // **必須在 `waitUntilExit()` 之前把 pipe 讀乾**（#394 verify R9 的診斷）。
        //
        // `standardOutput = Pipe()` 而沒有人讀，等於給 hook 一個 **8192 bytes**
        // （實測 `sysctl net.local.stream.recvspace`）的水桶：寫滿之後它**阻塞在
        // write 上**，而我們在 `waitUntilExit()` 等它 —— 雙方互等，永不結束。
        //
        // hook 的輸出實測 **29714 bytes**（3.6 倍於 buffer），所以這不是邊界情況，
        // 是必然。它**以前會過**是因為輸出隨守衛數量成長（現在 21 支），
        // 在某個時點越過 8 KB —— 從此每次 push 都掛。
        //
        // 症狀極具誤導性：三次失敗的耗時各不相同（2857／911／1173 秒），
        // 而 hook 的輸出**完全不出現在任何 log 裡**（它在那個沒人讀的 pipe 裡）。
        // 我為此先後假設過「編輯期間的競爭」「某支守衛是紅的」「並發碰撞」，
        // **三個都被自己的量測推翻**，直到去讀這幾行。
        let outHandle = (process.standardOutput as! Pipe).fileHandleForReading
        let errHandle = (process.standardError as! Pipe).fileHandleForReading
        try process.run()
        // 先讀到 EOF 再 wait —— 順序反了就是同一個死鎖。
        let outData = outHandle.readDataToEndOfFile()
        let errData = errHandle.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0,
                       "hook 失敗。輸出：\n"
                       + String(data: outData, encoding: .utf8)!.suffix(2000)
                       + "\n--- stderr ---\n"
                       + String(data: errData, encoding: .utf8)!.suffix(1000))
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
