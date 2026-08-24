import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #394 §6：識別碼欄位進 provenance 白名單，store format 12 → 13。
///
/// ## 觸發 bump 的只有一格，而那是量測出來的
///
/// 2026-08-24 對 format-12 binary（`6a234d4`）實測同一份 fixture：
///
/// | 新形狀 | format-12 binary 的行為 |
/// | --- | --- |
/// | `organization` 帶 `field: ror` 的 reference | **整檔 quarantine** |
/// | `venue` 帶 `issn:` ＋ `field: issn` | 載入，落 tolerant-preserve |
/// | `work` 帶 `references:` ＋ `doi:` | 載入，落 tolerant-preserve |
///
/// 原因是附著驗證只有 person 與 organization 有——**venue 先前完全沒有**（本 change
/// §5 才補上），所以舊 binary 對 `field: issn` 不會擲錯。design.md 原本寫「識別碼欄位
/// 加入白名單 → 舊 binary 讀到未知 field 是整檔 quarantine」，那句話對 venue 與 work
/// 不成立；此處以實測為準。
///
/// **venue 與 work 仍併入同一個 bump**，理由沿用 format 11 對 `venues:` 的既有裁決：
/// 「保留而不解讀」對一條 ref 邊等於反向查詢靜默漏資料。provenance 更尖銳——一筆
/// 不被解讀的 reference 不會被附著驗證，於是它可以指向一個不存在的值而沒有人發現。
final class Format13GateTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-fmt13-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func setFormat(_ n: Int) throws {
        try "format: \(n)\n".write(to: root.appendingPathComponent("store.yaml"),
                                   atomically: true, encoding: .utf8)
    }

    func testSupportedFormatIsThirteen() {
        XCTAssertEqual(StoreVersion.supported, 13)
    }

    /// organization 的 ror reference 是**硬觸發**——舊 binary 對它整檔 quarantine。
    func testWritingAnRORReferenceIsRefusedBelowFormat13() throws {
        try setFormat(12)
        var org = Organization(key: "academia-sinica")
        org.ror = ROR("05bqach95")
        org.references = [ProvenanceReference(
            field: "ror", value: nil,
            kind: .judgement(statement: "查 ROR",
                             restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try LibraryStore(root: root).writeOrganization(org)) { e in
            let m = "\(e)"
            XCTAssertTrue(m.contains("13"), "訊息要說明需要 format 13：\(m)")
            XCTAssertTrue(m.contains("ror"), "訊息要具名觸發的欄位：\(m)")
        }
    }

    func testWritingAnISSNReferenceIsRefusedBelowFormat13() throws {
        try setFormat(12)
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        v.references = [ProvenanceReference(
            field: "issn", value: "0003-066X",
            kind: .judgement(statement: "查 ISSN Portal",
                             restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try LibraryStore(root: root).writeVenue(v))
    }

    func testWritingWorkReferencesIsRefusedBelowFormat13() throws {
        try setFormat(12)
        var e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle, title: "T")
        e.doi = [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29"))]
        e.references = [ProvenanceReference(
            field: "doi", value: "10.1037/0003-066X.59.1.29",
            kind: .judgement(statement: "查 Crossref",
                             restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try LibraryStore(root: root).writeEntry(e))
    }

    /// **識別碼欄位本身不設閘**——它是 additive（頂層未知鍵走 tolerant-preserve，
    /// 上表實測）。設閘會讓遷移在 bump 之前跑不動，而 design.md 的部署順序要求
    /// 遷移**跑在舊解碼器上**、format bump 是最後一步。
    func testWritingIdentifierFieldsWithoutReferencesIsAllowedAtFormat12() throws {
        try setFormat(12)
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        XCTAssertNoThrow(try LibraryStore(root: root).writeVenue(v),
                         "識別碼欄位是 additive——設閘會讓遷移跑不動（先有雞先有蛋）")
    }

    func testEverythingIsAllowedAtFormat13() throws {
        try setFormat(13)
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        v.references = [ProvenanceReference(
            field: "issn", value: "0003-066X",
            kind: .judgement(statement: "查 ISSN Portal",
                             restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertNoThrow(try LibraryStore(root: root).writeVenue(v))
    }

    // MARK: - task 6.2 的驗證目標：未升級路徑讀 format 13 要拒讀並指路

    /// 比自己新的 format **整體拒絕開啟**，而不是按舊語意誤讀。
    ///
    /// 走 `check`（開 store 前的防線）而不是 `read`——後者只解析數字、不比對上限。
    /// 這裡用 supported+1 來扮演「未升級的 binary 讀 13」——**方向相同、
    /// 可執行**。直接把舊 binary 搬進測試套件是做不到的（那需要在測試裡編譯另一個
    /// 世代的原始碼），而 `tooNew` 這條路徑不分是哪一版寫的，只比數字。
    func testAFormatNewerThanSupportedIsRefusedWithGuidance() throws {
        try setFormat(StoreVersion.supported + 1)
        XCTAssertThrowsError(try StoreVersion.check(root: root)) { e in
            let m = "\(e)"
            XCTAssertTrue(m.contains("\(StoreVersion.supported)"),
                          "訊息要說明本 binary 支援到幾版：\(m)")
            XCTAssertTrue(m.contains("\(StoreVersion.supported + 1)"),
                          "訊息要說明讀到的是幾版：\(m)")
        }
    }

    /// format 12 的既有 store 仍讀得動——bump 是能力上限，不是下限。
    func testFormatTwelveStoresStillOpen() throws {
        try setFormat(12)
        XCTAssertEqual(try StoreVersion.read(root: root), 12)
    }
}
