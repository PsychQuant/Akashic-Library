import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #742（Spectra change `reconcile-work-from-fulltext`）：`akashic fulltext text`／`compare` 的真 binary 測試。
/// fixture PDF 在測試裡手寫（同 `SkillToolsCLITests.makePDF`），需要 poppler 的 `pdfinfo`／`pdftotext`。
final class FulltextReconcileCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!
    private var scratch: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-reconcile-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        scratch = base.appendingPathComponent("scratch")
        for d in [home!, scratch!] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try LibraryStore(root: root, key: nil, environment: [:]).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private var env: [String: String] { ["AKASHIC_HOME": home.path, "HOME": home.path] }

    private func hasPoppler() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["pdftotext", "-v"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus != 127
    }

    /// 每一頁一個內容串流：`lines` 為空的頁什麼字都不畫，只畫一條線（「只有圖形」的頁）。
    private func makePDF(pages: [[String]]) -> Data {
        var objs = ["<< /Type /Catalog /Pages 2 0 R >>", "", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
        var kids: [String] = []
        for lines in pages {
            let content = lines.isEmpty
                ? "0 0 m 300 300 l S"
                : "BT /F1 12 Tf 72 720 Td 14 TL " + lines.map { "(\($0)) Tj T*" }.joined(separator: " ") + " ET"
            objs.append("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
            let contentRef = objs.count
            objs.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents \(contentRef) 0 R >>")
            kids.append("\(objs.count) 0 R")
        }
        objs[1] = "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(pages.count) >>"
        var out = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (i, o) in objs.enumerated() { offsets.append(out.count); out.append(Data("\(i + 1) 0 obj\n\(o)\nendobj\n".utf8)) }
        let xref = out.count
        out.append(Data("xref\n0 \(objs.count + 1)\n0000000000 65535 f \n".utf8))
        for o in offsets { out.append(Data(String(format: "%010d 00000 n \n", o).utf8)) }
        out.append(Data("trailer\n<< /Size \(objs.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return out
    }

    /// 經真 binary 的 `store-source` 存一份 PDF，回 digest。
    private func storePDF(_ data: Data, name: String = "in.pdf") throws -> String {
        let f = scratch.appendingPathComponent(name)
        try data.write(to: f)
        let r = try CLITestHarness.run(["store-source", f.path, "--media-type", "application/pdf",
                                        "--retrieved", "2026-10-24T10:00:00+08:00", "--origin", "https://example.org/x.pdf",
                                        "--acquisition", "browser-download", "--json", "--library", root.path], env: env)
        XCTAssertEqual(r.status, 0, r.output)
        let start = try XCTUnwrap(r.output.firstIndex(of: "{")), end = try XCTUnwrap(r.output.lastIndex(of: "}"))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.output[start...end].utf8)) as? [String: Any])
        return try XCTUnwrap(o["digest"] as? String)
    }

    private func seedWork(sources: [String], citekey: String = "claw2018framework") throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T",
                      authors: [.literal("Claw, Katrina G.")])
        e.akashic.sources = sources
        try LibraryStore(root: root, key: nil, environment: [:]).writeEntry(e)
    }

    private func text(_ extra: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(["fulltext", "text", "--library", root.path] + extra, env: env)
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private let sevenPages: [[String]] = (1...7).map { n in n == 1
        ? ["A framework for enhancing ethical genomic research", "Katrina G. Claw, Matthew Z. Anderson"]
        : ["Page \(n) body text"] }

    // MARK: - 4.1 fulltext text

    /// spec「All pages are written」。
    func testAllSevenPagesAreWritten() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try storePDF(makePDF(pages: sevenPages))
        try seedWork(sources: [d])
        let out = scratch.appendingPathComponent("text.json")
        let r = try text(["--citekey", "claw2018framework", "--out", out.path])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try readJSON(out)
        XCTAssertEqual(j["citekey"] as? String, "claw2018framework")
        XCTAssertEqual(j["source"] as? String, d)
        XCTAssertEqual(j["pageCount"] as? Int, 7)
        XCTAssertEqual(j["hasTextLayer"] as? Bool, true)
        let pages = try XCTUnwrap(j["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.map { $0["page"] as? Int }, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertTrue((pages[0]["text"] as? String ?? "").contains("Katrina G. Claw"), "\(pages[0])")
        XCTAssertTrue((pages[6]["text"] as? String ?? "").contains("Page 7 body text"), "\(pages[6])")
        XCTAssertFalse((pages[1]["text"] as? String ?? "").contains("Page 3"), "頁與頁不得混在一起")
    }

    /// spec「An output path inside a git work tree is refused」。
    func testOutputInsideAGitWorkTreeIsRefused() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try storePDF(makePDF(pages: sevenPages))
        try seedWork(sources: [d])
        let repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let out = repo.appendingPathComponent("text.json")
        let r = try text(["--citekey", "claw2018framework", "--out", out.path])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("git"), r.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "不寫檔")
    }

    /// spec「Two linked PDFs without a source choice are refused」：列出 digest；給 --source 就照那一份。
    func testTwoLinkedPDFsNeedASourceChoice() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let a = try storePDF(makePDF(pages: [["Version of record"]]), name: "a.pdf")
        let b = try storePDF(makePDF(pages: [["Author manuscript"], ["Second page"]]), name: "b.pdf")
        try seedWork(sources: [a, b])
        let out = scratch.appendingPathComponent("text.json")
        let r = try text(["--citekey", "claw2018framework", "--out", out.path])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains(a) && r.output.contains(b), r.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
        let chosen = try text(["--citekey", "claw2018framework", "--source", b, "--out", out.path])
        XCTAssertEqual(chosen.status, 0, chosen.output)
        XCTAssertEqual(try readJSON(out)["pageCount"] as? Int, 2)
    }

    func testAbsentContentOrNoLinkedPDFIsRefused() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let out = scratch.appendingPathComponent("text.json")
        try seedWork(sources: [], citekey: "nolink2020")
        let none = try text(["--citekey", "nolink2020", "--out", out.path])
        XCTAssertNotEqual(none.status, 0, none.output)
        XCTAssertTrue(none.output.contains("PDF"), none.output)
        let absent = "sha256:" + String(repeating: "cd", count: 32)
        try seedWork(sources: [absent])
        let missing = try text(["--citekey", "claw2018framework", "--out", out.path])
        XCTAssertNotEqual(missing.status, 0, missing.output)
        XCTAssertTrue(missing.output.contains("sources/"), missing.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    // MARK: - 4.3 fulltext compare（spec「fulltext compare SHALL compare a proposal with the store and emit a ready replacement without writing」）

    private func compare(_ proposal: [String: Any], citekey: String = "claw2018framework") throws -> (status: Int32, output: String, json: [String: Any]?) {
        let pf = scratch.appendingPathComponent("proposal-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: proposal).write(to: pf)
        let out = scratch.appendingPathComponent("compare-\(UUID().uuidString).json")
        let r = try CLITestHarness.run(["fulltext", "compare", "--library", root.path, "--citekey", citekey,
                                        "--proposal", pf.path, "--out", out.path], env: env)
        let j = (try? Data(contentsOf: out)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return (r.status, r.output, j)
    }
    private func storeBytes() throws -> [Data] {
        let dir = root.appendingPathComponent("entities")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            .map { try Data(contentsOf: dir.appendingPathComponent($0)) }
    }
    private func seedClaw(authors: [Author]) throws -> String {
        let d = try storePDF(makePDF(pages: sevenPages))
        var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle,
                      title: "A framework for enhancing ethical genomic research with Indigenous communities",
                      authors: authors, date: "2018")
        e.fields = ["volume": "9", "number": "1", "eid": "2957", "journaltitle": "Nature Communications"]
        e.akashic.sources = [d]
        try LibraryStore(root: root, key: nil, environment: [:]).writeEntry(e)
        return d
    }
    private let byline: [[String: Any]] = [
        ["literal": "Katrina G. Claw"], ["literal": "Matthew Z. Anderson"], ["literal": "Rene L. Begay"],
        ["literal": "Krystal S. Tsosie"], ["literal": "Keolu Fox"], ["literal": "Nanibaa' A. Garrison"],
        ["group": "Summer internship for INdigenous peoples in Genomics (SING) Consortium"],
    ]

    /// spec「A differing byline yields a replacement object」：20 位 vs 7 項 → differs，replaceAuthors 交給 update-entry 乾跑不被拒；store 逐位元組不變。
    func testDifferingBylineYieldsAReplacementObjectAcceptedByUpdateEntry() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: (1...20).map { .literal("Crossref Author \($0)") })
        let before = try storeBytes()
        let r = try compare(["source": d, "authors": ["page": 1, "items": byline]])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try XCTUnwrap(r.json)
        let rows = try XCTUnwrap(j["rows"] as? [[String: Any]])
        let authors = try XCTUnwrap(rows.first { $0["field"] as? String == "authors" })
        XCTAssertEqual(authors["status"] as? String, "differs")
        XCTAssertEqual(authors["page"] as? Int, 1)
        XCTAssertEqual((authors["proposed"] as? [String])?.count, 7)
        XCTAssertEqual((authors["store"] as? [String])?.count, 20)
        XCTAssertTrue(j["refusal"] is NSNull, "\(j)")
        let replace = try XCTUnwrap(j["replaceAuthors"] as? [String: Any])
        let rf = scratch.appendingPathComponent("replace.json")
        try JSONSerialization.data(withJSONObject: replace).write(to: rf)
        let dry = try CLITestHarness.run(["update-entry", "claw2018framework", "--replace-authors", rf.path, "--library", root.path], env: env)
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertEqual(try storeBytes(), before, "compare 與乾跑都不寫 store")
    }

    /// spec「A proposal that drops a key is reported, not applied」：refusal 具名第 6 位、exit 0。
    func testProposalThatDropsAKeyIsReportedNotApplied() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        var stored: [Author] = (0..<7).map { .literal("Author \($0)") }
        stored[6] = .key("garrison-nanibaa")
        let d = try seedClaw(authors: stored)
        let r = try compare(["source": d, "authors": ["page": 1, "items": byline]])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try XCTUnwrap(r.json)
        let refusal = try XCTUnwrap(j["refusal"] as? String)
        XCTAssertTrue(refusal.contains("第 6 位") && refusal.contains("garrison-nanibaa"), refusal)
    }

    /// spec「A differing volume is listed only」：volume 一列 differs，輸出沒有任何非作者欄位的寫入命令。
    func testDifferingVolumeIsListedOnly() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        let r = try compare(["source": d, "authors": ["page": 1, "items": [["literal": "Katrina G. Claw"]]],
                             "volume": ["value": "10", "page": 1], "articleNumber": ["value": "2957", "page": 1],
                             "title": ["value": "A framework for enhancing ethical genomic research with Indigenous communities", "page": 1]])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try XCTUnwrap(r.json)
        let rows = try XCTUnwrap(j["rows"] as? [[String: Any]])
        func status(_ f: String) -> String? { rows.first { $0["field"] as? String == f }?["status"] as? String }
        XCTAssertEqual(status("volume"), "differs")
        XCTAssertEqual(status("articleNumber"), "same")
        XCTAssertEqual(status("title"), "same")
        XCTAssertEqual(status("authors"), "same")
        XCTAssertEqual(status("issue"), "notProposed")
        XCTAssertTrue(j["replaceAuthors"] is NSNull, "作者列相同時沒有替換物件")
        XCTAssertEqual(Set(j.keys), ["citekey", "rows", "replaceAuthors", "refusal", "applyRefusal"], "沒有非作者欄位的寫入命令（applyRefusal 是第四輪 verify 後的輸出欄位）")
    }

    func testUnknownProposalKeyIsRefused() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        let r = try compare(["source": d, "authors": ["page": 1, "items": byline], "journal": ["value": "x", "page": 1]])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("journal"), r.output)
    }

    // MARK: - 6.4 端到端：claw2018framework 的形狀（design Acceptance criteria 第 1 條）

    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    func testClawShapeEndToEnd() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let sing = "Summer internship for INdigenous peoples in Genomics (SING) Consortium"
        let members = ["Joseph M. Yracheta", "Alice Popejoy", "Deborah A. Bolnick", "Jessica Bardill", "Lucas Brutus",
                       "Jasmine Joseph", "Sean Fullerton", "Paul G. Spicer", "Ripan S. Malhi", "Kim TallBear",
                       "Jessica Blanchard", "Austin Reid", "Kelsey Dalton"]
        var pages: [[String]] = [["A framework for enhancing ethical genomic research",
                                  "Katrina G. Claw, Matthew Z. Anderson, Rene L. Begay, Krystal S. Tsosie, Keolu Fox,",
                                  "SING Consortium and Nanibaa A. Garrison"]]
        pages += (2...6).map { ["Page \($0) body text"] }
        pages.append(["SING Consortium"] + members)
        let d = try storePDF(makePDF(pages: pages))
        // Crossref 的形狀：20 位，第 20 位（index 19）已歸戶為 garrison-nanibaa；成員被攤成作者
        var crossref: [Author] = ["Claw, Katrina G.", "Anderson, Matthew Z.", "Begay, Rene L.", "Tsosie, Krystal S.",
                                  "Fox, Keolu"].map { .literal($0) }
        crossref += members.prefix(14).map { .literal($0) }
        while crossref.count < 19 { crossref.append(.literal("Extra \(crossref.count)")) }
        crossref.append(.key("garrison-nanibaa"))
        XCTAssertEqual(crossref.count, 20)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle,
                      title: "A framework for enhancing ethical genomic research with Indigenous communities",
                      authors: crossref, date: "2018")
        e.fields = ["journaltitle": "Nature Communications", "volume": "9", "number": "1", "eid": "2957"]
        e.akashic.sources = [d]
        try store.writeEntry(e)
        try store.writePerson(Person(key: "garrison-nanibaa", names: ["Garrison, Nanibaa' A."]))
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])

        // 1. 逐頁文字
        let textOut = scratch.appendingPathComponent("text.json")
        XCTAssertEqual(try text(["--citekey", "claw2018framework", "--out", textOut.path]).status, 0)
        let t = try readJSON(textOut)
        XCTAssertEqual(t["pageCount"] as? Int, 7)
        XCTAssertEqual(t["hasTextLayer"] as? Bool, true)
        // 2.–3. 提議與比對
        var items: [[String: Any]] = ["Katrina G. Claw", "Matthew Z. Anderson", "Rene L. Begay", "Krystal S. Tsosie",
                                      "Keolu Fox"].map { ["literal": $0] }
        items.append(["group": sing])
        items.append(["from": 19])
        let r = try compare(["source": d,
                             "authors": ["page": 1, "items": items, "reason": "PDF 第 1 頁 byline：Crossref 把 13 位聯盟成員列成作者"],
                             "groupMembers": [["group": sing, "page": 7, "members": members]]])
        XCTAssertEqual(r.status, 0, r.output)
        let replace = try XCTUnwrap(r.json?["replaceAuthors"] as? [String: Any], "\(String(describing: r.json))")
        XCTAssertTrue(r.json?["refusal"] is NSNull)
        let rf = scratch.appendingPathComponent("replace.json")
        try JSONSerialization.data(withJSONObject: replace).write(to: rf)
        // 4.–5. 乾跑、實寫
        let dry = try CLITestHarness.run(["update-entry", "claw2018framework", "--replace-authors", rf.path, "--library", root.path], env: env)
        XCTAssertEqual(dry.status, 0, dry.output)
        let apply = try CLITestHarness.run(["update-entry", "claw2018framework", "--replace-authors", rf.path,
                                            "--library", root.path, "--apply"], env: env)
        XCTAssertEqual(apply.status, 0, apply.output)

        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "claw2018framework" })
        XCTAssertEqual(after.authors.count, 7)
        XCTAssertEqual(after.authors[5], .literal("{\(sing)}"))
        XCTAssertEqual(after.authors[6], .key("garrison-nanibaa"))
        XCTAssertEqual(after.groupMembers.first?.members, members)
        XCTAssertEqual(after.groupMembers.first?.page, 7)
        XCTAssertEqual(after.authorListReplacementRecord?.record.segments.count, 7)
        XCTAssertEqual(after.authorListReplacementRecord?.record.page, 1)

        // export-bib：團體輸出為一個 corporate 名
        let bib = try CLITestHarness.run(["export-bib", "--library", root.path, "--citekeys", "claw2018framework"], env: env)
        XCTAssertEqual(bib.status, 0, bib.output)
        XCTAssertTrue(bib.output.contains("{\(sing)}"), bib.output)
        XCTAssertFalse(bib.output.contains("Joseph M. Yracheta"), "成員不進 AUTHOR：\(bib.output)")
        // validate 與 doctor：沒有這一族的 warning
        let validate = try CLITestHarness.run(["validate", "--library", root.path], env: env)
        XCTAssertEqual(validate.status, 0, validate.output)
        XCTAssertFalse(validate.output.contains("作者列替換記錄與目前的作者列對不上"), validate.output)
        let doctor = try CLITestHarness.run(["doctor", "--library", root.path], env: env)
        XCTAssertEqual(doctor.status, 0, doctor.output)
        XCTAssertFalse(doctor.output.contains("作者列替換記錄與目前的作者列對不上"), doctor.output)
        // 讀取面：get-entry 看得到 13 位成員
        let get = try CLITestHarness.run(["get-entry", "claw2018framework", "--library", root.path], env: env)
        XCTAssertTrue(get.output.contains("group-members") && get.output.contains("Kelsey Dalton"), get.output)

        // D8：替換之後再拆一位 → validate 報 warning、exit 0
        git(["add", "-A"]); git(["commit", "-q", "-m", "replaced"])
        let split = try CLITestHarness.run(["resolve-people", "--library", root.path,
                                            "--split-author", "claw2018framework:0: G. =測試：替換之後的拆分"], env: env)
        XCTAssertEqual(split.status, 0, split.output)
        let stale = try CLITestHarness.run(["validate", "--library", root.path], env: env)
        XCTAssertEqual(stale.status, 0, stale.output)
        XCTAssertTrue(stale.output.contains("作者列替換記錄與目前的作者列對不上"), stale.output)
    }

    // MARK: - 4.2 hasTextLayer

    /// spec「An image-only PDF」：沒有任何一頁含字母——只畫線的頁、只有數字的頁都不算有字母。
    func testImageOnlyPDFHasNoTextLayer() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try storePDF(makePDF(pages: [[], ["2957"], []]))
        try seedWork(sources: [d])
        let out = scratch.appendingPathComponent("text.json")
        let r = try text(["--citekey", "claw2018framework", "--out", out.path])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try readJSON(out)
        XCTAssertEqual(j["hasTextLayer"] as? Bool, false)
        XCTAssertEqual(j["pageCount"] as? Int, 3)
        XCTAssertEqual((j["pages"] as? [Any])?.count, 3)
    }

    // MARK: - 7.5–7.7 第一輪 verify 之後（#742 verify 報告，2026-10-25）

    /// spec「A text cover page over scanned pages」：逐頁 hasLetters；sourcePath 指向本機 sources/ 裡那一份。
    func testPerPageLettersAndSourcePath() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let pdf = makePDF(pages: [["Downloaded from an aggregator"], []])
        let d = try storePDF(pdf)
        try seedWork(sources: [d])
        let out = scratch.appendingPathComponent("text.json")
        let r = try text(["--citekey", "claw2018framework", "--out", out.path])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try readJSON(out)
        XCTAssertEqual(j["hasTextLayer"] as? Bool, true, "整份看起來有文字層")
        let pages = try XCTUnwrap(j["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.map { $0["hasLetters"] as? Bool }, [true, false], "第 2 頁是圖")
        let path = try XCTUnwrap(j["sourcePath"] as? String)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), pdf, "sourcePath 是那份全文")
    }

    /// spec「An existing output path is refused」：普通檔與 symlink 都不碰。
    func testExistingOutputIsRefused() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try storePDF(makePDF(pages: sevenPages))
        try seedWork(sources: [d])
        let existing = scratch.appendingPathComponent("existing.json")
        try Data("keep".utf8).write(to: existing)
        let r = try text(["--citekey", "claw2018framework", "--out", existing.path])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep", "既有檔不變")
        let target = scratch.appendingPathComponent("target.txt")
        try Data("target".utf8).write(to: target)
        let link = scratch.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let viaLink = try text(["--citekey", "claw2018framework", "--out", link.path])
        XCTAssertNotEqual(viaLink.status, 0, viaLink.output)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target", "不跟隨 symlink")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path, "symlink 本身不變")
        let pf = scratch.appendingPathComponent("p.json")
        try JSONSerialization.data(withJSONObject: ["source": d, "authors": ["page": 1, "items": [["literal": "Claw, Katrina G."]]]])
            .write(to: pf)
        let cmp = try CLITestHarness.run(["fulltext", "compare", "--library", root.path, "--citekey", "claw2018framework",
                                          "--proposal", pf.path, "--out", existing.path], env: env)
        XCTAssertNotEqual(cmp.status, 0, cmp.output)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep", "compare 也不覆寫")
    }

    /// 7.6：全文是第三方內容，輸出只有擁有者可讀寫。
    func testOutputIsOwnerOnly() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try storePDF(makePDF(pages: sevenPages))
        try seedWork(sources: [d])
        let out = scratch.appendingPathComponent("text.json")
        XCTAssertEqual(try text(["--citekey", "claw2018framework", "--out", out.path]).status, 0)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: out.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode & 0o777, 0o600)
    }

    /// spec「An invalid proposal is refused even when nothing would change」。
    func testInvalidProposalIsRefusedEvenWhenNothingWouldChange() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        let r = try compare(["source": d, "authors": ["page": 1, "items": [["literal": "Katrina G. Claw"]]],
                             "release": [["index": 0, "reason": "PDF byline 沒有這一位"]]])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try XCTUnwrap(r.json)
        XCTAssertTrue(j["replaceAuthors"] is NSNull, "\(j)")
        let refusal = try XCTUnwrap(j["refusal"] as? String, "作者列相同也要驗：\(j)")
        XCTAssertTrue(refusal.contains("release"), refusal)
    }

    /// spec「A member list alone yields a replacement object」。
    func testMemberListAloneYieldsAReplacementObject() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw"), .literal("{SING Consortium}")])
        let members: [[String: Any]] = [["group": "SING Consortium", "page": 7, "members": ["Joseph M. Yracheta"]]]
        let r = try compare(["source": d, "authors": ["page": 1, "items": [["literal": "Katrina G. Claw"], ["group": "SING Consortium"]]],
                             "groupMembers": members])
        XCTAssertEqual(r.status, 0, r.output)
        let j = try XCTUnwrap(r.json)
        let replace = try XCTUnwrap(j["replaceAuthors"] as? [String: Any], "\(j)")
        XCTAssertEqual((replace["groupMembers"] as? [[String: Any]])?.count, 1)
        XCTAssertTrue(j["refusal"] is NSNull, "\(j)")
    }

    /// 7.1：compare 的作者列比較逐位元組——NFD 的 store 值與 NFC 的提議是不同的值。
    func testCompareComparesAuthorsByBytes() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Jose\u{301} Rivera")])
        let r = try compare(["source": d, "authors": ["page": 1, "items": [["literal": "Jos\u{E9} Rivera"]]]])
        XCTAssertEqual(r.status, 0, r.output)
        let rows = try XCTUnwrap(r.json?["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.first { $0["field"] as? String == "authors" }?["status"] as? String, "differs")
    }

    /// 7.2：提議裡的頁序也精確解碼——2^64+1 不得變成第 1 頁。
    func testProposalIntegersOutsideTheIntRangeAreRefused() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        let pf = scratch.appendingPathComponent("p-range.json")
        try Data(#"{"source":"\#(d)","authors":{"page":18446744073709551617,"items":[{"literal":"Katrina G. Claw"}]}}"#.utf8).write(to: pf)
        let r = try CLITestHarness.run(["fulltext", "compare", "--library", root.path, "--citekey", "claw2018framework",
                                        "--proposal", pf.path], env: env)
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("整數範圍"), r.output)
    }

    // MARK: - 8.x 第二輪 verify 之後

    /// 8.3：作者位比狀態——literal「key:alice」不等於 person key `alice`。
    func testCompareDistinguishesALiteralFromAKey() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.key("alice")])
        let r = try compare(["source": d, "authors": ["page": 1, "items": [["literal": "key:alice"]]],
                             "release": [["index": 0, "reason": "重新核對後釋放"]]])
        XCTAssertEqual(r.status, 0, r.output)
        let rows = try XCTUnwrap(r.json?["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.first { $0["field"] as? String == "authors" }?["status"] as? String, "differs")
        XCTAssertNotNil(r.json?["replaceAuthors"] as? [String: Any])
    }

    /// 8.3：沒有名單與空名單相同；換了依據的名單不同。
    func testCompareMemberListsByContentAndSource() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw"), .literal("{SING Consortium}")])
        let b = try storePDF(makePDF(pages: sevenPages + [["Author manuscript"]]), name: "b.pdf")   // store 進 git 之前存
        let same: [[String: Any]] = [["literal": "Katrina G. Claw"], ["group": "SING Consortium"]]
        let empty = try compare(["source": d, "authors": ["page": 1, "items": same], "groupMembers": []])
        XCTAssertEqual(empty.status, 0, empty.output)
        let rows = try XCTUnwrap(empty.json?["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.first { $0["field"] as? String == "groupMembers" }?["status"] as? String, "same")
        XCTAssertTrue(empty.json?["replaceAuthors"] is NSNull, "\(String(describing: empty.json))")
        // 先以 d 寫入名單，再以另一份 PDF 核對同一份名單
        let members: [[String: Any]] = [["group": "SING Consortium", "page": 7, "members": ["A"]]]
        let first = try compare(["source": d, "authors": ["page": 1, "items": same], "groupMembers": members])
        let rf = scratch.appendingPathComponent("replace-1.json")
        try JSONSerialization.data(withJSONObject: try XCTUnwrap(first.json?["replaceAuthors"] as? [String: Any])).write(to: rf)
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "seed"])
        let applied = try CLITestHarness.run(["update-entry", "claw2018framework", "--replace-authors", rf.path,
                                              "--library", root.path, "--apply"], env: env)
        XCTAssertEqual(applied.status, 0, applied.output)
        var e = try XCTUnwrap(LibraryStore(root: root, key: nil, environment: [:]).load().entries.first)
        e.akashic.sources.append(b)
        try LibraryStore(root: root, key: nil, environment: [:]).writeEntry(e)
        git(["add", "-A"]); git(["commit", "-q", "-m", "second pdf"])
        let other = try compare(["source": b, "authors": ["page": 1, "items": same], "groupMembers": members])
        let rows2 = try XCTUnwrap(other.json?["rows"] as? [[String: Any]])
        XCTAssertEqual(rows2.first { $0["field"] as? String == "groupMembers" }?["status"] as? String, "differs", "依據換了")
        let row2 = try XCTUnwrap(rows2.first { $0["field"] as? String == "groupMembers" })
        XCTAssertEqual(((row2["store"] as? [[String: Any]])?.first)?["restsOn"] as? String, d, "名單列列出依據（9.5）")
        XCTAssertEqual(((row2["proposed"] as? [[String: Any]])?.first)?["restsOn"] as? String, b)
    }

    /// 8.3：提議的頁序對照那份 PDF 的頁數。
    func testComparePagesBeyondThePDFAreRefused() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        // 提議與 store 不同（否則 replaceAuthors 本來就是 null，量不到 fail-closed）
        let r = try compare(["source": d, "authors": ["page": 99, "items": [["literal": "Katrina Claw"]]]])
        XCTAssertEqual(r.status, 0, r.output)
        let refusal = try XCTUnwrap(r.json?["refusal"] as? String, "\(String(describing: r.json))")
        XCTAssertTrue(refusal.contains("99") && refusal.contains("7"), refusal)
        XCTAssertTrue(r.json?["replaceAuthors"] is NSNull, "被拒的提議不產生寫入命令（9.5）：\(String(describing: r.json?["replaceAuthors"]))")
    }

    /// 9.1：以 resolve-organizations --apply 升格（真 binary），compare 對與 store 一致的提議回 refusal: null、replaceAuthors: null。
    func testComparePassesAfterResolveOrganizationsPromotion() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw"), .literal("{SING Consortium}")])
        try LibraryStore(root: root, key: nil, environment: [:])
            .writeOrganization(Organization(key: "sing-consortium", names: TimelineOf([TemporalValue(value: "SING Consortium")])))
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "seed"])
        let members: [[String: Any]] = [["group": "SING Consortium", "page": 7, "members": ["A", "B"]]]
        let first = try compare(["source": d, "authors": ["page": 1, "items": [["literal": "Katrina G. Claw"], ["group": "SING Consortium"]]],
                                 "groupMembers": members])
        let rf = scratch.appendingPathComponent("replace-promote.json")
        try JSONSerialization.data(withJSONObject: try XCTUnwrap(first.json?["replaceAuthors"] as? [String: Any])).write(to: rf)
        let applied = try CLITestHarness.run(["update-entry", "claw2018framework", "--replace-authors", rf.path,
                                              "--library", root.path, "--apply"], env: env)
        XCTAssertEqual(applied.status, 0, applied.output)
        git(["add", "-A"]); git(["commit", "-q", "-m", "members"])
        let promote = try CLITestHarness.run(["resolve-organizations", "--apply", "--yes", "--org", "sing-consortium",
                                              "--library", root.path], env: env)
        XCTAssertEqual(promote.status, 0, promote.output)
        let e = try XCTUnwrap(LibraryStore(root: root, key: nil, environment: [:]).load().entries.first)
        XCTAssertEqual(e.authors.last, .organization("sing-consortium"), "前提：團體位已升格")
        git(["add", "-A"]); git(["commit", "-q", "-m", "promote"])
        let r = try compare(["source": d, "authors": ["page": 1, "items": [["from": 0], ["from": 1]]], "groupMembers": members])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.json?["refusal"] is NSNull, "\(String(describing: r.json?["refusal"]))")
        XCTAssertTrue(r.json?["replaceAuthors"] is NSNull, "與 store 一致，不必寫")
    }

    // MARK: - 10.x 第四輪 verify 之後

    /// 10.1：替換腿乾跑接受、但 store 會拒絕寫入（format 22）時，compare 另列 applyRefusal，不給寫入命令。
    func testCompareReportsApplyRefusalAndGivesNoWriteCommand() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        try StoreVersion.write(root: root, format: 22)
        let r = try compare(["source": d, "authors": ["page": 1, "items": [["literal": "Katrina Claw"]]]])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.json?["refusal"] is NSNull, "\(String(describing: r.json?["refusal"]))")
        let applyRefusal = try XCTUnwrap(r.json?["applyRefusal"] as? String, "\(String(describing: r.json))")
        XCTAssertTrue(applyRefusal.contains("23"), applyRefusal)
        XCTAssertTrue(r.json?["replaceAuthors"] is NSNull, "store 寫不進去就沒有寫入命令")
    }

    /// 10.1：讀不出 source 的頁數時寫進 refusal，不略過頁序檢查（另一份已連 source 的 index 行壞掉）。
    func testCompareRefusesWhenThePageCountCannotBeChecked() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        let b = try storePDF(makePDF(pages: [["Other"]]), name: "b.pdf")
        var e = try XCTUnwrap(LibraryStore(root: root, key: nil, environment: [:]).load().entries.first)
        e.akashic.sources.append(b)
        try LibraryStore(root: root, key: nil, environment: [:]).writeEntry(e)
        let index = root.appendingPathComponent("sources/index.jsonl")
        let kept = try String(contentsOf: index, encoding: .utf8).split(separator: "\n").filter { !$0.contains(b) }
        try (kept.joined(separator: "\n") + "\n{not json\n").write(to: index, atomically: true, encoding: .utf8)
        let r = try compare(["source": d, "authors": ["page": 9999, "items": [["literal": "Katrina Claw"]]]])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.json?["refusal"] is NSNull, "頁序閘沒跑時不得放行：\(String(describing: r.json))")
        XCTAssertTrue(r.json?["replaceAuthors"] is NSNull)
    }
}
