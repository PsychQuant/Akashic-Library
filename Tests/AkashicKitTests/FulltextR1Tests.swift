import XCTest
@testable import AkashicSkillTools

/// #629 第二塊 R1 驗證的回歸釘：補充資料標題的跨行、起疑訊號的 Python 邊界語意。
///
/// **期望值取自舊 Python 實作**（`verify_pdf.py`、`bot_signals.py`，從 `3c19c3b0^` 取出後逐案實跑），不是新實作說的話。
final class SupplementHeadWrapTests: XCTestCase {
    private func flags(_ page: String) -> [String] {
        FulltextVerify.assess(firstPage: page, pageCount: 1, title: "A Stub Title", pages: nil, doi: nil, metaDOI: nil).flags
    }

    /// 舊實作對「前三個非空行用 `\n` 接起來」的整段跑 `re.M`，`\s+` 跨過換行；第一版逐行判斷，把斷行的標題放過去（fail-open）。
    func testAHeaderWrappedOverLinesIsStillASupplement() {
        XCTAssertEqual(flags("Supplemental\nMaterial for\nA Stub Title\ndoi:10.1234/x"), ["supplement"], "兩行斷開")
        XCTAssertEqual(flags("Supplemental\nMaterial"), ["supplement"], "標記單獨在第 1 行")
        XCTAssertEqual(flags("Supporting\nInformation\nA Stub Title"), ["supplement"], "Supporting／Information")
        XCTAssertEqual(flags("Electronic\nSupplementary\nMaterial\nA Stub Title"), ["supplement"], "三行 Electronic／Supplementary／Material")
        XCTAssertEqual(flags("Online\nSupplement\nfoo"), ["supplement"])
        XCTAssertEqual(flags("supplementary\nmethods\nA"), ["supplement"])
        XCTAssertEqual(flags("Supplementary\nMaterials\nA"), ["supplement"], "複數 s")
    }

    /// pdftotext 用 `\f` 分頁，`splitlines()` 把它當行界——跨頁斷開的標題與換行斷開等價。
    func testAHeaderWrappedAcrossAFormFeedIsStillASupplement() {
        XCTAssertEqual(flags("Supplemental\u{0C}Material for\nA Stub Title"), ["supplement"])
    }

    func testIndentedAndSpacePaddedWrapsAreStillSupplements() {
        XCTAssertEqual(flags("  Supplemental  \n   materials\nX"), ["supplement"])
        XCTAssertEqual(flags("Supplemental\n\n\nMaterial\nA"), ["supplement"], "空行不算非空行，斷開的兩半仍在前三個非空行內")
    }

    /// 視窗仍是前 3 個非空行：標記從第 4 行開始、或斷在第 3 與第 4 行之間都不算（一篇正文自己在後面幾行帶的標題）。
    func testAWrapThatStartsPastTheThirdLineIsNotFlagged() {
        XCTAssertEqual(flags("Journal of X\nSome Title\nSupplemental\nMaterial for A Stub Title"), [], "第 3 行的半個標記接不上第 4 行")
        XCTAssertEqual(flags("Journal of X\nSome Title\nSupplemental\nMaterial\nA Stub Title"), [])
        XCTAssertEqual(flags("a\nb\nc\nSupplemental Material"), [], "第 4 行整句")
    }

    func testTheWordBoundaryStillApplies() {
        XCTAssertEqual(flags("Supplemental\nMaterialx\nA"), [], "標記後接字詞字元不算")
    }
}

final class BotSignalsPythonBoundaryTests: XCTestCase {
    /// Python `re.I` 把 U+0130／U+0131 當成 `i`；ICU 不會。`innerText` 套 `text-transform: uppercase` 時 `lang=tr` 頁面的 `i` 變成 `İ`。
    func testDottedAndDotlessIAreTreatedAsI() {
        XCTAssertEqual(BotSignals.detect("access denıed"), "access-denied")
        XCTAssertEqual(BotSignals.detect("unusual traffıc"), "unusual-traffic")
        XCTAssertEqual(BotSignals.detect("rate lımited"), "rate-limit")
        XCTAssertEqual(BotSignals.detect("checkıng your browser"), "pmc-pow-challenge")
        XCTAssertEqual(BotSignals.detect("preparİng to download"), "pmc-pow-challenge")
        XCTAssertEqual(BotSignals.detect("ACCESS DENİED"), "access-denied")
    }

    /// Python 的 `\b` 只把字母、數字、底線當字詞字元；ICU 的 `\b` 把組合標記與 ZWJ／ZWNJ 也算進去，於是後面接它們時漏掉。
    func testAWordBoundaryIsNotHiddenByACombiningMarkOrAJoiner() {
        XCTAssertEqual(BotSignals.detect("Access Denied\u{200D}"), "access-denied")
        XCTAssertEqual(BotSignals.detect("rate limited\u{0301}"), "rate-limit")
        XCTAssertEqual(BotSignals.detect("rate limit\u{200C}"), "rate-limit")
        XCTAssertEqual(BotSignals.detect("rate limit\u{0301}x"), "rate-limit")
        XCTAssertEqual(BotSignals.detect("\u{0301}access denied"), "access-denied")
        XCTAssertEqual(BotSignals.detect("access denied\u{0301}"), "access-denied")
        XCTAssertEqual(BotSignals.detect("\u{200D}access denied"), "access-denied")
    }

    /// 邊界仍是邊界：字母、數字、底線緊貼時不命中。
    func testAdjacentWordCharactersStillSuppressTheMatch() {
        XCTAssertNil(BotSignals.detect("xaccess denied"))
        XCTAssertNil(BotSignals.detect("access denied_"))
        XCTAssertNil(BotSignals.detect("access denied1"))
        XCTAssertNil(BotSignals.detect("rate limitedx"))
        XCTAssertNil(BotSignals.detect("rate limit９"), "全形數字也是字詞字元")
    }

    /// `ſ` 與 Kelvin sign 兩邊本來就一致（ICU 的不分大小寫比對認得），釘住以免有人把折疊改成別的東西。
    func testLongSAndKelvinSignAgreeWithPython() {
        XCTAssertEqual(BotSignals.detect("acceſs denied"), "access-denied")
        XCTAssertEqual(BotSignals.detect("chec\u{212A}ing your browser"), "pmc-pow-challenge")
    }

    /// 兩個 `\b` 換成的字元類必須與 Python 的 `\w`（`PyText.isWord`）在全部 Unicode scalar 上一致；差異會回到「某些字元旁邊漏訊號」。
    func testTheWordClassAgreesWithPythonsWordOnEveryScalar() throws {
        let regex = try NSRegularExpression(pattern: "^" + BotSignals.wordClass + "$")
        var differences: [String] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            // 私用區與未指派：兩邊的 Unicode 資料版本不同（Apple 的資料對 U+F8xx 有私用的數值屬性），與 Python 的 `\w` 無關
            if scalar.properties.generalCategory == .privateUse || scalar.properties.generalCategory == .unassigned { continue }
            let text = String(Character(scalar))
            let icu = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil
            if icu != PyText.isWord(scalar) { differences.append(String(format: "U+%04X", value)) }
            if differences.count > 400 { break }
        }
        XCTAssertEqual(differences, [], "字元類與 PyText.isWord 不一致的 scalar（前 400 個）")
    }
}

/// `abstracts-to-proposals`：JSON 語意與 Python 相同（重複鍵、字串內的 U+FEFF、尾隨逗號）；store 解析失敗的診斷。
final class AbstractProposalsPythonJSONTests: XCTestCase {
    private func convert(_ lines: [String]) throws -> AbstractProposals.Conversion {
        try AbstractProposals.convert(Data(lines.joined(separator: "\n").utf8), digest: "sha256:" + String(repeating: "0", count: 64))
    }

    private func abstracts(_ c: AbstractProposals.Conversion) -> [String] {
        c.proposals.compactMap { p in
            guard case .object(let pairs) = p, case .object(let f)? = pairs.first(where: { $0.0 == "fields" })?.1,
                  case .string(let a)? = f.first?.1 else { return nil }
            return a
        }
    }

    /// 舊腳本 `json.loads`：字串值開頭的 U+FEFF 保留（`str.strip()` 不把它當空白）→ 提案的摘要以 U+FEFF 開頭；
    /// Foundation 把它吃掉（`lossless-intake`：來源給什麼就收什麼）。
    func testALeadingByteOrderMarkInsideAStringValueIsKept() throws {
        let c = try convert([#"{"doi":"10.1/a","status":"got","abstract":"\#u{FEFF}An abstract."}"#])
        XCTAssertEqual(abstracts(c).first?.unicodeScalars.first?.value, 0xFEFF)
        let escaped = try convert([#"{"doi":"10.1/a","status":"got","abstract":"﻿An abstract."}"#])
        XCTAssertEqual(abstracts(escaped).first?.unicodeScalars.first?.value, 0xFEFF, "轉義形式同")
    }

    /// 以 U+FEFF 開頭的 Crossref 無 metadata 樣板：Python 的 `strip().startswith` 不成立 → 收為提案（Foundation 先剝掉 FEFF → 略過）。
    func testTheNoMetadataTemplateBehindAByteOrderMarkIsNotRecognisedJustLikePython() throws {
        let c = try convert([#"{"doi":"10.1/a","status":"got","abstract":"﻿This DOI is not currently attached to any metadata records."}"#])
        XCTAssertEqual(c.proposals.count, 1)
        XCTAssertEqual(c.skips.count, 0)
    }

    func testDuplicateKeysTakeTheLastValueLikePython() throws {
        let c = try convert([#"{"doi":"10.1/a","doi":"10.1/b","status":"got","abstract":"x","abstract":"second wins"}"#])
        XCTAssertEqual(abstracts(c), ["second wins"])
        guard case .object(let pairs) = c.proposals[0], case .string(let doi)? = pairs.first(where: { $0.0 == "doi" })?.1 else { return XCTFail() }
        XCTAssertEqual(doi, "10.1/b")
    }

    func testATrailingCommaIsRejectedLikePython() {
        XCTAssertThrowsError(try convert([#"{"doi":"10.1/a","status":"got","abstract":"x",}"#])) {
            XCTAssertTrue(($0 as? SkillToolError)?.errorDescription?.contains("第 1 行不是合法 JSON") == true, "\($0)")
        }
    }

    /// 形狀合法的 digest，store 解析失敗：錯誤原樣往上，不說成「不是合法的 digest」。
    func testAStoreResolutionFailureIsNotReportedAsAnInvalidDigest() {
        struct NoStore: Error, LocalizedError { var errorDescription: String? { "no library selected" } }
        let digest = "sha256:" + String(repeating: "0", count: 64)
        XCTAssertThrowsError(try AbstractProposals.resolveSource(digest) { _ in throw NoStore() }) {
            XCTAssertTrue($0 is NoStore, "原樣往上：\($0)")
        }
        // 形狀不合法仍是「不是合法的 digest」（不會呼叫 blobURL）
        XCTAssertThrowsError(try AbstractProposals.resolveSource("sha256:xyz") { _ in throw NoStore() }) {
            XCTAssertTrue(($0 as? SkillToolError)?.errorDescription?.contains("不是合法的 digest") == true, "\($0)")
        }
    }
}

/// `crossref-match`：200 而形狀不對不是「沒有候選」。
final class CrossrefMatchResponseShapeTests: XCTestCase {
    private struct Memory: CrossrefMatch.ResponseSource {
        var response: CrossrefMatch.Response
        func response(for request: CrossrefMatch.Request) throws -> CrossrefMatch.Response? { response }
    }

    private let work = CrossrefMatch.Work(citekey: .string("k1"), title: "A critique of the cross-lagged panel model", journal: "Psychological Methods", year: 2015)

    private func run(_ body: Any) throws -> CrossrefMatch.Outcome {
        try CrossrefMatch.run(works: [work], source: Memory(response: .json(body)), verify: true, mailto: nil)
    }

    func testAMalformedSearchBodyIsANamedFailureNotNoResult() {
        let shapes: [Any] = [
            ["status": "failed", "message": [["type": "filter-not-available"]]],   // message 是陣列
            ["status": "failed", "message": "rate limited"],                      // message 是字串
            ["message": ["items": "nope"]],                                        // items 不是陣列
            ["message": ["total-results": 0]],                                     // 沒有 items
            ["status": "failed"],                                                  // 沒有 message
        ]
        for body in shapes {
            XCTAssertThrowsError(try run(body), "\(body)") {
                XCTAssertTrue(($0 as? SkillToolError)?.errorDescription?.contains("查詢回應形狀不對") == true, "\(body)：\($0)")
            }
        }
    }

    /// 合法的空結果仍是「沒有候選」：`items` 存在且是空陣列。
    func testAnEmptyItemsListIsStillNoResult() throws {
        guard case .complete(let records) = try run(["message": ["items": [Any]()]]) else { return XCTFail() }
        XCTAssertEqual(records[0].status, "no_result")
    }
}
