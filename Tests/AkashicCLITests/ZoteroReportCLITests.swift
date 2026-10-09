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
        XCTAssertTrue(r.output.contains("新建的條目與另一筆 work 共用 DOI（#611）: 1 對——新建的條目照常建立，沒有合併、也沒有掛附加來源；記下的是沒有判斷的歧異提名"), r.output)
        XCTAssertFalse(r.output.contains("兩筆都已照建"), "另一筆是既有的，不是這一趟建的（#611 R3 verify 第 21／28 列）：\(r.output)")
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.contains("⊕ ") }, r.output)
        XCTAssertTrue(line.contains("↔ wos2025identifiability") && line.contains(doi) && line.contains("divergence "), String(line))
        let d = try cli(["divergences"])
        XCTAssertTrue(d.output.contains(doi) && d.output.contains("wos2025identifiability"), "記錄要真的在：\(d.output)")
    }

    /// 同一趟兩筆都新建、共用一個 DOI（R4 verify 第 6／8／18 列）：一對的「另一筆」也是這一趟建的——尾句不說它的狀態（R3 的「另一筆不動」
    /// 對這一種為假），只說確定的事。
    func testSameRunTwinsAreNominatedWithoutClaimingTheOtherIsUntouched() throws {
        let doi = "10.1017/psy.2025.2"
        try addDOIToTheZoteroArticle(doi)
        let db = try SQLiteDB(path: zoteroDB.path, readOnly: false)
        try db.execute("INSERT INTO items VALUES (11,1,'KEYART02',5,1)")
        try db.execute("INSERT INTO itemDataValues VALUES (102,'A second record of the same article')")
        try db.execute("INSERT INTO itemData VALUES (11,1,102)")
        try db.execute("INSERT INTO itemData VALUES (11,6,101)")
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("created: 2"), r.output)
        XCTAssertTrue(r.output.contains("新建的條目與另一筆 work 共用 DOI（#611）: 1 對——新建的條目照常建立，沒有合併、也沒有掛附加來源"), r.output)
        XCTAssertFalse(r.output.contains("另一筆不動"), r.output)
        XCTAssertEqual(r.output.split(separator: "\n").filter { $0.contains("⊕ ") }.count, 1, "同一趟的兩筆只記一次：\(r.output)")
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
        // R2 verify 第 24 列：標題只數真的記下的對；沒記下的另外說，不再宣稱「照建，並記一筆」
        XCTAssertTrue(r.output.contains("新建的條目與另一筆 work 共用 DOI（#611）: 0 對（另有 1 對沒記下）"), r.output)
        XCTAssertFalse(r.output.contains("並記一筆沒有判斷的歧異提名"), "沒記下的對不得被標題說成已記：\(r.output)")
        XCTAssertFalse(r.output.contains("記下的是沒有判斷的歧異提名"), "一對都沒記時不說「記下的是…」（#611 R3 verify 第 28 列）：\(r.output)")
    }

    /// #611 R1 verify 第 9 列：沒記下來的提名（這裡是共用 DOI 的 work 超過門檻）重新匯入不會再提名——CLI 印出摘要行、指路手記，並以非零結束。
    /// 匯入本身照建（`created: 1`）。記下來的提名（上一支）仍是 0。
    func testImportExitsNonZeroAndSaysSoWhenANominationWasNotRecorded() throws {
        let doi = "10.1017/psy.2025.1"
        try addDOIToTheZoteroArticle(doi)
        for n in 1...10 { try writeWork(String(format: "wos2025n%02d", n), doi: doi) }   // 加上這一趟新建的 ＝ 11 > 門檻 10
        let r = try cli(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("created: 1"), "照建：\(r.output)")
        XCTAssertTrue(r.output.contains("新建的條目與另一筆 work 共用 DOI（#611）: 0 對、1 個 DOI 的群組過大"), r.output)
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.contains("被 11 筆 work 共用") }, r.output)
        XCTAssertTrue(line.contains(doi) && line.contains("一對都沒記") && line.contains("超過 10 筆的門檻"), String(line))
        XCTAssertTrue(r.output.contains("有 1 列提名沒有記下來") && r.output.contains("重新匯入不會再提名")
                      && r.output.contains("record-divergence") && r.output.contains("以非零結束"), r.output)
        XCTAssertFalse(r.output.contains("⊕ "), "一對都沒記：\(r.output)")
        let d = try cli(["divergences"])
        XCTAssertFalse(d.output.contains(doi), "store 裡沒有提名：\(d.output)")
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
        // #709：index 以 entities/ 那份為準、略過 legacy 拷貝——重建成功，「index rebuilt」那一行說出略過了幾份
        XCTAssertEqual(r.status, 0, r.output)
        let rebuilt = try XCTUnwrap(r.output.split(separator: "\n").first { $0.hasPrefix("index rebuilt:") }, r.output)
        XCTAssertTrue(rebuilt.contains("略過 1 份 legacy 拷貝"), String(rebuilt))
    }
}

/// #705 第三次 verify（LOW 6）：`laterWriteRefused` 走到真的非零結束時，stderr 的第一行說要重跑幾筆。先前只有純函式的措辭測試與
/// 「沒有之後被拒」那一支的真 binary 測試——`printLines`／`printTrailer` 把計數交給 stderr 的那一段沒有真 binary 走過。
///
/// 造法：一筆 legacy work（`entries/` 唯讀、已 commit）帶 orphan 標記且 Zotero 端升了版——同一趟先清 orphan 標記（寫進 entities/、legacy 刪不掉），
/// 接著的書目更新被 #631 拒絕（`laterWriteRefused`）；另一筆新建的 item 與 10 筆既有 work 共用 DOI、提名沒記下，import 以 1 結束（沒有錯誤訊息）。
extension ZoteroReportCLITests {
    private func runSplit(_ args: [String]) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
        p.arguments = args + ["--library", root.path]
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        childEnv["AKASHIC_HOME"] = fakeHome.path
        p.environment = childEnv
        let outFile = fakeHome.appendingPathComponent("stdout-\(UUID().uuidString)")
        let errFile = fakeHome.appendingPathComponent("stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outFile.path, contents: nil)
        FileManager.default.createFile(atPath: errFile.path, contents: nil)
        let o = try FileHandle(forWritingTo: outFile), e = try FileHandle(forWritingTo: errFile)
        p.standardOutput = o; p.standardError = e
        try p.run()
        p.waitUntilExit()
        try o.close(); try e.close()
        return (p.terminationStatus, try String(contentsOf: outFile, encoding: .utf8), try String(contentsOf: errFile, encoding: .utf8))
    }

    func testANotAppliedLaterWriteReachesTheFirstStderrLineOnANonZeroExit() throws {
        let store = LibraryStore(root: root)
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        var e = Entry(id: UUID(), citekey: "legacy2025identifiability", type: .periodicalArticle, title: "舊標題")
        e.provenance = Provenance(zoteroKey: "KEYART01", zoteroVersion: 1, libraryID: 1, orphanedAt: gone)
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        // 第二個 item：與 10 筆既有 work 共用 DOI——新建後的提名超過門檻、沒記下，import 以 1 結束
        let doi = "10.1017/psy.2025.9"
        let db = try SQLiteDB(path: zoteroDB.path, readOnly: false)
        try db.execute("INSERT INTO items VALUES (11,1,'KEYNEW02',5,1)")
        try db.execute("INSERT INTO itemDataValues VALUES (110,'A second article')")
        try db.execute("INSERT INTO itemData VALUES (11,1,110)")
        try db.execute("INSERT INTO fields VALUES (6,'DOI')")
        try db.execute("INSERT INTO itemDataValues VALUES (111,?)", bind: [doi])
        try db.execute("INSERT INTO itemData VALUES (11,6,111)")
        for n in 1...10 { try writeWork(String(format: "wos2025m%02d", n), doi: doi) }
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.entriesDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }
        let probe = store.entriesDir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }

        let r = try runSplit(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 1, "前提：提名沒記下、以 1 結束：\(r.out)\n\(r.err)")
        XCTAssertTrue(r.out.contains("work「\(e.citekey)」") && r.out.contains(LegacyCopyLeft.laterWriteRefusedNote),
                      "stdout 的列帶「之後的寫入沒有套用」：\(r.out)")
        let first = String(r.err.split(separator: "\n").first ?? "")
        XCTAssertTrue(first.hasPrefix("已寫入 1 筆、搬移後的 legacy 拷貝沒刪掉"), "stderr 第一行：\(r.err)")
        XCTAssertTrue(first.contains("其中 1 筆之後的寫入沒套用，那幾筆在拷貝處理掉之後要重跑才補得上"), first)
        XCTAssertTrue(first.contains("沒有錯誤訊息"), "沒有訊息的非零結束另說：\(first)")
        XCTAssertFalse(first.contains("不必為了自己重跑"), first)
    }
}

/// #705（使用者 2026-10-05 裁決）：結束碼 0、但同一個操作之後的寫入沒套用時，stderr 多印一行——結束碼 0 時使用者最可能不看 stdout 的報告。
/// 2026-10-05 走得到這一格的 CLI 命令只有 `import-zotero`（`LegacyCopyReport.successStderrLine` 的 doc 寫了為什麼）。造法同上一支
/// 非零結束的測試，少了共用 DOI 的那 10 筆：同一趟先清 orphan 標記（寫進 entities/、legacy 刪不掉），接著的書目更新被 #631 拒絕，以 0 結束。
extension ZoteroReportCLITests {
    /// 一筆 legacy work（`entries/` 唯讀、已 commit）；回傳它與還原權限的 closure。權限擋不住刪檔（以 root 執行）時 skip。
    private func legacyWorkWithUndeletableCopy(orphaned: Bool) throws -> (entry: Entry, restore: () -> Void) {
        let store = LibraryStore(root: root)
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        var e = Entry(id: UUID(), citekey: "legacy2025identifiability", type: .periodicalArticle, title: "舊標題")
        e.provenance = Provenance(zoteroKey: "KEYART01", zoteroVersion: 1, libraryID: 1, orphanedAt: orphaned ? gone : nil)
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.entriesDir.path)
        let restore = { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }
        let probe = store.entriesDir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            restore()
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
        return (e, { _ = restore() })
    }

    func testAnExitZeroImportWithANotAppliedLaterWriteSaysSoOnStderr() throws {
        let (e, restore) = try legacyWorkWithUndeletableCopy(orphaned: true)
        defer { restore() }
        let r = try runSplit(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, "前提：以 0 結束：\(r.out)\n\(r.err)")
        XCTAssertTrue(r.out.contains("work「\(e.citekey)」") && r.out.contains(LegacyCopyLeft.laterWriteRefusedNote),
                      "前提：stdout 的列帶「之後的寫入沒有套用」：\(r.out)")
        let lines = r.err.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 1, "恰好一行：\(r.err)")
        let line = lines.first ?? ""
        XCTAssertTrue(line.hasPrefix("⚠ 結束碼 0，但有 1 筆之後的寫入沒套用"), line)
        XCTAssertTrue(line.contains("清單在 stdout 的 writtenWithLegacyCopy 段"), "說出去哪裡看：\(line)")
        XCTAssertTrue(line.contains("確認 entities/ 那份是新的之後刪掉 legacy 那份；那幾筆在拷貝處理掉之後要重跑才補得上"), "說出要重跑：\(line)")
        XCTAssertFalse(r.out.contains("⚠ 結束碼 0"), "那一行在 stderr、不混進 stdout 的報告")
    }

    /// 負面：同一趟只寫一次（沒有 orphan 標記，只有書目更新），legacy 拷貝刪不掉、沒有之後被拒的寫入——以 0 結束、stderr 什麼都不印。
    func testAnExitZeroImportWhoseWritesAllAppliedPrintsNothingOnStderr() throws {
        let (e, restore) = try legacyWorkWithUndeletableCopy(orphaned: false)
        defer { restore() }
        let r = try runSplit(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, "\(r.out)\n\(r.err)")
        XCTAssertTrue(r.out.contains("work「\(e.citekey)」"), "前提：留下 legacy 拷貝的那一筆在 stdout：\(r.out)")
        XCTAssertFalse(r.out.contains(LegacyCopyLeft.laterWriteRefusedNote), "前提：沒有之後被拒的寫入：\(r.out)")
        XCTAssertEqual(r.err, "", "全部套用時 stderr 什麼都不印")
    }
}

/// #700（使用者 2026-10-05 裁決第 1 項）：`import-zotero` 遇到讀不懂的 `.gitignore`（這裡是 Latin-1、沒有 sources 區塊）——不改寫它、
/// 照常匯入、以 0 結束，warning 在 stderr（stdout 是匯入報告）。匯入本身不寫 sources/：擋第三方存檔進版控的防線在 store-source，
/// 所以之後的 `store-source` 仍被擋（store 在 git 工作樹裡、sources/ 沒被排除）。b31 W5 到 b34 是在讀 zotero.sqlite 之前拒絕匯入。
extension ZoteroReportCLITests {
    func testImportWarnsOnStderrAndContinuesThenStoreSourceIsStillRefused() throws {
        let ignore = root.appendingPathComponent(".gitignore")
        let original = Data([0x23, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0A]) + Data("*.srt\n".utf8)
        try original.write(to: ignore)
        git(["init", "-q"])
        let r = try runSplit(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, "照常匯入：\(r.out)\n\(r.err)")
        XCTAssertTrue(r.out.contains("created: 1"), r.out)
        XCTAssertFalse(r.out.contains("⚠ .gitignore"), "warning 不混進 stdout 的報告：\(r.out)")
        let first = String(r.err.split(separator: "\n").first ?? "")
        XCTAssertTrue(first.hasPrefix("⚠ .gitignore 沒有 sources 排除區塊，import-zotero 沒有改寫它：") && first.contains("不是 UTF-8"), r.err)
        XCTAssertTrue(first.contains("匯入照常完成") && first.contains("store-source 拒絕寫入"), "說出防線在哪：\(first)")
        XCTAssertTrue(r.err.contains("\n    sources/\n"), "附上要自己加的那段：\(r.err)")
        XCTAssertEqual(try Data(contentsOf: ignore), original, ".gitignore 逐位元組不變")

        let pdf = fakeHome.appendingPathComponent("third-party.pdf")
        try Data("third-party bytes".utf8).write(to: pdf)
        let s = try runSplit(["store-source", pdf.path, "--media-type", "application/pdf", "--retrieved", "2026-10-05",
                              "--origin", "https://example.org/x.pdf", "--acquisition", "browser-download"])
        XCTAssertNotEqual(s.status, 0, "store-source 仍被擋：\(s.out)\n\(s.err)")
        XCTAssertTrue(s.err.contains("sources/ 未被版控忽略"), s.err)
        let blobs = (try? FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("sources").path)) ?? []
        XCTAssertEqual(blobs.filter { !$0.hasPrefix(".") }, [], "拒寫時不留任何位元組")
    }

    /// 負面：`.gitignore` 正常（setUp 的 ensureLayout 已加上區塊）時 stderr 什麼都不印。
    func testImportWithAWellFormedGitignorePrintsNothingOnStderr() throws {
        let r = try runSplit(["import-zotero", "--zotero-db", zoteroDB.path])
        XCTAssertEqual(r.status, 0, "\(r.out)\n\(r.err)")
        XCTAssertEqual(r.err, "", "沒有 warning")
    }
}
