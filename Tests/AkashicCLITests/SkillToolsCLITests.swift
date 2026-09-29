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

    func testURLRulePrintsTheDerivedURLOrNothing() throws {
        let hit = try runSplit(["fulltext", "url-rule", "https://onlinelibrary.wiley.com/doi/10.1111/jopy.12964"])
        XCTAssertEqual(hit.status, 0)
        XCTAssertEqual(hit.out, "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1111/jopy.12964\n")
        let psy = try runSplit(["fulltext", "url-rule", "https://psycnet.apa.org/doiLanding?doi=10.1037%2Fmet0000285", "/record/2022-13893-001?doi=1"])
        XCTAssertEqual(psy.out, "https://psycnet.apa.org/fulltext/2022-13893-001.pdf\n")
        let none = try runSplit(["fulltext", "url-rule", "https://www.tandfonline.com/doi/full/10.1080/x"])
        XCTAssertEqual(none.status, 0)
        XCTAssertEqual(none.out, "")
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

    func testFetchRefusesAMissingSafariBrowserAndAMissingWindow() throws {
        let missing = try runSplit(["fulltext", "fetch", "--window", "1", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x", "--out", base.appendingPathComponent("w.pdf").path,
                                    "--bin", base.appendingPathComponent("no-such-binary").path])
        XCTAssertEqual(missing.status, 1)
        XCTAssertTrue(missing.err.contains("safari-browser not found"), missing.err)
        // 一個只印 `[]` 的假 safari-browser：視窗不存在 → 結束碼 1，而且沒有開任何分頁
        let stub = base.appendingPathComponent("stub-safari")
        let log = base.appendingPathComponent("calls.log")
        try "#!/bin/sh\necho \"$@\" >> '\(log.path)'\nif [ \"$1\" = documents ]; then echo '[]'; fi\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let r = try runSplit(["fulltext", "fetch", "--window", "5", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x", "--out", base.appendingPathComponent("w.pdf").path, "--bin", stub.path])
        XCTAssertEqual(r.status, 1, r.err)
        XCTAssertTrue(r.err.contains("Safari window 5 not found"), r.err)
        let calls = try String(contentsOf: log, encoding: .utf8)
        XCTAssertEqual(calls, "documents --json\n", "只該問過 documents：\(calls)")
        XCTAssertEqual(try runSplit(["fulltext", "fetch", "--window", "0", "--expect-profile", "own", "--landing", "x", "--out", "y"]).status, 64)
    }

    /// `--expect-profile` 是唯一防止動到別人的 Safari session 的檢查：文件一直寫「一律帶」，命令列現在強制（R1 verify 第 31 則）。
    func testFetchRequiresAnExpectedProfile() throws {
        let noProfile = try runSplit(["fulltext", "fetch", "--window", "5", "--landing", "https://doi.org/10.1/x", "--out", base.appendingPathComponent("w.pdf").path])
        XCTAssertEqual(noProfile.status, 64, noProfile.err)
        XCTAssertTrue(noProfile.err.contains("expect-profile"), noProfile.err)
        let empty = try runSplit(["fulltext", "fetch", "--window", "5", "--expect-profile", "", "--landing", "https://doi.org/10.1/x", "--out", base.appendingPathComponent("w.pdf").path])
        XCTAssertEqual(empty.status, 64, empty.err)
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
