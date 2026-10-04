import XCTest
import Foundation

/// #629：由 Python／shell 移植的 skill 中間運算的 CLI 面——真 binary。`AkashicKitTests` 已逐案釘住各型別的行為；這裡只驗**命令接得起來**：
/// 引數、結束碼、stdout／stderr 的分工、不寫 store。沙箱紀律同其他 CLI 測試（`AKASHIC_HOME`／`HOME` 指 scratch）。
final class SkillToolsCLITests: XCTestCase {
    private var base: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-skilltools-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private var env: [String: String] { ["AKASHIC_HOME": home.appendingPathComponent(".akashic-home").path, "HOME": home.path] }

    private func run(_ args: [String]) throws -> (status: Int32, output: String) { try CLITestHarness.run(args, env: env) }

    /// stdout 與 stderr 分開收，並可餵 stdin（`bot-signals` 從 stdin 讀）。
    private func runSplit(_ args: [String], stdin: Data? = nil) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
        p.arguments = args
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        for (k, v) in env { childEnv[k] = v }
        p.environment = childEnv
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        try p.run()
        if let stdin { inp.fileHandleForWriting.write(stdin) }
        try? inp.fileHandleForWriting.close()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    private func makePDF(lines: [String]) -> Data {
        let text = "BT /F1 12 Tf 72 720 Td 14 TL " + lines.map { "(\($0)) Tj T*" }.joined(separator: " ") + " ET"
        let objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
                    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Length \(text.utf8.count) >>\nstream\n\(text)\nendstream"]
        var out = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (i, o) in objs.enumerated() { offsets.append(out.count); out.append(Data("\(i + 1) 0 obj\n\(o)\nendobj\n".utf8)) }
        let xref = out.count
        out.append(Data("xref\n0 \(objs.count + 1)\n0000000000 65535 f \n".utf8))
        for o in offsets { out.append(Data(String(format: "%010d 00000 n \n", o).utf8)) }
        out.append(Data("trailer\n<< /Size \(objs.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return out
    }

    private func hasPoppler() -> Bool {
        let r = try? runTool(["pdftotext", "-v"])
        return r != nil
    }

    private func runTool(_ argv: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        if p.terminationStatus == 127 { throw NSError(domain: "x", code: 127) }
        return p.terminationStatus
    }

    // MARK: fulltext

    func testVerifyPrintsTheJudgementAndExitsByIt() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let pdf = base.appendingPathComponent("own.pdf")
        try makePDF(lines: ["A Stub Title For Path Tests", "doi:10.1234/x", "Abstract"]).write(to: pdf)
        let ok = try runSplit(["fulltext", "verify", pdf.path, "--title", "A Stub Title For Path Tests", "--pages", "1--1", "--doi", "10.1234/x"])
        XCTAssertEqual(ok.status, 0, ok.err)
        XCTAssertTrue(ok.out.contains("\"doi_state\": \"page-match\""), ok.out)
        XCTAssertTrue(ok.out.contains("\"is_article\": true"), ok.out)
        XCTAssertTrue(ok.out.hasPrefix("{\"page_count\": 1, \"expected_pages\": 1, \"pages_ok\": true, \"title_match\": \"exact\""), ok.out)
        // 另一篇的 DOI：拒收、結束碼 1
        let bad = try runSplit(["fulltext", "verify", pdf.path, "--title", "A Stub Title For Path Tests", "--pages", "1--1", "--doi", "10.1234/other"])
        XCTAssertEqual(bad.status, 1)
        XCTAssertTrue(bad.out.contains("\"doi_state\": \"page-mismatch\""), bad.out)
        // 沒有 DOI：永不自動收
        XCTAssertEqual(try runSplit(["fulltext", "verify", pdf.path, "--title", "A Stub Title For Path Tests"]).status, 1)
    }

    func testVerifyOnANonPDFReportsAnErrorObject() throws {
        let f = base.appendingPathComponent("not.pdf")
        try Data("<html></html>".utf8).write(to: f)
        let r = try runSplit(["fulltext", "verify", f.path, "--title", "T"])
        XCTAssertEqual(r.status, 1)
        XCTAssertEqual(r.out, "{\"error\": \"not a PDF (no %PDF- header)\", \"is_article\": false}\n")
        // 缺 --title 是用法錯誤
        XCTAssertEqual(try runSplit(["fulltext", "verify", f.path]).status, 64)
    }

    /// #613：出版商拼網址規則刪除，子命令一起拿掉——舊的呼叫端得到命令列錯誤，而不是一個悄悄不同的答案。
    func testURLRuleIsGone() throws {
        XCTAssertEqual(try runSplit(["fulltext", "url-rule", "https://onlinelibrary.wiley.com/doi/10.1111/jopy.12964"]).status, 64)
    }

    func testBotSignalsReadsStdinAndExitsByWhetherItHit() throws {
        let hit = try runSplit(["fulltext", "bot-signals"], stdin: Data("<title>Just a moment...</title>".utf8))
        XCTAssertEqual(hit.status, 0)
        XCTAssertEqual(hit.out, "cloudflare-challenge\n")
        let clean = try runSplit(["fulltext", "bot-signals"], stdin: Data("An ordinary article about panel models".utf8))
        XCTAssertEqual(clean.status, 1)
        XCTAssertEqual(clean.out, "")
        XCTAssertEqual(try runSplit(["fulltext", "bot-signals", "--status", "429"], stdin: Data()).out, "http-429\n")
        // 非 UTF-8 的本文（舊 Python 版在這裡當掉、被 shell 的 `&&` 吞成「沒有訊號」）：照掃，不因解碼失敗而漏掉挑戰頁
        let binary = try runSplit(["fulltext", "bot-signals"], stdin: Data([0xFF, 0xFE] + Array("Just a moment...".utf8)))
        XCTAssertEqual(binary.out, "cloudflare-challenge\n")
        // #613：`--kind` 另印處置；命中的結束碼仍一律是 0（舊的呼叫端以 0＝停寫成）
        let verify = try runSplit(["fulltext", "bot-signals", "--kind"], stdin: Data("<title>Just a moment...</title>".utf8))
        XCTAssertEqual(verify.status, 0)
        XCTAssertEqual(verify.out, "cloudflare-challenge\tverify\n")
        let pause = try runSplit(["fulltext", "bot-signals", "--kind"], stdin: Data("Preparing your download".utf8))
        XCTAssertEqual(pause.status, 0)
        XCTAssertEqual(pause.out, "sciencedirect-download-challenge\tpause\n")
        XCTAssertEqual(try runSplit(["fulltext", "bot-signals", "--kind", "--status", "403"], stdin: Data()).out, "http-403\tpause\n")
        XCTAssertEqual(try runSplit(["fulltext", "bot-signals", "--kind"], stdin: Data("plain".utf8)).status, 1)
    }

    func testJitterDryRunPrintsAnIntervalInsideTheBoundsAndRejectsBadParameters() throws {
        let r = try runSplit(["fulltext", "jitter", "--dry-run"])
        XCTAssertEqual(r.status, 0, r.err)
        let x = Double(r.out.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNotNil(x, r.out)
        XCTAssertTrue((2.0...60.0).contains(x!), r.out)
        XCTAssertNotNil(r.out.range(of: #"^\d+\.\d{2}\n$"#, options: .regularExpression), "兩位小數（舊腳本的 %.2f）：\(r.out)")
        let bad = try runSplit(["fulltext", "jitter", "--dry-run", "--min", "5", "--max", "4"])
        XCTAssertEqual(bad.status, 64)
        XCTAssertTrue(bad.err.contains("need 0 <= min < median < max"), bad.err)
    }

    private var ledger: String { base.appendingPathComponent("ledger.jsonl").path }

    func testFetchRefusesAMissingSafariBrowserAndAMissingWindow() throws {
        let missing = try runSplit(["fulltext", "fetch", "--window", "1", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x", "--ledger", ledger,
                                    "--bin", base.appendingPathComponent("no-such-binary").path])
        XCTAssertEqual(missing.status, 1)
        XCTAssertTrue(missing.err.contains("safari-browser not found"), missing.err)
        // 一個只印 `[]` 的假 safari-browser：視窗不存在 → 結束碼 1，而且沒有開任何分頁
        let stub = base.appendingPathComponent("stub-safari")
        let log = base.appendingPathComponent("calls.log")
        try "#!/bin/sh\necho \"$@\" >> '\(log.path)'\nif [ \"$1\" = documents ]; then echo '[]'; fi\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let r = try runSplit(["fulltext", "fetch", "--window", "5", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x", "--ledger", ledger, "--bin", stub.path])
        XCTAssertEqual(r.status, 1, r.err)
        XCTAssertTrue(r.err.contains("Safari window 5 not found"), r.err)
        let calls = try String(contentsOf: log, encoding: .utf8)
        XCTAssertEqual(calls, "documents --json\n", "只該問過 documents：\(calls)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledger), "沒走到準備取 PDF，帳本不建")
        XCTAssertEqual(try runSplit(["fulltext", "fetch", "--window", "0", "--expect-profile", "own", "--landing", "x"]).status, 64)
    }

    /// `--expect-profile` 是唯一防止動到別人的 Safari session 的檢查：文件一直寫「一律帶」，命令列現在強制（R1 verify 第 31 則）。
    func testFetchRequiresAnExpectedProfile() throws {
        let noProfile = try runSplit(["fulltext", "fetch", "--window", "5", "--landing", "https://doi.org/10.1/x"])
        XCTAssertEqual(noProfile.status, 64, noProfile.err)
        XCTAssertTrue(noProfile.err.contains("expect-profile"), noProfile.err)
        let empty = try runSplit(["fulltext", "fetch", "--window", "5", "--expect-profile", "", "--landing", "https://doi.org/10.1/x"])
        XCTAssertEqual(empty.status, 64, empty.err)
    }

    /// #613：`fetch` 不再收輸出與驗證的旗標（它不取位元組）、不再有 `--prime`；舊的呼叫以命令列錯誤失敗，不會被讀成「存好了」。
    /// `--resume-tab` 與 `--resume-origin` 一起給，origin 要恰好是 `https://<主機>`。
    func testFetchRejectsTheRetiredFlagsAndHalfAResume() throws {
        let common = ["fulltext", "fetch", "--window", "5", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x", "--ledger", ledger]
        for extra in [["--out", "w.pdf"], ["--title", "T"], ["--pages", "1--2"], ["--doi", "10.1/x"], ["--prime", "https://pub.example/x.pdf"],
                      ["--resume-tab", "2"], ["--resume-origin", "https://pub.example"], ["--resume-tab", "0", "--resume-origin", "https://pub.example"],
                      ["--resume-tab", "2", "--resume-origin", "https://pub.example/path"], ["--resume-tab", "2", "--resume-origin", "http://pub.example"]] {
            let r = try runSplit(common + extra)
            XCTAssertEqual(r.status, 64, "\(extra)：\(r.err)")
        }
    }

    func testTakeSavesAVerifiedCopyAndLeavesTheSourceAlone() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let saved = base.appendingPathComponent("Downloads-copy.pdf")
        let pdf = makePDF(lines: ["A Stub Title For Path Tests", "doi:10.1234/x", "Abstract"])
        try pdf.write(to: saved)
        let outDir = base.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let ok = try runSplit(["fulltext", "take", "--from", saved.path, "--out", outDir.appendingPathComponent("k.pdf").path,
                               "--title", "A Stub Title For Path Tests", "--pages", "1--1", "--doi", "10.1234/x"])
        XCTAssertEqual(ok.status, 0, ok.err)
        XCTAssertEqual(try Data(contentsOf: outDir.appendingPathComponent("k.pdf")), pdf)
        XCTAssertEqual(try Data(contentsOf: saved), pdf, "--from 不動")
        let other = try runSplit(["fulltext", "take", "--from", saved.path, "--out", outDir.appendingPathComponent("m.pdf").path,
                                  "--title", "A Stub Title For Path Tests", "--pages", "1--1", "--doi", "10.1234/other"])
        XCTAssertEqual(other.status, 5, other.err)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("m.unverified.pdf").path))
        let html = base.appendingPathComponent("page.html")
        try Data("<html></html>".utf8).write(to: html)
        XCTAssertEqual(try runSplit(["fulltext", "take", "--from", html.path, "--out", outDir.appendingPathComponent("h.pdf").path, "--title", "T"]).status, 2)
        XCTAssertEqual(try runSplit(["fulltext", "take", "--from", saved.path]).status, 64, "缺 --out 是用法錯誤")
    }

    /// 使用者 2026-10-02：`--title` 必填、不得是空的。`--title "$(cat 缺的檔)"` 的形狀（SKILL 第 4 步）給的是空字串——不是「免驗證」。
    func testTakeRequiresANonEmptyTitle() throws {
        let saved = base.appendingPathComponent("saved.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: saved)
        let out = base.appendingPathComponent("o.pdf").path
        let missing = try runSplit(["fulltext", "take", "--from", saved.path, "--out", out])
        XCTAssertEqual(missing.status, 64, missing.err)
        let empty = try runSplit(["fulltext", "take", "--from", saved.path, "--out", out, "--title", ""])
        XCTAssertEqual(empty.status, 64, empty.err)
        XCTAssertTrue(empty.err.contains("--title"), empty.err)
        let blank = try runSplit(["fulltext", "take", "--from", saved.path, "--out", out, "--title", "  ", "--doi", "10.1/x"])
        XCTAssertEqual(blank.status, 64, blank.err)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out), "什麼都沒寫")
    }

    func testFetchResumeStageIsValidated() throws {
        let common = ["fulltext", "fetch", "--window", "5", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x", "--ledger", ledger]
        XCTAssertEqual(try runSplit(common + ["--resume-tab", "2", "--resume-origin", "https://pub.example", "--resume-stage", "later"]).status, 64)
        XCTAssertEqual(try runSplit(common + ["--resume-stage", "followed"]).status, 64, "沒有 --resume-tab 就不能有 --resume-stage")
    }

    // MARK: SKILL 第 0 步的 CLI 探測（#613 R2 verify 第 4、13、24 則）

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    /// SKILL.md 第 0 步的 bash 區塊原文。
    private func stepZeroBlock() throws -> String {
        let skill = try String(contentsOf: repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        guard let step = skill.range(of: "0. **確認 `akashic` CLI"),
              let fence = skill.range(of: "```bash\n", range: step.upperBound..<skill.endIndex),
              let close = skill.range(of: "```", range: fence.upperBound..<skill.endIndex) else {
            XCTFail("SKILL 第 0 步找不到 bash 區塊"); return ""
        }
        return String(skill[fence.upperBound..<close.lowerBound])
    }

    /// 把一段第 0 步的 bash（預設是 SKILL.md 現在的原文）在一個只放了指定 `akashic` 的 PATH 上跑；回（結束碼，stdout＋stderr）。
    private func runStepZeroProbe(akashic: URL, block given: String? = nil) throws -> (status: Int32, output: String) {
        let raw = try given ?? stepZeroBlock()
        let work = base.appendingPathComponent("probe-\(UUID().uuidString)")
        let bin = work.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("akashic"), withDestinationURL: akashic)
        let block = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        let script = block.replacingOccurrences(of: "<暫存目錄>", with: work.path) + "\necho PROBE-PASSED\n"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script]
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        for (k, v) in env { childEnv[k] = v }
        childEnv["PATH"] = bin.path + ":/usr/bin:/bin"
        p.environment = childEnv
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// 第 0 步要分得出比這一輪舊的 CLI：上一輪的 `take` 對 `--title ""` 跳過驗證、結束碼 0，而 SKILL 把 0 讀成「驗證過」。先前的探測只問
    /// 「`take` 在不在」——舊的 `take` 一樣回 1 加 `--from does not exist`，所以照樣通過。這裡跑 SKILL 裡的那段原文：真的 binary 要過；
    /// 一個對任何 `take` 都回 1 加 `--from does not exist` 的舊 CLI（不擋空標題）要被擋下。
    func testTheSkillsStepZeroProbeTellsThisCLIFromAnOlderOne() throws {
        let real = try runStepZeroProbe(akashic: CLITestHarness.productsDirectory.appendingPathComponent("akashic"))
        XCTAssertEqual(real.status, 0, real.output)
        XCTAssertTrue(real.output.contains("PROBE-PASSED"), real.output)

        let oldCLI = base.appendingPathComponent("old-akashic")
        try Data("#!/bin/sh\necho \"✗ --from does not exist: $4\" >&2\nexit 1\n".utf8).write(to: oldCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldCLI.path)
        let old = try runStepZeroProbe(akashic: oldCLI)
        XCTAssertNotEqual(old.status, 0, old.output)
        XCTAssertFalse(old.output.contains("PROBE-PASSED"), old.output)
        XCTAssertTrue(old.output.contains("先更新 CLI"), old.output)

        let missing = try runStepZeroProbe(akashic: base.appendingPathComponent("no-such-akashic"))
        XCTAssertNotEqual(missing.status, 0, "沒裝 CLI 也擋：\(missing.output)")
    }

    /// R2（e5182cf1）第 0 步的原文：只問 `take` 在不在、空的 `--title` 是不是 64。R1 起的 CLI 兩條都過，所以它分不出還沒套用 R2、R3 的 CLI
    /// （b31 W4 第 1 則）。留在這裡當對照：同一個舊 CLI 對它通過、對現在的第 0 步不通過。
    private static let r2StepZero = """
    W="<暫存目錄>"
    rc=0; akashic fulltext take --from "$W/does-not-exist.pdf" --out "$W/probe.pdf" --title probe 2>"$W/probe.err" || rc=$?
    [ "$rc" -eq 1 ] && grep -q -e '--from does not exist' -e 'refusing:' "$W/probe.err" \\
      || { echo "akashic CLI 比 #613 舊（或沒裝）" >&2; exit 1; }
    rc=0; akashic fulltext take --from "$W/does-not-exist.pdf" --out "$W/probe.pdf" --title "" 2>"$W/probe2.err" || rc=$?
    [ "$rc" -eq 64 ] \\
      || { echo "akashic CLI 比 #613 修正輪舊" >&2; exit 1; }
    """

    /// 一個行為與 R1／R2 的 CLI 相同的假 `akashic`：`take` 對空的 `--title` 回 64、對不存在的 `--from` 回 1；不認得 `contract`（ArgumentParser
    /// 對未知的子命令回 64）。
    private func writeR2LikeCLI() throws -> URL {
        let cli = base.appendingPathComponent("r2-akashic")
        let script = """
        #!/bin/sh
        if [ "$1" = fulltext ] && [ "$2" = take ]; then
          prev=""; title="unset"
          for a; do if [ "$prev" = "--title" ]; then title=$a; fi; prev=$a; done
          if [ -z "$title" ]; then echo "Error: --title 不得是空的" >&2; exit 64; fi
          echo "✗ --from does not exist: x" >&2; exit 1
        fi
        echo "Error: Unexpected argument '$2'" >&2
        exit 64
        """
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        return cli
    }

    /// 第 0 步要分得出 R3 以前的 CLI（b31 W4 第 1 則）：R2 的探測對 R1／R2 的 CLI 照樣通過，而 SKILL 依賴的是這一輪的契約（別的主機上讀不到的
    /// 分頁交給人、落地頁登入長相先判、分類用同一份快照）。現在的第 0 步問 `fulltext contract` 印的版本——唯讀、不碰瀏覽器、不連網。
    func testTheStepZeroProbeTellsAnR2CLIFromThisOne() throws {
        let r2 = try writeR2LikeCLI()
        let underOldProbe = try runStepZeroProbe(akashic: r2, block: Self.r2StepZero)
        XCTAssertEqual(underOldProbe.status, 0, "對照：舊的探測分不出它——\(underOldProbe.output)")
        XCTAssertTrue(underOldProbe.output.contains("PROBE-PASSED"), underOldProbe.output)

        let underNewProbe = try runStepZeroProbe(akashic: r2)
        XCTAssertNotEqual(underNewProbe.status, 0, underNewProbe.output)
        XCTAssertFalse(underNewProbe.output.contains("PROBE-PASSED"), underNewProbe.output)
        XCTAssertTrue(underNewProbe.output.contains("先更新 CLI"), underNewProbe.output)
    }

    /// 第 0 步擋得住契約 4 的 CLI（#613 R3）：b34 起文章站上讀不到的分頁、登入主機上的讀不到的分頁、主機標籤與路徑段的判斷都變了，
    /// 照這份 SKILL 跑的 agent 不能拿 R3 的 CLI 跑（b33 X3 第 25、27 則：版本號是手動的常數，行為變了要往上調）。
    func testTheStepZeroProbeTellsAnR3CLIFromThisOne() throws {
        let cli = base.appendingPathComponent("r3-akashic")
        try "#!/bin/sh\nif [ \"$1\" = fulltext ] && [ \"$2\" = contract ]; then echo 'fulltext-contract 4'; exit 0; fi\nexit 64\n"
            .write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let probe = try runStepZeroProbe(akashic: cli)
        XCTAssertNotEqual(probe.status, 0, probe.output)
        XCTAssertFalse(probe.output.contains("PROBE-PASSED"), probe.output)
    }

    /// SKILL 第 0 步要求的版本就是這個 binary 印的版本：版本號往上調時 SKILL 要一起調（要求高於 binary，真的 CLI 也過不了第 0 步；
    /// 要求低於 binary，舊的 CLI 會被放過）。
    func testTheContractVersionTheSkillRequiresIsTheOneThisCLIPrints() throws {
        let block = try stepZeroBlock()
        let required = block.range(of: #"-ge [0-9]+"#, options: .regularExpression).map { Int(block[$0].dropFirst(4))! }
        let r = try runSplit(["fulltext", "contract"])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.hasPrefix("fulltext-contract "), r.out)
        let printed = Int(r.out.dropFirst("fulltext-contract ".count).trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNotNil(required, block)
        XCTAssertEqual(required, printed, "SKILL 要 \(String(describing: required))、binary 印 \(r.out)")
        XCTAssertEqual(r.err, "", "不碰瀏覽器、不連網：沒有任何訊息")
    }

    // MARK: 每站上限的跨行程競爭（#613 修正輪）

    /// 一個只夠走到記錄嘗試那一步、導航之後顯示 PDF 的假 safari-browser（一個 shell 腳本）。
    private func writeRaceStub() throws -> URL {
        let state = base.appendingPathComponent("stub-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let stub = base.appendingPathComponent("race-safari")
        let script = """
        #!/bin/sh
        S='\(state.path)'
        case "$1" in
          documents)
            if [ -f "$S/navigated" ]; then u='https://pub.example/doi/pdf/10.1/x'; else u='https://pub.example/doi/10.1/x'; fi
            printf '[{"window":5,"index":1,"tab_in_window":1,"url":"https://user.example/","title":"mine","profile":"own","is_current":false},{"window":5,"index":2,"tab_in_window":2,"url":"%s","title":"Article","profile":"own","is_current":true}]\\n' "$u" ;;
          open) case " $* " in *" --new-tab "*) : ;; *) : > "$S/navigated" ;; esac ;;
          js)
            for a; do last=$a; done
            case "$last" in
              *innerText.slice*) printf '\\nArticle\\nBody text\\n' ;;
              *document.contentType*) printf 'application/pdf\\ncomplete\\n' ;;
              *citation_pdf_url*) echo 'GET https://pub.example/doi/pdf/10.1/x' ;;
              *document.readyState*) echo complete ;;
            esac ;;
          wait) : ;;
          close) : ;;
        esac
        exit 0
        """
        try script.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        return stub
    }

    /// 兩個行程搶最後一格：測試自己扮演「正在 `reserve` 的另一個行程」——握著帳本的 `flock`、帳本裡有 9 筆。真的 `akashic fulltext fetch` 起來、
    /// 走到記錄嘗試那一步時必須**卡在鎖上**（沒有鎖的實作這時已經讀到 9、記成第 10 次、導航了）；測試記下第 10 筆、放鎖之後，`fetch` 重讀到 10，
    /// 以結束碼 9 停下，帳本剛好 10 筆。
    func testTwoProcessesRacingForTheLastSlotGrantExactlyOne() throws {
        let stub = try writeRaceStub()
        // 用「今天」：fetch 用真的時鐘，所以帳本裡的 9 筆也要是今天（Asia/Taipei）
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Taipei")!; f.formatOptions = [.withInternetDateTime]
        let nowStamp = f.string(from: Date())
        let line = "{\"at\":\"\(nowStamp)\",\"landing\":\"https://doi.org/10.1/y\",\"site\":\"pub.example\"}\n"
        try Data(String(repeating: line, count: 9).utf8).write(to: URL(fileURLWithPath: ledger))

        let fd = open(ledger, O_RDWR | O_APPEND)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX), 0)

        let p = Process()
        p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
        p.arguments = ["fulltext", "fetch", "--window", "5", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x", "--ledger", ledger, "--bin", stub.path]
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        for (k, v) in env { childEnv[k] = v }
        p.environment = childEnv
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        // fetch 的節拍有真的睡眠（頁面落定 2 秒）：等到它必然已走到記錄嘗試那一步
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(p.isRunning, "fetch 應該卡在帳本的鎖上，而不是已經記完、導航完離開")
        XCTAssertEqual((try String(contentsOfFile: ledger, encoding: .utf8)).split(separator: "\n").count, 9, "鎖著的時候帳本不動")

        // 扮演贏了最後一格的另一個行程：記第 10 筆、放鎖
        let tenth = Data(line.utf8)
        XCTAssertEqual(tenth.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }, tenth.count)
        XCTAssertEqual(flock(fd, LOCK_UN), 0)

        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 9, String(decoding: e, as: UTF8.self) + String(decoding: o, as: UTF8.self))
        XCTAssertTrue(String(decoding: e, as: UTF8.self).contains("DAILY CAP"))
        XCTAssertEqual((try String(contentsOfFile: ledger, encoding: .utf8)).split(separator: "\n").count, 10, "剛好 10 筆，不是 11")
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("stub-state/navigated").path), "沒有導航到 PDF")
    }

    /// 標題可以以連字號開頭：ArgumentParser 預設的 `.next` 策略會把它當成另一個旗標而 exit 64；舊 shell 的 `TITLE=$2` 什麼值都收。
    func testATitleThatStartsWithAHyphenIsAValueNotAFlag() throws {
        for title in ["-Omics of things", "-1 to 1", "--weird"] {
            let r = try runSplit(["fulltext", "verify", base.appendingPathComponent("missing.pdf").path, "--title", title, "--doi", "-x"])
            XCTAssertEqual(r.status, 1, "\(title)：\(r.err)")   // 檔案不存在 → 判定 JSON 的 error、結束碼 1；重點是沒有 64
            XCTAssertTrue(r.out.contains("\"is_article\": false"), r.out)
        }
        let equalsForm = try runSplit(["fulltext", "verify", base.appendingPathComponent("missing.pdf").path, "--title=-Omics"])
        XCTAssertEqual(equalsForm.status, 1, equalsForm.err)
    }

    func testCalibrateListsMissingCrossrefRecordsAndMeasuresTheRest() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let pdfs = base.appendingPathComponent("pdfs"), cr = base.appendingPathComponent("crossref")
        try FileManager.default.createDirectory(at: pdfs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cr, withIntermediateDirectories: true)
        try makePDF(lines: ["First Paper About Panel Models", "doi:10.1234/first", "Abstract"]).write(to: pdfs.appendingPathComponent("a.pdf"))
        try makePDF(lines: ["Second Paper About Growth Curves", "doi:10.1234/second", "Abstract"]).write(to: pdfs.appendingPathComponent("b.pdf"))
        // 只有第一篇有 Crossref 回應（檔名不重要，以 message.DOI 對回）
        try Data(#"{"status":"ok","message":{"DOI":"10.1234/FIRST","title":["First Paper About Panel Models"],"page":"1-1"}}"#.utf8)
            .write(to: cr.appendingPathComponent("r-7.json"))
        let missing = try runSplit(["fulltext", "calibrate", pdfs.path, "--crossref", cr.path])
        XCTAssertEqual(missing.status, 3, missing.err)
        XCTAssertTrue(missing.out.contains("缺 1 個 DOI 的 Crossref 回應"), missing.out)
        XCTAssertTrue(missing.out.contains("10.1234/second"), missing.out)
        XCTAssertFalse(missing.out.contains("own title accepted"), "缺記錄時不宣稱數字：\(missing.out)")
        try Data(#"{"message":{"DOI":"10.1234/second","title":["Second Paper About Growth Curves"],"subtitle":["A Subtitle"],"page":"5-5"}}"#.utf8)
            .write(to: cr.appendingPathComponent("r-8.json"))
        let done = try runSplit(["fulltext", "calibrate", pdfs.path, "--crossref", cr.path])
        XCTAssertEqual(done.status, 0, done.out + done.err)
        XCTAssertTrue(done.out.contains("files with a DOI and a Crossref title: 2"), done.out)
        XCTAssertTrue(done.out.contains("wrong title accepted:      0/2"), done.out)
    }

    /// 缺記錄的清單帶完整網址（不是要人自己拼的模板）；形狀不合格的 DOI 不組網址、單獨列出，而且同樣算「沒量到」（結束碼 3）。
    func testCalibrateListsFullURLsAndKeepsUnsafeDOIsOutOfThem() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let pdfs = base.appendingPathComponent("pdfs"), cr = base.appendingPathComponent("crossref")
        try FileManager.default.createDirectory(at: pdfs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cr, withIntermediateDirectories: true)
        try makePDF(lines: ["Paper A", "doi:10.1234/a(b)c", "Abstract"]).write(to: pdfs.appendingPathComponent("a.pdf"))
        try makePDF(lines: ["Paper B", "doi:10.1234/x$y", "Abstract"]).write(to: pdfs.appendingPathComponent("b.pdf"))
        let r = try runSplit(["fulltext", "calibrate", pdfs.path, "--crossref", cr.path])
        XCTAssertEqual(r.status, 3, r.err)
        XCTAssertTrue(r.out.contains("10.1234/a(b)c\thttps://api.crossref.org/works/10.1234/a%28b%29c"), "完整、百分比編碼的網址：\(r.out)")
        XCTAssertTrue(r.out.contains("另有 1 個 DOI 形狀不合格"), r.out)
        XCTAssertTrue(r.out.contains("10.1234/x$y"), r.out)
        XCTAssertFalse(r.out.contains("works/10.1234/x"), "不合格的 DOI 不組網址：\(r.out)")
    }

    /// 全零的數字不是校準結果：資料夾不存在是具名失敗，沒有任何可量的檔案是結束碼 4（不是 0）。
    func testCalibrateDoesNotReportAnEmptyMeasurementAsSuccess() throws {
        let cr = base.appendingPathComponent("crossref")
        try FileManager.default.createDirectory(at: cr, withIntermediateDirectories: true)
        let missingFolder = try runSplit(["fulltext", "calibrate", base.appendingPathComponent("no-such-folder").path, "--crossref", cr.path])
        XCTAssertEqual(missingFolder.status, 1, missingFolder.err)
        XCTAssertTrue(missingFolder.err.contains("不是資料夾"), missingFolder.err)
        let empty = base.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let none = try runSplit(["fulltext", "calibrate", empty.path, "--crossref", cr.path])
        XCTAssertEqual(none.status, 4, none.out + none.err)
        XCTAssertTrue(none.err.contains("沒有量到任何檔案"), none.err)
    }

    // MARK: crossref-match

    private func writeWorks() throws -> URL {
        let works = base.appendingPathComponent("works.json")
        try Data(#"[{"citekey":"k1","title":"A critique of the cross-lagged panel model","journal":"Psychological Methods","year":2015}]"#.utf8).write(to: works)
        return works
    }

    /// 缺請求 → stdout 是 JSON（`pending`），exit 3；存回應後重跑 → 結果檔、exit 0。
    func testCrossrefMatchAsksForRequestsThenCompletes() throws {
        let works = try writeWorks()
        let responses = base.appendingPathComponent("responses")
        try FileManager.default.createDirectory(at: responses, withIntermediateDirectories: true)
        let out = base.appendingPathComponent("result.json")
        let args = ["crossref-match", "--works", works.path, "--responses", responses.path, "-o", out.path]

        let first = try runSplit(args)
        XCTAssertEqual(first.status, 3, first.err)
        let pending = try JSONSerialization.jsonObject(with: Data(first.out.utf8)) as! [String: Any]
        let requests = pending["pending"] as! [[String: String]]
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0]["url"]!.hasPrefix("https://api.crossref.org/works?query.bibliographic=A+critique+of+the+cross-lagged+panel+model&rows=5&select="), requests[0]["url"]!)
        XCTAssertEqual(requests[0]["id"]!.count, 16)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "沒做完不寫結果檔")

        let item = #"{"DOI":"10.1037/a0038889","type":"journal-article","title":["A critique of the cross-lagged panel model"],"container-title":["Psychological Methods"],"published":{"date-parts":[[2015,3]]},"author":[]}"#
        try Data("{\"message\":{\"items\":[\(item)]}}".utf8).write(to: responses.appendingPathComponent(requests[0]["id"]! + ".json"))
        let second = try runSplit(args)
        XCTAssertEqual(second.status, 3, second.err)   // 反向驗證的單筆查詢
        let verify = try JSONSerialization.jsonObject(with: Data(second.out.utf8)) as! [String: Any]
        let verifyReq = (verify["pending"] as! [[String: String]])[0]
        XCTAssertEqual(verifyReq["url"], "https://api.crossref.org/works/10.1037/a0038889")
        try Data("{\"message\":\(item)}".utf8).write(to: responses.appendingPathComponent(verifyReq["id"]! + ".json"))

        let third = try runSplit(args)
        XCTAssertEqual(third.status, 0, third.err)
        XCTAssertTrue(third.err.contains("confident: 1"), third.err)
        let result = try JSONSerialization.jsonObject(with: Data(contentsOf: out)) as! [[String: Any]]
        XCTAssertEqual(result[0]["status"] as? String, "confident")
        XCTAssertEqual(result[0]["reverse_verified"] as? Bool, true)
        // 結果檔的形狀：indent=1、鍵順序與舊腳本相同
        let text = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("[\n {\n  \"citekey\": \"k1\",\n  \"status\": \"confident\",\n  \"how\": \"direct\",\n  \"best\": {\n   \"doi\": \"10.1037/a0038889\","), text)
        XCTAssertFalse(text.hasSuffix("\n"), "舊腳本的 json.dump 沒有結尾換行")
    }

    func testCrossrefMatchRejectsBadInputsByName() throws {
        let works = try writeWorks()
        let missingDir = try runSplit(["crossref-match", "--works", works.path, "--responses", base.appendingPathComponent("nope").path])
        XCTAssertEqual(missingDir.status, 1)
        XCTAssertTrue(missingDir.err.contains("--responses 不是目錄"), missingDir.err)
        XCTAssertEqual(try runSplit(["crossref-match", "--works", works.path, "--responses", base.path, "--mailto", "not an email"]).status, 64)
    }

    // MARK: abstracts-to-proposals

    private func ndjson() -> Data {
        Data("{\"doi\": \"10.1/a\", \"status\": \"got\", \"abstract\": \"First.\"}\n{\"doi\": \"10.1/b\", \"status\": \"landing-failed\"}\n\n{\"doi\": \"10.1/a\", \"status\": \"got\", \"abstract\": \"First.\"}\n".utf8)
    }

    func testAbstractsToProposalsPathFormPrintsProposalsAndTheSkipReport() throws {
        let f = base.appendingPathComponent("abstracts.ndjson")
        try ndjson().write(to: f)
        let r = try runSplit(["abstracts-to-proposals", "--source", f.path])
        XCTAssertEqual(r.status, 0, r.err)
        let proposals = try JSONSerialization.jsonObject(with: Data(r.out.utf8)) as! [[String: Any]]
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals[0]["doi"] as? String, "10.1/a")
        XCTAssertEqual((proposals[0]["fields"] as? [String: String])?["abstract"], "First.")
        XCTAssertTrue((proposals[0]["sourceDigest"] as? String)?.hasPrefix("sha256:") == true)
        XCTAssertTrue(r.err.contains("skip\tstatus:landing-failed\t10.1/b\tline 2"), r.err)
        XCTAssertTrue(r.err.contains("skip\tduplicate-doi\t10.1/a\tline 4"), r.err)
        XCTAssertTrue(r.err.contains("rows=3 proposals=1 skipped=2 (duplicate-doi=1, status:landing-failed=1)"), r.err)
    }

    func testAbstractsToProposalsDigestFormResolvesThroughTheStoreAndWritesOut() throws {
        let data = ndjson()
        // digest 由位元組算：借 `path` 形先取得
        let f = base.appendingPathComponent("abstracts.ndjson")
        try data.write(to: f)
        let byPath = try runSplit(["abstracts-to-proposals", "--source", f.path])
        let digest = ((try JSONSerialization.jsonObject(with: Data(byPath.out.utf8)) as! [[String: Any]])[0]["sourceDigest"] as! String)
        let hexDigits = String(digest.dropFirst("sha256:".count))
        let root = base.appendingPathComponent("store")
        let shard = root.appendingPathComponent("sources/\(hexDigits.prefix(2))")
        try FileManager.default.createDirectory(at: shard, withIntermediateDirectories: true)
        try data.write(to: shard.appendingPathComponent(String(hexDigits.dropFirst(2))))
        let out = base.appendingPathComponent("proposals.json")
        let r = try runSplit(["abstracts-to-proposals", "--library", root.path, "--source", digest, "--out", out.path])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(r.out, "", "--out 時 stdout 為空")
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), byPath.out)
        XCTAssertTrue(r.err.contains("→ --out 寫入 \(out.path)") || r.err.contains("→ --out 寫入"), r.err)
        // 缺存檔：具名、非零
        let missing = try runSplit(["abstracts-to-proposals", "--library", root.path, "--source", "sha256:" + String(repeating: "f", count: 64)])
        XCTAssertEqual(missing.status, 1)
        XCTAssertTrue(missing.err.contains("存檔不存在"), missing.err)
    }

    func testAbstractsToProposalsRefusesASymlinkOut() throws {
        let f = base.appendingPathComponent("abstracts.ndjson")
        try ndjson().write(to: f)
        let victim = base.appendingPathComponent("victim.txt")
        try Data("SACRED\n".utf8).write(to: victim)
        let link = base.appendingPathComponent("outlink.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        let r = try runSplit(["abstracts-to-proposals", "--source", f.path, "--out", link.path])
        XCTAssertEqual(r.status, 1)
        XCTAssertTrue(r.err.contains("symlink"), r.err)
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "SACRED\n")
    }
}
