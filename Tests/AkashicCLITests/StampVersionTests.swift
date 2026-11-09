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

    private func run(_ exe: String, _ args: [String], in dir: URL) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = scrubbedGitEnvironment
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

    func testTermDuringTheCommandRestoresThePlaceholder() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["scripts/stamp-version.sh", versionFile, "--", "/bin/sleep", "30"]
        p.currentDirectoryURL = repo
        p.environment = scrubbedGitEnvironment
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        // 等到佔位檔被改寫（腳本已進入「命令執行中」），再送 TERM
        let deadline = Date().addingTimeInterval(10)
        while (try? currentFile()) == placeholder && Date() < deadline { usleep(50_000) }
        XCTAssertNotEqual(try currentFile(), placeholder, "10 秒內沒有看到戳記值寫進去")
        p.terminate()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 143)
        XCTAssertEqual(try currentFile(), placeholder, "收到 TERM 之後佔位檔要回到原樣")
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
}
