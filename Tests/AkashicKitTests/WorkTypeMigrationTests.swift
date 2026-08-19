import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// `migrate-work-types`（#325 階段一）的契約測試。
///
/// 四條契約各一個測試——它們是 `VenueMigration` 家族的共同紀律，不是本次發明的：
/// dry-run 零寫入／只改一個鍵／idempotent／per-file trackedness。
final class WorkTypeMigrationTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wtm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func seed(_ citekey: String, type: String,
                      fields: [String: String] = [:]) throws -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: type, title: "T",
                      authors: [.literal("Someone")], date: "2020")
        e.fields = fields
        _ = try store.writeEntry(e)
        return e
    }

    /// **dry-run 零寫入**：不帶 apply 時檔案位元組不得改變。
    func testDryRunWritesNothing() throws {
        let e = try seed("a2020x", type: "article")
        let url = store.entityURL(id: e.id)
        let before = try Data(contentsOf: url)

        let report = try WorkTypeMigration.run(store: store, apply: false)
        XCTAssertEqual(report.planned.count, 1)
        XCTAssertEqual(report.applied, 0)
        XCTAssertEqual(try Data(contentsOf: url), before, "dry-run 不得改動任何位元組")
    }

    /// **對映在具名值上成立**，且兩個舊值合流到 conference-session。
    ///
    /// 斷言走 `run()` 而不是直接讀一張表——**表已經不在這裡了**（見
    /// `WorkTypeMigration` 頂部的說明：遷移表與讀 `.bib` 的逆向表是同一張，
    /// 住在 `WorkType.init?(biblatexEntryType:fields:)`）。測行為而非測表，
    /// 順帶把「遷移真的接上那個 initializer」也釘住。
    func testMappingCoversNamedLegacyValues() throws {
        _ = try seed("a2020", type: "article")
        _ = try seed("i2020", type: "incollection")
        _ = try seed("o2020", type: "online")
        // APA7 10.5 不分 presentation 與 inproceedings——舊值域把同一類拆成兩個名字
        _ = try seed("p2020", type: "presentation")
        _ = try seed("c2020", type: "inproceedings")

        let r = try WorkTypeMigration.run(store: store, apply: false)
        let to = Dictionary(uniqueKeysWithValues: r.planned.map { ($0.citekey, $0.to) })
        XCTAssertEqual(to["a2020"], "periodical-article")
        XCTAssertEqual(to["i2020"], "book-chapter")
        XCTAssertEqual(to["o2020"], "webpage")
        XCTAssertEqual(to["p2020"], "conference-session")
        XCTAssertEqual(to["c2020"], "conference-session")
        XCTAssertTrue(r.unmapped.isEmpty, "具名舊值不得落到 unmapped：\(r.unmapped)")
    }

    /// **條件對映**：額外訊號把值升級到更細的類別；沒有訊號時的行為**兩個舊值不同**。
    ///
    /// ## 為什麼 `misc` 與 `unpublished` 的裸值處置不對稱
    ///
    /// 這個不對稱是**判定**，不是疏漏——寫出來免得下一個人「順手統一」掉：
    ///
    /// - **`misc` 無 `url` → unmapped（不猜）**。`misc` 在 biblatex 裡本來就是
    ///   「其他」，不攜帶任何書目意義，沒有哪個 ch10 節是它的直譯。
    /// - **`unpublished` 無 `location` → `unpublished-work`（不是猜）**。APA7 10.8
    ///   的節名字面就是 "Unpublished and Informally Published Works"，裸
    ///   `unpublished` 對到它是**直譯**；`location` 訊號是把它*升級*到 10.5 的東西。
    ///
    /// 判準：**這個舊值有沒有一個字面對應的 ch10 節？** 有就是直譯（不是猜），
    /// 沒有才需要額外訊號。
    ///
    /// ## 這裡有一個具名的語意改變
    ///
    /// 第一版把裸 `unpublished` 也判為 unmapped。折表時（遷移表與 `.bib` 逆向表
    /// 合一）發現兩邊對它的處置不同，依上面的判準裁定為直譯。**實務影響為零**：
    /// 實測 21 筆 `unpublished` 全部帶 `fields.location`，裸值在真 store 不存在。
    /// 記在這裡是因為零影響的語意改變最容易被當成沒發生過。
    func testConditionalMappingRequiresEvidence() throws {
        _ = try seed("m2018wiki", type: "misc", fields: ["url": "https://example.org"])
        _ = try seed("m2018bare", type: "misc")                       // 無 url → 不猜
        _ = try seed("u2020conf", type: "unpublished", fields: ["location": "Taipei"])
        _ = try seed("u2020bare", type: "unpublished")                // 無 location → 直譯

        let r = try WorkTypeMigration.run(store: store, apply: false)
        let plannedTo = Dictionary(uniqueKeysWithValues: r.planned.map { ($0.citekey, $0.to) })
        XCTAssertEqual(plannedTo["m2018wiki"], "wikipedia-entry")
        XCTAssertEqual(plannedTo["u2020conf"], "conference-session", "location 訊號升級到 10.5")
        XCTAssertEqual(plannedTo["u2020bare"], "unpublished-work", "10.8 的直譯")
        XCTAssertEqual(r.unmapped.map(\.citekey).sorted(), ["m2018bare"],
                       "沒有字面對應節的舊值必須進 unmapped 點名交人，不得猜")
    }

    /// **idempotent**：已是新值域的不再列入 planned。
    func testAlreadyMigratedIsSkipped() throws {
        _ = try seed("j2020ok", type: "periodical-article")
        _ = try seed("w2020ok", type: "wikipedia-entry", fields: ["url": "https://x"])
        let r = try WorkTypeMigration.run(store: store, apply: false)
        XCTAssertTrue(r.planned.isEmpty, "新值域的 entry 不該再被遷移：\(r.planned)")
        XCTAssertEqual(r.alreadyMigrated.sorted(), ["j2020ok", "w2020ok"])
    }

    /// **per-file trackedness**：非 git repo 下 apply 必須擲錯，而不是硬寫。
    ///
    /// 這條防的是最貴的失敗：未追蹤的檔改壞了**沒有回復路徑**。
    func testApplyRefusesWhenTrackednessUnknown() throws {
        _ = try seed("a2020y", type: "article")
        XCTAssertThrowsError(try WorkTypeMigration.run(store: store, apply: true)) { err in
            XCTAssertTrue(String(describing: err).contains("無回復路徑"),
                          "非 git repo 下必須因無從確認追蹤狀態而拒絕，實得：\(err)")
        }
    }
}
