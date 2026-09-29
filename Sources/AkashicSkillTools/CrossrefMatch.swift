import Foundation
import CryptoKit
import AkashicCore

/// 用標題＋期刊＋年份比對 Crossref 記錄取得 DOI，並做反向驗證（#629 由 `crossref_match.py` 移植）。
///
/// # 與舊腳本的關係
///
/// 舊腳本自己以 `urllib` 直連 Crossref（違反 `.claude/rules/web-access-via-safari-browser.md`：`Sources/` 不新增 HTTP client，
/// skill 取外部資料一律經 safari-browser）。**比對與計分邏輯原封搬過來**（四訊號合取、門檻、三段式解決、反向驗證），
/// **取得**改成 skill 的事：
///
/// - 本型別是一個**重播式狀態機**：給它作品清單與「目前已取得的回應」，它算出每一筆作品的下一步——要嘛給出結果，要嘛說
///   「我需要這個 URL 的回應」。回應以 URL 的雜湊（`Request.id`）為檔名存在一個目錄（`--responses`）；skill 逐個取回、
///   存檔、重跑，直到沒有待取的請求。每次重跑都從頭重算（不留狀態檔，狀態就是那個目錄），所以任何時候中止、重跑都安全。
/// - 每筆作品最多四個請求（一般查詢 → 剝審稿後綴的單筆查詢 → 限定 journal-article 重查 → 反向驗證的單筆查詢），前一個的
///   結果決定下一個是否需要——這就是為什麼不是「先把全部 URL 列出來」。
///
/// # 判定要求四個獨立訊號合取
///
/// 不是把單一訊號的門檻調高——preprint 的標題相似度可以是 1.00，比期刊版還高。詳見
/// `plugin/skills/akashic-bootstrap/references/work-sources.md`。
public enum CrossrefMatch {

    public static let endpoint = "https://api.crossref.org/works"
    static let nonArticleTypes: Set<String> = ["peer-review", "posted-content", "component"]
    static let selectFields = "DOI,title,container-title,volume,issue,page,author,published,type"

    // MARK: 輸入

    public struct Work: Equatable {
        public var citekey: PyJSON
        public var title: String
        public var journal: String?
        public var year: Int?
        public init(citekey: PyJSON, title: String, journal: String?, year: Int?) {
            self.citekey = citekey; self.title = title; self.journal = journal; self.year = year
        }
    }

    /// 解析輸入 JSON：`[{"citekey", "title", "journal", "year"}, …]`（`journal`、`year` 可缺，但缺了會削弱判定）。
    public static func parseWorks(_ data: Data) throws -> [Work] {
        let root: Any
        do { root = try PyJSONParser.parse(data) } catch {
            throw SkillToolError.failure("works 檔不是合法 JSON：\(displaySafeErrorText(error))")
        }
        guard let items = root as? [Any] else { throw SkillToolError.failure("works 檔的頂層必須是陣列：[{citekey, title, journal, year}, …]") }
        return try items.enumerated().map { n, item in
            guard let obj = item as? [String: Any], let title = obj["title"] as? String else {
                throw SkillToolError.failure("works 檔第 \(n + 1) 筆不是帶 title 字串的物件")   // display-safe-exempt: n 是 Int 序號
            }
            let journal = (obj["journal"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Work(citekey: PyJSONBridge.convert(obj["citekey"]), title: title, journal: journal, year: pyInt(obj["year"]))
        }
    }

    // MARK: 正規化與相似度

    /// 比對用正規化：轉小寫、非英數字轉空白、壓縮空白。
    static func norm(_ s: String?) -> Scalars {
        var mapped = Scalars()
        for c in (s ?? "").unicodeScalars {
            if PyText.isAlnum(c) { mapped.append(contentsOf: PyText.lower(Scalars([c]))) } else { mapped.append(" ") }
        }
        return joinWords(mapped)
    }

    private static func joinWords(_ s: Scalars) -> Scalars {
        var words: [Scalars] = []
        var cur = Scalars()
        for c in s {
            if PyText.isSpace(c) { if !cur.isEmpty { words.append(cur); cur = [] } } else { cur.append(c) }
        }
        if !cur.isEmpty { words.append(cur) }
        var out = Scalars()
        for (i, w) in words.enumerated() {
            if i > 0 { out.append(" ") }
            out.append(contentsOf: w)
        }
        return out
    }

    /// 期刊名正規化：在 `norm` 之上處理常見縮寫差異（依序全部替換，不分詞界——與舊實作同）。
    static func jnorm(_ s: String?) -> Scalars {
        var t = norm(s)
        for (a, b) in [("journal of", "j"), ("the ", ""), ("and ", ""), ("&", "")] {
            t = PyText.replacing(t, Scalars(a.unicodeScalars), with: Scalars(b.unicodeScalars))
        }
        return joinWords(t)
    }

    static func sim(_ a: Scalars, _ b: Scalars) -> Double { PySequenceMatcher(a, b).ratio() }

    // MARK: 計分

    public struct Candidate: Equatable {
        public var doi: String?
        public var type: String?
        public var title: String
        public var container: String
        public var year: Int?
        public var tsim: Double
        public var jsim: Double
        public var yearOK: Bool
        var volume: PyJSON
        var issue: PyJSON
        var page: PyJSON
        public var nAuthors: Int
        public var nAffiliated: Int

        /// 與舊腳本逐位元相同的鍵順序。
        public var json: PyJSON {
            .object([
                ("doi", doi.map { .string($0) } ?? .null),
                ("type", type.map { .string($0) } ?? .null),
                ("title", .string(title)),
                ("container", .string(container)),
                ("year", year.map { .int($0) } ?? .null),
                ("tsim", .double(tsim)),
                ("jsim", .double(jsim)),
                ("year_ok", .bool(yearOK)),
                ("volume", volume),
                ("issue", issue),
                ("page", page),
                ("n_authors", .int(nAuthors)),
                ("n_affiliated", .int(nAffiliated)),
            ])
        }
    }

    /// 把一筆 Crossref 記錄對照期望值，回傳各訊號的分數。
    static func score(_ item: [String: Any], _ work: Work) -> Candidate {
        let title = firstString(item["title"])
        let container = firstString(item["container-title"])
        let parts = ((item["published"] as? [String: Any])?["date-parts"] as? [Any]).flatMap { $0.isEmpty ? nil : $0 }
        let firstPart = (parts?.first as? [Any])?.first
        let year = pyInt(firstPart)
        let yearOK: Bool
        if let want = work.year, want != 0, let y = year, y != 0 { yearOK = abs(y - want) <= 1 } else { yearOK = false }
        let authors = (item["author"] as? [Any]) ?? []
        return Candidate(
            doi: item["DOI"] as? String,
            type: item["type"] as? String,
            title: title,
            container: container,
            year: year,
            tsim: PyJSON.rounded(sim(norm(title), norm(work.title)), digits: 3),
            jsim: (!container.isEmpty && work.journal != nil) ? PyJSON.rounded(sim(jnorm(container), jnorm(work.journal)), digits: 3) : 0.0,
            yearOK: yearOK,
            volume: PyJSONBridge.convert(item["volume"]),
            issue: PyJSONBridge.convert(item["issue"]),
            page: PyJSONBridge.convert(item["page"]),
            nAuthors: authors.count,
            nAffiliated: authors.filter { a in
                guard let aff = (a as? [String: Any])?["affiliation"] else { return false }
                if let list = aff as? [Any] { return !list.isEmpty }
                if let text = aff as? String { return !text.isEmpty }
                return true
            }.count)
    }

    /// `(item.get(key) or [""])[0]`：清單的第一個字串，沒有就是空字串。
    private static func firstString(_ any: Any?) -> String { ((any as? [Any])?.first as? String) ?? "" }

    /// Python 的 `int(x)`（只收整數與整數字串）；不能轉的回 nil。
    static func pyInt(_ any: Any?) -> Int? {
        if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            let d = n.doubleValue
            return d.isFinite && abs(d) < 1e15 ? Int(d) : nil
        }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    // MARK: 判定

    public enum Status: String { case confident, probable, needsReview = "needs_review", noResult = "no_result" }

    /// 四訊號合取。期刊完全相符且年份吻合時，標題門檻可降到 0.85——那通常是來源標題帶了更正註記或被截斷，實測零誤收。
    static func classify(_ c: Candidate?) -> Status {
        guard let c else { return .noResult }
        if let type = c.type, nonArticleTypes.contains(type) { return .needsReview }
        if c.tsim >= 0.92, c.jsim >= 0.75, c.yearOK { return .confident }
        if c.jsim >= 0.95, c.yearOK, c.tsim >= 0.85 { return .confident }
        if c.tsim >= 0.92, c.jsim >= 0.75 || c.yearOK { return .probable }
        return .needsReview
    }

    /// 標題權重加倍——它是最強的單一訊號，只是不能單獨用。**穩定排序**（Python 的 `sorted(reverse=True)` 對相等的鍵保持原順序）。
    static func rank(_ cands: [Candidate]) -> [Candidate] {
        func key(_ c: Candidate) -> Double { c.tsim * 2 + c.jsim + (c.yearOK ? 0.5 : 0) }
        return cands.enumerated().sorted { l, r in
            let kl = key(l.element), kr = key(r.element)
            return kl != kr ? kl > kr : l.offset < r.offset
        }.map(\.element)
    }

    /// `^(.*?)/v\d+/review\d+$`：審稿報告的 DOI 是「原文 DOI ＋ /vN/reviewM」，剝掉後綴就是原文。
    static func stripReviewSuffix(_ doi: String) -> String? {
        let s = Scalars(doi.unicodeScalars)
        var i = s.count
        var digits2 = 0
        while i > 0, PyText.isDecimal(s[i - 1]) { i -= 1; digits2 += 1 }
        guard digits2 > 0 else { return nil }
        let review = Scalars("/review".unicodeScalars)
        guard i >= review.count, PyText.hasPrefix(s, review, at: i - review.count) else { return nil }
        i -= review.count
        var digits1 = 0
        while i > 0, PyText.isDecimal(s[i - 1]) { i -= 1; digits1 += 1 }
        guard digits1 > 0, i >= 2, s[i - 1] == "v", s[i - 2] == "/" else { return nil }
        return PyText.string(Scalars(s[..<(i - 2)]))
    }

    // MARK: 請求

    /// 一個待取的 API 請求。`id` 是 URL 的 SHA-256 前 16 個十六進位字元（skill 用它當回應檔名——序號與檔名不從 DOI、citekey、
    /// 標題導出，見 web-access.md〈開哪個網址〉）；`url` 帶 `mailto`（若有），`id` 不含它，所以換信箱不會讓已取的回應失效。
    public struct Request: Hashable {
        public let id: String
        public let url: String
        /// 以 DOI 單筆查詢時，回應必須是這個 DOI（核對身分用）。
        let expectedDOI: String?
        public static func == (l: Request, r: Request) -> Bool { l.id == r.id }
        public func hash(into h: inout Hasher) { h.combine(id) }
    }

    static func makeRequest(path: String, query: [(String, String)], expectedDOI: String? = nil, mailto: String?) -> Request {
        var base = endpoint + path
        if !query.isEmpty { base += "?" + query.map { "\(quotePlus($0.0))=\(quotePlus($0.1))" }.joined(separator: "&") }
        let id = SHA256.hash(data: Data(base.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        var url = base
        if let mailto { url += (query.isEmpty ? "?" : "&") + "mailto=" + quotePlus(mailto) }
        return Request(id: id, url: url, expectedDOI: expectedDOI)
    }

    /// `urllib.parse.quote_plus`：字母數字與 `_.-~` 原樣，空格變 `+`，其餘 UTF-8 位元組百分比編碼。
    static func quotePlus(_ s: String) -> String { quote(s, safe: "", spacePlus: true) }

    /// `urllib.parse.quote(s, safe="/")`（單筆 DOI 查詢的路徑）。
    static func quotePath(_ s: String) -> String { quote(s, safe: "/", spacePlus: false) }

    private static func quote(_ s: String, safe: String, spacePlus: Bool) -> String {
        var out = ""
        for b in s.utf8 {
            let c = Character(Unicode.Scalar(b))
            if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || "_.-~".contains(c) || safe.contains(c) {
                out.append(c)
            } else if spacePlus, b == 0x20 {
                out += "+"
            } else {
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    /// DOI 進網址前的形狀檢查（web-access.md〈插值前先驗形狀〉的 DOI 一列）：`^10\.[0-9]{4,9}/[^\s'"\\$`#?%]+$`，
    /// 且以 `/` 分隔的段都不是 `.` 或 `..`。回應裡的 DOI 是第三方登記的字串；形狀不合的不拿去組下一個請求。
    static func isSafeDOI(_ doi: String) -> Bool {
        let s = Scalars(doi.unicodeScalars)
        guard s.count > 3, s[0] == "1", s[1] == "0", s[2] == "." else { return false }
        var i = 3
        var digits = 0
        while i < s.count, s[i].isASCII, ("0"..."9").contains(s[i]) { digits += 1; i += 1 }
        guard (4...9).contains(digits), i < s.count, s[i] == "/" else { return false }
        guard s.count > i + 1 else { return false }
        for c in s[(i + 1)...] where PyText.isSpace(c) || "'\"\\$`#?%".unicodeScalars.contains(c) { return false }
        return !doi.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == "." || $0 == ".." }
    }

    // MARK: 回應

    public enum Response {
        /// HTTP 200 的 JSON 本文。
        case json(Any)
        /// HTTP 404（Crossref 對不存在的 DOI 回 404 加純文字本文）：查無此筆，不是中止訊號。
        case notFound
    }

    public protocol ResponseSource {
        /// 這個請求已取得的回應；還沒取則 nil。回應檔壞掉（不是合法 JSON）時擲出具名錯誤。
        func response(for request: Request) throws -> Response?
    }

    /// 讀取失敗的具名描述，形狀與舊腳本記進 `reverse.error` 的字串一致（`<型別>: <訊息>`）。
    struct FetchFailure: Error {
        let text: String
        static let notFound = FetchFailure(text: "HTTPError: HTTP Error 404: Not Found")
    }

    struct NeedResponse: Error { let request: Request }

    /// 取一個請求的回應；沒有就擲 `NeedResponse`（讓呼叫端知道下一步要什麼）。
    private static func fetch(_ request: Request, from source: ResponseSource) throws -> [String: Any] {
        guard let response = try source.response(for: request) else { throw NeedResponse(request: request) }
        switch response {
        case .notFound: throw FetchFailure.notFound
        case .json(let any):
            guard let obj = any as? [String: Any] else { throw FetchFailure(text: "TypeError: response is not a JSON object") }
            return obj
        }
    }

    /// 單筆 DOI 查詢的回應：`["message"]`，且它的 DOI 必須就是請求的 DOI（讀回後核對身分，web-access.md〈取一次 API〉）。
    private static func fetchByDOI(_ request: Request, from source: ResponseSource) throws -> [String: Any] {
        let obj = try fetch(request, from: source)
        guard let message = obj["message"] as? [String: Any] else { throw FetchFailure(text: "KeyError: 'message'") }
        if let expected = request.expectedDOI {
            let got = (message["DOI"] as? String).map(FulltextVerify.normDOI)
            if got != FulltextVerify.normDOI(expected) {
                throw FetchFailure(text: "IdentityMismatch: 請求的是 \(displaySafeInvisible(expected, max: 200))，回應是 \(displaySafeInvisible(got ?? "(無 DOI)", max: 200))")
            }
        }
        return message
    }

    // MARK: 解決

    struct Resolution {
        var best: Candidate?
        var candidates: [Candidate]
        var status: Status
        var how: String
    }

    private static func search(_ work: Work, typed: Bool, source: ResponseSource, mailto: String?) throws -> [Candidate] {
        var q: [(String, String)] = [("query.bibliographic", work.title), ("rows", "5"), ("select", selectFields)]
        if typed {
            q.append(("filter", "type:journal-article"))
            if let journal = work.journal { q.append(("query.container-title", journal)) }
        }
        let request = makeRequest(path: "", query: q, mailto: mailto)
        let obj: [String: Any]
        do { obj = try fetch(request, from: source) } catch let f as FetchFailure {
            // 一般查詢端點不會 404；回應是 404 或形狀不對，是 skill 的取得步驟出了問題，不是「沒有結果」
            throw SkillToolError.failure("查詢回應無法使用（請求 \(request.id)）：\(f.text)")   // display-safe-exempt: request：id 是 URL 的十六進位雜湊；f：text 由本檔組成（DOI 已 displaySafeInvisible，其餘是固定文字）
        }
        // 200 而形狀不對（`message` 不是物件、`items` 不是陣列——`{"status":"failed","message":"rate limited"}` 之類）是取得步驟出了問題，
        // 不是「沒有候選」：當成空清單會讓「查無此筆」與「回應壞了」在輸出裡不可區分（R1 verify 第 40 則；舊腳本在這裡拋 AttributeError）
        guard let message = obj["message"] as? [String: Any], let items = message["items"] as? [Any] else {
            throw SkillToolError.failure("查詢回應形狀不對（請求 \(request.id)）：需要 message.items 陣列——那是取得步驟出了問題，不是「沒有結果」，不要重試同一個回應")   // display-safe-exempt: request：id 是 URL 的十六進位雜湊
        }
        return rank(try items.map { item in
            guard let dict = item as? [String: Any] else { throw SkillToolError.failure("查詢回應（請求 \(request.id)）的 items 含非物件項目") }   // display-safe-exempt: request：id 是 URL 的十六進位雜湊
            return score(dict, work)
        })
    }

    /// 三段式：一般查詢 → 剝審稿後綴 → 限定 journal-article 重查。
    static func resolve(_ work: Work, source: ResponseSource, mailto: String?) throws -> Resolution {
        let cands = try search(work, typed: false, source: source, mailto: mailto)
        let best = cands.first
        let st = classify(best)
        if st == .confident { return Resolution(best: best, candidates: Array(cands.prefix(3)), status: st, how: "direct") }

        // preprint／審稿報告／會議摘要 → 試著救
        if let best, let doi = best.doi, let stripped = stripReviewSuffix(doi), isSafeDOI(stripped) {
            do {
                let request = makeRequest(path: "/" + quotePath(stripped), query: [], expectedDOI: stripped, mailto: mailto)
                let c = score(try fetchByDOI(request, from: source), work)
                if classify(c) == .confident {
                    return Resolution(best: c, candidates: Array(cands.prefix(3)), status: .confident, how: "strip-review-suffix")
                }
            } catch is FetchFailure {
                // 舊實作在這一步吞掉所有例外，退回下一段
            }
        }

        let retyped = try search(work, typed: true, source: source, mailto: mailto)
        if let c = retyped.first {
            let s2 = classify(c)
            if s2 == .confident || s2 == .probable {
                return Resolution(best: c, candidates: Array(retyped.prefix(3)), status: s2, how: "typed-requery")
            }
            return Resolution(best: c, candidates: Array(retyped.prefix(3)), status: .needsReview, how: "typed-requery")
        }
        return Resolution(best: best, candidates: Array(cands.prefix(3)), status: st, how: "direct")
    }

    /// 用選定的 DOI 回查，比對回來的標題／期刊／年份／type。方向與查詢階段相反，所以「查詢時選錯候選」不會一致地重複。
    static func reverseVerify(doi: String?, work: Work, source: ResponseSource, mailto: String?) throws -> (ok: Bool, detail: PyJSON) {
        guard let doi, isSafeDOI(doi) else {
            return (false, .object([("error", .string("UnsafeDOI: 候選的 DOI 不存在或形狀不合格，不拿去組請求"))]))
        }
        do {
            let request = makeRequest(path: "/" + quotePath(doi), query: [], expectedDOI: doi, mailto: mailto)
            let c = score(try fetchByDOI(request, from: source), work)
            let ok = c.type == "journal-article" && c.tsim >= 0.90 && c.jsim >= 0.70 && c.yearOK
            return (ok, c.json)
        } catch let f as FetchFailure {
            return (false, .object([("error", .string(f.text))]))
        }
    }

    // MARK: 整批

    public struct Record {
        public var citekey: PyJSON
        public var status: String
        public var how: String
        public var best: Candidate?
        public var candidates: [Candidate]
        public var reverseVerified: Bool?
        var reverse: PyJSON?
        public var note: String?

        public var json: PyJSON {
            var pairs: [(String, PyJSON)] = [
                ("citekey", citekey), ("status", .string(status)), ("how", .string(how)),
                ("best", best?.json ?? .null), ("candidates", .array(candidates.map(\.json))),
            ]
            if let reverseVerified, let reverse {
                pairs.append(("reverse_verified", .bool(reverseVerified)))
                pairs.append(("reverse", reverse))
            }
            if let note { pairs.append(("note", .string(note))) }
            return .object(pairs)
        }
    }

    public enum Outcome {
        case complete([Record])
        /// 還有作品要等回應。`requests` 是這一輪每筆未完成作品的下一個請求（去重、依作品順序）。
        case pending(requests: [Request], resolved: Int)
    }

    public static func run(works: [Work], source: ResponseSource, verify: Bool, mailto: String?) throws -> Outcome {
        var records: [Record] = []
        var pending: [Request] = []
        var seen = Set<String>()
        var resolvedCount = 0
        for work in works {
            do {
                let res = try resolve(work, source: source, mailto: mailto)
                var rec = Record(citekey: work.citekey, status: res.status.rawValue, how: res.how, best: res.best, candidates: res.candidates)
                if let best = res.best, res.status == .confident || res.status == .probable, verify {
                    let (ok, back) = try reverseVerify(doi: best.doi, work: work, source: source, mailto: mailto)
                    rec.reverseVerified = ok
                    rec.reverse = back
                    if !ok {
                        rec.status = Status.needsReview.rawValue
                        rec.note = "反向驗證未過——人工核對後才可採用"
                    }
                }
                records.append(rec)
                resolvedCount += 1
            } catch let need as NeedResponse {
                if seen.insert(need.request.id).inserted { pending.append(need.request) }
            }
        }
        if pending.isEmpty { return .complete(records) }
        return .pending(requests: pending, resolved: resolvedCount)
    }
}

/// Foundation JSON 值 → `PyJSON`（只用在「原樣透傳」的欄位：卷、期、頁碼、citekey）。
enum PyJSONBridge {
    static func convert(_ any: Any?) -> PyJSON {
        switch any {
        case nil: return .null
        case is NSNull: return .null
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) { return .double(n.doubleValue) }
            return .int(n.intValue)
        case let a as [Any]: return .array(a.map { convert($0) })
        case let d as [String: Any]: return .object(d.keys.sorted().map { ($0, convert(d[$0])) })
        default: return .null
        }
    }
}

/// 回應存在一個目錄裡（`crossref-match --responses`）：`<id>.json` 是 HTTP 200 的本文、`<id>.404` 是「查無此筆」的標記。
/// 其他狀態碼不存檔——那是中止條款（skill 整批停），不是這裡的輸入。
public struct DirectoryResponseSource: CrossrefMatch.ResponseSource {
    public let directory: String

    public init(directory: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            throw SkillToolError.failure("--responses 不是目錄：\(displaySafeInvisible(directory, max: 300))——先建立它（skill 把每個回應存成 <id>.json）")
        }
        self.directory = directory
    }

    public func response(for request: CrossrefMatch.Request) throws -> CrossrefMatch.Response? {
        let json = directory + "/" + request.id + ".json"
        let notFound = directory + "/" + request.id + ".404"
        let fm = FileManager.default
        let hasJSON = fm.fileExists(atPath: json), hasNotFound = fm.fileExists(atPath: notFound)
        if hasJSON && hasNotFound {
            throw SkillToolError.failure("請求 \(request.id) 同時有 .json 與 .404 兩個回應檔——同一個請求只能有一個結果，刪掉錯的那個")   // display-safe-exempt: request：id 是 URL 的十六進位雜湊
        }
        if hasNotFound { return .notFound }
        guard hasJSON else { return nil }
        guard let data = fm.contents(atPath: json) else {
            throw SkillToolError.failure("讀不到回應檔 \(request.id).json")   // display-safe-exempt: request：id 是 URL 的十六進位雜湊
        }
        do {
            return .json(try PyJSONParser.parse(data, loneSurrogates: .replacementCharacter))
        } catch {
            // 200 的 JSON 端點回了不是 JSON 的本文（驗證頁、擋截頁）是中止條款；檔案不該被存下來（web-access.md〈中止條款〉第 4 點）
            throw SkillToolError.failure("回應檔 \(request.id).json 不是合法 JSON：\(displaySafeErrorText(error))——那是中止條款的訊號，不要重試")   // display-safe-exempt: request：id 是 URL 的十六進位雜湊
        }
    }
}
