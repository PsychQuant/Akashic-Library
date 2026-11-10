import XCTest
import Foundation

/// `scripts/stamp-version.sh`（#775）：建置期間把 `git describe` 寫進受追蹤的佔位檔，建完一定還原。
///
/// 移植自 safari-browser 的同名腳本（safari-browser#278）。這裡測的是 Akashic 版本的三個差異與它沿用的保證：
///   · 版本字串是裸的 `<12 位 hash>[-dirty]`——這個 repo 的 tag（`akashic-mcp-v*`、`idd-*-baseline`）都不描述 CLI 的建置，
///     所以全部排除；hook 只需要解析這一種形狀。
///   · 命令成功、失敗、收到 TERM，佔位檔都回到原樣（位元組相同）。少了這一條，戳記值會被當成原始碼 commit 進去。
///   · 不在自己 repo 的根目錄、或根本不是 git repo 時印 `unknown`，不借用外層 repo 的歷史。
///
/// 每支測試都在暫存的 git repo 裡跑：只複製真的腳本與一個佔位檔，git 的全域與系統設定都隔離掉
/// （使用者可能設了 commit 簽章或 hook，測試不該依賴它們）。
final class StampVersionTests: XCTestCase {
    private var repo: URL!
    private let placeholder = "/// placeholder\nenum BuildVersion { static let value = \"unknown\" }\n"
    private let versionFile = "Sources/akashic/BuildVersion.swift"

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    override func setUpWithError() throws {
        repo = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: repo.appendingPathComponent("Sources/akashic"), withIntermediateDirectories: true)
        try fm.createDirectory(at: repo.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try fm.copyItem(at: Self.repoRoot.appendingPathComponent("scripts/stamp-version.sh"),
                        to: repo.appendingPathComponent("scripts/stamp-version.sh"))
        try placeholder.write(to: repo.appendingPathComponent(versionFile), atomically: true, encoding: .utf8)
        try "readme\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git("init", "-q")
        try git("add", "-A")
        try git("commit", "-q", "-m", "init")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo) }

    // MARK: - helpers

    /// 先剝除所有 `GIT_*`（#234／#239）：從 git hook（pre-push）執行時父環境帶著 `GIT_DIR` 等變數，`-C` 與 cwd 都擋不住，
    /// 暫存 repo 的 init／commit 會寫進真的 repo。剝除之後才加這支測試自己要的設定。
    private var scrubbedGitEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_AUTHOR_NAME"] = "t"; env["GIT_AUTHOR_EMAIL"] = "t@example.invalid"
        env["GIT_COMMITTER_NAME"] = "t"; env["GIT_COMMITTER_EMAIL"] = "t@example.invalid"
        return env
    }

    @discardableResult
    private func git(_ args: String..., in dir: URL? = nil) throws -> String {
        let r = try run("/usr/bin/git", args, in: dir ?? repo)
        guard r.status == 0 else {
            throw NSError(domain: "StampVersionTests", code: Int(r.status),
                          userInfo: [NSLocalizedDescriptionKey: "git \(args) 失敗：\(r.err)"])
        }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ exe: String, _ args: [String], in dir: URL,
                     env extra: [String: String] = [:]) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = dir
        var env = scrubbedGitEnvironment
        for (k, v) in extra { env[k] = v }
        p.environment = env
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let out = o.fileHandleForReading.readDataToEndOfFile()
        let err = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    /// 跑戳記腳本，被包的命令是「印出佔位檔」——它看到的就是建置會讀到的內容。
    private func stampAndCat(in dir: URL? = nil, script: String = "scripts/stamp-version.sh",
                             file: String? = nil) throws -> (status: Int32, out: String, err: String) {
        let f = file ?? versionFile
        return try run("/bin/bash", [script, f, "--", "/bin/cat", f], in: dir ?? repo)
    }

    private func currentFile() throws -> String {
        try String(contentsOf: repo.appendingPathComponent(versionFile), encoding: .utf8)
    }

    private func stampedValue(_ out: String) -> String? {
        guard let r = out.range(of: #"static let value = "([^"]*)""#, options: .regularExpression) else { return nil }
        return String(out[r]).replacingOccurrences(of: "static let value = \"", with: "").dropLast().description
    }

    // MARK: - tests

    func testCommandSeesTheCommitAndThePlaceholderComesBack() throws {
        let head = try git("rev-parse", "--short=12", "HEAD")
        let r = try stampAndCat()
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(stampedValue(r.out), head, "命令看到的應是 HEAD 的 12 位 hash：\(r.out)")
        XCTAssertEqual(try currentFile(), placeholder, "命令結束後佔位檔要回到原樣")
    }

    func testTagsAreIgnoredSoTheValueIsAlwaysABareHash() throws {
        try git("tag", "-a", "akashic-mcp-v9.9.9", "-m", "release")
        try git("tag", "idd-1-baseline")
        let head = try git("rev-parse", "--short=12", "HEAD")
        let r = try stampAndCat()
        XCTAssertEqual(stampedValue(r.out), head, "tag 不得出現在版本字串裡：\(r.out)")
    }

    func testUncommittedChangesAddTheDirtySuffix() throws {
        try "changed\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let head = try git("rev-parse", "--short=12", "HEAD")
        let r = try stampAndCat()
        XCTAssertEqual(stampedValue(r.out), head + "-dirty", r.out)
    }

    func testAFailingCommandStillRestoresAndKeepsItsStatus() throws {
        let r = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/bin/sh", "-c", "exit 7"], in: repo)
        XCTAssertEqual(r.status, 7)
        XCTAssertEqual(try currentFile(), placeholder)
    }

    /// 啟動一次戳記建置（被包的命令是 `sleep 30`），等到佔位檔被改寫（腳本已進入「命令執行中」）才回傳。
    private func startLongStampedBuild() throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["scripts/stamp-version.sh", versionFile, "--", "/bin/sleep", "30"]
        p.currentDirectoryURL = repo
        p.environment = scrubbedGitEnvironment
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let deadline = Date().addingTimeInterval(10)
        while (try? currentFile()) == placeholder && Date() < deadline { usleep(50_000) }
        XCTAssertNotEqual(try currentFile(), placeholder, "10 秒內沒有看到戳記值寫進去")
        return p
    }

    private func assertSignalRestores(_ signal: Int32, exit expected: Int32,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let p = try startLongStampedBuild()
        kill(p.processIdentifier, signal)
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, expected, file: file, line: line)
        XCTAssertEqual(try currentFile(), placeholder, "收到訊號 \(signal) 之後佔位檔要回到原樣", file: file, line: line)
    }

    // 四種訊號各一支（verify r1 第 13 項：changelog 說四種都還原，先前只測了 TERM）
    func testTermDuringTheCommandRestoresThePlaceholder() throws { try assertSignalRestores(SIGTERM, exit: 143) }
    func testInterruptDuringTheCommandRestoresThePlaceholder() throws { try assertSignalRestores(SIGINT, exit: 130) }
    func testHangupDuringTheCommandRestoresThePlaceholder() throws { try assertSignalRestores(SIGHUP, exit: 129) }
    func testQuitDuringTheCommandRestoresThePlaceholder() throws { try assertSignalRestores(SIGQUIT, exit: 131) }

    /// bash 3.2 的背景命令忽略 INT／QUIT，在子 shell 裡 `trap - INT QUIT` 也還原不了（2026-11-10 實測）。腳本自己收到
    /// 這兩個訊號時改送 TERM 給命令（上面兩支）。這支釘住現況：哪天被包的命令收得到 INT，檔頭那段說明要跟著改。
    func testTheWrappedCommandItselfIgnoresInterrupts() throws {
        let r = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/bin/sh", "-c", "kill -INT $$; echo survived"], in: repo)
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.contains("survived"), r.out)
        XCTAssertEqual(try currentFile(), placeholder)
    }

    // MARK: - 佔位檔不是佔位值、寫不進去（verify r1 blocking 3）

    private let stamped = "/// stamped\nenum BuildVersion { static let value = \"0123456789ab\" }\n"

    /// 兩次重疊的戳記建置：第二次看到的是第一次寫進去的戳記值。先前它把那個值當成原檔備份、建完「還原」回去，
    /// 戳記值就永久留在受追蹤的檔裡。
    func testASecondRunWhileTheFirstIsStillRunningIsRefused() throws {
        let first = try startLongStampedBuild()
        defer { if first.isRunning { first.terminate(); first.waitUntilExit() } }
        let marker = repo.appendingPathComponent("second-ran")
        let second = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/usr/bin/touch", marker.path], in: repo)
        XCTAssertEqual(second.status, 3, second.err)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "被拒絕時不得執行命令")
        XCTAssertNotEqual(try currentFile(), placeholder, "第一次建置還在跑，它的戳記值應該還在")
        first.terminate(); first.waitUntilExit()
        XCTAssertEqual(try currentFile(), placeholder, "兩次都結束後佔位檔要回到原樣")
    }

    /// 被 SIGKILL 的建置留下戳記值：下一次不得把它當成原檔。
    func testALeftoverStampedValueIsRefused() throws {
        try stamped.write(to: repo.appendingPathComponent(versionFile), atomically: true, encoding: .utf8)
        let marker = repo.appendingPathComponent("ran")
        let r = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/usr/bin/touch", marker.path], in: repo)
        XCTAssertEqual(r.status, 3, r.err)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(try currentFile(), stamped, "拒絕時不動檔案")
        XCTAssertTrue(r.err.contains("placeholder"), r.err)
    }

    /// 其他測試用的都是自製的兩行佔位檔。這支拿 repo 裡真的 `Sources/akashic/BuildVersion.swift`：腳本認佔位值靠的是
    /// 檔裡那一段 `static let value = "unknown"`，真檔的寫法一改，腳本會拒絕每一次建置（結束碼 3），訊息還會說成
    /// 「另一次建置還在跑」。
    func testTheTrackedPlaceholderFileIsAccepted() throws {
        let real = try String(contentsOf: Self.repoRoot.appendingPathComponent(versionFile), encoding: .utf8)
        try real.write(to: repo.appendingPathComponent(versionFile), atomically: true, encoding: .utf8)
        try git("commit", "-q", "-am", "real placeholder")
        let head = try git("rev-parse", "--short=12", "HEAD")
        let r = try stampAndCat()
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(stampedValue(r.out), head, r.out)
        XCTAssertEqual(try currentFile(), real, "建完要回到真檔的內容")
    }

    /// 戳記寫不進去（唯讀）：先前照樣建置，binary 印的是佔位值而沒有人知道。
    func testAWriteFailureAbortsBeforeTheCommand() throws {
        let path = repo.appendingPathComponent(versionFile).path
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
        let marker = repo.appendingPathComponent("ran")
        let r = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/usr/bin/touch", marker.path], in: repo)
        XCTAssertEqual(r.status, 4, r.err)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "寫入失敗時不得執行命令")
        XCTAssertEqual(try currentFile(), placeholder)
    }

    // MARK: - -dirty 與白名單

    /// `git describe --dirty` 不看未追蹤檔，SwiftPM 卻會編譯它們（verify r1 第 12 項）。
    func testAnUntrackedFileInThePackageSourceAddsTheDirtySuffix() throws {
        try "// new\n".write(to: repo.appendingPathComponent("Sources/akashic/New.swift"), atomically: true, encoding: .utf8)
        let head = try git("rev-parse", "--short=12", "HEAD")
        let r = try stampAndCat()
        XCTAssertEqual(stampedValue(r.out), head + "-dirty", r.out)
    }

    func testAnUntrackedFileOutsideThePackageSourceDoesNot() throws {
        try "scratch\n".write(to: repo.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let head = try git("rev-parse", "--short=12", "HEAD")
        let r = try stampAndCat()
        XCTAssertEqual(stampedValue(r.out), head, "不進 binary 的未追蹤檔不算：\(r.out)")
    }

    /// 白名單以外的字元一律變成 `unknown`（verify r1 第 13 項）。先前的檢查經過 `$(…)`，內部的換行被吃掉；
    /// 字元範圍也要在 C locale 下比（bash 3.2 在 UTF-8 locale 下 `A-Z` 會放行非 ASCII 字母）。
    func testADescribeOutsideTheWhitelistBecomesUnknown() throws {
        let stub = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-stub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stub) }
        try FileManager.default.createDirectory(at: stub, withIntermediateDirectories: true)
        let fakeGit = stub.appendingPathComponent("git")
        try "#!/bin/sh\ncase \"$1\" in\n  rev-parse) pwd -P ;;\n  describe) printf '%b' \"$FAKE_DESCRIBE\" ;;\n  *) exit 0 ;;\nesac\n"
            .write(to: fakeGit, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGit.path)
        // 非 ASCII 字母用八進位跳脫交給假 git 的 `printf %b` 印出（UTF-8 的 é 是 303 251）。不能把 "abé" 直接放進環境變數：
        // Foundation 的 `Process` 把參數與環境變數轉成分解形，腳本收到的是 `e` 加 U+0301（2026-11-10 實測 65 cc 81），
        // 那個值在任何 locale 下都會被擋，測不到「字元範圍要在 C locale 下比」——負對照拿掉 `local LC_ALL=C`，這支仍然通過。
        for hostile in ["ab\"c", "ab\\ncd", "ab\\0303\\0251", "a b"] {
            let r = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/bin/cat", versionFile], in: repo,
                            env: ["PATH": stub.path + ":/usr/bin:/bin", "LANG": "en_US.UTF-8", "FAKE_DESCRIBE": hostile])
            XCTAssertEqual(r.status, 0, r.err)
            XCTAssertEqual(stampedValue(r.out), "unknown", "describe 印出 \(hostile)：\(r.out)")
            XCTAssertEqual(r.out.split(separator: "\n").count, 3, "戳記檔應該只有三行（標記、註解、值）：\(r.out)")
        }
    }

    /// 兩支腳本各有一份「會被編進 binary 的路徑」，要是同一行（同一件事的兩份描述，由這支對帳）。
    func testTheStampScriptAndTheHookListTheSamePackagePaths() throws {
        func line(_ rel: String) throws -> String {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(rel), encoding: .utf8)
            let lines = text.components(separatedBy: "\n").filter { $0.hasPrefix("COMPILED_PATHS=(") }
            XCTAssertEqual(lines.count, 1, "\(rel) 應該恰有一行 COMPILED_PATHS=(…)")
            return lines.first ?? ""
        }
        let stamp = try line("scripts/stamp-version.sh")
        XCTAssertFalse(stamp.isEmpty)
        XCTAssertEqual(stamp, try line("plugin/hooks/check-cli.sh"))
    }

    func testNotTheRootOfItsOwnRepositoryGivesUnknown() throws {
        let sub = repo.appendingPathComponent("Sources")
        let r = try stampAndCat(in: sub, script: "../scripts/stamp-version.sh", file: "akashic/BuildVersion.swift")
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(stampedValue(r.out), "unknown", "不在 repo 根目錄時不得借用 git 的答案：\(r.out)")
    }

    func testOutsideAnyRepositoryGivesUnknown() throws {
        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-plain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: plain) }
        try FileManager.default.createDirectory(at: plain.appendingPathComponent("Sources/akashic"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plain.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repo.appendingPathComponent("scripts/stamp-version.sh"),
                                         to: plain.appendingPathComponent("scripts/stamp-version.sh"))
        try placeholder.write(to: plain.appendingPathComponent(versionFile), atomically: true, encoding: .utf8)
        let r = try stampAndCat(in: plain)
        XCTAssertEqual(stampedValue(r.out), "unknown", r.out + r.err)
    }

    func testAMissingVersionFileIsAUsageError() throws {
        let r = try run("/bin/bash", ["scripts/stamp-version.sh", "nope.swift", "--", "/usr/bin/true"], in: repo)
        XCTAssertEqual(r.status, 2)
    }

    // MARK: - verify r2

    /// 一支放在 PATH 最前面的假 git：`when` 這個子命令出現時先做 `before`，其餘原樣交給真的 git。
    private func gitStub(when subcommand: String, _ before: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stub = dir.appendingPathComponent("git")
        try "#!/bin/sh\nfor a in \"$@\"; do if [ \"$a\" = \(subcommand) ]; then \(before); fi; done\nexec /usr/bin/git \"$@\"\n"
            .write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        return dir
    }

    private func waitForFile(_ url: URL, seconds: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { usleep(50_000) }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 檢查與備份之間隔著幾個 git 查詢（verify r2）。另一次建置在這段時間寫入戳記的話，這一次備份到的就是戳記，建完
    /// 「還原」回去的也是戳記——兩邊都回 0，戳記留在受追蹤的檔裡。備份之後要再查一次備份本身。
    /// 順序不靠 sleep：B 的 `git describe` 卡住，直到 A 已經戳記；A 的「建置」則等到 B 結束才結束，所以 B 備份的時候
    /// A 的戳記一定還在檔裡。
    func testAStampWrittenBetweenTheCheckAndTheBackupIsRefused() throws {
        let sync = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sync) }
        let waiting = sync.appendingPathComponent("b-in-describe"), stampedByA = sync.appendingPathComponent("a-stamped")
        let stub = try gitStub(when: "describe", """
            : > '\(waiting.path)'; i=0; while [ ! -e '\(stampedByA.path)' ] && [ $i -lt 100 ]; do /bin/sleep 0.1; i=$((i+1)); done
            """)
        defer { try? FileManager.default.removeItem(at: stub) }
        let ranB = repo.appendingPathComponent("b-ran")

        let b = Process()
        b.executableURL = URL(fileURLWithPath: "/bin/bash")
        b.arguments = ["scripts/stamp-version.sh", versionFile, "--", "/usr/bin/touch", ranB.path]
        b.currentDirectoryURL = repo
        var env = scrubbedGitEnvironment
        env["PATH"] = stub.path + ":/usr/bin:/bin"
        b.environment = env
        b.standardOutput = FileHandle.nullDevice; b.standardError = FileHandle.nullDevice
        b.standardInput = FileHandle.nullDevice
        try b.run()
        XCTAssertTrue(waitForFile(waiting), "B 沒有走到 git describe")

        // A：這時才開始。戳記之後留下記號（B 才繼續），然後等 B 結束（最多 20 秒）
        let a = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/bin/sh", "-c", """
            : > '\(stampedByA.path)'; i=0
            while kill -0 \(b.processIdentifier) 2>/dev/null && [ $i -lt 200 ]; do /bin/sleep 0.1; i=$((i+1)); done
            """], in: repo)
        b.waitUntilExit()
        XCTAssertEqual(a.status, 0, a.err)
        XCTAssertEqual(b.terminationStatus, 3, "B 備份到的是 A 的戳記，要拒絕")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ranB.path), "被拒絕時不得執行命令")
        XCTAssertEqual(try currentFile(), placeholder, "兩次都結束後佔位檔要回到原樣")
    }

    /// 戳記值本身是 `unknown`（不是 git repo）時，戳記過的檔仍然認得出來（verify r2）：只看值的話，它與佔位檔一樣。
    func testAnUnknownStampIsStillRecognisedAsAStamp() throws {
        let bare = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-bare-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bare) }
        let fm = FileManager.default
        try fm.createDirectory(at: bare.appendingPathComponent("Sources/akashic"), withIntermediateDirectories: true)
        try fm.createDirectory(at: bare.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try fm.copyItem(at: Self.repoRoot.appendingPathComponent("scripts/stamp-version.sh"),
                        to: bare.appendingPathComponent("scripts/stamp-version.sh"))
        let file = bare.appendingPathComponent(versionFile)
        try placeholder.write(to: file, atomically: true, encoding: .utf8)

        let first = Process()
        first.executableURL = URL(fileURLWithPath: "/bin/bash")
        first.arguments = ["scripts/stamp-version.sh", versionFile, "--", "/bin/sleep", "30"]
        first.currentDirectoryURL = bare
        first.environment = scrubbedGitEnvironment
        first.standardOutput = FileHandle.nullDevice; first.standardError = FileHandle.nullDevice
        first.standardInput = FileHandle.nullDevice
        try first.run()
        defer { if first.isRunning { first.terminate(); first.waitUntilExit() } }
        let deadline = Date().addingTimeInterval(10)
        while (try? String(contentsOf: file, encoding: .utf8)) == placeholder && Date() < deadline { usleep(50_000) }
        let during = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(stampedValue(during), "unknown", during)
        XCTAssertNotEqual(during, placeholder, "10 秒內沒有看到戳記寫進去")

        let marker = bare.appendingPathComponent("second-ran")
        let second = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/usr/bin/touch", marker.path], in: bare)
        XCTAssertEqual(second.status, 3, second.err)
        XCTAssertFalse(fm.fileExists(atPath: marker.path))
        first.terminate(); first.waitUntilExit()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), placeholder, "兩次都結束後佔位檔要回到原樣")
    }

    /// 被中斷的建置留下 `unknown` 的戳記：下一次不得把它當成原檔。
    func testALeftoverUnknownStampIsRefused() throws {
        let leftover = "// stamp-version:stamped\n/// 戳記值\nenum BuildVersion { static let value = \"unknown\" }\n"
        try leftover.write(to: repo.appendingPathComponent(versionFile), atomically: true, encoding: .utf8)
        let marker = repo.appendingPathComponent("ran")
        let r = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/usr/bin/touch", marker.path], in: repo)
        XCTAssertEqual(r.status, 3, r.err)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(try currentFile(), leftover, "拒絕時不動檔案")
    }

    /// 腳本寫進去的戳記帶著它認得的那個標記（上面兩支的前提）。
    func testTheStampCarriesTheMarkTheScriptLooksFor() throws {
        let r = try stampAndCat()
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.contains("stamp-version:stamped"), r.out)
        XCTAssertFalse(placeholder.contains("stamp-version:stamped"))
        let real = try String(contentsOf: Self.repoRoot.appendingPathComponent(versionFile), encoding: .utf8)
        XCTAssertFalse(real.contains("stamp-version:stamped"), "真的佔位檔不得帶戳記的標記")
    }

    /// submodule 裡的未追蹤檔也算 `-dirty`（verify r2）：`git describe --dirty` 不看它，SwiftPM 會編譯它。
    /// `submodule.<名字>.ignore=all` 也不得把它藏起來。
    func testAnUntrackedFileInsideASubmoduleAddsTheDirtySuffix() throws {
        let sub = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-sub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sub) }
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "// lib\n".write(to: sub.appendingPathComponent("Lib.swift"), atomically: true, encoding: .utf8)
        try git("init", "-q", in: sub)
        try git("add", "-A", in: sub)
        try git("commit", "-q", "-m", "lib", in: sub)
        try git("-c", "protocol.file.allow=always", "submodule", "--quiet", "add", sub.path, "repos/biblatex-apa-swift")
        try git("commit", "-q", "-m", "add submodule")
        let head = try git("rev-parse", "--short=12", "HEAD")
        XCTAssertEqual(stampedValue(try stampAndCat().out), head, "乾淨的 submodule 不算 dirty")

        try "// half-written\n".write(to: repo.appendingPathComponent("repos/biblatex-apa-swift/Half.swift"),
                                      atomically: true, encoding: .utf8)
        XCTAssertEqual(stampedValue(try stampAndCat().out), head + "-dirty")
        try git("config", "submodule.repos/biblatex-apa-swift.ignore", "all")
        XCTAssertEqual(stampedValue(try stampAndCat().out), head + "-dirty", "ignore=all 也照樣算")
    }

    /// `git status` 失敗時不宣稱是乾淨的建置（verify r2）：失敗的輸出是空的，與「沒有未追蹤檔」一樣。
    func testAStatusThatFailsDoesNotClaimACleanBuild() throws {
        let stub = try gitStub(when: "status", "exit 128")
        defer { try? FileManager.default.removeItem(at: stub) }
        let head = try git("rev-parse", "--short=12", "HEAD")
        let r = try run("/bin/bash", ["scripts/stamp-version.sh", versionFile, "--", "/bin/cat", versionFile], in: repo,
                        env: ["PATH": stub.path + ":/usr/bin:/bin"])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(stampedValue(r.out), head + "-dirty", r.out)
    }

}
