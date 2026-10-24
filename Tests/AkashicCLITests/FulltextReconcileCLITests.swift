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
        XCTAssertEqual(Set(j.keys), ["citekey", "rows", "replaceAuthors", "refusal"], "沒有非作者欄位的寫入命令")
    }

    func testUnknownProposalKeyIsRefused() throws {
        try XCTSkipUnless(hasPoppler(), "需要 poppler")
        let d = try seedClaw(authors: [.literal("Katrina G. Claw")])
        let r = try compare(["source": d, "authors": ["page": 1, "items": byline], "journal": ["value": "x", "page": 1]])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("journal"), r.output)
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
}
