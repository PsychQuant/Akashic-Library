import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

final class ServiceTests: XCTestCase {
    var root: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-svc-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
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
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"]))
        service = AkashicService(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
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
        var e3 = Entry(id: UUID(), citekey: "cheng2020analysis", type: "thesis",
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
    func testFreshnessDetectsExternalDeletion() throws {
        _ = try service.search(journal: "Psychometrika")   // 建 index（2 筆）
        Thread.sleep(forTimeInterval: 1.1)                  // 目錄 mtime 秒級粒度
        try FileManager.default.removeItem(
            at: LibraryStore(root: root).entriesDir.appendingPathComponent("olsson1979maximum.yaml"))
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
