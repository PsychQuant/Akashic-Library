import XCTest
import Foundation

/// akashic-mcp plugin 的 SessionStart hook `plugin/hooks/check-cli.sh`（#775）。
///
/// 移植自 safari-browser 的 `hooks/check-cli.sh`。每支測試在暫存目錄裡組一個世界：
///   · `src/`：暫存的原始碼 repo，commit 的時間由測試指定，`refs/remotes/origin/main` 由測試自建；
///   · `plugin/`：真的 hook 與真的 `akashic-fetch-fulltext/SKILL.md`（契約數字從這裡抽）；
///   · `stubs/bin/akashic`：假 CLI，依環境變數印 `--version`、`fulltext contract`，或回 64、或卡住；
///   · `home/`：暫存 HOME。
/// 不連網、不碰真的 `~/bin/akashic`。
///
/// **契約數字不寫死**：要求值取自測試建置的 `akashic fulltext contract`（即 `FulltextFetch.contractVersion`）。
/// `testRealSkillRequirementMatchesTheCLIConstant` 因此同時釘住兩件事：hook 抽得到 SKILL 第 0 步的數字，
/// 以及那個數字等於 CLI 的契約常數——升契約版本卻忘了改 SKILL，這支會紅。
final class CheckCLIHookTests: XCTestCase {
    private var root: URL!
    private var src: URL { root.appendingPathComponent("src") }
    private var shas: [String: String] = [:]   // 標籤 → 完整 sha

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// CLI 自己的契約常數（測試建置的 `akashic fulltext contract`）。
    private static let required: Int = {
        let r = try? CLITestHarness.run(["fulltext", "contract"], env: [:])
        let line = r?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(line.replacingOccurrences(of: "fulltext-contract ", with: "")) ?? -1
    }()

    override func setUpWithError() throws {
        XCTAssertGreaterThan(Self.required, 0, "讀不到測試建置的 fulltext contract")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("checkcli-\(UUID().uuidString)")
        let fm = FileManager.default
        for d in ["home", "src", "stubs/bin", "plugin/hooks", "plugin/skills/akashic-fetch-fulltext"] {
            try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try fm.copyItem(at: Self.repoRoot.appendingPathComponent("plugin/hooks/check-cli.sh"),
                        to: root.appendingPathComponent("plugin/hooks/check-cli.sh"))
        try fm.copyItem(at: Self.repoRoot.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"),
                        to: root.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"))
        try writeExecutable("stubs/bin/akashic", Self.fakeCLI)

        // 原始碼 repo：A 動 Sources、B 只動文件、C 動 Sources、D 動 Package.swift
        try git("init", "-q")
        try commit("A", ["Sources/akashic/a.swift": "// a\n"], date: "2026-01-01T12:00:00+08:00")
        try commit("B", ["README.md": "docs\n"], date: "2026-01-02T12:00:00+08:00")
        try commit("C", ["Sources/AkashicCore/c.swift": "// c\n"], date: "2026-01-03T12:00:00+08:00")
        try commit("D", ["Package.swift": "// package\n"], date: "2026-01-04T12:00:00+08:00")
        try git("update-ref", "refs/remotes/origin/main", shas["D"]!)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - fixture helpers

    private static let fakeCLI = """
        #!/bin/bash
        [ -n "${CALL_LOG:-}" ] && echo "$*" >> "$CALL_LOG"
        case "$1" in
          --version)
            [ -n "${FAKE_VERSION_HANG:-}" ] && exec /bin/sleep 30
            if [ "${FAKE_VERSION_RC:-0}" != 0 ]; then echo "Error: Unknown option '--version'" >&2; exit 64; fi
            echo "${FAKE_VERSION:-unknown}" ;;
          fulltext)
            [ "$2" = contract ] || exit 64
            if [ -z "${FAKE_CONTRACT:-}" ]; then echo "Error: Unexpected argument 'contract'" >&2; exit 64; fi
            echo "fulltext-contract $FAKE_CONTRACT" ;;
          *) exit 64 ;;
        esac
        """

    private func writeExecutable(_ rel: String, _ text: String) throws {
        let u = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
    }

    private func gitEnvironment(date: String? = nil) -> [String: String] {
        var env: [String: String] = ["PATH": "/usr/bin:/bin", "HOME": root.appendingPathComponent("home").path,
                                     "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
                                     "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
                                     "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"]
        if let date { env["GIT_AUTHOR_DATE"] = date; env["GIT_COMMITTER_DATE"] = date }
        return env
    }

    @discardableResult
    private func git(_ args: String..., date: String? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = src
        p.environment = gitEnvironment(date: date)
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e; p.standardInput = FileHandle.nullDevice
        try p.run()
        let out = o.fileHandleForReading.readDataToEndOfFile()
        let err = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "CheckCLIHookTests", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "git \(args)：\(String(decoding: err, as: UTF8.self))"])
        }
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit(_ label: String, _ files: [String: String], date: String) throws {
        for (path, text) in files {
            let u = src.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try git("add", "-A")
        try git("commit", "-q", "-m", label, date: date)
        shas[label] = try git("rev-parse", "HEAD")
    }

    private func short(_ label: String) throws -> String { try git("rev-parse", "--short=12", shas[label]!) }

    private func setBinaryTime(_ iso: String, at rel: String = "stubs/bin/akashic") throws {
        let date = ISO8601DateFormatter().date(from: iso)!
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: root.appendingPathComponent(rel).path)
    }

    private struct HookResult { let status: Int32; let out: String; let err: String; let seconds: Double }

    private func runHook(_ env: [String: String] = [:], onPath: Bool = true,
                         sourceDir: String? = nil) throws -> HookResult {
        var e = gitEnvironment()
        e["PATH"] = (onPath ? root.appendingPathComponent("stubs/bin").path + ":" : "") + "/usr/bin:/bin"
        e["CLAUDE_PLUGIN_ROOT"] = root.appendingPathComponent("plugin").path
        e["AKASHIC_SOURCE_DIR"] = sourceDir ?? src.path
        for (k, v) in env { e[k] = v }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [root.appendingPathComponent("plugin/hooks/check-cli.sh").path]
        p.environment = e
        let o = Pipe(), er = Pipe()
        p.standardOutput = o; p.standardError = er; p.standardInput = FileHandle.nullDevice
        let start = Date()
        try p.run()
        let out = o.fileHandleForReading.readDataToEndOfFile()
        let err = er.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return HookResult(status: p.terminationStatus, out: String(decoding: out, as: UTF8.self),
                          err: String(decoding: err, as: UTF8.self), seconds: Date().timeIntervalSince(start))
    }

    private func assertQuietSuccess(_ r: HookResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.status, 0, r.out, file: file, line: line)
        XCTAssertEqual(r.err, "", "hook 不得寫 stderr", file: file, line: line)
    }

    private let behind = "落後原始碼"
    private let olderThanSource = "比原始碼舊"
    private let fallsBack = "改比檔案時間"

    // MARK: - CLI 在不在

    func testMissingCLIPrintsTheBuildInstructions() throws {
        let r = try runHook(onPath: false)
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("找不到 akashic CLI"), r.out)
        XCTAssertTrue(r.out.contains("scripts/stamp-version.sh Sources/akashic/BuildVersion.swift -- swift build -c release --product akashic"), r.out)
        XCTAssertTrue(r.out.contains("install -m 755"), r.out)
        XCTAssertFalse(r.out.contains("git clone"), "原始碼目錄在時不必 clone：\(r.out)")
    }

    func testMissingCLIAndMissingSourceSaysToCloneFirst() throws {
        let r = try runHook(onPath: false, sourceDir: root.appendingPathComponent("nowhere").path)
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("git clone"), r.out)
    }

    func testCLIOnlyInHomeBinIsFoundAndSaidToBeOffPath() throws {
        try writeExecutable("home/bin/akashic", Self.fakeCLI)
        let r = try runHook(["FAKE_VERSION": try short("D"), "FAKE_CONTRACT": "\(Self.required)"], onPath: false)
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("✓ akashic CLI"), r.out)
        XCTAssertTrue(r.out.contains("不在 PATH 上"), r.out)
    }

    // MARK: - 契約

    func testRealSkillRequirementMatchesTheCLIConstant() throws {
        let low = try runHook(["FAKE_VERSION": try short("D"), "FAKE_CONTRACT": "\(Self.required - 1)"])
        assertQuietSuccess(low)
        XCTAssertTrue(low.out.contains("fulltext 契約是 \(Self.required - 1)，akashic-fetch-fulltext 要求 ≥ \(Self.required)"),
                      "SKILL 第 0 步的要求值應等於 CLI 的契約常數 \(Self.required)：\(low.out)")
        let ok = try runHook(["FAKE_VERSION": try short("D"), "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(ok)
        XCTAssertFalse(ok.out.contains("契約"), "契約足夠時不出聲：\(ok.out)")
        XCTAssertFalse(ok.out.contains(behind), ok.out)
    }

    func testCLIWithoutTheContractSubcommandIsReported() throws {
        let r = try runHook(["FAKE_VERSION_RC": "64"])   // 比 #775 還舊、也比契約 4 還舊的 CLI
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("讀不到 akashic CLI 的 fulltext 契約"), r.out)
        XCTAssertTrue(r.out.contains("要求 ≥ \(Self.required)"), r.out)
    }

    func testSkillWithoutTheStepZeroLineIsSaidNotPassed() throws {
        try "# no contract line here\n".write(to: root.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"),
                                              atomically: true, encoding: .utf8)
        let r = try runHook(["FAKE_VERSION": try short("D"), "FAKE_CONTRACT": "1"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("讀不到 akashic-fetch-fulltext 要求的契約版本"), r.out)
        XCTAssertFalse(r.out.contains("fulltext 契約是"), "抽不到要求值就不比對：\(r.out)")
    }

    func testWithoutASourceCheckoutOnlyTheContractIsCompared() throws {
        try setBinaryTime("2025-01-01T00:00:00+08:00")
        let r = try runHook(["FAKE_VERSION": try short("A"), "FAKE_CONTRACT": "\(Self.required - 1)"],
                            sourceDir: root.appendingPathComponent("nowhere").path)
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("fulltext 契約是 \(Self.required - 1)"), r.out)
        XCTAssertFalse(r.out.contains(behind), r.out)
        XCTAssertFalse(r.out.contains(olderThanSource), r.out)
    }

    // MARK: - 落後幾個 commit

    func testCountsOnlyCommitsTouchingThePackageSource() throws {
        let r = try runHook(["FAKE_VERSION": try short("A"), "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("\(behind)"), r.out)
        XCTAssertTrue(r.out.contains("有 2 個 commit 動到 package 原始碼"), "B 只改文件，不算：\(r.out)")
        XCTAssertTrue(r.out.contains("origin/main"), r.out)
        XCTAssertTrue(r.out.contains("scripts/stamp-version.sh"), "落後時要給重建指令：\(r.out)")
    }

    func testDirtyBuildSaysSomeChangesMayAlreadyBeIn() throws {
        let r = try runHook(["FAKE_VERSION": try short("A") + "-dirty", "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("有 2 個 commit"), r.out)
        XCTAssertTrue(r.out.contains("未 commit 的修改"), r.out)
    }

    func testOriginMainIsPreferredOverAStaleHead() throws {
        try git("checkout", "-q", shas["B"]!)   // checkout 停在 B；origin/main 是 D
        let r = try runHook(["FAKE_VERSION": try short("A"), "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("有 2 個 commit"), "應以 origin/main 計數，不是落後的 HEAD：\(r.out)")
    }

    func testHeadIsTheBaseWhenThereIsNoOriginMain() throws {
        try git("update-ref", "-d", "refs/remotes/origin/main")
        try git("checkout", "-q", shas["C"]!)
        let r = try runHook(["FAKE_VERSION": try short("A"), "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("HEAD 有 1 個 commit"), r.out)
    }

    func testABuildWithTheSameSourceAsTheBaseIsUpToDate() throws {
        // squash merge 的常態：建置的 commit 不在基準的歷史裡，但 package 原始碼與基準相同
        try commit("S", ["README.md": "squashed\n"], date: "2026-01-05T12:00:00+08:00")
        let r = try runHook(["FAKE_VERSION": try short("S"), "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertFalse(r.out.contains(behind), r.out)
        XCTAssertFalse(r.out.contains(fallsBack), r.out)
    }

    func testABuildNewerThanTheBaseExplainsAndFallsBackToFileTimes() throws {
        try commit("N", ["Sources/akashic/n.swift": "// n\n"], date: "2026-01-05T12:00:00+08:00")
        try setBinaryTime("2026-01-06T00:00:00+08:00")
        let r = try runHook(["FAKE_VERSION": try short("N"), "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("比 origin/main 新"), r.out)
        XCTAssertTrue(r.out.contains(fallsBack), r.out)
        XCTAssertFalse(r.out.contains(olderThanSource), "binary 比基準的最後一次修改新：\(r.out)")
    }

    func testABuildFromAnUnknownCommitExplainsAndFallsBack() throws {
        try setBinaryTime("2026-01-03T00:00:00+08:00")   // 比 D（01-04）舊
        let r = try runHook(["FAKE_VERSION": "0123456789ab", "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains("沒有這個 commit"), r.out)
        XCTAssertTrue(r.out.contains(olderThanSource), r.out)
    }

    // MARK: - 檔案時間

    func testUnknownVersionComparesFileTimes() throws {
        try setBinaryTime("2026-01-03T00:00:00+08:00")
        let old = try runHook(["FAKE_VERSION": "unknown", "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(old)
        XCTAssertTrue(old.out.contains(olderThanSource), old.out)
        XCTAssertTrue(old.out.contains("scripts/stamp-version.sh"), old.out)

        try setBinaryTime("2026-01-10T00:00:00+08:00")
        let fresh = try runHook(["FAKE_VERSION": "unknown", "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(fresh)
        XCTAssertFalse(fresh.out.contains(olderThanSource), fresh.out)
    }

    func testACLIThatRejectsVersionComparesFileTimes() throws {
        try setBinaryTime("2026-01-03T00:00:00+08:00")
        let r = try runHook(["FAKE_VERSION_RC": "64", "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        XCTAssertTrue(r.out.contains(olderThanSource), r.out)
    }

    // MARK: - 卡住

    func testAHangingVersionProbeIsBoundedAndSkipsTheSecondProbe() throws {
        let log = root.appendingPathComponent("calls.log")
        let r = try runHook(["FAKE_VERSION_HANG": "1", "FAKE_CONTRACT": "\(Self.required)", "CALL_LOG": log.path])
        assertQuietSuccess(r)
        XCTAssertLessThan(r.seconds, 7, "單次探測的上限約 4 秒")
        XCTAssertTrue(r.out.contains("✓ akashic CLI"), r.out)
        // 只量時間證不到「沒有探第二次」：假 CLI 的 `fulltext contract` 不會卡，探了也只多零點幾秒。直接看它被叫了什麼。
        let calls = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        XCTAssertTrue(calls.contains("--version"), "應該探過 --version：\(calls)")
        XCTAssertFalse(calls.contains("fulltext"), "--version 逾時就不該再探契約：\(calls)")
    }

    // MARK: - 正常

    func testAnUpToDateCLIPrintsOneLine() throws {
        let r = try runHook(["FAKE_VERSION": try short("D"), "FAKE_CONTRACT": "\(Self.required)"])
        assertQuietSuccess(r)
        let lines = r.out.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, r.out)
        XCTAssertTrue(r.out.contains("✓ akashic CLI"), r.out)
        XCTAssertTrue(r.out.contains(try short("D")), r.out)
    }
}
