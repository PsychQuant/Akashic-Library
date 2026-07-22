import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite
@testable import AkashicZoteroImport

/// Zotero fixture：以最小 schema 子集在 temp 目錄建 zotero.sqlite。
/// 只建 importer 會讀的表；schema 對齊實際 Zotero 7。
struct ZoteroFixture {
    let dbURL: URL
    let db: SQLiteDB

    init(dir: URL) throws {
        dbURL = dir.appendingPathComponent("zotero.sqlite")
        db = try SQLiteDB(path: dbURL.path, readOnly: false)
        for sql in [
            "CREATE TABLE itemTypes(itemTypeID INTEGER PRIMARY KEY, typeName TEXT)",
            "CREATE TABLE items(itemID INTEGER PRIMARY KEY, itemTypeID INT, key TEXT, version INT)",
            "CREATE TABLE fields(fieldID INTEGER PRIMARY KEY, fieldName TEXT)",
            "CREATE TABLE itemDataValues(valueID INTEGER PRIMARY KEY, value TEXT)",
            "CREATE TABLE itemData(itemID INT, fieldID INT, valueID INT)",
            "CREATE TABLE creators(creatorID INTEGER PRIMARY KEY, firstName TEXT, lastName TEXT, fieldMode INT)",
            "CREATE TABLE creatorTypes(creatorTypeID INTEGER PRIMARY KEY, creatorType TEXT)",
            "CREATE TABLE itemCreators(itemID INT, creatorID INT, creatorTypeID INT, orderIndex INT)",
            "CREATE TABLE deletedItems(itemID INT)",
            "CREATE TABLE itemAttachments(itemID INT, parentItemID INT, path TEXT, contentType TEXT)",
            "CREATE TABLE tags(tagID INTEGER PRIMARY KEY, name TEXT)",
            "CREATE TABLE itemTags(itemID INT, tagID INT, type INT)",
        ] {
            try db.execute(sql)
        }
        try db.execute("INSERT INTO itemTypes VALUES (1,'journalArticle'),(2,'book'),(3,'attachment'),(4,'note')")
        try db.execute("INSERT INTO creatorTypes VALUES (1,'author'),(2,'editor')")
        try db.execute("INSERT INTO fields VALUES (1,'title'),(2,'date'),(3,'publicationTitle'),(4,'volume'),(5,'issue'),(6,'DOI'),(7,'pages')")
    }

    func addField(item: Int, field: Int, value: String, valueID: Int) throws {
        try db.execute("INSERT INTO itemDataValues VALUES (?,?)", bind: [valueID, value])
        try db.execute("INSERT INTO itemData VALUES (?,?,?)", bind: [item, field, valueID])
    }

    /// 標準 fixture：一篇 article（雙作者、tag、storage 附件）+ 一本 book。
    func seedStandard() throws {
        try db.execute("INSERT INTO items VALUES (10,1,'KEYART01',5)")
        try addField(item: 10, field: 1, value: "Identifiability of polychoric models", valueID: 100)
        try addField(item: 10, field: 2, value: "2025-04-01", valueID: 101)
        try addField(item: 10, field: 3, value: "Psychometrika", valueID: 102)
        try addField(item: 10, field: 4, value: "90", valueID: 103)
        try addField(item: 10, field: 5, value: "2", valueID: 104)
        try addField(item: 10, field: 6, value: "10.1017/psy.2025.1", valueID: 105)
        try db.execute("INSERT INTO creators VALUES (1,'Che','Cheng',0),(2,'Hau-Hung','Yang',0)")
        try db.execute("INSERT INTO itemCreators VALUES (10,1,1,0),(10,2,1,1)")
        try db.execute("INSERT INTO tags VALUES (1,'identifiability')")
        try db.execute("INSERT INTO itemTags VALUES (10,1,0)")
        // storage 附件（child item 20）
        try db.execute("INSERT INTO items VALUES (20,3,'KEYATT01',5)")
        try db.execute("INSERT INTO itemAttachments VALUES (20,10,'storage:paper.pdf','application/pdf')")
        // book（單作者 fieldMode 1）
        try db.execute("INSERT INTO items VALUES (11,2,'KEYBOOK1',7)")
        try addField(item: 11, field: 1, value: "Matrix Visualization", valueID: 110)
        try addField(item: 11, field: 2, value: "2004", valueID: 111)
        try db.execute("INSERT INTO creators VALUES (3,'','Chun-Houh Chen',1)")
        try db.execute("INSERT INTO itemCreators VALUES (11,3,1,0)")
    }
}

final class ZoteroImportTests: XCTestCase {
    var dir: URL!
    var store: LibraryStore!
    var fixture: ZoteroFixture!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-zimport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = LibraryStore(root: dir.appendingPathComponent("library"))
        try store.ensureLayout()
        fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func runImport() throws -> ImportReport {
        let importer = ZoteroImporter(store: store)
        return try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_000_000))
    }

    func testFirstImportCreatesEntries() throws {
        let report = try runImport()
        XCTAssertEqual(report.created.sorted(), ["chen2004matrix", "cheng2025identifiability"])
        XCTAssertEqual(report.updated, [])
        XCTAssertEqual(report.orphaned, [])

        let load = try store.load()
        let article = load.entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(article.type, "article")
        XCTAssertEqual(article.title, "Identifiability of polychoric models")
        XCTAssertEqual(article.authors, [.literal("Che Cheng"), .literal("Hau-Hung Yang")])
        XCTAssertEqual(article.date, "2025-04-01")
        XCTAssertEqual(article.fields["journaltitle"], "Psychometrika")
        XCTAssertEqual(article.fields["volume"], "90")
        XCTAssertEqual(article.fields["number"], "2")
        XCTAssertEqual(article.fields["doi"], "10.1017/psy.2025.1")
        XCTAssertEqual(article.attachments, [AttachmentRef(kind: .zotero, path: "storage/KEYATT01/paper.pdf")])
        XCTAssertEqual(article.provenance?.zoteroKey, "KEYART01")
        XCTAssertEqual(article.provenance?.zoteroVersion, 5)
        XCTAssertEqual(article.akashic.tags, ["identifiability"])  // 建檔 seed

        let book = load.entries.first { $0.citekey == "chen2004matrix" }!
        XCTAssertEqual(book.type, "book")
        XCTAssertEqual(book.authors, [.literal("Chun-Houh Chen")])  // fieldMode 1
    }

    func testSecondImportIsIdempotent() throws {
        _ = try runImport()
        let before = try store.load().entries
        let report = try runImport()
        XCTAssertEqual(report.created, [])
        XCTAssertEqual(report.updated, [])
        XCTAssertEqual(report.orphaned, [])
        XCTAssertEqual(report.unchanged, 2)
        XCTAssertEqual(try store.load().entries, before)
    }

    func testVersionBumpUpdatesBiblatexButNotAkashic() throws {
        _ = try runImport()
        // 使用者在 akashic namespace 加了衍生資料
        var article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        article.akashic.status = "reading"
        article.akashic.relations.cites = ["olsson1979maximum"]
        try store.writeEntry(article)
        // Zotero 端改 title + bump version
        try fixture.db.execute("UPDATE itemDataValues SET value='Updated title' WHERE valueID=100")
        try fixture.db.execute("UPDATE items SET version=9 WHERE itemID=10")

        let report = try runImport()
        XCTAssertEqual(report.updated, ["cheng2025identifiability"])
        let after = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(after.title, "Updated title")
        XCTAssertEqual(after.provenance?.zoteroVersion, 9)
        XCTAssertEqual(after.akashic.status, "reading")                       // akashic 不被覆寫
        XCTAssertEqual(after.akashic.relations.cites, ["olsson1979maximum"])
        XCTAssertEqual(after.id, article.id)                                   // UUID 不變
    }

    func testZoteroDeletionMarksOrphanNotDelete() throws {
        _ = try runImport()
        try fixture.db.execute("INSERT INTO deletedItems VALUES (11)")
        let report = try runImport()
        XCTAssertEqual(report.orphaned, ["chen2004matrix"])
        let book = try store.load().entries.first { $0.citekey == "chen2004matrix" }!
        XCTAssertNotNil(book.provenance?.orphanedAt)   // 標記，不刪檔
        // 再跑一次不重複 orphan
        let report2 = try runImport()
        XCTAssertEqual(report2.orphaned, [])
    }

    func testResolvedAuthorsArePreservedOnUpdate() throws {
        _ = try runImport()
        var article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        article.authors[0] = .key("cheng-che")   // 使用者已解析第一作者
        try store.writeEntry(article)
        try fixture.db.execute("UPDATE items SET version=10 WHERE itemID=10")

        _ = try runImport()
        let after = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(after.authors.first, .key("cheng-che"))   // 解析成果不被 pull 摧毀
    }
}

extension ZoteroImportTests {
    // DA/Codex 確認的 data-loss 路徑：quarantined 檔絕不可被 import 覆寫
    func testQuarantinedFileIsNeverOverwritten() throws {
        let brokenURL = store.entriesDir.appendingPathComponent("cheng2025identifiability.yaml")
        let brokenContent = "this is: [not a valid entry\n"
        try brokenContent.write(to: brokenURL, atomically: true, encoding: .utf8)

        let report = try runImport()
        // 原檔一個 byte 都不能動
        XCTAssertEqual(try String(contentsOf: brokenURL, encoding: .utf8), brokenContent)
        // 新 entry 讓位：拿衝突後綴 key
        XCTAssertTrue(report.created.contains("cheng2025bidentifiability"), "\(report.created)")
    }

    func testOrphanClearedWhenItemReturnsAtSameVersion() throws {
        _ = try runImport()
        try fixture.db.execute("INSERT INTO deletedItems VALUES (11)")
        _ = try runImport()
        try fixture.db.execute("DELETE FROM deletedItems WHERE itemID = 11")
        let report = try runImport()
        XCTAssertEqual(report.orphanCleared, ["chen2004matrix"])
        let book = try store.load().entries.first { $0.citekey == "chen2004matrix" }!
        XCTAssertNil(book.provenance?.orphanedAt)
    }

    func testUnmappedZoteroFieldsAreReportedNotSilentlyDropped() throws {
        try fixture.db.execute("INSERT INTO fields VALUES (8,'extra')")
        try fixture.addField(item: 10, field: 8, value: "PMID: 12345", valueID: 199)
        let report = try runImport()
        XCTAssertEqual(report.droppedFields["extra"], 1)
    }

    func testDeletedAttachmentChildIsExcluded() throws {
        try fixture.db.execute("INSERT INTO deletedItems VALUES (20)")
        _ = try runImport()
        let article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertTrue(article.attachments.isEmpty)
    }
}
