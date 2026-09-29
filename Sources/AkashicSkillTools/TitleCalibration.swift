import Foundation
import AkashicCore

/// 在一個資料夾的真實 PDF 上量 `FulltextVerify` 的標題規則（#629 由 `calibrate_title_match.py` 移植）。
///
/// 對每個首頁帶 DOI 的 PDF，取那個 DOI 的 Crossref 標題，然後量：
///
///     own    每個檔案對它自己的標題        → 應該被收
///     main   每個檔案對它的主標題（無副標題）→ 應該被收
///     cross  每個檔案對**其他每一個**標題    → 應該被拒
///
/// 各量兩次：只看標題規則（`titleMatch`），以及整個判定（`assess`，帶檔案自己的中繼資料 DOI、記錄的 DOI 與 Crossref 的頁碼範圍）。
/// 整個判定的「別篇標題」欄在這裡近乎套套邏輯——每個檔案的 DOI 是從它自己的首頁讀出來的，別筆記錄的 DOI 不可能相符；它守的是
/// 迴歸，量不到 `FulltextVerify` 註解裡寫的回應文／勘誤殘餘。規則改了或出現新種類的 PDF 就重跑。不是單元測試：它需要一個
/// 全文資料夾，而那些檔案永遠不進 repository。
///
/// # 與舊腳本的差別：Crossref 記錄改讀本機檔
///
/// 舊腳本自己以 `urllib` 向 Crossref 取每個 DOI 的標題與頁碼（違反 `web-access-via-safari-browser`）。這裡讀一個**目錄**裡的
/// Crossref 回應檔（每個檔是 `https://api.crossref.org/works/<DOI>` 的回應，`{"message": {…}}`），以回應裡的 `DOI` 對回 PDF
/// ——檔名不重要（skill 存檔的檔名是序號，見 web-access.md）。缺哪些 DOI 的回應，這裡列出來（含要取的網址），由 skill 經
/// safari-browser 取回、存進那個目錄後重跑。**不自己連網。**
public enum TitleCalibration {

    public struct Row {
        public var file: String
        public var doi: String
        public var title: String
        public var pages: String?
        public var count: Int
        public var text: String
        public var meta: String?
    }

    public struct Loaded {
        public var rows: [Row]
        /// 首頁有 DOI、但 `--crossref` 目錄裡沒有它的回應，**而且 DOI 形狀合格**（可以放心組成網址交給 skill 取）。
        public var missing: [String]
        /// 首頁讀出的 DOI 形狀不合格（含 `'`、`$`、反引號、`#`、`?`、`%`、`.`／`..` 路徑段……）——它來自第三方 PDF 的文字層，
        /// 不組成網址、不交給 agent 取，這個檔就量不到（R1 verify 第 30 則：`crossref-match` 對 DOI 有同一道形狀檢查，calibrate 沒有）。
        public var unsafeDOIs: [String] = []
        /// 首頁沒有 DOI 而略過的 PDF 數。
        public var withoutDOI: Int
        /// `--crossref` 目錄裡讀不了或不是 Crossref 回應的檔數。
        public var unusableResponses: Int
        public var crossrefRecords: Int
    }

    /// 一筆 Crossref `message` 的標題（含副標題，`標題: 副標題`）與頁碼範圍。
    static func titleAndPages(_ message: [String: Any]) -> (title: String?, pages: String?) {
        let title = ((message["title"] as? [Any])?.first as? String).flatMap { $0.isEmpty ? nil : $0 }
        let sub = ((message["subtitle"] as? [Any])?.first as? String).flatMap { $0.isEmpty ? nil : $0 }
        let full = (title != nil && sub != nil) ? "\(title!): \(sub!)" : title
        return (full, message["page"] as? String)
    }

    /// 讀 `--crossref` 目錄：`*.json`，每個檔是一個 Crossref 回應（或直接是 `message` 物件）。
    public static func loadCrossref(directory: String) throws -> (records: [String: [String: Any]], unusable: Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            throw SkillToolError.failure("--crossref 不是目錄：\(displaySafeInvisible(directory, max: 300))")
        }
        var records: [String: [String: Any]] = [:]
        var unusable = 0
        let names = ((try? fm.contentsOfDirectory(atPath: directory)) ?? []).filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted()
        for name in names {
            guard let data = fm.contents(atPath: directory + "/" + name),
                  let root = (try? PyJSONParser.parse(data)) as? [String: Any] else { unusable += 1; continue }
            let message = (root["message"] as? [String: Any]) ?? root
            guard let doi = message["DOI"] as? String, !doi.isEmpty else { unusable += 1; continue }
            records[FulltextVerify.normDOI(doi)] = message
        }
        return (records, unusable)
    }

    /// 走過資料夾裡的每個 PDF（遞迴、略過隱藏檔），配上 Crossref 記錄。
    public static func load(folder: String, crossrefDirectory: String) throws -> Loaded {
        let (records, unusable) = try loadCrossref(directory: crossrefDirectory)
        let fm = FileManager.default
        // 資料夾不存在（或不是資料夾）不是「零個 PDF」：那會印出全零的量測結果並以 0 結束（R1 verify 第 26 則）
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
            throw SkillToolError.failure("不是資料夾：\(displaySafeInvisible(folder, max: 300))")
        }
        guard let walker = fm.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else {
            throw SkillToolError.failure("讀不到資料夾：\(displaySafeInvisible(folder, max: 300))")
        }
        var pdfs: [String] = []
        for case let url as URL in walker where url.pathExtension == "pdf" { pdfs.append(url.path) }
        pdfs.sort()
        var loaded = Loaded(rows: [], missing: [], withoutDOI: 0, unusableResponses: unusable, crossrefRecords: records.count)
        for path in pdfs {
            let first = try ToolRunner.run(["pdftotext", "-l", "1", path, "-"], timeout: ToolRunner.popplerTimeout)
            let text1 = Scalars(String(decoding: first.stdout, as: UTF8.self).unicodeScalars)
            guard let found = FulltextVerify.findDOI(in: text1, stop: FulltextVerify.xmlDOIStop) else { loaded.withoutDOI += 1; continue }
            let doi = PyText.string(PyText.rstrip(found, Set(".,;)".unicodeScalars)))
            guard let message = records[FulltextVerify.normDOI(doi)] else {
                if CrossrefMatch.isSafeDOI(doi) {
                    if !loaded.missing.contains(doi) { loaded.missing.append(doi) }
                } else if !loaded.unsafeDOIs.contains(doi) {
                    loaded.unsafeDOIs.append(doi)
                }
                continue
            }
            let (title, pages) = titleAndPages(message)
            guard let title else { continue }
            let info = try ToolRunner.run(["pdfinfo", path], timeout: ToolRunner.popplerTimeout)
            guard let count = PDFReader.pageCount(fromPdfinfo: String(decoding: info.stdout, as: UTF8.self)) else { continue }
            let two = try ToolRunner.run(["pdftotext", "-l", "2", path, "-"], timeout: ToolRunner.popplerTimeout)
            loaded.rows.append(Row(file: (path as NSString).lastPathComponent, doi: doi, title: title, pages: pages, count: count,
                                   text: String(decoding: two.stdout, as: UTF8.self), meta: try PDFReader.metadataDOI(path: path)))
        }
        return loaded
    }

    /// 取這個 DOI 的 Crossref 回應要打的網址（`https://api.crossref.org/works/<百分比編碼的 DOI>`）；DOI 形狀不合格回 nil。
    /// 與 `crossref-match` 組單筆查詢網址是同一條路（`quotePath` ＋ `isSafeDOI`），calibrate 印給 skill 的網址不再是要人自己拼的模板。
    public static func crossrefURL(forDOI doi: String) -> String? {
        CrossrefMatch.isSafeDOI(doi) ? CrossrefMatch.endpoint + "/" + CrossrefMatch.quotePath(doi) : nil
    }

    /// 主標題：第一個 `:` `?` `—`（含）之前的部分，去掉尾端的 `:` `—` 與空白。
    static func mainTitle(_ title: String) -> String {
        let s = Scalars(title.unicodeScalars)
        var head = s
        if let i = s.firstIndex(where: { $0 == ":" || $0 == "?" || $0 == "\u{2014}" }) { head = Scalars(s[...i]) }
        return PyText.string(PyText.strip(PyText.rstrip(head, [":", "\u{2014}"])))
    }

    public struct Report {
        public var lines: [String]
        /// 「別篇標題被收」的總數（兩個判定加總）。非零＝規則放行了不該放行的東西，`calibrate` 以非零結束碼回報。
        public var wrongAccepts: Int
    }

    /// 量測。`rows` 是全部帶 DOI 與 Crossref 標題的檔案；其中檔名含 `supplement` 的不算「文章」（own／main 只量文章，cross 量全部）。
    public static func evaluate(rows: [Row]) -> Report {
        var lines = ["files with a DOI and a Crossref title: \(rows.count)"]
        let articles = rows.filter { !$0.file.lowercased().contains("supplement") }
        let pairs = rows.flatMap { a in rows.filter { $0.doi != a.doi }.map { (a, $0) } }
        var wrongTotal = 0
        let judges: [(String, (Row, Row, String) -> Bool)] = [
            ("title rule", { f, _, t in FulltextVerify.titleMatch(t, firstPages: f.text) != nil }),
            ("whole decision, record DOI", { f, rec, t in
                FulltextVerify.assess(firstPage: f.text, pageCount: f.count, title: t, pages: rec.pages, doi: rec.doi, metaDOI: f.meta).isArticle
            }),
        ]
        func clip(_ s: String, _ n: Int) -> String { String(String.UnicodeScalarView(s.unicodeScalars.prefix(n))) }
        for (name, ok) in judges {
            let own = articles.filter { !ok($0, $0, $0.title) }
            let main = articles.filter { !ok($0, $0, mainTitle($0.title)) }
            let wrong = pairs.filter { ok($0.0, $0.1, $0.1.title) }
            lines.append("── \(name)")
            lines.append("   own title accepted:        \(articles.count - own.count)/\(articles.count)")
            lines.append("   main title only accepted:  \(articles.count - main.count)/\(articles.count)")
            lines.append("   wrong title accepted:      \(wrong.count)/\(pairs.count)")
            for r in own { lines.append("     own REJECTED: \(displaySafeInvisible(r.file, max: 120)) | \(displaySafeInvisible(clip(r.title, 60), max: 200)) | pages \(r.pages.map { displaySafeInvisible($0, max: 60) } ?? "None")") }
            for r in main { lines.append("     main-title REJECTED: \(displaySafeInvisible(r.file, max: 120)) | \(displaySafeInvisible(clip(mainTitle(r.title), 60), max: 200)) | pages \(r.pages.map { displaySafeInvisible($0, max: 60) } ?? "None")") }
            for (a, b) in wrong { lines.append("     WRONG ACCEPT: \(displaySafeInvisible(a.file, max: 120)) <- \(displaySafeInvisible(clip(b.title, 60), max: 200))") }
            wrongTotal += wrong.count
        }
        return Report(lines: lines, wrongAccepts: wrongTotal)
    }
}
