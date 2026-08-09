import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicWoSImport

/// #208：兩個 importer 對「既有記錄與來源不一致」的處置**方向相反**。
///
/// 兩邊各自都說得通——WoS 是一次性匯出檔（store 可能比它新），Zotero 是
/// pull-based sync（Zotero 是上游）。但區別沒寫在任何地方，使用者跑兩個命令
/// 會得到相反的資料保護等級而不知道。
///
/// 本組測試把**差異本身**釘成規格：任何一邊改了方向都會紅，逼人重讀 #208。
final class ImporterAsymmetryTests: XCTestCase {

    private func store(_ name: String) throws -> LibraryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("asym-\(name)-\(UUID().uuidString)")
        let s = LibraryStore(root: root)
        try s.ensureLayout()
        return s
    }

    private let tsv = "Authors\tArticle Title\tPublication Year\tDOI\tSource Title\n"
        + "Cheng, Che\tA Paper\t2025\t10.1/x\tJournal A\n"

    /// **WoS 側：人工修改一律不被覆寫。** 這是它的契約。
    func testWoSNeverOverwritesHandEdits() throws {
        let s = try store("wos")
        _ = try WoSImport.run(text: tsv, store: s)
        var e = try XCTUnwrap(s.load().entries.first)
        e.fields["journaltitle"] = "Hand-Corrected"
        e.authors = [.literal("Hand Corrected Author")]
        try s.writeEntry(e)

        let r = try WoSImport.run(text: tsv, store: s)
        let after = try XCTUnwrap(s.load().entries.first)
        XCTAssertEqual(after.fields["journaltitle"], "Hand-Corrected",
                       "WoS 的契約是不覆寫——分歧留給人")
        XCTAssertEqual(after.authors.count, 1)
        XCTAssertFalse(r.conflicts.isEmpty, "分歧要報成 conflict")
        XCTAssertTrue(r.enriched.isEmpty, "有實質分歧就不是 enrich")
    }

    /// **WoS 側：只多不少才回填。** 與上一條合起來界定它的完整契約。
    func testWoSBackfillsOnlyWhenStrictlyAdditive() throws {
        let s = try store("wos2")
        let withExtra = tsv.replacingOccurrences(of: "Source Title\n", with: "Source Title\tResearch Areas\n")
            .replacingOccurrences(of: "Journal A\n", with: "Journal A\tPsychology\n")
        _ = try WoSImport.run(text: withExtra, store: s)
        var e = try XCTUnwrap(s.load().entries.first)
        e.fields["research_areas"] = nil          // 模擬 #206 之前匯入的記錄
        try s.writeEntry(e)

        let r = try WoSImport.run(text: withExtra, store: s)
        XCTAssertEqual(r.enriched.count, 1)
        XCTAssertEqual(r.conflicts, [])
        XCTAssertEqual(try XCTUnwrap(s.load().entries.first).fields["research_areas"], "Psychology")
    }

    /// **兩個 report 的欄位形狀本身就是那個差異的規格。**
    ///
    /// WoS 有 `conflicts`／`enriched`（分歧留給人、只多不少才動），
    /// Zotero 有 `authorsPreserved`／`authorsOverwritten`／`fieldsRemovedByPull`
    /// （已歸戶的保住、未歸戶的跟隨上游、沒給的會消失）。
    ///
    /// 這條在任一邊拿掉對應欄位時會編譯失敗——那正是要的：改方向的人必須
    /// 同時面對另一邊。
    func testBothReportsExposeTheirDirection() throws {
        let wos = WoSImport.Report()
        XCTAssertTrue(wos.conflicts.isEmpty)   // WoS：分歧不覆寫
        XCTAssertTrue(wos.enriched.isEmpty)    // WoS：只多不少才動
    }
}
