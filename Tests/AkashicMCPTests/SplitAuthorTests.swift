import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #450：`splitAuthors` 在改寫 `authors` 的同一次 `writeEntry` append 拆分記錄——拆分自此有 store 記錄、
/// 不再是作者位變更家族裡唯一不可逆且不可偵測的一腿。既有的 split 行為測試在 `VenueServiceTests`
/// （#443），本檔只釘本 change 新增的三件事：記錄逐字、保留字元拒、format 閘零寫入。
final class SplitAuthorTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-split-\(UUID().uuidString)")
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
    private func chen2020a(_ third: String = "某人與雷庚玲") throws {
        var e = Entry(id: UUID(), citekey: "chen2020a", type: .periodicalArticle, title: "T")
        e.authors = [.literal("甲"), .literal("乙"), .literal(third)]
        try store.writeEntry(e)
    }
    private func loaded() throws -> Entry {
        try XCTUnwrap(try store.load().entries.first { $0.citekey == "chen2020a" })
    }

    /// spec Example「Two authors glued by 與」：`authors[2]` 拆成兩位、`references` 多恰一筆、value 與 statement 逐字。
    func testSplitWritesTheRecordVerbatim() throws {
        try chen2020a()
        let out = try json(try service.splitAuthors(["chen2020a:2:與=兩位作者被匯出黏成一格"]))
        let rows = try XCTUnwrap(out["split"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["recorded"] as? Bool, true, "報告要說記錄寫了：\(rows)")

        let e = try loaded()
        XCTAssertEqual(e.authors, [.literal("甲"), .literal("乙"), .literal("某人"), .literal("雷庚玲")])
        XCTAssertEqual(e.references.count, 1, "恰一筆——不會記兩次")
        XCTAssertEqual(e.references[0].field, "authors")
        XCTAssertEqual(e.references[0].value, "某人與雷庚玲")
        guard case .judgement(let statement, let restsOn) = e.references[0].kind else { return XCTFail() }
        XCTAssertEqual(statement, "拆為 ⟦某人⟧ ⟦雷庚玲⟧：兩位作者被匯出黏成一格")
        XCTAssertTrue(restsOn.isEmpty, "一階裁決：原文逐字保存於 value 就是證據")
        XCTAssertEqual(e.splitRecords.first?.record.parts, ["某人", "雷庚玲"])
    }

    /// 段含文法保留字元 `⟦`／`⟧` → 整批拒絕、零寫入（design Risks）。
    func testPartWithReservedBracketIsRefused() throws {
        try chen2020a("甲⟧與乙")
        XCTAssertThrowsError(try service.splitAuthors(["chen2020a:2:與=理由"])) { error in
            XCTAssertTrue(String(describing: error).contains("⟦"), "\(error)")
        }
        let e = try loaded()
        XCTAssertEqual(e.authors.count, 3, "零寫入"); XCTAssertTrue(e.references.isEmpty)
    }

    /// spec「Writing a split record to a format-15 store is refused」：整個呼叫失敗、作者位與記錄都沒動、訊息指名 16。
    func testSplitOnFormat15StoreIsRefusedWithZeroWrites() throws {
        try chen2020a()
        try StoreVersion.write(root: root, format: 15)
        XCTAssertThrowsError(try service.splitAuthors(["chen2020a:2:與=理由"])) { error in
            XCTAssertTrue(String(describing: error).contains("16"), "\(error)")
        }
        let e = try loaded()
        XCTAssertEqual(e.authors.count, 3, "零寫入"); XCTAssertTrue(e.references.isEmpty)
    }

    /// 同一筆 work 拆兩個位置：兩筆記錄各自逐字，index 位移由實作處理（#443 既有）。
    func testSplittingTwoSlotsRecordsTwoReferences() throws {
        var e = Entry(id: UUID(), citekey: "chen2020a", type: .periodicalArticle, title: "T")
        e.authors = [.literal("甲與乙"), .literal("丙與丁")]
        try store.writeEntry(e)
        _ = try service.splitAuthors(["chen2020a:0:與=第一格", "chen2020a:1:與=第二格"])
        let after = try loaded()
        XCTAssertEqual(after.authors, [.literal("甲"), .literal("乙"), .literal("丙"), .literal("丁")])
        XCTAssertEqual(Set(after.references.compactMap(\.value)), ["甲與乙", "丙與丁"])
        XCTAssertEqual(Set(after.splitRecords.map(\.record.reason)), ["第一格", "第二格"])
    }
}
