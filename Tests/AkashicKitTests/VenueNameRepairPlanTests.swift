import XCTest
@testable import AkashicCore

/// #575：venue 名字不變式的機械修復計畫（`VenueNameRepair.plan`）。判準見那個檔的檔頭——這裡逐條釘住：
/// 只改「只違反 canonical 形、正規化後合法、改完整筆 validate 過」的；其餘只具名；同一筆記錄還有判斷項時改寫全部延後。
final class VenueNameRepairPlanTests: XCTestCase {

    private func venue(names: [String], authorized: [String] = [], variant: [String] = [],
                       references: [ProvenanceReference] = []) -> Venue {
        var v = Venue(key: "some-journal", type: .periodical,
                      names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized,
                      references: references)
        v.variant = variant
        return v
    }
    private func errors(_ v: Venue) -> [String] { v.validate().filter { $0.severity == .error }.map(\.message) }

    func testCleanVenueHasNoPlan() {
        XCTAssertNil(VenueNameRepair.plan(venue(names: ["Psychometrika"], authorized: ["Psychometrika"])))
    }

    /// 尾隨空白在 names 與 authorized 各一筆：兩筆都改、authorized ⊆ names 仍成立、改完 validate 零 error。
    func testTrailingWhitespaceIsRewrittenAcrossListsConsistently() throws {
        let v = venue(names: ["Psychometrika "], authorized: ["Psychometrika "])
        XCTAssertFalse(errors(v).isEmpty, "fixture：原記錄要有 error")
        let p = try XCTUnwrap(VenueNameRepair.plan(v))
        XCTAssertEqual(p.rewrites.map(\.list), ["names", "authorized"])
        XCTAssertEqual(p.rewrites.map(\.after), ["Psychometrika", "Psychometrika"])
        XCTAssertEqual(try XCTUnwrap(p.rewrites.first).changes, ["尾隨空白"])
        XCTAssertTrue(p.judgments.isEmpty, "\(p.judgments)")
        let repaired = try XCTUnwrap(p.repaired)
        XCTAssertEqual(errors(repaired), [])
        XCTAssertNil(VenueNameRepair.plan(repaired), "冪等：改完再算一次是空計畫")
    }

    /// NFD 位元組改成 NFC——Swift `==` 看不出差別，所以要比位元組，改動說明要說出來。
    func testNFDIsRewrittenToNFCBytes() throws {
        let nfd = "Sankhya\u{0304}"
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: [nfd])))
        XCTAssertEqual(p.rewrites.count, 1)
        let r = try XCTUnwrap(p.rewrites.first)
        XCTAssertEqual(Array(r.after.utf8), Array("Sankhy\u{0101}".utf8))
        XCTAssertEqual(r.changes, ["未 NFC（改成預組形）"])
        XCTAssertNotNil(p.repaired)
    }

    /// NFC 的單一碼位替換（CJK 相容表意文字 U+FA10 → U+585A）是位元組層有損的——照樣是確定性改寫（canonical 形的定義），
    /// 但改動說明要逐碼位說出來：兩個字形在終端機上常常看起來一樣，過目的人要知道自己同意的是換碼位，不只是換編碼。
    func testSingletonReplacementIsDisclosed() throws {
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: ["\u{FA10}\u{5B78}\u{5831}"])))
        XCTAssertEqual(p.rewrites.count, 1)
        let r = try XCTUnwrap(p.rewrites.first)
        XCTAssertEqual(Array(r.after.unicodeScalars.map(\.value)), [0x585A, 0x5B78, 0x5831])
        XCTAssertEqual(r.changes.count, 1, "\(r.changes)")
        let change = try XCTUnwrap(r.changes.first)
        XCTAssertTrue(change.contains("U+FA10→U+585A") && change.contains("有損"), change)
        XCTAssertNotNil(p.repaired)
        // 一般的分解形 → 預組形不是換碼位，說明維持原句
        XCTAssertEqual(VenueNameRepair.singletonReplacements(in: "Sankhya\u{0304}"), [])
        XCTAssertEqual(VenueNameRepair.singletonReplacements(in: "\u{2126}\u{212B}\u{2126}"), ["U+2126→U+03A9", "U+212B→U+00C5"],
                       "重複的碼位只列一次")
    }

    /// tab、連續空白、NBSP、前導空白都說得出來。
    func testWhitespaceChangesAreDescribed() {
        XCTAssertEqual(VenueNameRepair.changes(from: "Journal\tof  X"), ["內部空白（連續、tab 或非 U+0020 的空白）收成一個 U+0020"])
        XCTAssertEqual(VenueNameRepair.changes(from: " Journal\u{00A0}X "), ["前導空白", "尾隨空白", "內部空白（連續、tab 或非 U+0020 的空白）收成一個 U+0020"])
        XCTAssertEqual(VenueNameRepair.changes(from: "Journal X"), [])
    }

    /// 正規化之後仍含不可見字元：只具名，理由說的是真正的問題（不是「不是 canonical 形」）；不改寫。
    func testStillInvalidAfterCanonicalizationIsOnlyNamed() throws {
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: ["Foo\u{200B}bar "])))
        XCTAssertTrue(p.rewrites.isEmpty)
        XCTAssertNil(p.repaired)
        XCTAssertEqual(p.judgments.count, 1, "逐字串的那一則不得被 validate 的「不是 canonical 形」重報一次：\(p.judgments)")
        let j = try XCTUnwrap(p.judgments.first)
        XCTAssertTrue(j.reason.contains("U+200B") && j.reason.contains("正規化"), j.reason)
        XCTAssertEqual(j.subject, .value(list: "names", index: 0, value: "Foo\u{200B}bar "))
    }

    func testBlankAndSymbolOnlyNamesAreOnlyNamed() throws {
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: ["Journal", "   ", "×"])))
        XCTAssertTrue(p.rewrites.isEmpty)
        XCTAssertEqual(p.judgments.map(\.subject), [.value(list: "names", index: 1, value: "   "),
                                                    .value(list: "names", index: 2, value: "×")])
    }

    /// 改完會與同清單另一筆 canonical 相同：near-duplicate 是判斷（留哪一筆），整筆延後、改寫照列。
    func testRewriteThatWouldCreateANearDuplicateIsDeferred() throws {
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: ["Psychometrika ", "Psychometrika"])))
        XCTAssertEqual(p.rewrites.count, 1, "改寫仍列出（延後）")
        XCTAssertNil(p.repaired)
        XCTAssertTrue(p.judgments.contains { $0.subject == .record && $0.reason.contains("近重複") }, "\(p.judgments)")
    }

    /// 同名的沿革段（兩段都帶不相交的時間）不是近重複——照 store 自己的定義判，改寫照套。
    func testDisjointRenamingHistoryIsNotANearDuplicate() throws {
        var v = venue(names: [])
        v.names = Timeline([TemporalValue(value: "Sankhy\u{0101} ", range: DateRange(start: "1933", end: "1960")),
                            TemporalValue(value: "Sankhy\u{0101}", range: DateRange(start: "2002", end: "2007"))])
        let p = try XCTUnwrap(VenueNameRepair.plan(v))
        XCTAssertEqual(p.rewrites.count, 1)
        let repaired = try XCTUnwrap(p.repaired, "\(p.judgments)")
        XCTAssertEqual(repaired.names.entries.map(\.range), v.names.entries.map(\.range), "時間欄位不動")
        XCTAssertEqual(errors(repaired), [])
    }

    /// 同一筆記錄一個可改、一個要判斷：可改的延後（記錄還有 error 就寫不進去），兩者都列。
    func testAJudgmentBlocksTheWholeRecord() throws {
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: ["Psychometrika ", "Tag\u{E0041}Name"])))
        XCTAssertEqual(p.rewrites.map(\.index), [0])
        XCTAssertNil(p.repaired)
        XCTAssertEqual(p.judgments.map(\.subject), [.value(list: "names", index: 1, value: "Tag\u{E0041}Name")])
    }

    /// authorized 的髒拼法讓 authorized ⊄ names：改完就一致了。
    func testAuthorizedSubsetIsRestoredByTheRewrite() throws {
        let v = venue(names: ["Psychometrika"], authorized: ["Psychometrika "])
        let p = try XCTUnwrap(VenueNameRepair.plan(v))
        XCTAssertEqual(p.rewrites.map(\.list), ["authorized"])
        XCTAssertEqual(try XCTUnwrap(p.repaired).authorized, ["Psychometrika"])
    }

    /// 只有近重複（兩筆都已是 canonical）：沒有改寫、只具名。
    func testNearDuplicateAloneIsOnlyNamed() throws {
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: ["Sankhya"], authorized: ["Sankhya", "Sankhya"])))
        XCTAssertTrue(p.rewrites.isEmpty)
        XCTAssertNil(p.repaired)
        XCTAssertTrue(p.judgments.contains { $0.subject == .record && $0.reason.contains("近重複") }, "\(p.judgments)")
    }

    /// 名字內容沒有違反、只有別的 error（孤兒 variant）：不在本命令範圍——validate 報它。
    func testOtherErrorsAloneAreOutOfScope() {
        let v = venue(names: ["Psychometrika"], variant: ["Orphan"])
        XCTAssertFalse(errors(v).isEmpty, "fixture：孤兒 variant 是 error")
        XCTAssertNil(VenueNameRepair.plan(v))
    }

    /// reference 指著舊拼法（位元組相同）：改寫會讓它對不上，要不要跟著改是判斷。
    func testAReferencePinnedToTheOldSpellingBlocksTheRewrite() throws {
        let ref = ProvenanceReference(field: "names", value: "Psychometrika ",
                                      kind: .judgement(statement: "fixture", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))
        let p = try XCTUnwrap(VenueNameRepair.plan(venue(names: ["Psychometrika "], references: [ref])))
        XCTAssertTrue(p.rewrites.isEmpty)
        XCTAssertNil(p.repaired)
        XCTAssertEqual(p.judgments.count, 1, "\(p.judgments)")
        let j = try XCTUnwrap(p.judgments.first)
        XCTAssertTrue(j.reason.contains("reference"), j.reason)
    }
}
