import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #513：`unsplitAuthors` 是 `splitAuthors` 的具名逆操作。
///
/// 在此之前拆錯只能手改 YAML（三個動作要一致），而 `literal-first-then-key` 的整套論證建立在
/// 「誤可逆」上——split 這一腿在本面之前不可逆。
final class UnSplitAuthorTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-unsplit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        service = AkashicService(root: root, key: nil, environment: [:])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func seed(_ authors: [Author]) throws {
        var e = Entry(id: UUID(), citekey: "chen2020a", type: .periodicalArticle, title: "T")
        e.authors = authors
        try store.writeEntry(e)
    }
    private func loaded() throws -> Entry {
        try XCTUnwrap(try store.load().entries.first { $0.citekey == "chen2020a" })
    }
    private func splitOnce() throws {
        try seed([.literal("甲"), .literal("乙"), .literal("某人與雷庚玲")])
        _ = try service.splitAuthors(["chen2020a:2:與=兩位作者被匯出黏成一格"])
    }

    /// **往返**：split → un-split 之後 `authors` 與 `references` 都回到原狀。
    /// 這是本面存在的全部理由——少了它，「誤可逆」在 split 這一腿是空頭承諾。
    func testRoundTripRestoresAuthorsAndRemovesTheRecord() throws {
        try splitOnce()
        XCTAssertEqual(try loaded().authors.count, 4, "前提：拆完是 4 個作者位")
        XCTAssertEqual(try loaded().splitRecords.count, 1)

        let out = try json(try service.unsplitAuthors(["chen2020a:某人與雷庚玲"]))
        XCTAssertEqual(out["count"] as? Int, 1)
        let e = try loaded()
        XCTAssertEqual(e.authors, [.literal("甲"), .literal("乙"), .literal("某人與雷庚玲")],
                       "作者位逐字回到拆分前")
        XCTAssertEqual(e.splitRecords.count, 0,
                       "記錄要刪掉——留著會讓 store 斷言「拆為 ⟦…⟧」這件已經為假的事")
        XCTAssertFalse(e.references.contains { $0.field == "authors" })
    }

    /// **被刪掉的理由要說出來**——丟棄必須可見（`lossless-intake` 執行細節 3）。
    func testTheDroppedReasonIsReported() throws {
        try splitOnce()
        let out = try json(try service.unsplitAuthors(["chen2020a:某人與雷庚玲"]))
        let rows = try XCTUnwrap(out["unsplit"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["droppedReason"] as? String, "兩位作者被匯出黏成一格")
        XCTAssertEqual(rows[0]["restored"] as? String, "某人與雷庚玲")
        XCTAssertEqual(rows[0]["from"] as? [String], ["某人", "雷庚玲"])
        XCTAssertEqual(rows[0]["recordRemoved"] as? Bool, true)
    }

    /// **已升格的段要拒絕，且訊息指向 demote 而不是「找不到」。**
    /// un-split 會把一個已歸戶的身分塞回一個黏著的字串——那是判定的逆轉，不屬本面。
    func testPromotedPartIsRefusedAndPointsAtDemote() throws {
        try splitOnce()
        var e = try loaded()
        e.authors[2] = .key("someone")          // 「某人」升格
        try store.writeEntry(e)
        XCTAssertThrowsError(try service.unsplitAuthors(["chen2020a:某人與雷庚玲"])) { err in
            let m = "\(err)"
            XCTAssertTrue(m.contains("demote"), m)
        }
        XCTAssertEqual(try loaded().splitRecords.count, 1, "拒絕必須零寫入")
    }

    /// **各段不連續 → 拒絕**，並指向 `validate` 報同一件事的那條 warning。
    func testNonContiguousPartsAreRefused() throws {
        try splitOnce()
        var e = try loaded()
        e.authors = [.literal("某人"), .literal("甲"), .literal("雷庚玲")]   // 中間插了別人
        try store.writeEntry(e)
        XCTAssertThrowsError(try service.unsplitAuthors(["chen2020a:某人與雷庚玲"])) { err in
            XCTAssertTrue("\(err)".contains("連續同序"), "\(err)")
        }
    }

    /// **同 value 多筆記錄 → 拒絕不判定**（裁決 ①，形狀取自 enrich 的 DOI ambiguity）。
    func testDuplicateRecordsForOneLiteralAreRefused() throws {
        try splitOnce()
        var e = try loaded()
        // 手工造出第二筆同 value 的記錄（parts 不同）——store 裡沒有東西說得出哪幾個
        // 作者位屬於哪一筆。
        let second = try XCTUnwrap(SplitRecordValue(parts: ["某", "人與雷庚玲"], reason: "另一種切法"))
        e.references.append(ProvenanceReference(field: "authors", value: "某人與雷庚玲",
                                                kind: .judgement(statement: second.encoded, restsOn: [])))
        try store.writeEntry(e)
        XCTAssertThrowsError(try service.unsplitAuthors(["chen2020a:某人與雷庚玲"])) { err in
            XCTAssertTrue("\(err)".contains("拒絕不判定"), "\(err)")
        }
        XCTAssertEqual(try loaded().splitRecords.count, 2, "拒絕必須零寫入")
    }

    /// **整批拒絕零寫入**：一批裡有一筆不合法，另一筆合法的也不得寫。
    func testABadSpecInTheBatchWritesNothing() throws {
        try splitOnce()
        XCTAssertThrowsError(try service.unsplitAuthors(
            ["chen2020a:某人與雷庚玲", "chen2020a:不存在的literal"]))
        XCTAssertEqual(try loaded().authors.count, 4, "整批拒絕——合法的那筆也不得寫")
        XCTAssertEqual(try loaded().splitRecords.count, 1)
    }

    /// **孤兒 verdict 掃描自然回綠**（#513 Expected 4）：拆分後掛在退役 literal 上的 verdict
    /// 在 un-split 之後重新有效，不需要另外處理。
    func testOrphanedSplitVerdictScanGoesGreenAfterUnsplit() throws {
        try splitOnce()
        var p = Person(key: "lei-genglin", names: ["雷庚玲"])
        p.references = [ProvenanceReference(
            field: "resolution-rejected",
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: "chen2020a", literal: "某人與雷庚玲").encoded,
            kind: .judgement(statement: "不是同一個人", restsOn: []))]
        try store.writePerson(p)
        let before = store.health(from: try store.load()).orphanedSplitVerdicts.count
        XCTAssertGreaterThan(before, 0, "前提：拆分後那條 verdict 的錨失效")

        _ = try service.unsplitAuthors(["chen2020a:某人與雷庚玲"])
        XCTAssertEqual(store.health(from: try store.load()).orphanedSplitVerdicts.count, 0,
                       "錨重新有效——掃描自然回綠，不需要另外處理")
    }
}
