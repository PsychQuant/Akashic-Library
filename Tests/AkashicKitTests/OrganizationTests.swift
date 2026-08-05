import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicExport

/// 機構作為第三種記錄形狀，以及隸屬的指涉化。
final class OrganizationTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-org-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func sinica() -> Organization {
        Organization(key: "academia-sinica",
                     names: TimelineOf([TemporalValue(value: "中央研究院")]),
                     founded: "1928")
    }

    // MARK: - 形狀

    /// 機構寫出、載入、再編碼逐位元穩定，且由**標籤**判別而非欄位組成。
    func testOrganizationRoundTrips() throws {
        let o = sinica()
        try store.writeOrganization(o)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.organizations.count, 1)
        XCTAssertEqual(load.entries.count, 0, "機構不得被算成著作")
        let back = try XCTUnwrap(load.organizations.first)
        XCTAssertEqual(back, o)
        let text = try OrganizationYAML.encode(back)
        XCTAssertTrue(text.hasPrefix("organization:\n"), "應以裸標籤開頭：\n\(text)")
        XCTAssertEqual(text, try OrganizationYAML.encode(try OrganizationYAML.decode(text)))
    }

    /// **`key` 與 person 同名是刻意的**：判別由標籤負責，identity 欄位不必兼差當形狀名。
    /// 這是改用標籤之後才可行的——欄位組成判別時它會造成歧義。
    func testOrganizationAndPersonMayShareIdentityFieldName() throws {
        try store.writeOrganization(Organization(key: "iss"))
        _ = try store.writePerson(Person(key: "iss"))
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.organizations.count, 1)
        XCTAssertEqual(load.people.count, 1)
        // 同一個 key 在兩個形狀下必須推出不同 UUID，否則兩筆會撞成同一個檔。
        XCTAssertNotEqual(DeterministicUUID.forOrganization(key: "iss"),
                          DeterministicUUID.forPerson(key: "iss"))
    }

    /// 機構改名後，既有的人指向它的參照**不需重寫**——參照走 identity 而非名稱。
    func testRenamingOrganizationDoesNotBreakReferences() throws {
        var o = sinica()
        try store.writeOrganization(o)
        var p = Person(key: "chen-che")
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .key("academia-sinica"), range: DateRange(start: "2010"))])
        _ = try store.writePerson(p)

        // 改名：加一段新名稱，舊名稱給結束時間。key 不變。
        o.names = TimelineOf([
            TemporalValue(value: "中央研究院", range: DateRange(start: "1928", end: "2030")),
            TemporalValue(value: "中研院", range: DateRange(start: "2030"))])
        try store.writeOrganization(o)

        let load = try store.load()
        let person = try XCTUnwrap(load.people.first)
        // 參照的字面內容完全沒動
        XCTAssertEqual(person.profile.affiliations.sorted.first?.value, .key("academia-sinica"))
        XCTAssertEqual(load.organizations.first?.displayName, "中研院")
    }

    // MARK: - 隸屬是指涉或字面

    /// 未歸戶的隸屬以字面值載入，**沒有任何旗標欄位**宣告它未歸戶。
    func testUnresolvedAffiliationIsLiteralWithoutFlag() throws {
        var p = Person(key: "chen-che")
        p.profile.affiliations = TimelineOf([TemporalValue(value: .literal("中央研究院"))])
        _ = try store.writePerson(p)
        let text = try String(contentsOf: store.entityURL(id: p.id), encoding: .utf8)
        XCTAssertTrue(text.contains("literal: 中央研究院"), text)
        XCTAssertFalse(text.lowercased().contains("resolved"), "不得出現歸戶旗標：\n\(text)")
        let back = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(back.profile.affiliations.sorted.first?.value, .literal("中央研究院"))
    }

    /// `key` 與 `literal` 並存 → 拒絕。兩者可以互相矛盾，一個 sum type 不會。
    func testAffiliationRejectsBothKeyAndLiteral() throws {
        let id = UUID()
        let yaml = """
            person:
            id: \(id.uuidString)
            key: x
            profile:
              affiliations:
              - value:
                  key: a
                  literal: b
            """
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
    }

    /// 遷移偏向過度切分：兩個相近但不相同的字串維持兩筆，不自動合併。
    /// 過度切分可回復（之後合併即可），過度合併不可回復。
    func testResolutionIsBiasedTowardSplitting() throws {
        var p = Person(key: "chen-che")
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("中央研究院"), range: DateRange(start: "2010", end: "2015")),
            TemporalValue(value: .literal("中研院"), range: DateRange(start: "2015"))])
        _ = try store.writePerson(p)
        let back = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(back.profile.affiliations.entries.count, 2, "相近字串不得被自動合併")
    }

    /// 其餘四個維度不受影響：純字串、開放值域、相等性與儲存順序無關。
    func testOtherTemporalDimensionsUnaffected() throws {
        var p = Person(key: "chen-che")
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2015")),
            TemporalValue(value: "副研究員", range: DateRange(start: "2010", end: "2015"))])
        p.profile.administrative = Timeline([TemporalValue(value: "所長")])
        p.profile.appointments = Timeline([TemporalValue(value: "兼任")])
        p.profile.fields = Timeline([TemporalValue(value: "統計")])
        _ = try store.writePerson(p)
        let back = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(back.profile.ranks, p.profile.ranks)
        // 順序無關的相等性（encode canary 曾靠它抓出問題）
        let reversed = Timeline(p.profile.ranks.entries.reversed())
        XCTAssertEqual(reversed, p.profile.ranks)
        let once = try PersonYAML.encode(back)
        XCTAssertEqual(once, try PersonYAML.encode(try PersonYAML.decode(once)))
    }

    // MARK: - 兩個 predicate 分離

    /// work 形狀上**沒有**任何機構欄位——論文的機構隸屬無處可放，由形狀本身擋下。
    /// 這是 §7 predicate 定義域規則的迴歸防線。
    func testWorkShapeHasNoOrganizationField() throws {
        let id = UUID()
        let yaml = """
            work:
            id: \(id.uuidString)
            citekey: x2020
            type: article
            title: T
            affiliations:
            - value:
                key: academia-sinica
            """
        // affiliations 不是 work 的已知欄位——它會被 tolerant-preserve 當未知欄位保留，
        // 但**不會**成為一個可查詢的隸屬。模型上沒有那個欄位可放。
        let e = try EntryYAML.decode(yaml)
        XCTAssertFalse(e.unknownFields.isEmpty, "應被當成未知欄位而非隸屬")
        XCTAssertEqual(Mirror(reflecting: e).children.compactMap { $0.label }
            .filter { $0.lowercased().contains("affiliation") }.count, 0,
            "Entry 不得有任何機構欄位")
    }

    /// 機構的上級關係記在機構自己身上，與人的隸屬是不同欄位、不同形狀。
    func testContainmentLivesOnTheOrganization() throws {
        var iss = Organization(key: "iss", names: TimelineOf([TemporalValue(value: "統計所")]))
        iss.parents = TimelineOf([TemporalValue(value: .key("academia-sinica"))])
        try store.writeOrganization(iss)
        try store.writeOrganization(sinica())
        let load = try store.load()
        let back = try XCTUnwrap(load.organizations.first { $0.key == "iss" })
        XCTAssertEqual(back.parents.current?.value, .key("academia-sinica"))
    }

    // MARK: - 匯出

    /// 端到端：歸戶的隸屬有外鍵、字面值的為 NULL、懸空參照也是 NULL（不造 id）。
    func testExportForeignKeys() throws {
        let org = sinica()
        var resolved = Person(key: "a-resolved")
        resolved.profile.affiliations = TimelineOf([TemporalValue(value: .key("academia-sinica"))])
        var literal = Person(key: "b-literal")
        literal.profile.affiliations = TimelineOf([TemporalValue(value: .literal("某大學"))])
        var dangling = Person(key: "c-dangling")
        dangling.profile.affiliations = TimelineOf([TemporalValue(value: .key("no-such-org"))])

        let t = RelationalExport.tables(entries: [], people: [resolved, literal, dangling],
                                        organizations: [org])
        XCTAssertEqual(t.organization.rows.count, 1)
        let fkIdx = try XCTUnwrap(t.researcherTimeline.columns.firstIndex(of: "organization_id"))
        let byPerson = Dictionary(uniqueKeysWithValues:
            t.researcherTimeline.rows.map { ($0[0]!, $0[fkIdx]) })
        XCTAssertEqual(byPerson[resolved.id.uuidString], org.id.uuidString, "已歸戶應有外鍵")
        XCTAssertNil(byPerson[literal.id.uuidString] ?? nil, "字面值的外鍵應為 NULL")
        XCTAssertNil(byPerson[dangling.id.uuidString] ?? nil, "懸空參照不得憑空造 id")
    }

    /// 匯出腳本含機構表，且隸屬列的外鍵可空。
    func testDuckDBScriptDeclaresOrganization() {
        let sql = RelationalExport.duckDBScript()
        XCTAssertTrue(sql.contains("CREATE TABLE organization"))
        XCTAssertTrue(sql.contains("organization_id UUID REFERENCES organization(organization_id)"))
    }

    /// #92：`organization` 的自我參照外鍵（`parent_id`）**不得在建立列的同一個
    /// statement 內填入**。
    ///
    /// DuckDB 對 FK 的檢查是針對「statement 開始前的表狀態」——同一個 bulk INSERT
    /// 裡，後面的列看不到前面的列。CSV 把母機構排在前面也不救。最小重現：
    ///
    /// ```sql
    /// CREATE TABLE o(id INTEGER PRIMARY KEY, p INTEGER REFERENCES o(id));
    /// INSERT INTO o SELECT * FROM (VALUES (1,NULL),(2,1)) t(a,b);  -- ✗ Constraint Error
    /// ```
    ///
    /// 所以載入必須兩步：先插骨架、再回填 `parent_id`。這保留 FK 約束，而不是靠
    /// 拿掉約束來繞過（拿掉之後下游就再也擋不住懸空 parent）。
    ///
    /// 斷言寫成「**不是** `INSERT INTO organization` 後面直接 `SELECT *`」＋「必須
    /// 有回填 parent_id 的 UPDATE」，而非釘住某段 SQL 字面——前者描述的是那個會讓
    /// 腳本跑不起來的性質本身。
    func testOrganizationLoadsInTwoStepsForSelfReferencingFK() {
        let sql = RelationalExport.duckDBScript()
        XCTAssertFalse(sql.contains("INSERT INTO organization\n            SELECT * FROM read_csv"),
                       "organization 不得用單一 SELECT * bulk insert——parent_id 的自我參照會 abort")
        XCTAssertTrue(sql.contains("UPDATE organization"),
                      "必須有回填 parent_id 的第二步")
        XCTAssertTrue(sql.contains("SET parent_id"), "回填的是 parent_id")
        // 骨架那一步必須顯式列欄位且不含 parent_id，否則等於沒分兩步
        guard let insertRange = sql.range(of: "INSERT INTO organization") else {
            return XCTFail("找不到 organization 的 INSERT")
        }
        // 只取這一個 statement（到第一個分號為止）——取寬了會把後面回填用的 UPDATE
        // 也吃進來，讓「骨架不得含 parent_id」變成永遠失敗的假斷言。
        let tail = sql[insertRange.lowerBound...]
        let stmt = String(tail.prefix(upTo: tail.firstIndex(of: ";") ?? tail.endIndex))
        XCTAssertTrue(stmt.contains("organization_id") && stmt.contains("org_key"),
                      "骨架 INSERT 必須顯式列欄位：\(stmt)")
        XCTAssertFalse(stmt.contains("parent_id"),
                       "骨架 INSERT 不得含 parent_id：\(stmt)")
    }
}
