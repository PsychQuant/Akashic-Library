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

    /// **對映表在具名值上成立**，且三個舊值合流到 conference-session。
    func testMappingCoversNamedLegacyValues() {
        XCTAssertEqual(WorkTypeMigration.mapping["article"], "journal-article")
        XCTAssertEqual(WorkTypeMigration.mapping["incollection"], "book-chapter")
        XCTAssertEqual(WorkTypeMigration.mapping["online"], "webpage")
        // APA7 10.5 不分 presentation 與 inproceedings——舊值域把同一類拆成三個名字
        XCTAssertEqual(WorkTypeMigration.mapping["presentation"], "conference-session")
        XCTAssertEqual(WorkTypeMigration.mapping["inproceedings"], "conference-session")
    }

    /// **條件對映**：`misc` 只在帶 url 時→wikipedia-entry；`unpublished` 只在帶
    /// location 時→conference-session。**判準不成立就不猜**。
    func testConditionalMappingRequiresEvidence() throws {
        _ = try seed("m2018wiki", type: "misc", fields: ["url": "https://example.org"])
        _ = try seed("m2018bare", type: "misc")                       // 無 url → 不猜
        _ = try seed("u2020conf", type: "unpublished", fields: ["location": "Taipei"])
        _ = try seed("u2020bare", type: "unpublished")                // 無 location → 不猜

        let r = try WorkTypeMigration.run(store: store, apply: false)
        let plannedTo = Dictionary(uniqueKeysWithValues: r.planned.map { ($0.citekey, $0.to) })
        XCTAssertEqual(plannedTo["m2018wiki"], "wikipedia-entry")
        XCTAssertEqual(plannedTo["u2020conf"], "conference-session")
        XCTAssertEqual(r.unmapped.map(\.citekey).sorted(), ["m2018bare", "u2020bare"],
                       "判準不成立者必須進 unmapped 點名交人，不得猜")
    }

    /// **idempotent**：已是新值域的不再列入 planned。
    func testAlreadyMigratedIsSkipped() throws {
        _ = try seed("j2020ok", type: "journal-article")
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
