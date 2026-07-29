import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex
@testable import AkashicQuery
@testable import AkashicSQLite

/// Index/Query/Graph 共用 fixture：5 entries + 2 people，涵蓋
/// key/literal 作者、同期刊、cites/related、orphan。
enum QueryFixture {
    static func populate(_ store: LibraryStore) throws {
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article",
                       title: "Identifiability of polychoric models",
                       authors: [.key("cheng-che"), .literal("Hau-Hung Yang")], date: "2025-04-01")
        e1.fields["journaltitle"] = "Psychometrika"
        e1.akashic.tags = ["identifiability"]
        e1.akashic.relations.cites = ["olsson1979maximum"]
        e1.akashic.relations.related = ["foldnes2019bivariate"]
        try store.writeEntry(e1)

        var e2 = Entry(id: UUID(), citekey: "olsson1979maximum", type: "article",
                       title: "Maximum likelihood estimation of the polychoric correlation",
                       authors: [.literal("Ulf Olsson")], date: "1979")
        e2.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e2)

        var e3 = Entry(id: UUID(), citekey: "foldnes2019bivariate", type: "article",
                       title: "On the bivariate normality assumption",
                       authors: [.literal("Njål Foldnes")], date: "2019")
        e3.fields["journaltitle"] = "Structural Equation Modeling"
        try store.writeEntry(e3)

        let e4 = Entry(id: UUID(), citekey: "chen2004matrix", type: "book",
                       title: "Matrix Visualization", authors: [.key("chen-chun-houh")], date: "2004")
        try store.writeEntry(e4)

        let e5 = Entry(id: UUID(), citekey: "chen2010gap", type: "article",
                       title: "Generalized association plots", authors: [.key("chen-chun-houh")], date: "2010")
        try store.writeEntry(e5)

        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"]))
        try store.writePerson(Person(key: "chen-chun-houh", names: ["Chun-Houh Chen", "陳君厚"]))
    }
}

final class IndexQueryTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var engine: QueryEngine!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-index-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try QueryFixture.populate(store)
        let stats = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(stats.entries, 5)
        XCTAssertEqual(stats.people, 2)
        XCTAssertEqual(stats.relations, 2)
        engine = try QueryEngine(indexPath: store.indexURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func citekeys(_ result: [EntrySummary]) -> [String] { result.map(\.citekey) }

    func testFindByAuthorKey() throws {
        var filter = QueryFilter()
        filter.author = "cheng-che"
        XCTAssertEqual(citekeys(try engine.find(filter)), ["cheng2025identifiability"])
    }

    func testFindByAuthorLiteralSubstring() throws {
        var filter = QueryFilter()
        filter.author = "olsson"
        XCTAssertEqual(citekeys(try engine.find(filter)), ["olsson1979maximum"])
    }

    func testFindByJournal() throws {
        var filter = QueryFilter()
        filter.journal = "psychometrika"
        XCTAssertEqual(citekeys(try engine.find(filter)),
                       ["cheng2025identifiability", "olsson1979maximum"])
    }

    func testFindByYearRange() throws {
        var filter = QueryFilter()
        filter.yearFrom = 2000
        filter.yearTo = 2019
        XCTAssertEqual(citekeys(try engine.find(filter)),
                       ["chen2004matrix", "chen2010gap", "foldnes2019bivariate"])
    }

    func testFindByTagAndType() throws {
        var byTag = QueryFilter()
        byTag.tag = "identifiability"
        XCTAssertEqual(citekeys(try engine.find(byTag)), ["cheng2025identifiability"])
        var byType = QueryFilter()
        byType.type = "book"
        XCTAssertEqual(citekeys(try engine.find(byType)), ["chen2004matrix"])
    }

    func testSameJournalExcludesSelf() throws {
        XCTAssertEqual(citekeys(try engine.sameJournal(as: "cheng2025identifiability")),
                       ["olsson1979maximum"])
    }

    func testSameAuthorViaPersonKey() throws {
        XCTAssertEqual(citekeys(try engine.sameAuthor(as: "chen2004matrix")), ["chen2010gap"])
    }

    func testCitesAndCitedBy() throws {
        XCTAssertEqual(citekeys(try engine.cites(of: "cheng2025identifiability")),
                       ["olsson1979maximum"])
        XCTAssertEqual(citekeys(try engine.citedBy("olsson1979maximum")),
                       ["cheng2025identifiability"])
    }

    func testRelatedIsBidirectional() throws {
        XCTAssertEqual(citekeys(try engine.related(to: "cheng2025identifiability")),
                       ["foldnes2019bivariate"])
        XCTAssertEqual(citekeys(try engine.related(to: "foldnes2019bivariate")),
                       ["cheng2025identifiability"])
    }

    func testRebuildIsIdempotent() throws {
        let stats = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(stats.entries, 5)
        let again = try QueryEngine(indexPath: store.indexURL)
        var filter = QueryFilter()
        filter.journal = "psychometrika"
        XCTAssertEqual(try again.find(filter).count, 2)
    }
}

extension IndexQueryTests {
    func testSameAuthorLiteralIsCaseInsensitive() throws {
        var e6 = Entry(id: UUID(), citekey: "olsson1985more", type: "article",
                       title: "More on polychorics", authors: [.literal("ULF OLSSON")], date: "1985")
        e6.fields["journaltitle"] = "Applied Psych Measurement"
        try store.writeEntry(e6)
        _ = try LibraryIndex(store: store).rebuild()
        let engine2 = try QueryEngine(indexPath: store.indexURL)
        XCTAssertEqual(engine2.citekeysOf(try engine2.sameAuthor(as: "olsson1979maximum")),
                       ["olsson1985more"])
    }

    func testAuthorFilterEscapesLikeWildcards() throws {
        var filter = QueryFilter()
        filter.author = "u_f"
        // 未 escape 時 `_` 是萬用字元會誤中 "Ulf Olsson"；escape 後應為空
        XCTAssertTrue(try engine.find(filter).isEmpty)
    }
}

extension QueryEngine {
    func citekeysOf(_ result: [EntrySummary]) -> [String] { result.map(\.citekey) }
}

/// #13 多 library：index 的 entry_libraries 表 + query 的 library 篩選。
final class LibraryQueryTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-libquery-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeLibrary(Library(key: "sinica", name: "中研院"))
        try store.writeLibrary(Library(key: "psychology", name: "心理學"))
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article",
                       title: "Identifiability", date: "2025")
        e1.akashic.libraries = ["sinica"]
        e1.akashic.tags = ["identifiability"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "chen2004matrix", type: "book",
                       title: "Matrix Visualization", date: "2004")
        e2.akashic.libraries = ["sinica", "psychology"]
        try store.writeEntry(e2)
        try store.writeEntry(Entry(id: UUID(), citekey: "olsson1979maximum", type: "article",
                                   title: "MLE", date: "1979"))
        _ = try LibraryIndex(store: store).rebuild()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func query() throws -> QueryEngine {
        try QueryEngine(indexPath: store.indexURL)
    }

    func testLibraryFilterReturnsMembersOnly() throws {
        var f = QueryFilter()
        f.library = "sinica"
        XCTAssertEqual(try query().find(f).map(\.citekey).sorted(),
                       ["chen2004matrix", "cheng2025identifiability"])
        f.library = "psychology"
        XCTAssertEqual(try query().find(f).map(\.citekey), ["chen2004matrix"])
    }

    func testLibraryFilterComposesWithOtherFilters() throws {
        var f = QueryFilter()
        f.library = "sinica"
        f.tag = "identifiability"
        XCTAssertEqual(try query().find(f).map(\.citekey), ["cheng2025identifiability"])
    }

    func testUnknownLibraryYieldsEmpty() throws {
        var f = QueryFilter()
        f.library = "ghost"
        XCTAssertTrue(try query().find(f).isEmpty, "未知 library＝空集合（無成員）")
    }

    func testNoLibraryFilterReturnsAll() throws {
        XCTAssertEqual(try query().find(QueryFilter()).count, 3, "未指定 library＝全集（零行為變化）")
    }
}

/// #13 verify fix round：index schema 版本——舊 index 撞新查詢不得炸 no such table。
final class IndexSchemaVersionTests: XCTestCase {
    func testStaleIndexIsDetectedAndRebuildRestoresQuery() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeLibrary(Library(key: "sinica", name: "中研院"))
        var e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article", title: "T")
        e.akashic.libraries = ["sinica"]
        try store.writeEntry(e)
        _ = try LibraryIndex(store: store).rebuild()
        XCTAssertTrue(try LibraryIndex.isCurrent(indexPath: store.indexURL))

        // 模擬 v1.1 舊 index：砍掉新表 + 歸零版本
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: false)
        try db.execute("DROP TABLE entry_libraries")
        try db.execute("PRAGMA user_version = 0")
        XCTAssertFalse(try LibraryIndex.isCurrent(indexPath: store.indexURL),
                       "舊 schema 必須被偵測為 stale")

        // ensureCurrent：stale → rebuild → 查詢可用
        _ = try LibraryIndex(store: store).ensureCurrent()
        var f = QueryFilter()
        f.library = "sinica"
        let hits = try QueryEngine(indexPath: store.indexURL).find(f)
        XCTAssertEqual(hits.map(\.citekey), ["cheng2025identifiability"])
    }
}
