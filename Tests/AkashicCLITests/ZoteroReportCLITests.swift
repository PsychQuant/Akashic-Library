import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite

/// CLI `import-zotero` 的歧義報告與 `doctor` 的 orphan 兩行（#610、#609）。
///
/// 資料邏輯由 `AkashicKitTests` 覆蓋；這裡走**真 binary** 釘住使用者實際讀到的那幾行——先前 `ambiguousSourceClaims` 的逐行輸出與
/// doctor 的 `orphaned additional sources:` 一行都沒有測試，那幾段被刪或改名沒有東西會紅（#610／#609 R1 verify，requirements 席）。
/// fixture 用一個最小的 zotero.sqlite（schema 與 `ZoteroFixture` 同一組表；那個 struct 住在 AkashicKitTests，這個 target 不能引用）。
final class ZoteroReportCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var zoteroDB: URL!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    private let gone = Date(timeIntervalSince1970: 1_753_000_000)

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zrep-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zrep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        try LibraryStore(root: root).ensureLayout()
        zoteroDB = fakeHome.appendingPathComponent("zotero.sqlite")
        let db = try SQLiteDB(path: zoteroDB.path, readOnly: false)
        for sql in [
            "CREATE TABLE itemTypes(itemTypeID INTEGER PRIMARY KEY, typeName TEXT)",
            "CREATE TABLE items(itemID INTEGER PRIMARY KEY, itemTypeID INT, key TEXT, version INT, libraryID INT)",
            "CREATE TABLE fields(fieldID INTEGER PRIMARY KEY, fieldName TEXT)",
            "CREATE TABLE itemDataValues(valueID INTEGER PRIMARY KEY, value TEXT)",
            "CREATE TABLE itemData(itemID INT, fieldID INT, valueID INT)",
            "CREATE TABLE creators(creatorID INTEGER PRIMARY KEY, firstName TEXT, lastName TEXT, fieldMode INT)",
            "CREATE TABLE creatorTypes(creatorTypeID INTEGER PRIMARY KEY, creatorType TEXT)",
            "CREATE TABLE itemCreators(itemID INT, creatorID INT, creatorTypeID INT, orderIndex INT)",
            "CREATE TABLE itemTypeCreatorTypes(itemTypeID INT, creatorTypeID INT, primaryField INT)",
            "CREATE TABLE deletedItems(itemID INT)",
            "CREATE TABLE itemAttachments(itemID INT, parentItemID INT, path TEXT, contentType TEXT)",
            "CREATE TABLE tags(tagID INTEGER PRIMARY KEY, name TEXT)",
            "CREATE TABLE itemTags(itemID INT, tagID INT, type INT)",
        ] { try db.execute(sql) }
        try db.execute("INSERT INTO itemTypes VALUES (1,'journalArticle')")
        try db.execute("INSERT INTO creatorTypes VALUES (1,'author')")
        try db.execute("INSERT INTO itemTypeCreatorTypes VALUES (1,1,1)")
        try db.execute("INSERT INTO fields VALUES (1,'title')")
        try db.execute("INSERT INTO items VALUES (10,1,'KEYART01',5,1)")
        try db.execute("INSERT INTO itemDataValues VALUES (100,'Identifiability of polychoric models')")
        try db.execute("INSERT INTO itemData VALUES (10,1,100)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func source(_ key: String, lib: Int, orphaned: Bool = false) -> Provenance {
        Provenance(zoteroKey: key, zoteroVersion: 1, libraryID: lib, orphanedAt: orphaned ? gone : nil)
    }

    private func write(_ citekey: String, primary: Provenance?, additional: [Provenance] = []) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: citekey)
        e.provenance = primary
        e.additionalProvenance = additional
        try LibraryStore(root: root).writeEntry(e)
    }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    // MARK: - import-zotero

    /// 兩筆 entry 宣稱同一個 `(library_id, zotero_key)`：逐行印出來源鍵與宣稱者，標題行指向 validate 的跨記錄警告。
    func testImportPrintsTheAmbiguousSourceClaims() throws {
        try write("twin2025a", primary: source("KEYART01", lib: 1))
        try write("twin2025b", primary: source("KEYART01", lib: 1))
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("同一個 Zotero 來源被多筆 entry 宣稱、本趟未更新任何一筆"), r.output)
        XCTAssertTrue(r.output.contains("⚠ 1:KEYART01：twin2025a, twin2025b"), r.output)
        XCTAssertTrue(r.output.contains("akashic validate 的跨記錄警告"), r.output)
        XCTAssertTrue(r.output.contains("created: 0"), "歧義的條目不得新建：\(r.output)")
    }

    /// 舊檔（沒記 library_id）的裸 key 桶，鍵寫成 `?:<key>`——而標題行指向的 validate 警告真的存在（先前 legacy 桶沒有）。
    func testImportPrintsTheLegacyBareKeyBucketAndValidateReportsIt() throws {
        try write("legacy2025a", primary: Provenance(zoteroKey: "KEYART01", zoteroVersion: 1))
        try write("legacy2025b", primary: Provenance(zoteroKey: "KEYART01", zoteroVersion: 1))
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("⚠ ?:KEYART01：legacy2025a, legacy2025b"), r.output)
        let v = try cli(["validate"])
        XCTAssertTrue(v.output.contains("[跨記錄] 沒記 library_id 的 Zotero 來源（裸 key「KEYART01」）被 2 筆 entry 宣稱"),
                      "import 的提示指向的警告要真的存在：\(v.output)")
    }

    /// 沒有歧義時不印那一段。
    func testImportPrintsNothingWhenThereIsNoAmbiguity() throws {
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("created: 1"), r.output)
        XCTAssertFalse(r.output.contains("被多筆 entry 宣稱"), r.output)
    }

    // MARK: - doctor

    /// `orphaned:` 一行改讀 `health`（先前自己推導 `provenance?.orphanedAt != nil`，看不見「只有附加來源、全部已刪除」）；
    /// 新的一行 `orphaned additional sources:` 列出主連結仍在、附加來源已刪除的 entry，兩張清單不相交。
    func testDoctorPrintsBothOrphanLinesFromHealth() throws {
        try write("alive2020", primary: source("A", lib: 1))
        try write("partial2020", primary: source("B", lib: 1), additional: [source("B2", lib: 5, orphaned: true)])
        try write("allgone2020", primary: nil, additional: [source("C", lib: 5, orphaned: true)])
        try write("primarygone2020", primary: source("D", lib: 1, orphaned: true))
        let r = try cli(["doctor"])
        XCTAssertEqual(r.status, 0, r.output)
        let orphanedLine = try XCTUnwrap(r.output.split(separator: "\n").first { $0.hasPrefix("orphaned:") }, r.output)
        XCTAssertTrue(orphanedLine.hasPrefix("orphaned: 2"), String(orphanedLine))
        XCTAssertTrue(orphanedLine.contains("allgone2020") && orphanedLine.contains("primarygone2020"),
                      "只有附加來源、全部已刪除也是整筆 orphan：\(orphanedLine)")
        XCTAssertFalse(orphanedLine.contains("partial2020"), String(orphanedLine))
        let partialLine = try XCTUnwrap(r.output.split(separator: "\n").first { $0.hasPrefix("orphaned additional sources:") }, r.output)
        XCTAssertTrue(partialLine.hasPrefix("orphaned additional sources: 1"), String(partialLine))
        XCTAssertTrue(partialLine.contains("partial2020") && partialLine.contains("App 裁決台"), String(partialLine))
    }

    func testDoctorPrintsZeroForBothLinesOnAHealthyStore() throws {
        try write("alive2020", primary: source("A", lib: 1))
        let r = try cli(["doctor"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("orphaned: 0\n"), r.output)
        XCTAssertTrue(r.output.contains("orphaned additional sources: 0\n"), r.output)
    }
}
