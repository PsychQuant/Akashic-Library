import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import AkashicSQLite

final class ServiceTests: XCTestCase {
    var root: URL!
    var service: AkashicService!

    /// #37：index 現在住在 `$AKASHIC_HOME/index/<key>.sqlite`。測試必須注入假 home——
    /// 否則會寫進**使用者真實的** `~/.akashic/index/`（實測發生過，留下 `other.sqlite`）。
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-svc-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        // fixture 手寫原始檔進 entries/、people/，需自己宣告 legacy 目錄（#101）
        for sub in ["entries", "people"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article",
                       title: "Identifiability of polychoric models",
                       authors: [.key("cheng-che"), .literal("Hau-Hung Yang")], date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        e1.akashic.tags = ["identifiability"]
        e1.akashic.relations.cites = ["olsson1979maximum"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "olsson1979maximum", type: "article",
                       title: "Maximum likelihood estimation", authors: [.literal("Ulf Olsson")], date: "1979")
        e2.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e2)
        // #81：對外顯示名由 `authorized` 指定，`names` 的順序不再帶語意。
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"],
                                     authorized: ["Che Cheng", "鄭澈"]))
        service = AkashicService(root: root, environment: env)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func json(_ s: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(s.utf8))
    }

    func testSearchByJournal() throws {
        let out = try service.search(journal: "Psychometrika")
        let arr = try json(out) as! [[String: Any]]
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr.first?["citekey"] as? String, "cheng2025identifiability")
    }

    func testGetEntryIncludesAkashicNamespace() throws {
        let out = try service.getEntry(citekey: "cheng2025identifiability")
        let obj = try json(out) as! [String: Any]
        let akashic = obj["akashic"] as! [String: Any]
        XCTAssertEqual(akashic["tags"] as? [String], ["identifiability"])
        XCTAssertThrowsError(try service.getEntry(citekey: "nope"))
    }

    func testRelationsKinds() throws {
        let cites = try json(try service.relations(citekey: "cheng2025identifiability", kind: "cites")) as! [[String: Any]]
        XCTAssertEqual(cites.first?["citekey"] as? String, "olsson1979maximum")
        let sameJournal = try json(try service.relations(citekey: "cheng2025identifiability", kind: "same-journal")) as! [[String: Any]]
        XCTAssertEqual(sameJournal.count, 1)
        XCTAssertThrowsError(try service.relations(citekey: "cheng2025identifiability", kind: "bogus"))
    }

    func testGraphMermaid() throws {
        let out = try service.graph(focus: "cheng2025identifiability", depth: 1, format: "mermaid")
        XCTAssertTrue(out.hasPrefix("graph LR"))
    }

    func testExportBibAndCSL() throws {
        let bib = try service.export(citekeys: ["cheng2025identifiability"], format: "bib")
        XCTAssertTrue(bib.contains("@ARTICLE{cheng2025identifiability,"))
        let csl = try service.export(citekeys: nil, format: "csl-json")
        XCTAssertEqual((try json(csl) as! [[String: Any]]).count, 2)
        XCTAssertThrowsError(try service.export(citekeys: ["nope"], format: "bib"))
    }

    func testPeopleQuery() throws {
        let all = try json(try service.people(query: nil)) as! [[String: Any]]
        XCTAssertEqual(all.count, 1)
        let hit = try json(try service.people(query: "鄭")) as! [[String: Any]]
        XCTAssertEqual(hit.first?["key"] as? String, "cheng-che")
    }

    func testDoctorStats() throws {
        let obj = try json(try service.doctor()) as! [String: Any]
        XCTAssertEqual(obj["entries"] as? Int, 2)
        XCTAssertEqual(obj["people"] as? Int, 1)
        XCTAssertEqual(obj["unresolvedAuthorLiterals"] as? Int, 2)
        XCTAssertNil(obj["unknownFieldFiles"], "無未知欄位時不 emit（與 quarantined 同慣例）")
    }

    // #23 tolerant-preserve：doctor 對含未知欄位（較新 schema）的檔案給計數提示
    func testDoctorReportsUnknownFieldFiles() throws {
        let f = root.appendingPathComponent("people/future-person.yaml")
        try """
        key: future-person
        names:
          - Future Person
        affiliations:
          - organization: ISS
        """.write(to: f, atomically: true, encoding: .utf8)
        let obj = try json(try service.doctor()) as! [String: Any]
        XCTAssertEqual(obj["people"] as? Int, 2, "新 schema 檔必須可用，不進 quarantine")
        XCTAssertNil(obj["quarantined"])
        XCTAssertEqual(obj["unknownFieldFiles"] as? [String], ["people/future-person.yaml"])
    }

    func testSetStatusPersistsAndReindexes() throws {
        _ = try service.setStatus(citekey: "olsson1979maximum", status: "reading")
        let store = LibraryStore(root: root)
        let entry = try store.load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(entry.akashic.status, "reading")
    }

    func testTagAddRemove() throws {
        _ = try service.tag(citekey: "olsson1979maximum", add: ["classic", "polychoric"], remove: [])
        _ = try service.tag(citekey: "olsson1979maximum", add: [], remove: ["classic"])
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(entry.akashic.tags, ["polychoric"])
    }

    func testLinkAddRemove() throws {
        _ = try service.link(citekey: "olsson1979maximum", kind: "related",
                             add: ["cheng2025identifiability"], remove: [])
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(entry.akashic.relations.related, ["cheng2025identifiability"])
        XCTAssertThrowsError(try service.link(citekey: "olsson1979maximum", kind: "bogus", add: ["x"], remove: []))
    }

    func testResolvePeopleListsAndAppliesSelectively() throws {
        let e3 = Entry(id: UUID(), citekey: "cheng2020analysis", type: "thesis",
                       title: "Analysis of growth curves", authors: [.literal("Che Cheng")], date: "2020")
        try LibraryStore(root: root).writeEntry(e3)
        let list = try json(try service.resolvePeople(apply: nil)) as! [[String: Any]]
        XCTAssertEqual(list.count, 1)
        let id = list.first?["id"] as? String ?? ""
        XCTAssertEqual(id, "cheng2020analysis:0")
        _ = try service.resolvePeople(apply: [id])
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "cheng2020analysis" }!
        XCTAssertEqual(entry.authors, [.key("cheng-che")])
        // 逐候選：Hau-Hung Yang（無 person）不受影響
        let e1 = try LibraryStore(root: root).load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(e1.authors[1], .literal("Hau-Hung Yang"))
    }

    func testCreateEntryGeneratesCitekeyAndPersists() throws {
        let out = try json(try service.createEntry(
            type: "article", title: "Manual reference entry",
            authors: ["Some Author"], date: "2024",
            fields: ["journaltitle": "Manual Journal"])) as! [String: Any]
        let citekey = out["citekey"] as? String ?? ""
        XCTAssertEqual(citekey, "author2024manual")
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == citekey }!
        XCTAssertNil(entry.provenance)   // 庫外文獻：無 provenance
    }

    func testAddPersonRejectsDuplicate() throws {
        _ = try service.addPerson(key: "yang-hau-hung", names: ["Hau-Hung Yang"], orcid: nil, openalex: nil)
        XCTAssertThrowsError(try service.addPerson(key: "cheng-che", names: ["X"], orcid: nil, openalex: nil))
    }

    func testIndexFreshnessAfterExternalWrite() throws {
        _ = try service.search(journal: "Psychometrika")   // 建 index
        var e3 = Entry(id: UUID(), citekey: "new2026entry", type: "article",
                       title: "Externally added", authors: [], date: "2026")
        e3.fields["journaltitle"] = "Psychometrika"
        try LibraryStore(root: root).writeEntry(e3)        // service 之外寫入
        let arr = try json(try service.search(journal: "Psychometrika")) as! [[String: Any]]
        XCTAssertEqual(arr.count, 3)                        // mtime stale → 自動重建
    }

    func testImportZoteroMissingDBFailsLoud() {
        XCTAssertThrowsError(try service.importZotero(zoteroDb: "/nonexistent/z.sqlite", libraryID: nil))
    }
}

// ── Verify R1 修復（#9）──

extension ServiceTests {
    // DA CONFIRMED HIGH：createEntry 不得覆寫 quarantined 檔
    func testCreateEntryNeverOverwritesQuarantinedFile() throws {
        let store = LibraryStore(root: root)
        let broken = "broken: [yaml\n"
        // 會與 createEntry 生成的 citekey（author2024manual）同名
        try broken.write(to: store.entriesDir.appendingPathComponent("author2024manual.yaml"),
                         atomically: true, encoding: .utf8)
        let out = try service.createEntry(type: "article", title: "Manual reference entry",
                                          authors: ["Some Author"], date: "2024", fields: [:])
        let citekey = (try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any])["citekey"] as! String
        XCTAssertEqual(citekey, "author2024bmanual")   // 讓位取衝突後綴
        XCTAssertEqual(try String(contentsOf: store.entriesDir.appendingPathComponent("author2024manual.yaml"),
                                  encoding: .utf8), broken)
    }

    // DA CONFIRMED HIGH：addPerson 不得覆寫 quarantined people 檔
    func testAddPersonNeverOverwritesQuarantinedFile() throws {
        let store = LibraryStore(root: root)
        let broken = "not: [valid person\n"
        try broken.write(to: store.peopleDir.appendingPathComponent("yang-hau-hung.yaml"),
                         atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.addPerson(key: "yang-hau-hung", names: ["Hau-Hung Yang"],
                                                   orcid: nil, openalex: nil))
        XCTAssertEqual(try String(contentsOf: store.peopleDir.appendingPathComponent("yang-hau-hung.yaml"),
                                  encoding: .utf8), broken)
    }

    // Codex/Logic CONFIRMED：外部刪檔後 freshness 要偵測到（目錄 mtime）
    //
    // #56：**檔案位置由 store 自己解析**，不寫死 legacy 路徑。原本假設
    // `entriesDir/<citekey>.yaml`，但新建的 store 走 entities 佈局（`entities/<uuid>.yaml`），
    // 於是刪不到檔。本測試要驗的是「外部刪檔 → freshness 偵測得到」，與佈局無關——
    // 讓它跑在**實際出貨格式**上比釘死 legacy 更有價值。
    func testFreshnessDetectsExternalDeletion() throws {
        _ = try service.search(journal: "Psychometrika")   // 建 index（2 筆）
        Thread.sleep(forTimeInterval: 1.1)                  // 目錄 mtime 秒級粒度
        let store = LibraryStore(root: root)
        let target = try XCTUnwrap(
            store.load().entries.first { $0.citekey == "olsson1979maximum" },
            "測試前提：store 內須有 olsson1979maximum")
        let targetURL = store.usesEntitiesLayout
            ? store.entityURL(id: target.id)
            : store.entryURL(citekey: target.citekey)
        try FileManager.default.removeItem(at: targetURL)
        let out = try service.search(journal: "Psychometrika")
        let arr = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [[String: Any]]
        XCTAssertEqual(arr.count, 1)
    }

    // get_entry 完整性：provenance 時間欄位入 JSON
    func testGetEntryIncludesProvenanceTimestamps() throws {
        let store = LibraryStore(root: root)
        var e = try store.load().entries.first { $0.citekey == "olsson1979maximum" }!
        e.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1,
                                  importedAt: Date(timeIntervalSince1970: 1_753_000_000),
                                  orphanedAt: Date(timeIntervalSince1970: 1_753_100_000))
        try store.writeEntry(e)
        let obj = try JSONSerialization.jsonObject(
            with: Data(try service.getEntry(citekey: "olsson1979maximum").utf8)) as! [String: Any]
        let prov = obj["provenance"] as! [String: Any]
        XCTAssertNotNil(prov["imported_at"])
        XCTAssertNotNil(prov["orphaned_at"])
    }
}

/// #13 多 library：akashic_libraries service handler + search 的 library 篩選。
extension ServiceTests {
    func testLibrariesLifecycleViaService() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        let list = try json(service.libraries(action: "list", key: nil, name: nil,
                                              description: nil, citekey: nil)) as! [[String: Any]]
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0]["key"] as? String, "sinica")
        XCTAssertEqual(list[0]["members"] as? Int, 0)

        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let hits = try json(service.search(library: "sinica")) as! [[String: Any]]
        XCTAssertEqual(hits.map { $0["citekey"] as! String }, ["cheng2025identifiability"])
        XCTAssertTrue((try json(service.search(library: "ghost")) as! [Any]).isEmpty)

        _ = try service.libraries(action: "remove", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        XCTAssertTrue((try json(service.search(library: "sinica")) as! [Any]).isEmpty)
    }

    func testLibrariesActionValidation() throws {
        XCTAssertThrowsError(try service.libraries(action: "bogus", key: nil, name: nil,
                                                   description: nil, citekey: nil))
        XCTAssertThrowsError(try service.libraries(action: "create", key: nil, name: "X",
                                                   description: nil, citekey: nil),
                             "create 缺 key 要拒")
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        XCTAssertThrowsError(try service.libraries(action: "create", key: "sinica", name: "重複",
                                                   description: nil, citekey: nil),
                             "重複 create 要拒")
        XCTAssertThrowsError(try service.libraries(action: "add", key: "ghostlib", name: nil,
                                                   description: nil, citekey: "cheng2025identifiability"),
                             "未知 library 要拒")
    }
}

/// #13 verify fix round：getEntry 含 libraries、dangling remove、create 驗證順序。
extension ServiceTests {
    func testGetEntryIncludesLibraries() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let entry = try json(service.getEntry(citekey: "cheng2025identifiability")) as! [String: Any]
        let akashic = entry["akashic"] as! [String: Any]
        XCTAssertEqual(akashic["libraries"] as? [String], ["sinica"],
                       "getEntry 必須回傳 membership（MCP 完整 entry 契約）")
    }

    func testRemoveWorksOnDanglingMembership() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        // registry 檔被手動刪除 → dangling membership；remove 仍須可清理
        try FileManager.default.removeItem(
            at: LibraryStore(root: root).libraryURL(key: "sinica"))
        _ = try service.libraries(action: "remove", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let entry = try json(service.getEntry(citekey: "cheng2025identifiability")) as! [String: Any]
        let akashic = entry["akashic"] as! [String: Any]
        XCTAssertNil(akashic["libraries"], "dangling membership 清掉後不應殘留")
    }

    func testCreateValidatesKeyBeforePathProbe() throws {
        // librariesDir/../oracle.yaml = root/oracle.yaml——存在性 oracle 的目標
        try "x".write(to: root.appendingPathComponent("oracle.yaml"),
                      atomically: true, encoding: .utf8)
        do {
            _ = try service.libraries(action: "create", key: "../oracle", name: "X",
                                      description: nil, citekey: nil)
            XCTFail("畸形 key 必須擲錯")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("不符合"),
                          "錯誤必須是 key 格式拒絕，不是洩漏路徑存在性的「已存在」：\(msg)")
        }
    }
}

/// DA must-fix #1/#7：MCP 側 stale-schema 自我修復 + getEntry 零 libraries case。
extension ServiceTests {
    func testServiceRecoversFromStaleSchemaIndex() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        // 模擬舊 binary 建的 index：砍新表 + 版本歸零
        let store = LibraryStore(root: root)
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: false)
        try db.execute("DROP TABLE entry_libraries")
        try db.execute("PRAGMA user_version = 0")
        let hits = try json(service.search(library: "sinica")) as! [[String: Any]]
        XCTAssertEqual(hits.map { $0["citekey"] as! String }, ["cheng2025identifiability"],
                       "MCP freshness 必須偵測 schema 過舊並重建，不得 no such table")
    }

    func testGetEntryOmitsLibrariesWhenEmpty() throws {
        let entry = try json(service.getEntry(citekey: "olsson1979maximum")) as! [String: Any]
        let akashic = (entry["akashic"] as? [String: Any]) ?? [:]
        XCTAssertNil(akashic["libraries"], "零 membership 時 key 省略（與 tags 慣例一致）")
    }
}

/// #14 人物檢索：person 聚合 handler。
extension ServiceTests {
    func testPersonByKeyAggregates() throws {
        let out = try json(service.person(key: "cheng-che", name: nil, library: nil)) as! [String: Any]
        XCTAssertEqual((out["person"] as? [String: Any])?["key"] as? String, "cheng-che")
        XCTAssertEqual((out["publications"] as? [[String: Any]])?.map { $0["citekey"] as! String },
                       ["cheng2025identifiability"])
        let co = out["co_authors"] as! [[String: Any]]
        XCTAssertEqual(co.first?["name"] as? String, "Hau-Hung Yang")
        XCTAssertEqual(co.first?["count"] as? Int, 1)
    }

    func testPersonByFuzzyNameReturnsCandidatesNeverAutoSelects() throws {
        let out = try json(service.person(key: nil, name: "cheng", library: nil)) as! [String: Any]
        let candidates = out["candidates"] as! [[String: Any]]
        XCTAssertTrue(candidates.contains { ($0["person_key"] as? String) == "cheng-che" })
        XCTAssertNil(out["publications"], "模糊名只回候選，絕不自動選定聚合")
    }

    func testPersonScopedByLibrary() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        let none = try json(service.person(key: "cheng-che", name: nil, library: "sinica")) as! [String: Any]
        XCTAssertTrue((none["publications"] as! [Any]).isEmpty, "未加入 library 前 scoped 應為空")
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let some = try json(service.person(key: "cheng-che", name: nil, library: "sinica")) as! [String: Any]
        XCTAssertEqual((some["publications"] as! [[String: Any]]).count, 1)
    }

    func testPersonValidation() throws {
        XCTAssertThrowsError(try service.person(key: nil, name: nil, library: nil), "key/name 至少其一")
        XCTAssertThrowsError(try service.person(key: "ghost-person", name: nil, library: nil), "未知 person 擲錯")
    }
}

/// #14 verify fix round：R1 findings 釘住。
extension ServiceTests {
    func testPersonRejectsEmptyAndBothInputs() throws {
        XCTAssertThrowsError(try service.person(key: nil, name: "", library: nil), "空白 name 拒絕")
        XCTAssertThrowsError(try service.person(key: "  ", name: nil, library: nil), "空白 key 拒絕")
        XCTAssertThrowsError(try service.person(key: "cheng-che", name: "cheng", library: nil),
                             "key 與 name 互斥")
    }

    func testPersonScopedCoAuthorsConsistentWithLibrary() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        // 未加入 library：scoped 聚合的 publications 與 co_authors 都必須為空（內部一致）
        let none = try json(service.person(key: "cheng-che", name: nil, library: "sinica")) as! [String: Any]
        XCTAssertTrue((none["publications"] as! [Any]).isEmpty)
        XCTAssertTrue((none["co_authors"] as! [Any]).isEmpty,
                      "co_authors 必須吃 library 過濾（聚合內部一致性）")
        // 存在性不受 scope 影響：record 存在 → 不 notFound（上面沒 throw 即證）
    }

    func testPersonExistenceUsesUnscopedPublications() throws {
        // 無 people record、只有 literal→無 key。改用有 record 的：刪 record 後靠全集 pubs 存在
        // 構造：person key 出現在 entry 但 people/ 無記錄
        var e = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        e.authors = [.key("olsson-ulf")]
        try LibraryStore(root: root).writeEntry(e)
        _ = try service.libraries(action: "create", key: "empty-lib", name: "空庫",
                                  description: nil, citekey: nil)
        // scoped 查詢：全集有著作 → 不得 notFound；scoped publications 空
        let out = try json(service.person(key: "olsson-ulf", name: nil, library: "empty-lib")) as! [String: Any]
        XCTAssertTrue((out["publications"] as! [Any]).isEmpty)
    }

    func testPersonResolvedCoAuthorNameIsHumanReadable() throws {
        // 讓 cheng-che 與另一個 resolved person 合著
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "yang-hau-hung", names: ["Hau-Hung Yang"],
                                     authorized: ["Hau-Hung Yang"]))
        var e = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        e.authors = [.key("cheng-che"), .key("yang-hau-hung")]
        try store.writeEntry(e)
        let out = try json(service.person(key: "cheng-che", name: nil, library: nil)) as! [String: Any]
        let co = out["co_authors"] as! [[String: Any]]
        XCTAssertEqual(co.first?["person_key"] as? String, "yang-hau-hung")
        XCTAssertEqual(co.first?["name"] as? String, "Hau-Hung Yang",
                       "resolved 合著者的 name 給人讀的名字，不是 key")
    }
}

/// #14 R2：篇數語意（per-entry 去重）+ truncated 標記。
extension ServiceTests {
    func testFuzzyCountsPublicationsNotOccurrences() throws {
        let store = LibraryStore(root: root)
        var e = try store.load().entries.first { $0.citekey == "olsson1979maximum" }!
        e.authors = [.literal("Dup Person"), .literal("Dup Person")]   // 同篇重複掛名
        try store.writeEntry(e)
        let out = try json(service.person(key: nil, name: "dup person", library: nil)) as! [String: Any]
        let c = (out["candidates"] as! [[String: Any]]).first!
        XCTAssertEqual(c["publications"] as? Int, 1, "同篇重複掛名只計一篇")
    }

    func testFuzzyTruncationFlag() throws {
        let store = LibraryStore(root: root)
        for i in 0..<55 {
            try store.writePerson(Person(key: String(format: "zz-person-%02d", i),
                                         names: ["Zz Common \(i)"]))
        }
        let out = try json(service.person(key: nil, name: "zz", library: nil)) as! [String: Any]
        XCTAssertEqual((out["candidates"] as! [Any]).count, 50)
        XCTAssertEqual(out["truncated"] as? Bool, true)
    }
}

/// #18 多檔案：akashic_files handler（list / use；session-scoped 切換）。
extension ServiceTests {
    private func makeSecondUniverse() throws -> (configURL: URL, otherRoot: URL) {
        let otherRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-svc-other-\(UUID().uuidString)")
        let store = LibraryStore(root: otherRoot)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "other2020paper", type: "article",
                                   title: "Another universe", authors: [.literal("Someone Else")],
                                   date: "2020"))
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-svc-cfg-\(UUID().uuidString).yaml")
        var config = AkashicConfig()
        config.files = ["origin": root.path, "other": otherRoot.path]
        config.current = "origin"
        try config.write(to: configURL)
        return (configURL, otherRoot)
    }

    func testFilesListShowsRegistryAndActiveRoot() throws {
        let (configURL, _) = try makeSecondUniverse()
        let svc = AkashicService(root: root, configURL: configURL, environment: env)
        let out = try json(svc.files(action: "list", key: nil)) as! [String: Any]
        let files = out["files"] as! [[String: Any]]
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(out["active_root"] as? String, root.path)
        XCTAssertTrue(files.contains { ($0["key"] as? String) == "other" })
    }

    func testFilesUseSwitchesUniverseCompletely() throws {
        let (configURL, otherRoot) = try makeSecondUniverse()
        let svc = AkashicService(root: root, configURL: configURL, environment: env)
        // 切換前：搜得到本 universe 的 entry
        XCTAssertTrue(try svc.search(journal: "Psychometrika").contains("cheng2025identifiability"))
        let out = try json(svc.files(action: "use", key: "other")) as! [String: Any]
        XCTAssertEqual(out["active_root"] as? String, otherRoot.path)
        // 切換後：互不相通——舊 universe 的內容看不到、新 universe 的看得到
        let all = try svc.search()
        XCTAssertTrue(all.contains("other2020paper"), all)
        XCTAssertFalse(all.contains("cheng2025identifiability"), "互不相通：舊 universe 內容不得洩入")
    }

    func testFilesUseValidation() throws {
        let (configURL, _) = try makeSecondUniverse()
        let svc = AkashicService(root: root, configURL: configURL, environment: env)
        XCTAssertThrowsError(try svc.files(action: "use", key: "ghost"), "未註冊 key 擲錯")
        XCTAssertThrowsError(try svc.files(action: "use", key: nil), "use 缺 key 擲錯")
        XCTAssertThrowsError(try svc.files(action: "teleport", key: nil), "未知 action 擲錯")
    }
}

// R9（R8-verify M15）：resolve-people 的 per-item 收容契約 regression
extension ServiceTests {
    func testResolvePeopleContainsWriteFailurePerItem() throws {
        // 凍結記錄（decode 容忍、encode 平移不變式拒寫）+ literal 作者可解析
        let frozen = """
        id: 7C1F6C2E-0000-0000-0000-00000000CC01
        citekey: frozen3
        type: article
        title: T
        authors:
          - literal: Che Cheng
        akashic:
            tags:
            - keep
            weird: [a,
          b]
        """
        try (frozen + "\n").write(
            to: root.appendingPathComponent("entries/frozen3.yaml"),
            atomically: true, encoding: .utf8)
        let list = try json(try service.resolvePeople(apply: nil)) as! [[String: Any]]
        let ids = list.compactMap { $0["id"] as? String }
        XCTAssertTrue(ids.contains("frozen3:0"), "\(ids)")
        let out = try json(try service.resolvePeople(apply: ["frozen3:0"])) as! [String: Any]
        // 收容：不 throw、writeFailed 記錄、applied 不誇報
        let failed = out["writeFailed"] as? [String: String]
        XCTAssertNotNil(failed?["frozen3"], "\(out)")
        XCTAssertEqual(out["applied"] as? [String], [])
        XCTAssertEqual(out["entriesRewritten"] as? Int, 0)
        // 磁碟原封不動（fail-closed 不毀檔）
        let onDisk = try String(
            contentsOf: root.appendingPathComponent("entries/frozen3.yaml"), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("- literal: Che Cheng"))
    }
}

/// #77 層次 2：MCP 面的歧異記錄入口——LLM 驅動的資料補完流程正是 #71 診斷裡
/// 「七次歧異全部在寫入前被判斷掉」的實際發生點，MCP 記不了歧異等於逼流程
/// 當場判斷。刻意**不**提供 MCP 版 resolve（消歧含合併＋刪檔，屬人工確認面）。
final class ServiceRecordDivergenceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-divsvc-\(UUID().uuidString)")
        let store = LibraryStore(root: root, key: nil,
                                 environment: ["AKASHIC_HOME": fakeHome.path])
        try store.ensureLayout()
        try store.writePerson(Person(key: "chen-h-y", names: ["Chen, H.-Y."]))
        try store.writePerson(Person(key: "chen-hui-yun", names: ["Chen, Hui-Yun"]))
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    func testRecordDivergenceWritesRecord() throws {
        let out = try service.recordDivergence(
            question: "縮寫 H.-Y. 是否即 Hui-Yun",
            candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: [])
        XCTAssertTrue(out.contains("id"), "回傳要含記錄 id：\(out)")
        let load = try LibraryStore(root: root, key: nil,
                                    environment: ["AKASHIC_HOME": fakeHome.path]).load()
        XCTAssertEqual(load.divergences.count, 1)
        XCTAssertEqual(load.divergences.first?.candidates.map(\.key).sorted(),
                       ["chen-h-y", "chen-hui-yun"])
    }

    func testRecordDivergenceRejectsSingleCandidate() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:person"], judgement: nil, restsOn: []))
    }

    func testRecordDivergenceRejectsJudgementWithoutBasis() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: "同一人", restsOn: []),
            "判斷與依據必須成對（#71 不變式）——MCP 面與 CLI 同紀律")
    }

    func testRecordDivergenceRejectsMalformedCandidateSpec() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y", "chen-hui-yun:person"],
            judgement: nil, restsOn: []),
            "候選格式 key:shape——與 CLI 同格式，錯格式要指明")
    }

    /// #133 verify F1：同組候選 re-record 的三態——補寫允許、更新允許、毀損拒絕。
    func testRecordDivergenceRefusesToSilentlyEraseJudgement() throws {
        _ = try service.recordDivergence(
            question: "q1", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: "同一人", restsOn: ["https://example.org/roster"])
        // 有→nil：拒絕（曾經靜默抹掉判斷與 question）
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q2", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: [])) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(m.contains("判斷") && !m.contains("不符合"),
                          "要指明既有判斷會被抹掉、且不得套 key-pattern 框架：\(m)")
        }
        // 有→有：更新允許
        XCTAssertNoThrow(try service.recordDivergence(
            question: "q3", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: "仍同一人，另據", restsOn: ["https://example.org/other"]))
    }

    /// #133 verify F2：shape 說是什麼就到那個形狀的集合驗——person 記成 work 拒絕；
    /// 真正的 work（citekey）從此可用（曾因 known 漏掉 entries 而結構上不可用）。
    func testRecordDivergenceValidatesShapeMembership() throws {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:work", "chen-hui-yun:work"],
            judgement: nil, restsOn: []),
            "person 的 key 記成 work＝寫出一筆永遠無法消歧的記錄，必須當場拒絕")
    }

    /// #133 verify F3：拒絕訊息不得套「不符合 key 正規式」的假框架。
    func testRecordDivergenceErrorsDoNotClaimKeyPatternViolation() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:person"], judgement: nil, restsOn: [])) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertFalse(m.contains("不符合"),
                           "候選數不足與 key 語法無關——框架錯了 LLM 會去清洗 key：\(m)")
        }
    }

    func testRecordDivergenceRejectsUnknownCandidate() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["ghost-person:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: []),
            "對不存在的鍵記歧異沒有意義（store 層既有守衛，經 MCP 面透傳）")
    }
}

/// #76：「承載必須可觀察」的 MCP 面——#71 第 7 條只在 CLI 落實，#133 之後
/// MCP 能寫歧異卻仍看不見它（寫得進、看不見比純粹看不見更糟——#133 verify F2
/// 實測：MCP 寫出 validate 會警告的記錄，警告只在 CLI 面出現）。
final class ServiceObservabilityTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-obs-\(UUID().uuidString)")
        let store = LibraryStore(root: root, key: nil,
                                 environment: ["AKASHIC_HOME": fakeHome.path])
        try store.ensureLayout()
        try store.writePerson(Person(key: "chen-h-y", names: ["Chen, H.-Y."]))
        try store.writePerson(Person(key: "chen-hui-yun", names: ["Chen, Hui-Yun"]))
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
        _ = try service.recordDivergence(
            question: "縮寫是否同一人", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: [])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    func testDoctorReportsDivergenceCount() throws {
        let out = try service.doctor()
        XCTAssertTrue(out.contains("\"divergences\""),
                      "MCP doctor 要與 CLI 對齊——同一個 store 不得從兩個 consumer 看到不同的事實：\(out)")
    }

    func testDoctorReportsCrossRecordIssues() throws {
        // 構造一筆跨記錄問題：歧異候選指向的 person 刪掉 → 懸空
        try FileManager.default.removeItem(
            at: try XCTUnwrap(FileManager.default
                .contentsOfDirectory(at: root.appendingPathComponent("entities"),
                                     includingPropertiesForKeys: nil)
                .first { url in
                    (try? String(contentsOf: url, encoding: .utf8))?.contains("chen-h-y") == true
                        && (try? String(contentsOf: url, encoding: .utf8))?.contains("divergence") != true
                }))
        let out = try service.doctor()
        XCTAssertTrue(out.contains("crossRecordIssues"),
                      "跨記錄警告（含「歧異無法被消歧」）不得只在 CLI 面可見：\(out)")
    }

    func testDivergencesListTool() throws {
        let out = try service.listDivergences()
        XCTAssertTrue(out.contains("縮寫是否同一人"), "list 要含 question：\(out)")
        XCTAssertTrue(out.contains("chen-h-y"), "list 要含候選鍵：\(out)")
        XCTAssertTrue(out.contains("hasJudgement"), "\(out)")
    }
}
