import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// `getEntry` 的 payload 必須看得到反向邊（#260）。
///
/// 依 `entity-backlink-completeness`：「呈現一個 entity 時，與它有關的 entity 都要
/// 看得到——不論那條關係是存在它自己身上，還是存在對方身上。」
///
/// 兩條衍生鏈（`QueryEngine.citedBy` / `.related`）**早就存在且 index-backed**，
/// 缺的只是接線——與該規則失敗史的原句同形：「衍生鏈完整，但只有 MCP 接上去」。
///
/// **真 store 驗不到**：實測 `~/.akashic` 的 937 筆記錄裡 `cites` 與 `related` 邊
/// 各為 **0**，所以驗收只能靠注入的 fixture。
final class GetEntryBacklinkTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-backlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = LibraryStore(root: root)
        try store.ensureLayout()
        service = AkashicService(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func payload(_ citekey: String) throws -> [String: Any] {
        let json = try service.getEntry(citekey: citekey)
        return (try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    /// **`citedBy` 是封閉列舉第 2 條邊（`cites`）的反向**，先前完全缺席。
    ///
    /// 被引用的那一筆自己身上**什麼都沒存**——這條邊只存在引用者身上。若不現算，
    /// 「誰引用了我」在 payload 上完全不可見。
    func testCitedByIsComputedFromTheOtherSide() throws {
        var cited = Entry(id: UUID(), citekey: "cited2020", type: .periodicalArticle, title: "Cited")
        cited.fields = ["journaltitle": "J"]
        var citing = Entry(id: UUID(), citekey: "citing2021", type: .periodicalArticle, title: "Citing")
        citing.fields = ["journaltitle": "J"]
        citing.akashic.relations.cites = ["cited2020"]
        try store.writeEntry(cited)
        try store.writeEntry(citing)

        let d = try payload("cited2020")
        XCTAssertEqual(d["citedBy"] as? [String], ["citing2021"],
                       "被引用者的 payload 必須看得到引用它的那筆——這條邊只存在對方身上")

        // 反向：引用者自己不該長出 citedBy（沒人引用它）。
        let e = try payload("citing2021")
        XCTAssertNil(e["citedBy"], "沒有人引用它時不得 emit 空的 citedBy")
    }

    /// **對稱邊的另一半**：`related` 只存在一側，兩側都該看得到。
    ///
    /// 規則明文：`related` 存在 entry 側是**約定**、非推導。所以「只顯示本側」是
    /// 實作巧合，不是語意——刪掉任一端那條邊都會消失。
    func testRelatedIsSymmetricInThePayload() throws {
        var a = Entry(id: UUID(), citekey: "alpha2020", type: .periodicalArticle, title: "A")
        a.fields = ["journaltitle": "J"]
        var b = Entry(id: UUID(), citekey: "beta2021", type: .periodicalArticle, title: "B")
        b.fields = ["journaltitle": "J"]
        // 邊**只**存在 a 身上。
        a.akashic.relations.related = ["beta2021"]
        try store.writeEntry(a)
        try store.writeEntry(b)

        let da = (try payload("alpha2020")["akashic"] as? [String: Any]) ?? [:]
        XCTAssertEqual(da["related"] as? [String], ["beta2021"], "存邊那側照常看得到")

        let db = (try payload("beta2021")["akashic"] as? [String: Any]) ?? [:]
        XCTAssertEqual(db["related"] as? [String], ["alpha2020"],
                       "**另一側也要看得到**——對稱邊只存一次，反向現算")
    }

    /// 沒有任何關係時，兩個鍵都不出現——空集合不得 emit 成空陣列。
    ///
    /// 與 `doctor` 的既有慣例一致（「無未知欄位時不 emit」）。
    func testNoRelationsEmitsNeitherKey() throws {
        var lone = Entry(id: UUID(), citekey: "lone2020", type: .periodicalArticle, title: "L")
        lone.fields = ["journaltitle": "J"]
        try store.writeEntry(lone)

        let d = try payload("lone2020")
        XCTAssertNil(d["citedBy"])
        XCTAssertNil((d["akashic"] as? [String: Any])?["related"])
    }
}
