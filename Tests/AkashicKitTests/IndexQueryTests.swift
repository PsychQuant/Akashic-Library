import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex
@testable import AkashicQuery

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
