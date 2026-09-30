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

    /// #611：新建的條目與既有的 work 共用 DOI——照建，逐對印出提名，記成歧異記錄（`divergences` 列得出來）。
    private func addDOIToTheZoteroArticle(_ doi: String) throws {
        let db = try SQLiteDB(path: zoteroDB.path, readOnly: false)
        try db.execute("INSERT INTO fields VALUES (6,'DOI')")
        try db.execute("INSERT INTO itemDataValues VALUES (101,?)", bind: [doi])
        try db.execute("INSERT INTO itemData VALUES (10,6,101)")
    }

    private func writeWork(_ citekey: String, doi: String) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: citekey)
        e.doi = [try XCTUnwrap(DOI(doi))]
        try LibraryStore(root: root).writeEntry(e)
    }

    func testImportPrintsTheDOINominationAndDivergencesListsTheRecord() throws {
        let doi = "10.1017/psy.2025.1"
        try addDOIToTheZoteroArticle(doi)
        try writeWork("wos2025identifiability", doi: doi)
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("created: 1"), "照建：\(r.output)")
        XCTAssertTrue(r.output.contains("新建的條目與另一筆 work 共用 DOI（#611）: 1 對"), r.output)
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.contains("⊕ ") }, r.output)
        XCTAssertTrue(line.contains("↔ wos2025identifiability") && line.contains(doi) && line.contains("divergence "), String(line))
        let d = try cli(["divergences"])
        XCTAssertTrue(d.output.contains(doi) && d.output.contains("wos2025identifiability"), "記錄要真的在：\(d.output)")
    }

    /// citekey 重複的既有那一筆不點名，印 ⚠。**結束狀態不是這一行造成的**：重複的 citekey 讓 index rebuild 撞 UNIQUE（既有行為），
    /// 提名那一段印在 rebuild 之前。
    func testImportPrintsTheUnlocatableNominationWithoutNamingIt() throws {
        let doi = "10.1017/psy.2025.1"
        try addDOIToTheZoteroArticle(doi)
        try writeWork("dup2025identifiability", doi: doi)
        try writeWork("dup2025identifiability", doi: doi)
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.contains("⚠ ") && $0.contains("↔ dup2025identifiability") },
                                 r.output)
        XCTAssertTrue(line.contains("未記") && line.contains("無法唯一定位"), String(line))
        XCTAssertFalse(r.output.contains("⊕ "), r.output)
    }

    /// 沒有歧義時不印那一段。
    func testImportPrintsNothingWhenThereIsNoAmbiguity() throws {
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("created: 1"), r.output)
        XCTAssertFalse(r.output.contains("被多筆 entry 宣稱"), r.output)
        XCTAssertFalse(r.output.contains("歧異提名"), "沒有共用 DOI 時不印提名那一段：\(r.output)")
    }

    /// #694：主來源 hash 不同、Zotero 那一列已同步且 version 沒動——自己一行、不算進 `updated:`；這一行只說觀察到的事實、可能的原因不排序。
    func testImportPrintsThePrimaryHashOnlyLineApartFromUpdated() throws {
        try write("hashonly2025", primary: Provenance(zoteroKey: "KEYART01", zoteroVersion: 5, libraryID: 1, zoteroHash: "stale"))
        let db = try SQLiteDB(path: zoteroDB.path, readOnly: false)
        try db.execute("ALTER TABLE items ADD COLUMN synced INT NOT NULL DEFAULT 1")   // 實際的 Zotero schema 有這一欄
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("updated: 0\n"), "hash-only 的那一筆不算進 updated：\(r.output)")
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.hasPrefix("updated（只有 mapping hash 不同") }, r.output)
        XCTAssertTrue(line.contains("hashonly2025") && line.contains("#694"), String(line))
        XCTAssertTrue(!line.contains("沒有人改"), "只說觀察到的事實：\(line)")
        // R1 verify：先說「不宣稱原因」又說「多半是 mapping 定義演進」是自相矛盾——兩個可能都列、不排序
        XCTAssertTrue(line.contains("mapping 定義改了") && line.contains("子項附件增減") && !line.contains("多半"), String(line))
        // 同一段整份替換照樣拿掉手加的欄位、覆寫未歸戶作者——這一行要指向說出這件事的那兩行
        XCTAssertTrue(line.contains("authors overwritten") && line.contains("fields removed by pull"), String(line))
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

/// #705：寫進 `entities/`、搬移後的 legacy 拷貝沒刪掉的那一筆——`import-zotero` 印在 `writtenWithLegacyCopy`，不在 `write failed`。
/// #702 讓它兩邊都出現：同一筆記錄一半說寫了、一半說失敗。
extension ZoteroReportCLITests {
    /// #239：hook 環境帶 `GIT_DIR`，`-C` 擋不住它——不剝的話 fixture 的 commit 會寫進使用者的 repo。
    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    func testImportPrintsTheLegacyCopyLeftOnTheSuccessSide() throws {
        let store = LibraryStore(root: root)
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        var e = Entry(id: UUID(), citekey: "legacy2025identifiability", type: .periodicalArticle, title: "舊標題")
        e.provenance = Provenance(zoteroKey: "KEYART01", zoteroVersion: 1, libraryID: 1)
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.entriesDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }
        let probe = store.entriesDir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }

        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertTrue(r.output.contains("updated: 1"), "寫了，算在 updated：\(r.output)")
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.hasPrefix("writtenWithLegacyCopy") }, r.output)
        XCTAssertTrue(line.hasSuffix(": 1"), String(line))
        XCTAssertTrue(r.output.contains("work「\(e.citekey)」"), r.output)
        XCTAssertFalse(r.output.contains("write failed"), "不是寫入失敗：\(r.output)")
    }
}
