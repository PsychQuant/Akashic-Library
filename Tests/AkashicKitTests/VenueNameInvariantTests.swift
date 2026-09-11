import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// venue 名字內容的不變式住在 **store 邊界**（#554 R4 verify，使用者裁決 D8）。
///
/// R2→R4 三輪把名字內容的閘（空白／控制字元／不是名字／存 canonical）裝在 `updateVenue` 的
/// 三個迴圈裡，R4 verify 指出同一個 `names` 欄位還有兩個寫入者沒經過它——`addVenue` 原樣
/// 存入（連空字串都收）、`VenueBootstrap` 只 trim。`Venue.swift` 自己的 doc 早就寫著答案：
/// 「守衛住在 validate → writeVenue 的交會處才擋得住所有路徑」。所以：
///
/// - `NameIdentity.wellFormednessIssue` 是**一份**謂詞，與輸出閘 `UnsafeToEmitScalar` 共用
///   危險 scalar 的定義（R4 的 `forbiddenScalar` 是 19 個例子的列舉、170 個 Cf 漏 149，且與
///   `UnsafeToEmitScalar` 分岔——ALM 輸入放行、輸出逃脫）
/// - `Venue.validate()` 對 names／authorized／variant 逐條驗（error 級）、names 內無 canonical-相等對
/// - 所有寫入者存 `NameIdentity.canonical`
///
/// live store 2026-09-12 實測 485 筆 venue：無字母 0、含 Cf／Cc 0、非 canonical 拼法 0、
/// NBSP／U+3000 0——提級不拒絕任何既有記錄。
final class VenueNameInvariantTests: XCTestCase {

    private func venue(names: [String], authorized: [String] = [], variant: [String] = []) -> Venue {
        var v = Venue(key: "j", type: .periodical,
                      names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.variant = variant
        return v
    }
    private func errors(_ v: Venue) -> [String] {
        v.validate().filter { $0.severity == .error }.map(\.message)
    }

    // MARK: - 謂詞本身

    func testCanonicalWellFormedNamesPass() {
        for ok in ["Psychometrika", "1843", "2600", "心理計量學", "Zeitschrift für Psychologie",
                   "Психометрика", "サイコメトリカ", "نشریه\u{200C}روان\u{200D}سنجی", "J. B."] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok)
        }
    }

    /// 純數字刊名是真的（*1843*、*2600*）——判準是「至少一個字母**或數字**」，`×`／`—`／`…` 仍擋。
    func testSymbolOnlyIsNotANameButDigitsAre() {
        XCTAssertNil(NameIdentity.wellFormednessIssue("1843"))
        for bad in ["×", "÷", "—", "…", "× ÷"] { XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad) }
    }

    /// 非 canonical 形（前後／連續空白、tab、NFD）不是合法的儲存形——寫入者要先 canonical。
    func testNonCanonicalSpellingIsRejected() {
        for bad in ["Psychometrika ", " Psychometrika", "Journal  of  X", "New\tJournal",
                    "Psychome\u{301}trika", "心理　計量"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        XCTAssertNil(NameIdentity.wellFormednessIssue(NameIdentity.canonical("Journal  of  X")))
    }

    /// 危險 scalar 是**性質**不是列舉（R4 verify 第 2 列：TAG 字元、ALM 漏過），且與 `UnsafeToEmitScalar` 同一份。
    func testFormatAndControlScalarsAreRejectedAsAClass() {
        let cases: [(String, String)] = [
            ("Psychometrika\u{202E}", "RLO"), ("Psycho\u{200B}metrika", "ZWSP"), ("Psycho\u{00AD}metrika", "SHY"),
            ("Psycho\u{061C}metrika", "ARABIC LETTER MARK"), ("Tag\u{E0041}\u{E007F}Name", "TAG"),
            ("Iss\u{206A}Name", "U+206A"), ("Iaa\u{FFF9}Name", "U+FFF9"), ("Mvs\u{180E}Name", "U+180E"),
            ("Bom\u{FEFF}Name", "BOM"), ("Line\u{2028}Name", "LS"),
        ]
        for (s, label) in cases { XCTAssertNotNil(NameIdentity.wellFormednessIssue(s), label) }
        // 與輸出閘同一份定義：UnsafeToEmitScalar 收的，這裡也收
        for v: UInt32 in [0x202E, 0x2066, 0x200E, 0x061C, 0xFEFF, 0x2028] {
            XCTAssertTrue(UnsafeToEmitScalar.contains(v))
            XCTAssertNotNil(NameIdentity.wellFormednessIssue("A" + String(Unicode.Scalar(v)!) + "B"), String(v, radix: 16))
        }
    }

    /// 接合字元只在兩個字母（或標記）之間合法（R4 verify 第 9 列：尾隨 ZWJ、拉丁字母間的 ZWNJ 重開
    /// 「看起來一樣、canonical 不相等」的通道）。波斯文／印度系文字的合法用法保留。
    func testJoinersOnlyBetweenLetters() {
        XCTAssertNil(NameIdentity.wellFormednessIssue("نشریه\u{200C}روان"), "ZWNJ between Arabic letters")
        XCTAssertNil(NameIdentity.wellFormednessIssue("क्\u{200D}ष"), "ZWJ after virama (Devanagari)")
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("Zwj\u{200D}"), "trailing")
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("\u{200C}Zwnj"), "leading")
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("Zw \u{200D}j"), "next to space")
    }

    // MARK: - validate 是所有路徑的交會處

    func testValidateRejectsMalformedNamesInAllThreeLists() {
        XCTAssertFalse(errors(venue(names: ["Psychometrika "])).isEmpty, "names 非 canonical")
        XCTAssertFalse(errors(venue(names: ["Psycho\u{200B}metrika"])).isEmpty, "names 零寬")
        XCTAssertFalse(errors(venue(names: ["×"])).isEmpty, "names 不是名字")
        XCTAssertFalse(errors(venue(names: [""])).isEmpty, "空名")
        XCTAssertFalse(errors(venue(names: ["Psychometrika", "Psychometrika "], authorized: ["Psychometrika "])).isEmpty,
                       "authorized 非 canonical（且 names 有近重複對）")
        XCTAssertTrue(errors(venue(names: ["Psychometrika", "1843"], authorized: ["Psychometrika"], variant: ["1843"])).isEmpty)
    }

    /// names 內不得有兩筆 canonical-相等的條目（venue 沒有 `validateNearDuplicates`——person 有）。
    func testValidateRejectsCanonicalEqualPairInNames() {
        let msgs = errors(venue(names: ["Psychometrika", "Psychometrika"]))
        XCTAssertFalse(msgs.isEmpty, "完全重複也是近重複對")
        XCTAssertTrue(msgs.contains { $0.contains("近重複") }, "\(msgs)")
    }

    // MARK: - 第五個寫入者：bootstrap 存 canonical

    func testBootstrapStoresCanonicalNames() {
        var e = Entry(id: UUID(), citekey: "a", type: .periodicalArticle, title: "T",
                      authors: [.literal("A, A.")], date: "2020")
        e.fields = ["journaltitle": "  Journal  of  X "]
        let r = VenueBootstrap.result(entries: [e], existing: [])
        let venues = VenueBootstrap.makeVenues(r.candidates)
        XCTAssertEqual(venues.first?.names.entries.map(\.value), ["Journal of X"])
        XCTAssertEqual(venues.first?.authorized, ["Journal of X"])
        XCTAssertTrue(venues.allSatisfy { errors($0).isEmpty })
    }
}
