import XCTest
@testable import AkashicSkillTools

/// `TitleCalibration`（#629，由 `calibrate_title_match.py` 移植）：量測邏輯與 Crossref 記錄的讀取。
/// 規則本身的行為在 `FulltextVerifyTests`；這裡驗「量測怎麼算」與「Crossref 記錄改讀本機檔」。
final class TitleCalibrationTests: XCTestCase {

    /// 主標題：第一個 `:` `?` `—`（含）之前，去掉尾端的 `:` `—` 與空白（舊腳本 `re.split(r"(?<=[:?—])\s*", t)[0].rstrip(":—").strip()`）。
    func testMainTitleMatchesTheOldRegexSplit() {
        XCTAssertEqual(TitleCalibration.mainTitle("Structure and Dynamics: A Latent Curve Model"), "Structure and Dynamics")
        XCTAssertEqual(TitleCalibration.mainTitle("Is it real? Yes: maybe"), "Is it real?")   // `?` 保留（rstrip 只去 `:` `—`）
        XCTAssertEqual(TitleCalibration.mainTitle("Panel models — a critique"), "Panel models")
        XCTAssertEqual(TitleCalibration.mainTitle("  No separator here  "), "No separator here")
        XCTAssertEqual(TitleCalibration.mainTitle(": leading"), "")
    }

    func testCrossrefTitleJoinsTheSubtitleAndKeepsPages() {
        let r = TitleCalibration.titleAndPages(["title": ["Main"], "subtitle": ["Sub"], "page": "71-98"])
        XCTAssertEqual(r.title, "Main: Sub")
        XCTAssertEqual(r.pages, "71-98")
        XCTAssertEqual(TitleCalibration.titleAndPages(["title": ["Main"]]).title, "Main")
        XCTAssertNil(TitleCalibration.titleAndPages(["subtitle": ["Sub"]]).title)
        XCTAssertNil(TitleCalibration.titleAndPages([:]).pages)
    }

    private func row(_ file: String, _ doi: String, _ title: String, pages: String? = nil, count: Int = 10, text: String, meta: String? = nil) -> TitleCalibration.Row {
        .init(file: file, doi: doi, title: title, pages: pages, count: count, text: text, meta: meta)
    }

    /// 兩個互不相同的檔案：自己的標題被收、主標題被收、別篇標題不被收；補充資料檔（檔名含 supplement）不算「文章」但算別篇標題的來源。
    func testEvaluateCountsOwnMainAndWrongAcceptsWithTheOldOutputShape() {
        let a = row("a.pdf", "10.1/a", "Growth Curves: A Primer", pages: "1--10", count: 10,
                    text: "Journal\nGrowth Curves: A Primer\ndoi:10.1/a\nAbstract", meta: "10.1/a")
        let b = row("b.pdf", "10.1/b", "Panel Models", pages: "5--14", count: 10,
                    text: "Journal\nPanel Models\ndoi:10.1/b\nAbstract", meta: "10.1/b")
        let s = row("b-supplement.pdf", "10.1/s", "Panel Models Supplement", count: 4, text: "Supplemental Material\nPanel Models Supplement\ndoi:10.1/s")
        let report = TitleCalibration.evaluate(rows: [a, b, s])
        XCTAssertEqual(report.wrongAccepts, 0, report.lines.joined(separator: "\n"))
        XCTAssertEqual(report.lines.first, "files with a DOI and a Crossref title: 3")
        XCTAssertTrue(report.lines.contains("── title rule"))
        XCTAssertTrue(report.lines.contains("── whole decision, record DOI"))
        XCTAssertTrue(report.lines.contains("   own title accepted:        2/2"), report.lines.joined(separator: "\n"))
        XCTAssertTrue(report.lines.contains("   main title only accepted:  2/2"))
        XCTAssertTrue(report.lines.contains("   wrong title accepted:      0/6"), "3 個檔 × 其他 2 個 DOI 的標題 ＝ 6 對")
    }

    /// 規則放行了不該放行的別篇：每個判定各報一次，`wrongAccepts` 加總，逐筆列出 `WRONG ACCEPT`。
    func testEvaluateReportsWrongAccepts() {
        // b 的文字裡有一行恰好等於 a 的標題（例如章節標題）→ 標題規則收下別篇
        let a = row("a.pdf", "10.1/a", "Introduction", text: "Journal\nIntroduction\ndoi:10.1/a", meta: "10.1/a")
        let b = row("b.pdf", "10.1/b", "Other Work", text: "Other Work\nIntroduction\nMore text\ndoi:10.1/b", meta: "10.1/b")
        let report = TitleCalibration.evaluate(rows: [a, b])
        XCTAssertGreaterThan(report.wrongAccepts, 0)
        XCTAssertTrue(report.lines.contains { $0.hasPrefix("     WRONG ACCEPT: b.pdf <- Introduction") }, report.lines.joined(separator: "\n"))
    }

    func testCrossrefDirectoryIsKeyedByTheResponsesOwnDOIAndCountsUnusableFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"message":{"DOI":"10.1037/ABC","title":["T"]}}"#.utf8).write(to: dir.appendingPathComponent("r-1.json"))
        try Data(#"{"DOI":"10.1037/bare","title":["Bare"]}"#.utf8).write(to: dir.appendingPathComponent("r-2.json"))   // 直接是 message 物件
        try Data("<html>captcha</html>".utf8).write(to: dir.appendingPathComponent("r-3.json"))                          // 壞的
        try Data(#"{"message":{"title":["no doi"]}}"#.utf8).write(to: dir.appendingPathComponent("r-4.json"))            // 沒有 DOI
        try Data("ignored".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let loaded = try TitleCalibration.loadCrossref(directory: dir.path)
        XCTAssertEqual(Set(loaded.records.keys), ["10.1037/abc", "10.1037/bare"])
        XCTAssertEqual(loaded.unusable, 2)
        XCTAssertThrowsError(try TitleCalibration.loadCrossref(directory: dir.path + "/missing"))
    }
}
