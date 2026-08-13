import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicExport

/// #274：view-scoped 匯出——`ViewExtension.scope(_:)` 把 load 收斂成子集，
/// 再餵既有的 `RelationalExport.tables`。
///
/// 收斂語意的三個判定都在這裡釘住：成員 in／非成員 out、被引用的合著者保留
/// （FK 完整性）、機構閉包（隸屬 + parents 遞移）。空外延是合法結果不是錯誤。
final class ViewExportTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-view-export-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func person(_ key: String, affiliation: OrgRef?) throws {
        var p = Person(key: key, names: [key])
        if let a = affiliation {
            p.profile.affiliations = TimelineOf([TemporalValue(value: a, range: DateRange())])
        }
        try store.writePerson(p)
    }
    private func work(_ citekey: String, authors: [Author]) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: "article", title: "T")
        e.authors = authors; e.date = "2020"
        try store.writeEntry(e)
    }
    private let def = ViewDefinition(key: "v", personAffiliation: "iss",
                                     workHasAuthorInView: true)

    // MARK: - 成員資格

    func testScopeKeepsMembersAndTheirWorksDropsTheRest() throws {
        try person("member", affiliation: .key("iss"))
        try person("outsider", affiliation: .key("other"))
        try work("in2020member", authors: [.key("member")])
        try work("out2020outsider", authors: [.key("outsider")])
        let load = try store.load()
        let scoped = def.extension_(in: load).scope(load)
        XCTAssertEqual(scoped.entries.map(\.citekey), ["in2020member"])
        XCTAssertEqual(scoped.people.map(\.key), ["member"])
    }

    /// 零著作的成員照樣在——view 的 person 判準獨立於 work 判準。
    func testMemberWithNoWorksIsStillExported() throws {
        try person("member", affiliation: .key("iss"))
        let load = try store.load()
        let scoped = def.extension_(in: load).scope(load)
        XCTAssertEqual(scoped.people.map(\.key), ["member"])
        XCTAssertTrue(scoped.entries.isEmpty)
    }

    // MARK: - FK 完整性：合著者

    /// 非成員合著者的 Person 記錄保留。濾掉的話，`RelationalExport` 會把已歸戶的
    /// `.key` 退化成 `researcher_id IS NULL` ＋ name_full 印 key 字串——「已歸戶但
    /// 非成員」與「未歸戶」折成同一個觀察，事後無法區分。
    func testCoAuthorOfScopedWorkIsKeptForFKIntegrity() throws {
        try person("member", affiliation: .key("iss"))
        try person("coauthor", affiliation: .key("other"))
        try work("joint2020", authors: [.key("member"), .key("coauthor")])
        let load = try store.load()
        let scoped = def.extension_(in: load).scope(load)
        XCTAssertEqual(scoped.people.map(\.key).sorted(), ["coauthor", "member"])

        let tables = RelationalExport.tables(entries: scoped.entries, people: scoped.people,
                                             organizations: scoped.organizations)
        // 兩位 .key 作者的 researcher_id 都不得是 NULL
        let authorIDs = tables.publicationAuthor.rows.map { $0[2] }
        XCTAssertEqual(authorIDs.count, 2)
        XCTAssertFalse(authorIDs.contains(nil), "已歸戶作者在 view 匯出中不得退化成 NULL")
    }

    /// 未歸戶的 literal 作者照樣 NULL——那是誠實狀態，scope 不改變它。
    func testLiteralAuthorStaysNullInScopedExport() throws {
        try person("member", affiliation: .key("iss"))
        try work("mixed2020", authors: [.key("member"), .literal("Wang, C.")])
        let load = try store.load()
        let scoped = def.extension_(in: load).scope(load)
        let tables = RelationalExport.tables(entries: scoped.entries, people: scoped.people,
                                             organizations: scoped.organizations)
        let rows = tables.publicationAuthor.rows
        XCTAssertEqual(rows.count, 2)
        let literalRow = rows.first { $0[3] == "Wang, C." }
        XCTAssertNotNil(literalRow)
        XCTAssertNil(literalRow?[2] ?? nil, "literal 作者的 researcher_id 應為 NULL")
    }

    // MARK: - 機構閉包

    /// 隸屬引用的機構 + parents 遞移閉包保留；無關機構濾掉。
    func testOrganizationClosureFollowsAffiliationsAndParents() throws {
        var iss = Organization(key: "iss")
        iss.parents = TimelineOf([TemporalValue(value: .key("academia-sinica"))])
        try store.writeOrganization(iss)
        try store.writeOrganization(Organization(key: "academia-sinica"))
        try store.writeOrganization(Organization(key: "unrelated"))
        try person("member", affiliation: .key("iss"))
        let load = try store.load()
        let scoped = def.extension_(in: load).scope(load)
        XCTAssertEqual(scoped.organizations.map(\.key).sorted(),
                       ["academia-sinica", "iss"])

        // organization 表的 parent_id 外鍵閉合（academia-sinica 的列存在）
        let tables = RelationalExport.tables(entries: scoped.entries, people: scoped.people,
                                             organizations: scoped.organizations)
        let orgIDs = Set(tables.organization.rows.compactMap { $0[0] })
        let parentIDs = tables.organization.rows.compactMap { $0[5] }
        XCTAssertFalse(parentIDs.isEmpty)
        XCTAssertTrue(parentIDs.allSatisfy { orgIDs.contains($0) },
                      "parent_id 必須指向匯出集合內的 organization 列")
    }

    /// 懸空的 parents `.key` 走不動、自然終止——不 crash、不造 id。
    func testDanglingParentKeyTerminatesClosureQuietly() throws {
        var iss = Organization(key: "iss")
        iss.parents = TimelineOf([TemporalValue(value: .key("ghost"))])
        try store.writeOrganization(iss)
        try person("member", affiliation: .key("iss"))
        let load = try store.load()
        let scoped = def.extension_(in: load).scope(load)
        XCTAssertEqual(scoped.organizations.map(\.key), ["iss"])
    }

    // MARK: - 空外延

    /// 判準無人命中 → 空表是合法結果，不是錯誤。
    func testEmptyViewExportsEmptyTablesWithoutError() throws {
        try person("outsider", affiliation: .key("other"))
        try work("out2020", authors: [.key("outsider")])
        let load = try store.load()
        let scoped = def.extension_(in: load).scope(load)
        XCTAssertTrue(scoped.entries.isEmpty)
        XCTAssertTrue(scoped.people.isEmpty)
        XCTAssertTrue(scoped.organizations.isEmpty)
        let tables = RelationalExport.tables(entries: scoped.entries, people: scoped.people,
                                             organizations: scoped.organizations)
        for t in tables.all { XCTAssertTrue(t.rows.isEmpty, "\(t.name) 應為空") }
    }
}
