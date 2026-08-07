import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #70 第一題：「某時點成立、起訖皆不明」（attested-at）——#63 `ended` 的鏡像。
///
/// 把發表年填 `start` 是「從那年起」的偽造斷言；真實的知識狀態是「這幾個時點
/// 觀測到成立」。形狀（使用者拍板 2026-08-07）：**多觀測點列表** `attested:
/// ["2003", "2011"]`——同人同機構 5 篇論文＝5 個觀測點，each 日後可掛 #66 的
/// reference 逐點溯源。
///
/// 段內新鍵是 strict → **non-additive → format 7**（#131 判準與 gate 機制照抄）。
final class AttestedRangeTests: XCTestCase {

    // MARK: - 語意

    func testAttestedOnlyRangeIsNotOpen() {
        let r = DateRange(attested: ["2003", "2011"])
        XCTAssertFalse(r.isOpen, "有觀測不等於進行中——current／status 不得採計")
    }

    func testAttestedDoesNotAffectCurrent() {
        let open = TemporalValue(value: "研究員", range: DateRange(start: "2020"))
        let att = TemporalValue(value: "助研究員", range: DateRange(attested: ["2003"]))
        let t = TimelineOf([att, open])
        XCTAssertEqual(t.current?.value, "研究員", "attested-only 段不是現況")
    }

    /// 矛盾防線（同 ended 的 encoder 防線）：attested 與 start/end/endedUnknown
    /// 並存拒收——起點若已知就不是「起訖皆不明」。
    func testAttestedContradictionsRejectedAtEncode() {
        for bad in [DateRange(start: "2003", attested: ["2005"]),
                    DateRange(end: "2010", attested: ["2005"]),
                    DateRange(endedUnknown: true, attested: ["2005"])] {
            var p = Person(key: "x")
            p.profile.ranks = Timeline([TemporalValue(value: "v", range: bad)])
            XCTAssertThrowsError(try PersonYAML.encode(p),
                                 "矛盾組合必須被 encoder 擋：\(bad)")
        }
    }

    // MARK: - 全序（#143 的教訓：== 的欄位 < 都要比）

    func testTotalOrderCoversAttested() {
        let a = DateRange(attested: ["2003"])
        let b = DateRange(attested: ["2011"])
        let c = DateRange()
        for (x, y) in [(a, b), (a, c), (b, c)] {
            XCTAssertTrue(x < y || y < x || x == y,
                          "incomparable ⟹ equal 必須維持：\(x) vs \(y)")
        }
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a < b, "觀測點字典序")
    }

    // MARK: - YAML round-trip + format gate

    func testAttestedRoundTrip() throws {
        var p = Person(key: "chiou-j-m")
        p.names = ["Chiou, J-M."]
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("中研院統計所"),
                          range: DateRange(attested: ["2003", "2011"]),
                          source: "https://example.org/paper1")])
        let text = try PersonYAML.encode(p)
        XCTAssertTrue(text.contains("attested"), text)
        let back = try PersonYAML.decode(text)
        XCTAssertEqual(back.profile.affiliations.entries.first?.range.attested,
                       ["2003", "2011"])
        XCTAssertEqual(try PersonYAML.encode(back), text, "位元組冪等")
    }

    func testWriteGateRefusesAttestedBelowFormat7() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-att-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: dir, format: 6)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(root: dir)
        var p = Person(key: "x")
        p.profile.ranks = Timeline([
            TemporalValue(value: "v", range: DateRange(attested: ["2003"]))])
        XCTAssertThrowsError(try store.writePerson(p),
                             "format 6 store 寫 attested＝替舊 binary 埋 quarantine 地雷") { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("7") && msg.contains("format"), msg)
        }
        try StoreVersion.write(root: dir, format: 7)
        XCTAssertNoThrow(try store.writePerson(p), "format 7 放行")
    }

    /// 目前的精確 format 值（#131 verify 慣例：釘精確值防「意外多 bump 一次」，
    /// 每次刻意 bump 隨新 format 的測試搬家——本次從 EndedUnknownTests 搬來，#70）。
    func testCurrentSupportedFormatIsExactlySeven() {
        XCTAssertEqual(StoreVersion.supported, 7)
    }

    /// 無 attested 的既有記錄零 diff（向後相容——canary 面自動涵蓋，這裡顯式釘）。
    func testRecordsWithoutAttestedUnchanged() throws {
        var p = Person(key: "plain")
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2003"))])
        let text = try PersonYAML.encode(p)
        XCTAssertFalse(text.contains("attested"), "無 attested 不寫出該鍵：\(text)")
    }
}
