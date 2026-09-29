import Foundation
import AkashicCore

/// 下載下來的檔案是不是記錄所描述的那篇正式論文？（#629 由 `verify_pdf.py` 移植；#613 起的判定。）
///
/// `%PDF` 檔頭只說「這是某個 PDF」。2026-09-23 有一個 `%PDF` 合格的下載是文章的補充文字（10 頁、首行
/// 「Supplemental Material」）而不是 28 頁的正文，另一個是 NIH 作者稿；兩者都通過檔頭檢查。本型別把檔案與記錄
/// 所說的比對。
///
/// **判定本身逐條照舊**（門檻與程序是拿舊實作量出來的：29 份真實 PDF × Crossref 標題，own 22/28、wrong 0/808），
/// 下面的長註解是舊檔頭註解的完整搬移——它們是校準的紀錄，不是裝飾。
///
/// # 一個 `%PDF` 之外，怎麼判「是這篇」
///
/// 前兩版用字詞重疊判定：記錄標題的字有多少比例出現在前兩頁，≥ 0.9 就收——在 10 份檔案上「校準」。
/// 2026-09-24 在 29 份真實 PDF（各自的 DOI 從首頁讀出、標題取自 Crossref）上量，把每個檔案與其他所有標題交叉：
///
///     字詞重疊 ≥ 0.9     own 28/28   wrong 14/808
///     標題行（下述）      own 28/28   wrong  0/808
///
/// 同領域的論文共用詞彙：一篇談 within-between 之爭的摘要，含有「A critique of the cross-lagged panel model」的
/// 每一個字。CJK 用字元二連詞同樣失敗（末兩字不同的論文得 0.91），單純包含關係則會收下更長的、把目標標題包在裡面的
/// 標題。
///
/// 規則：前 80 行裡有連續 1–10 個非空行，去掉空白、換行與標點後**等於**記錄標題——或以它開頭、後接副標題分隔符
/// （`:` `?` `—`）再接更多文字（記錄常只帶主標題）。標題尾巴的註腳標記（≤ 2 位數字）容忍。
///
/// # 身分是分級的
///
/// R4–R6 審查（2026-09-24）一再找到通過的別篇：泛稱標題（Introduction）、「標題：對某某的回應」、標題前一行的回應標記、
/// 德文版、續集「Title 2」，以及 R6 的勘誤（首頁**引用**原文 DOI 排在自己的前面，所以「首頁第一個 DOI」也不是身分）。
/// 字詞清單收斂不了。**頁面印的可以引用任何東西；檔案自己說的不可能是引用**：
///
///     強   PDF 自己的中繼資料（XMP）帶 DOI。29 份文章實測 13 份有、13 份都等於自己的 DOI、沒有一份帶第二個 DOI。
///     中   首頁印的第一個 DOI——通常是自己的（29/29），但勘誤或回應文可能先印原文的。
///     弱   只有標題行與頁數。
///
///     中繼資料 DOI ＝ 記錄            → 標題行 ＋ 頁數不衝突
///     中繼資料 DOI ≠ 記錄            → 拒收（檔案自己說它是另一篇）
///     沒有中繼資料、首頁 DOI ＝ 記錄  → 標題行 ＋ 頁數**吻合**；副標題分隔符後接回應字樣者拒收
///     沒有中繼資料、首頁 DOI ≠ 記錄  → 拒收
///     根本沒有 DOI 可比               → 永不自動收（結束碼 5）
///
/// 殘餘（寫出來而不藏）：一篇回應文先印原文的 DOI、沒有中繼資料 DOI、把原文標題印成一行、**而且**頁數落在原文的
/// 容許範圍內，會被收下。R4–R6 的其餘案例都有測試拒絕。
/// 代價（**舊的 `calibrate_title_match.py`** 在 29 份 PDF 上量，2026-09-24）：own 22/28、wrong 0/808。**移植後的 `fulltext calibrate`
/// 沒有在那組上重跑**——那批 PDF 與當時的 Crossref 標題不在本機（#629 R1 verify 第 2、14 則；本機語料上的新舊對跑見
/// `changelog/2026-09-29-b13p-verify-r1.md`）。被拒的 6 份都沒有中繼資料 DOI 也沒有
/// 可比的頁數（3 份線上優先刊出、1 份沒有頁碼的預印本、2 份不比頁數的 PMC 作者稿）——交給人看。
///
/// 已知限制：繁體與簡體中文互不相符（NFKC 不統一兩者）。那會拒收正確的論文（結束碼 5，人看一眼），不會收下錯的。
public enum FulltextVerify {

    // MARK: 常數（舊檔頭的註解逐條保留）

    /// 補充資料：標記必須開頭於前 `headLines` 個非空行之一。2026-09-24 在 41 份檔案上量：三份真補充檔都在第 1 行以它
    /// 開頭（「Supplemental Material: …」「Supplementary Material for:」），而 Taylor & Francis 的**正文**封面帶
    /// 「View supplementary material」（第 11 行），被「任何位置都算」的規則誤判。正文也會在前面幾頁自己帶
    /// 「Supporting Information」標題或附註（ACS、Wiley），所以視窗是前 3 行（第 1 行加下載戳記的餘地）。
    static let headLines = 3
    static let titleScanLines = 80
    static let titleMaxSpan = 10
    static let titleSubtitleSeparators: Set<Unicode.Scalar> = [":", "\u{FF1A}", "?", "\u{FF1F}", "\u{2014}", "\u{2013}"]

    // MARK: Python 字串輔助（`\w` 的字元類、`_prep`、`collapse`……）

    /// `_prep`：NFKC → 小寫 → `&` 換成 ` and `（記錄與 PDF 常常在 & 與 and 上不一致，R4）。
    static func prep(_ s: Scalars) -> Scalars {
        PyText.replacing(PyText.lower(PyText.nfkc(s)), ["&"], with: Array(" and ".unicodeScalars))
    }

    /// 只留字母與數字、小寫：換行、空白、標點都消失。
    static func collapse(_ s: Scalars) -> Scalars { prep(s).filter(PyText.isAlnum) }

    /// 同 `collapse`，但副標題分隔符變成 `|` 留下來。
    static func marked(_ s: Scalars) -> Scalars {
        prep(s).map { titleSubtitleSeparators.contains($0) ? "|" : $0 }.filter { $0 == "|" || PyText.isAlnum($0) }
    }

    /// `normalize`：NFKC＋小寫後以非 `\w` 切開，留長度 > 2 的詞（長度是 code point 數）。
    static func normalizeWords(_ s: Scalars) -> [Scalars] {
        let text = PyText.lower(PyText.nfkc(s))
        var words: [Scalars] = []
        var cur = Scalars()
        for c in text {
            if PyText.isWord(c) { cur.append(c) } else { words.append(cur); cur = [] }
        }
        words.append(cur)
        return words.filter { $0.count > 2 }
    }

    static func isCJK(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF: return true
        default: return false
        }
    }

    // MARK: DOI

    /// DOI 正規化：百分比解碼、去空白、小寫、去掉 `https://doi.org/`／`doi:` 前綴與查詢／片段、去尾端標點。
    public static func normDOI(_ doi: String) -> String {
        var d = PyText.lower(PyText.strip(PyText.unquote(Scalars(doi.unicodeScalars))))
        // `^(https?://(dx\.)?doi\.org/|doi:\s*)` 是**一個**交替式：至多剝一個前綴（`https://doi.org/doi:10.x` 剝完網址
        // 前綴就停，不再剝 `doi:`）
        var stripped = false
        for prefix in ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/"] {
            let p = Scalars(prefix.unicodeScalars)
            if PyText.hasPrefix(d, p) { d = Scalars(d[p.count...]); stripped = true; break }
        }
        if !stripped, PyText.hasPrefix(d, Scalars("doi:".unicodeScalars)) {
            d = Scalars(d[4...])
            while let f = d.first, PyText.isSpace(f) { d.removeFirst() }
        }
        if let cut = d.firstIndex(where: { $0 == "?" || $0 == "#" }) { d = Scalars(d[..<cut]) }   // 貼上的網址的查詢或片段不是 DOI
        return PyText.string(PyText.rstrip(d, Set(".,;:)]}/".unicodeScalars)))
    }

    /// `\b10\.\d{4,9}/[^…]+`：在 `s` 裡找第一個 DOI。`stop` 是 DOI 本體不可含的字元（空白另外處理）。
    ///
    /// 頁面文字用 `stop = ["\""]`（SICI 式 DOI 含 `<` `>`）；XMP 是 XML，DOI 到下一個標籤結束，`<` 絕不可能是 DOI 的一部分，
    /// 所以多擋 `<` `>`。**第一版的 XMP 讀取沿用頁面文字的樣式，抓到 `10.1080/…</dc:identifier>`，每個中繼資料 DOI 都
    /// 「不相符」、19/28 篇正確的論文被拒收——由校準抓到，不是單元測試（2026-09-24）。**
    static func findDOI(in s: Scalars, stop: Set<Unicode.Scalar>) -> Scalars? {
        var i = 0
        while i + 3 <= s.count {
            defer { i += 1 }
            guard s[i] == "1", s[i + 1] == "0", s[i + 2] == "." else { continue }
            if i > 0, PyText.isWord(s[i - 1]) { continue }   // \b：前一個字元不能是字詞字元
            var j = i + 3
            var digits = 0
            while j < s.count, PyText.isDecimal(s[j]) { digits += 1; j += 1 }
            guard (4...9).contains(digits), j < s.count, s[j] == "/" else { continue }
            var k = j + 1
            while k < s.count, !PyText.isSpace(s[k]), !stop.contains(s[k]) { k += 1 }
            guard k > j + 1 else { continue }
            return Scalars(s[i..<k])
        }
        return nil
    }

    static let pageTextDOIStop: Set<Unicode.Scalar> = ["\""]
    static let xmlDOIStop: Set<Unicode.Scalar> = ["\"", "<", ">"]

    /// PDF 自己的 XMP 中繼資料裡的 DOI（檔案的身分，不是引用）。
    public static func doiFromXMP(_ xmp: String) -> String? {
        guard let raw = findDOI(in: Scalars(xmp.unicodeScalars), stop: xmlDOIStop) else { return nil }
        return normDOI(PyText.string(HTMLEntities.unescape(raw)))
    }

    /// 首頁印出的第一個 DOI（pdftotext 以 `\f` 分頁）。
    public static func pageOneDOI(_ firstPages: String) -> String? {
        let text = Scalars(firstPages.unicodeScalars)
        let firstPage = Scalars(text.split(separator: "\u{0C}", maxSplits: 1, omittingEmptySubsequences: false).first ?? [])
        guard let raw = findDOI(in: firstPage, stop: pageTextDOIStop) else { return nil }
        return normDOI(PyText.string(raw))
    }

    // MARK: 標題

    /// 「這一行是記錄標題」：`"exact"`、`"main-title"`（PDF 多了副標題）、`"main-title-response"`（分隔符後面讀起來像
    /// 回應／評論／更正），或 nil。
    public static func titleMatch(_ title: String, firstPages: String) -> String? {
        let t = collapse(Scalars(title.unicodeScalars))
        guard !t.isEmpty else { return nil }
        var lines: [Scalars] = []
        for ln in PyText.splitLines(Scalars(firstPages.unicodeScalars)) {
            let m = marked(ln)
            if m.contains(where: { $0 != "|" }) { lines.append(m) }
        }
        lines = Array(lines.prefix(titleScanLines))
        for i in 0..<lines.count {
            var block = Scalars()
            var plain = Scalars()
            for k in 0..<titleMaxSpan {
                guard i + k < lines.count else { break }
                block.append(contentsOf: lines[i + k])
                plain.append(contentsOf: lines[i + k].filter { $0 != "|" })
                if plain == t || isTitleWithFootnote(plain, t) { return "exact" }
                if PyText.hasPrefix(plain, t) {
                    if let after = afterSeparator(block, t.count) {
                        return isResponseAfterSeparator(after) ? "main-title-response" : "main-title"
                    }
                }
                if plain.count > t.count + 2, !PyText.hasPrefix(plain, t) { break }
            }
        }
        return nil
    }

    /// `re.fullmatch(re.escape(t) + r"\d{1,2}", plain)`：標題後只多 1–2 位數字（註腳標記）。
    private static func isTitleWithFootnote(_ plain: Scalars, _ t: Scalars) -> Bool {
        let extra = plain.count - t.count
        guard (1...2).contains(extra), PyText.hasPrefix(plain, t) else { return false }
        return plain[t.count...].allSatisfy(PyText.isDecimal)
    }

    /// block 的第 n 個字母之後，若緊接分隔符且其後還有文字，回傳從分隔符起的剩餘部分。
    private static func afterSeparator(_ block: Scalars, _ n: Int) -> Scalars? {
        var seen = 0
        for (j, ch) in block.enumerated() where ch != "|" {
            seen += 1
            if seen == n {
                let rest = Scalars(block[(j + 1)...])
                return rest.first == "|" && rest.contains(where: { $0 != "|" }) ? rest : nil
            }
        }
        return nil
    }

    /// 分隔符之後這些字樣標示**另一篇**回應該標題的文章。只在沒有 DOI 可比時才用（見類型註解）。
    /// `^\|+(a|an|the)?(reply|rejoinder|response|comment|commentary|correction|erratum|corrigendum|retraction|addendum|回應|評論|评论|勘誤|勘误|更正|商榷)`
    static let responseWords: [Scalars] = ["reply", "rejoinder", "response", "comment", "commentary", "correction", "erratum",
                                           "corrigendum", "retraction", "addendum", "回應", "評論", "评论", "勘誤", "勘误",
                                           "更正", "商榷"].map { Scalars($0.unicodeScalars) }

    static func isResponseAfterSeparator(_ after: Scalars) -> Bool {
        var i = 0
        while i < after.count, after[i] == "|" { i += 1 }
        guard i > 0 else { return false }
        for article in ["a", "an", "the", ""] {
            let a = Scalars(article.unicodeScalars)
            guard PyText.hasPrefix(after, a, at: i) else { continue }
            if responseWords.contains(where: { PyText.hasPrefix(after, $0, at: i + a.count) }) { return true }
        }
        return false
    }

    /// 標題的內容字詞有多少比例出現在首頁——**只回報，不再決定**（保留是因為低分一眼就說明為什麼被拒）。
    /// CJK 與全是短字的標題沒有詞可數，改回報最長連續比對佔的比例。
    public static func titleScore(_ title: String, firstPage: String) -> Double {
        let titleScalars = Scalars(title.unicodeScalars)
        let wanted = normalizeWords(titleScalars)
        if titleScalars.contains(where: isCJK) || wanted.isEmpty {
            let t = collapse(titleScalars)
            let p = collapse(Scalars(firstPage.unicodeScalars))
            if t.isEmpty { return 0.0 }
            let m = PySequenceMatcher(t, p, autojunk: false).findLongestMatch(alo: 0, ahi: t.count, blo: 0, bhi: p.count)
            return Double(m.size) / Double(t.count)
        }
        let present = Set(normalizeWords(Scalars(firstPage.unicodeScalars)).map { PyText.string($0) })
        let hits = wanted.filter { present.contains(PyText.string($0)) }.count
        return Double(hits) / Double(wanted.count)
    }

    // MARK: 頁碼

    /// `71--98` → 28。非數字或單頁 → nil（不做頁數檢查）。
    public static func expectedPageCount(_ pages: String?) -> Int? {
        guard let pages else { return nil }
        let s = Scalars(pages.unicodeScalars)
        var i = 0
        func skipSpace() { while i < s.count, PyText.isSpace(s[i]) { i += 1 } }
        func number() -> Int? {
            let start = i
            var v = 0
            while i < s.count, PyText.isDecimal(s[i]) {
                v = min(v * 10 + Int(s[i].properties.numericValue ?? 0), 1_000_000_000_000_000)   // Python 是任意精度；超過這個量級都不是頁碼
                i += 1
            }
            return i > start ? v : nil
        }
        skipSpace()
        guard let first = number() else { return nil }
        skipSpace()
        let dashStart = i
        while i < s.count, s[i] == "-" || s[i] == "\u{2013}" || s[i] == "\u{2014}" { i += 1 }
        guard i > dashStart else { return nil }
        skipSpace()
        guard let last = number() else { return nil }
        skipSpace()
        guard i == s.count else { return nil }
        return last >= first ? last - first + 1 : nil
    }

    // MARK: 判定

    public struct Assessment: Equatable {
        public var pageCount: Int
        public var expectedPages: Int?
        public var pagesOK: Bool?
        public var titleMatch: String?
        public var doiInMetadata: String?
        public var doiOnPage: String?
        public var doiState: String
        public var titleScore: Double
        public var flags: [String]
        public var isArticle: Bool
        public var versionOfRecord: Bool

        /// 與舊腳本逐位元相同的判定 JSON（鍵順序、`": "` 分隔、非 ASCII 原樣）。**DOI 是頁面文字或 XMP 裡的第三方字串**，
        /// 輸出前逐個 `displaySafeInvisible`（比對已在之前完成，消毒只發生在輸出邊界）。
        public var json: PyJSON {
            func opt(_ s: String?) -> PyJSON { s.map { .string(displaySafeInvisible($0, max: 500)) } ?? .null }
            return .object([
                ("page_count", .int(pageCount)),
                ("expected_pages", expectedPages.map { .int($0) } ?? .null),
                ("pages_ok", pagesOK.map { .bool($0) } ?? .null),
                ("title_match", titleMatch.map { .string($0) } ?? .null),
                ("doi_in_metadata", opt(doiInMetadata)),
                ("doi_on_page", opt(doiOnPage)),
                ("doi_state", .string(doiState)),
                ("title_score", .double(PyJSON.rounded(titleScore, digits: 2))),
                ("flags", .array(flags.map { .string($0) })),
                ("is_article", .bool(isArticle)),
                ("version_of_record", .bool(versionOfRecord)),
            ])
        }
    }

    /// `\bauthor\s+manuscript\b`（不分大小寫）：前兩頁任何位置。
    static func hasAuthorManuscript(_ text: Scalars) -> Bool {
        let s = PyText.lower(text)
        let author = Scalars("author".unicodeScalars), manuscript = Scalars("manuscript".unicodeScalars)
        var from = 0
        while let i = PyText.firstIndex(of: author, in: s, from: from) {
            from = i + 1
            if i > 0, PyText.isWord(s[i - 1]) { continue }
            var j = i + author.count
            let ws = j
            while j < s.count, PyText.isSpace(s[j]) { j += 1 }
            guard j > ws, PyText.hasPrefix(s, manuscript, at: j) else { continue }
            let end = j + manuscript.count
            if end == s.count || !PyText.isWord(s[end]) { return true }
        }
        return false
    }

    /// 補充資料標題：前 `headLines` 個非空行**以換行接起來**的文字裡，某一行（去掉前導空白後）以補充資料的標記開頭，
    /// 且標記後是字詞邊界；片語內的空白**含換行**（PDF 的標題常被斷行：`Supplemental` ⏎ `Material for`）。
    ///
    /// `^\s*(supplement(al|ary)\s+(material|text|information|appendix|methods)s?|supporting\s+information|electronic\s+supplementary\s+material|online\s+supplement)\b`
    /// 以 `re.I | re.M` 對「前三個非空行用 `\n` 接起來」的整段文字跑——`^` 只在整段的開頭與每個 `\n` 之後成立，`\s+` 可以跨過
    /// `\n`。**#629 第一版逐行判斷（「逐行照舊」），把跨行的片語放過去了**（R1 verify 第 3 則：`Supplemental` ⏎ `Material for`
    /// 在舊實作被標成補充、新版判成正式版——中止補充檔當正文的那道閘，方向是 fail-open）。
    static func hasSupplementHead(lines: [Scalars]) -> Bool {
        var joined = Scalars()
        for (i, line) in lines.enumerated() {
            if i > 0 { joined.append("\n") }
            joined.append(contentsOf: line)
        }
        let s = PyText.lower(joined)
        var starts = [0]
        for (i, c) in s.enumerated() where c == "\n" { starts.append(i + 1) }
        return starts.contains { supplementMarker(in: s, from: $0) }
    }

    /// `s`（已小寫）在 `from` 這個行首之後：略過空白，接著是不是補充資料的標記，標記後是字詞邊界。
    private static func supplementMarker(in s: Scalars, from start: Int) -> Bool {
        var first = start
        while first < s.count, PyText.isSpace(s[first]) { first += 1 }
        func word(_ w: String, at i: Int) -> Int? {
            let p = Scalars(w.unicodeScalars)
            return PyText.hasPrefix(s, p, at: i) ? i + p.count : nil
        }
        func spaces(at i: Int) -> Int? {
            var j = i
            while j < s.count, PyText.isSpace(s[j]) { j += 1 }
            return j > i ? j : nil
        }
        func boundary(at i: Int) -> Bool { i == s.count || !PyText.isWord(s[i]) }

        // supplement(al|ary)\s+(material|text|information|appendix|methods)s?
        if let a = word("supplement", at: first) {
            for suffix in ["al", "ary"] {
                guard let b = word(suffix, at: a), let c = spaces(at: b) else { continue }
                for noun in ["material", "text", "information", "appendix", "methods"] {
                    guard let d = word(noun, at: c) else { continue }
                    if d < s.count, s[d] == "s", boundary(at: d + 1) { return true }
                    if boundary(at: d) { return true }
                }
            }
        }
        // supporting\s+information
        if let a = word("supporting", at: first), let b = spaces(at: a), let c = word("information", at: b), boundary(at: c) { return true }
        // electronic\s+supplementary\s+material
        if let a = word("electronic", at: first), let b = spaces(at: a), let c = word("supplementary", at: b),
           let d = spaces(at: c), let e = word("material", at: d), boundary(at: e) { return true }
        // online\s+supplement
        if let a = word("online", at: first), let b = spaces(at: a), let c = word("supplement", at: b), boundary(at: c) { return true }
        return false
    }

    public static func assess(firstPage: String, pageCount: Int, title: String, pages: String?,
                              doi: String? = nil, metaDOI: String? = nil) -> Assessment {
        let page = Scalars(firstPage.unicodeScalars)
        let nonEmpty = PyText.splitLines(page).filter { !PyText.strip($0).isEmpty }
        let head = Array(nonEmpty.prefix(headLines))
        var flags: [String] = []
        if hasSupplementHead(lines: head) { flags.append("supplement") }
        if hasAuthorManuscript(page) { flags.append("author-manuscript") }
        let score = titleScore(title, firstPage: firstPage)
        let expected = expectedPageCount(pages)
        // 出版社 PDF 會多一兩頁封面；作者稿重排後常更長。正式版容許 +3 / −0；已被標記為非正式版的不做頁數檢查。
        let pagesOK: Bool? = (expected == nil || !flags.isEmpty) ? nil : (expected! <= pageCount && pageCount <= expected! + 3)
        let match = titleMatch(title, firstPages: firstPage)
        let onPage = pageOneDOI(firstPage)
        // Python 的真值判斷：`norm_doi(x) if x else None`，之後 `if wanted and own`——正規化後是空字串的視同沒有
        let wanted = (doi?.isEmpty == false) ? normDOI(doi!) : nil
        let own = (metaDOI?.isEmpty == false) ? normDOI(metaDOI!) : nil
        let wantedSet = wanted.flatMap { $0.isEmpty ? nil : $0 }
        let ownSet = own.flatMap { $0.isEmpty ? nil : $0 }
        let onPageSet = onPage.flatMap { $0.isEmpty ? nil : $0 }
        let state: String
        if let w = wantedSet, let o = ownSet {
            state = o == w ? "metadata-match" : "metadata-mismatch"
        } else if let w = wantedSet, let p = onPageSet {
            state = p == w ? "page-match" : "page-mismatch"
        } else {
            state = "absent"
        }
        let base = match != nil && !flags.contains("supplement") && pagesOK != false
        let isArticle: Bool
        switch state {
        case "metadata-match": isArticle = base
        case "page-match": isArticle = base && pagesOK == true && match != "main-title-response"
        default: isArticle = false   // metadata-mismatch、page-mismatch、absent
        }
        return Assessment(pageCount: pageCount, expectedPages: expected, pagesOK: pagesOK, titleMatch: match,
                          doiInMetadata: own, doiOnPage: onPage, doiState: state, titleScore: score, flags: flags,
                          isArticle: isArticle, versionOfRecord: isArticle && flags.isEmpty)
    }
}

/// `html.unescape` 的子集（XMP 是 XML，DOI 裡出現的只有 `&lt; &gt; &amp; &quot; &apos;` 與數字參照；SICI 式 DOI 的角括號
/// 在 XMP 裡以 `&lt;` `&gt;` 儲存）。其他 HTML5 具名實體原樣保留——DOI 內實務上不出現。
enum HTMLEntities {
    static func unescape(_ s: Scalars) -> Scalars {
        guard s.contains("&") else { return s }
        var out = Scalars()
        var i = 0
        while i < s.count {
            guard s[i] == "&", let semi = s[i...].prefix(34).firstIndex(of: ";") else { out.append(s[i]); i += 1; continue }
            let body = PyText.string(Scalars(s[(i + 1)..<semi]))
            if let v = codePoint(for: body), let scalar = Unicode.Scalar(v) {
                out.append(scalar)
                i = semi + 1
            } else {
                out.append(s[i]); i += 1
            }
        }
        return out
    }

    /// 具名或數字參照的碼位；不認得的回 nil（原樣保留）。
    private static func codePoint(for reference: String) -> UInt32? {
        switch reference {
        case "lt": return 0x3C
        case "gt": return 0x3E
        case "amp": return 0x26
        case "quot": return 0x22
        case "apos": return 0x27
        default: break
        }
        guard reference.hasPrefix("#"), reference.count > 1 else { return nil }
        let digits = reference.dropFirst()
        let value: UInt32?
        if digits.hasPrefix("x") || digits.hasPrefix("X") { value = UInt32(digits.dropFirst(), radix: 16) } else { value = UInt32(digits) }
        guard let v = value else { return nil }   // `&#abc;` 不是參照，原樣保留
        // 0、代理對、超出 Unicode 範圍：HTML 規範取代成 U+FFFD
        guard v != 0, Unicode.Scalar(v) != nil else { return 0xFFFD }
        return v
    }
}
