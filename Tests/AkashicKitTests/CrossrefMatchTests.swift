import XCTest
import AkashicCore
@testable import AkashicSkillTools

/// `CrossrefMatch`（#629，由 `crossref_match.py` 移植）。期望值取自 Python 舊實作的輸出：`norm`／`jnorm`／`SequenceMatcher`、
/// `urllib.parse` 的編碼、請求 URL 與它的雜湊。整份程式的新舊逐位元差分（30 個種子、1,860 筆作品，結果檔 `cmp` 相同）記在
/// changelog——那是一次性的證據，不在這個檔裡。
final class CrossrefMatchTests: XCTestCase {

    // MARK: 正規化與編碼（期望值取自 Python）

    func testNormAndJnormMatchPython() {
        func n(_ s: String?) -> String { PyText.string(CrossrefMatch.norm(s)) }
        func j(_ s: String?) -> String { PyText.string(CrossrefMatch.jnorm(s)) }
        XCTAssertEqual(n("The Journal of Educational  Psychology"), "the journal of educational psychology")
        XCTAssertEqual(j("The Journal of Educational  Psychology"), "j educational psychology")
        XCTAssertEqual(j("British Journal of Mathematical & Statistical Psychology"), "british j mathematical statistical psychology")
        XCTAssertEqual(n("  Psychometrika. "), "psychometrika")
        XCTAssertEqual(n("ÄÖÜ İstanbul Σίσυφος ΑΣ"), "äöü i\u{307}stanbul σίσυφος ασ")   // 逐字元小寫：Python 的 `c.lower()` 沒有詞尾 sigma 脈絡
        XCTAssertEqual(n("心理學報 (Chinese)"), "心理學報 chinese")
        XCTAssertEqual(n("A-B_C/D"), "a b c d")
        XCTAssertEqual(n(nil), "")
        XCTAssertEqual(j("the and journal of the the "), "j the")   // 依序全部替換、不分詞界
        XCTAssertEqual(j("And the Andes"), "andes")
        XCTAssertEqual(n("٣٤ Ⅳ ① ½"), "٣٤ ⅳ ① ½")
    }

    func testURLEncodingMatchesPythonUrllib() {
        XCTAssertEqual(CrossrefMatch.quotePlus("a b/ü?&=+%~._-:,"), "a+b%2F%C3%BC%3F%26%3D%2B%25~._-%3A%2C")
        XCTAssertEqual(CrossrefMatch.quotePath("10.1002/(SICI)1099-0984<x>;2-A é#?%"), "10.1002/%28SICI%291099-0984%3Cx%3E%3B2-A%20%C3%A9%23%3F%25")
    }

    /// 請求 URL 與 `id`（URL 的 SHA-256 前 16 hex）逐字等於 Python `f"{CROSSREF}?{urlencode(q)}"` 與 `hashlib.sha256(url)`。
    func testRequestURLsAndIdsMatchPython() {
        let q: [(String, String)] = [("query.bibliographic", "Psychometrics: 心理 & stats"), ("rows", "5"), ("select", CrossrefMatch.selectFields)]
        let a = CrossrefMatch.makeRequest(path: "", query: q, mailto: nil)
        XCTAssertEqual(a.url, "https://api.crossref.org/works?query.bibliographic=Psychometrics%3A+%E5%BF%83%E7%90%86+%26+stats&rows=5&select=DOI%2Ctitle%2Ccontainer-title%2Cvolume%2Cissue%2Cpage%2Cauthor%2Cpublished%2Ctype")
        XCTAssertEqual(a.id, "28db9e34da55e4d2")
        let b = CrossrefMatch.makeRequest(path: "", query: q + [("filter", "type:journal-article"), ("query.container-title", "J. Test & Co")], mailto: nil)
        XCTAssertEqual(b.id, "054161da3ae51283")
        let c = CrossrefMatch.makeRequest(path: "/" + CrossrefMatch.quotePath("10.1037/met0000285"), query: [], mailto: nil)
        XCTAssertEqual(c.url, "https://api.crossref.org/works/10.1037/met0000285")
        XCTAssertEqual(c.id, "072ce526239c12c4")
    }

    /// 信箱進網址的 `mailto` 參數，但不進 `id`：換信箱不讓已取的回應失效。
    func testMailtoIsInTheURLButNotTheId() {
        let plain = CrossrefMatch.makeRequest(path: "/x", query: [], mailto: nil)
        let with = CrossrefMatch.makeRequest(path: "/x", query: [], mailto: "me@example.org")
        XCTAssertEqual(with.id, plain.id)
        XCTAssertEqual(with.url, plain.url + "?mailto=me%40example.org")
        let q = CrossrefMatch.makeRequest(path: "", query: [("rows", "5")], mailto: "me@example.org")
        XCTAssertTrue(q.url.hasSuffix("?rows=5&mailto=me%40example.org"), q.url)
    }

    func testDOIShapeCheckBeforeBuildingARequest() {
        XCTAssertTrue(CrossrefMatch.isSafeDOI("10.1037/met0000285"))
        XCTAssertTrue(CrossrefMatch.isSafeDOI("10.1002/(SICI)1099-0984(199909/10)13:5<389::AID-PER361>3.0.CO;2-A"))
        for bad in ["10.1037/../../x", "10.1037/a/./b", "10.1037/a b", "10.1037/a?x", "10.1037/a#x", "10.1037/a%2e", "10.1037/a\"b",
                    "10.1/x", "10.12345678901/x", "11.1037/x", "10.1037/", "10.1037", "10.1037/a$b", "10.1037/a\\b", "10.1037/a`b", "10.1037/a'b", ""] {
            XCTAssertFalse(CrossrefMatch.isSafeDOI(bad), bad)
        }
    }

    func testReviewSuffixIsStrippedToTheOriginalDOI() {
        XCTAssertEqual(CrossrefMatch.stripReviewSuffix("10.1234/abc/v1/review2"), "10.1234/abc")
        XCTAssertEqual(CrossrefMatch.stripReviewSuffix("10.1234/abc/v12/review345"), "10.1234/abc")
        XCTAssertEqual(CrossrefMatch.stripReviewSuffix("10.1234/x/v1/review1/v2/review2"), "10.1234/x/v1/review1")
        for none in ["10.1234/abc", "10.1234/abc/v1/review", "10.1234/abc/v/review1", "10.1234/abc/review1", "10.1234/abc/v1/reviewx1"] {
            XCTAssertNil(CrossrefMatch.stripReviewSuffix(none), none)
        }
    }

    // MARK: 判定

    private func cand(type: String? = "journal-article", tsim: Double, jsim: Double, yearOK: Bool, doi: String? = "10.1/x") -> CrossrefMatch.Candidate {
        .init(doi: doi, type: type, title: "t", container: "c", year: 2000, tsim: tsim, jsim: jsim, yearOK: yearOK,
              volume: .null, issue: .null, page: .null, nAuthors: 0, nAffiliated: 0)
    }

    /// 四訊號合取的每一條邊界（門檻 0.92／0.85／0.75／0.95）。
    func testClassifyBoundaries() {
        XCTAssertEqual(CrossrefMatch.classify(nil), .noResult)
        XCTAssertEqual(CrossrefMatch.classify(cand(type: "peer-review", tsim: 1, jsim: 1, yearOK: true)), .needsReview)
        XCTAssertEqual(CrossrefMatch.classify(cand(type: "posted-content", tsim: 1, jsim: 1, yearOK: true)), .needsReview)
        XCTAssertEqual(CrossrefMatch.classify(cand(type: "component", tsim: 1, jsim: 1, yearOK: true)), .needsReview)
        XCTAssertEqual(CrossrefMatch.classify(cand(type: nil, tsim: 1, jsim: 1, yearOK: true)), .confident)
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.92, jsim: 0.75, yearOK: true)), .confident)
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.919, jsim: 0.75, yearOK: true)), .needsReview)
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.92, jsim: 0.749, yearOK: true)), .probable)     // 年份吻合但期刊不夠
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.92, jsim: 0.75, yearOK: false)), .probable)     // 期刊夠但年份不吻合
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.92, jsim: 0.0, yearOK: false)), .needsReview)
        // 期刊完全相符且年份吻合時，標題門檻降到 0.85
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.85, jsim: 0.95, yearOK: true)), .confident)
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.849, jsim: 0.95, yearOK: true)), .needsReview)
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.85, jsim: 0.949, yearOK: true)), .needsReview)
        XCTAssertEqual(CrossrefMatch.classify(cand(tsim: 0.85, jsim: 0.95, yearOK: false)), .needsReview)
    }

    /// 標題權重加倍；相等的鍵保持原順序（Python `sorted(reverse=True)` 是穩定的）。
    func testRankWeightsTitleTwiceAndIsStable() {
        let a = cand(tsim: 0.5, jsim: 0.0, yearOK: false, doi: "a")   // 1.0
        let b = cand(tsim: 0.4, jsim: 0.3, yearOK: true, doi: "b")    // 0.8+0.3+0.5 = 1.6
        let c = cand(tsim: 0.5, jsim: 0.0, yearOK: false, doi: "c")   // 1.0，與 a 同分
        XCTAssertEqual(CrossrefMatch.rank([a, b, c]).map(\.doi), ["b", "a", "c"])
        XCTAssertEqual(CrossrefMatch.rank([c, a]).map(\.doi), ["c", "a"])
    }

    // MARK: 記憶體內的回應來源

    private struct Memory: CrossrefMatch.ResponseSource {
        var byId: [String: CrossrefMatch.Response] = [:]
        func response(for request: CrossrefMatch.Request) throws -> CrossrefMatch.Response? { byId[request.id] }
    }

    private func item(doi: String, title: String, container: String = "Psychological Methods", year: Int = 2015, type: String = "journal-article") -> [String: Any] {
        ["DOI": doi, "title": [title], "container-title": [container], "type": type, "published": ["date-parts": [[year, 3]]],
         "volume": "20", "issue": "1", "page": "1-19", "author": [["affiliation": [["name": "X"]]], ["affiliation": []]]]
    }

    private let work = CrossrefMatch.Work(citekey: .string("k1"), title: "A critique of the cross-lagged panel model", journal: "Psychological Methods", year: 2015)

    private func searchRequest(typed: Bool = false, mailto: String? = nil) -> CrossrefMatch.Request {
        var q: [(String, String)] = [("query.bibliographic", work.title), ("rows", "5"), ("select", CrossrefMatch.selectFields)]
        if typed { q += [("filter", "type:journal-article"), ("query.container-title", work.journal!)] }
        return CrossrefMatch.makeRequest(path: "", query: q, mailto: mailto)
    }

    private func byDOIRequest(_ doi: String) -> CrossrefMatch.Request {
        CrossrefMatch.makeRequest(path: "/" + CrossrefMatch.quotePath(doi), query: [], expectedDOI: doi, mailto: nil)
    }

    private func searchBody(_ items: [[String: Any]]) -> CrossrefMatch.Response { .json(["message": ["items": items]]) }

    private func run(_ source: Memory, verify: Bool = true) throws -> CrossrefMatch.Outcome {
        try CrossrefMatch.run(works: [work], source: source, verify: verify, mailto: nil)
    }

    func testEmptySourceAsksForTheSearchFirst() throws {
        guard case .pending(let requests, let resolved) = try run(Memory()) else { return XCTFail() }
        XCTAssertEqual(requests.map(\.id), [searchRequest().id])
        XCTAssertEqual(resolved, 0)
    }

    /// 一般查詢得到 confident → 下一步是反向驗證（單筆 DOI 查詢）；驗證回應進來之後完成。
    func testConfidentDirectThenReverseVerifyCompletes() throws {
        let good = item(doi: "10.1037/a0038889", title: work.title)
        var src = Memory(byId: [searchRequest().id: searchBody([good])])
        guard case .pending(let need, _) = try run(src) else { return XCTFail() }
        XCTAssertEqual(need.map(\.id), [byDOIRequest("10.1037/a0038889").id])
        src.byId[byDOIRequest("10.1037/a0038889").id] = .json(["message": good])
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].status, "confident")
        XCTAssertEqual(records[0].how, "direct")
        XCTAssertEqual(records[0].reverseVerified, true)
        XCTAssertNil(records[0].note)
    }

    func testNoVerifyCompletesWithoutTheReverseRequest() throws {
        let good = item(doi: "10.1037/a0038889", title: work.title)
        guard case .complete(let records) = try run(Memory(byId: [searchRequest().id: searchBody([good])]), verify: false) else { return XCTFail() }
        XCTAssertNil(records[0].reverseVerified)
    }

    /// 反向驗證回 404（DOI 不在 Crossref：DataCite、mEDRA 常見）＝查無此筆、不是中止訊號：該筆 needs_review，錯誤字串與舊腳本相同。
    func testReverseVerify404IsNotFoundNotAStop() throws {
        let good = item(doi: "10.1037/a0038889", title: work.title)
        let src = Memory(byId: [searchRequest().id: searchBody([good]), byDOIRequest("10.1037/a0038889").id: .notFound])
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records[0].status, "needs_review")
        XCTAssertEqual(records[0].reverseVerified, false)
        XCTAssertEqual(records[0].note, "反向驗證未過——人工核對後才可採用")
        XCTAssertEqual(records[0].reverse, .object([("error", .string("HTTPError: HTTP Error 404: Not Found"))]))
    }

    /// 讀回後核對身分（PsychQuant/safari-browser#190 的形狀）：以 DOI 查的，回應裡的 DOI 必須就是請求的。
    func testReverseVerifyRejectsAResponseAboutAnotherDOI() throws {
        let good = item(doi: "10.1037/a0038889", title: work.title)
        let other = item(doi: "10.1037/zzz", title: work.title)   // 內容看起來完全吻合，但不是被請求的那個 DOI
        let src = Memory(byId: [searchRequest().id: searchBody([good]), byDOIRequest("10.1037/a0038889").id: .json(["message": other])])
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records[0].status, "needs_review")
        guard case .object(let pairs)? = records[0].reverse, case .string(let text)? = pairs.first?.1 else { return XCTFail() }
        XCTAssertTrue(text.hasPrefix("IdentityMismatch: "), text)
    }

    /// DOI 大小寫、百分比編碼不同不算不吻合（Crossref 回小寫）。
    func testIdentityCheckIgnoresCaseAndDOIPrefixes() throws {
        let good = item(doi: "10.1037/A0038889", title: work.title)
        var lower = good; lower["DOI"] = "10.1037/a0038889"
        let src = Memory(byId: [searchRequest().id: searchBody([good]), byDOIRequest("10.1037/A0038889").id: .json(["message": lower])])
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records[0].reverseVerified, true)
    }

    /// 三段式的第二段：最佳候選是審稿報告（`…/v1/review1`）→ 剝後綴查原文 → 原文 confident 即採用。
    func testStripReviewSuffixRescuesTheOriginal() throws {
        let review = item(doi: "10.1037/a0038889/v1/review1", title: work.title, type: "peer-review")
        let original = item(doi: "10.1037/a0038889", title: work.title)
        var src = Memory(byId: [searchRequest().id: searchBody([review])])
        guard case .pending(let need, _) = try run(src) else { return XCTFail() }
        XCTAssertEqual(need.map(\.id), [byDOIRequest("10.1037/a0038889").id])
        src.byId[byDOIRequest("10.1037/a0038889").id] = .json(["message": original])
        // 原文回應也是反向驗證要的那一筆——同一個請求，不需要再取
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records[0].how, "strip-review-suffix")
        XCTAssertEqual(records[0].status, "confident")
        XCTAssertEqual(records[0].best?.doi, "10.1037/a0038889")
    }

    /// 剝後綴那一步的任何失敗（404、身分不符）都退回第三段，不中斷（舊實作吞掉那一步的所有例外）。
    func testStripReviewSuffixFailureFallsThroughToTheTypedRequery() throws {
        let review = item(doi: "10.1037/a0038889/v1/review1", title: work.title, type: "peer-review")
        var src = Memory(byId: [searchRequest().id: searchBody([review]), byDOIRequest("10.1037/a0038889").id: .notFound])
        guard case .pending(let need, _) = try run(src) else { return XCTFail() }
        XCTAssertEqual(need.map(\.id), [searchRequest(typed: true).id])
        // 限定 journal-article 重查找到原文：採用；反向驗證要的是同一個 `/works/<原文 DOI>`（上一步已取得、404），所以不再需要新請求
        src.byId[searchRequest(typed: true).id] = searchBody([item(doi: "10.1037/a0038889", title: work.title)])
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records[0].how, "typed-requery")
        XCTAssertEqual(records[0].status, "needs_review")   // 反向驗證撞到 404
        XCTAssertEqual(records[0].reverse, .object([("error", .string("HTTPError: HTTP Error 404: Not Found"))]))
    }

    func testTypedRequeryWithNothingFallsBackToTheDirectResult() throws {
        let wrongPaper = item(doi: "10.1037/other", title: "Something else entirely different", container: "Assessment", year: 1999)
        let src = Memory(byId: [searchRequest().id: searchBody([wrongPaper]), searchRequest(typed: true).id: searchBody([])])
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records[0].how, "direct")
        XCTAssertEqual(records[0].status, "needs_review")
        XCTAssertEqual(records[0].best?.doi, "10.1037/other")
    }

    func testNoItemsAnywhereIsNoResult() throws {
        let src = Memory(byId: [searchRequest().id: searchBody([]), searchRequest(typed: true).id: searchBody([])])
        guard case .complete(let records) = try run(src) else { return XCTFail() }
        XCTAssertEqual(records[0].status, "no_result")
        XCTAssertNil(records[0].best)
        XCTAssertEqual(records[0].json, records[0].json)
        guard case .object(let pairs) = records[0].json else { return XCTFail() }
        XCTAssertEqual(pairs.map(\.0), ["citekey", "status", "how", "best", "candidates"])   // 沒驗證就沒有 reverse 欄位
    }

    /// 查詢端點回 404 或形狀不對，是 skill 的取得步驟出了問題，不是「沒有結果」：具名失敗，整批中止。
    func testASearchThatCameBack404IsAnInputError() {
        XCTAssertThrowsError(try run(Memory(byId: [searchRequest().id: .notFound]))) { error in
            XCTAssertTrue("\(error)".contains("查詢回應無法使用"), "\(error)")
        }
    }

    /// 兩筆作品要同一個請求時只列一次（去重）。
    func testPendingRequestsAreDeduplicatedAcrossWorks() throws {
        guard case .pending(let requests, _) = try CrossrefMatch.run(works: [work, work], source: Memory(), verify: true, mailto: nil) else { return XCTFail() }
        XCTAssertEqual(requests.count, 1)
    }

    /// 候選的 DOI 形狀不合格（路徑折疊、`?`、`#`）不拿去組請求——反向驗證直接記錯誤，不出現在 pending。
    func testAnUnsafeCandidateDOIIsNeverTurnedIntoARequest() throws {
        let sneaky = item(doi: "10.1037/../../etc", title: work.title)
        guard case .complete(let records) = try run(Memory(byId: [searchRequest().id: searchBody([sneaky])])) else { return XCTFail() }
        XCTAssertEqual(records[0].status, "needs_review")
        guard case .object(let pairs)? = records[0].reverse, case .string(let text)? = pairs.first?.1 else { return XCTFail() }
        XCTAssertTrue(text.hasPrefix("UnsafeDOI: "), text)
    }

    // MARK: 輸入與回應檔

    func testParseWorksAcceptsStringAndNumericYearsAndDropsEmptyJournal() throws {
        let data = Data(#"[{"citekey":"a","title":"T","journal":"","year":"1998"},{"citekey":null,"title":"U","year":2001}]"#.utf8)
        let works = try CrossrefMatch.parseWorks(data)
        XCTAssertEqual(works.map(\.year), [1998, 2001])
        XCTAssertEqual(works.map(\.journal), [nil, nil])
        XCTAssertEqual(works[1].citekey, .null)
        XCTAssertThrowsError(try CrossrefMatch.parseWorks(Data(#"[{"citekey":"a"}]"#.utf8)))
        XCTAssertThrowsError(try CrossrefMatch.parseWorks(Data(#"{"a":1}"#.utf8)))
    }

    func testDirectoryResponseSourceReadsJsonAnd404Markers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crossref-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = try DirectoryResponseSource(directory: dir.path)
        let req = searchRequest()
        XCTAssertNil(try src.response(for: req))
        try Data(#"{"message":{"items":[]}}"#.utf8).write(to: dir.appendingPathComponent(req.id + ".json"))
        guard case .json? = try src.response(for: req) else { return XCTFail() }
        // 同一個請求同時有 .json 與 .404：拒絕，不猜
        try Data().write(to: dir.appendingPathComponent(req.id + ".404"))
        XCTAssertThrowsError(try src.response(for: req))
        try FileManager.default.removeItem(at: dir.appendingPathComponent(req.id + ".json"))
        guard case .notFound? = try src.response(for: req) else { return XCTFail() }
        // 壞的 JSON：那是中止條款的訊號，不當成沒有結果
        let other = byDOIRequest("10.1037/x")
        try Data("<html>captcha</html>".utf8).write(to: dir.appendingPathComponent(other.id + ".json"))
        XCTAssertThrowsError(try src.response(for: other))
        XCTAssertThrowsError(try DirectoryResponseSource(directory: dir.path + "/missing"))
    }
}
