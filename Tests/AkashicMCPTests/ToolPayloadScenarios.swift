import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// 一次真實呼叫：哪個工具的哪一條腿、預期回什麼形狀、怎麼呼叫。
///
/// `expects` 是守衛自己的護欄——情境若因為 fixture 漂移而悄悄退成錯誤訊息或純文字，`.object` 的預期會讓它紅，
/// 而不是讓「零個鍵」被當成「全部有描述」。
struct PayloadScenario {
    enum Kind { case object, array, text }
    let tool: String
    let leg: String
    let expects: Kind
    let run: (PayloadWorld) throws -> String

    init(_ tool: String, _ leg: String, _ expects: Kind = .object, run: @escaping (PayloadWorld) throws -> String) {
        self.tool = tool; self.leg = leg; self.expects = expects; self.run = run
    }
}

/// 全部情境。每個工具至少一條主要的腿；一個工具有多種回應形狀時（乾跑／實跑、各寫入腿）每種形狀一個情境。
///
/// **做不到的腿**（守衛沒有涵蓋，見報告）：
/// - `akashic_files` 的 `use`：切換 session 的 active store，需要 registry；`list` 有涵蓋。
/// - 需要外部網路或使用者本機資料的分支：本檔全部用本機 fixture，不打網路。
enum ToolPayloadScenarios {
    static let all: [PayloadScenario] = reading + entries + libraries + persons + venues + organizations + divergences + imports + resolvePeople + resolveVenues + resolveOrganizations + s2

    private static let firstEntry = "cheng2025identifiability"

    // MARK: - 讀取面

    static let reading: [PayloadScenario] = [
        PayloadScenario("akashic_search", "journal", .array) { try $0.service.search(journal: "Psychometrika") },
        PayloadScenario("akashic_get_entry", "citekey") { try $0.service.getEntry(citekey: firstEntry) },
        PayloadScenario("akashic_get_entry", "with identifiers") {
            let made = try $0.object(try $0.service.createEntry(type: "periodical-article", title: "With identifiers", authors: [], date: "2026",
                                                                fields: [:], doi: ["10.1000/guard.2"], pmid: ["87654321"], isbn: nil))
            return try $0.service.getEntry(citekey: try XCTUnwrap(made["citekey"] as? String))
        },
        PayloadScenario("akashic_relations", "cites", .array) { try $0.service.relations(citekey: firstEntry, kind: "cites") },
        PayloadScenario("akashic_graph", "mermaid", .text) { try $0.service.graph(focus: firstEntry, depth: 1, format: "mermaid") },
        PayloadScenario("akashic_export", "bib", .text) { try $0.service.export(citekeys: nil, format: "bib") },
        PayloadScenario("akashic_export", "csl-json", .array) { try $0.service.export(citekeys: nil, format: "csl-json") },
        PayloadScenario("akashic_people", "all", .array) { try $0.service.people(query: nil) },
        PayloadScenario("akashic_doctor", "report") { try $0.service.doctor() },
        PayloadScenario("akashic_doctor", "owner") { try $0.service.recordIssueDetail(owner: "person:cheng-che") },
        PayloadScenario("akashic_doctor", "owner with issues") {
            try $0.dirtyStore()
            return try $0.service.recordIssueDetail(owner: "work:dupedge2020")
        },
        PayloadScenario("akashic_doctor", "dirty store") {
            try $0.dirtyStore()
            return try $0.service.doctor()
        },
        PayloadScenario("akashic_doctor", "fatal cross-record") {
            try $0.duplicateCitekey()
            return try $0.service.doctor()
        },
        PayloadScenario("akashic_files", "list") { try $0.service.files(action: "list", key: nil) },
        PayloadScenario("akashic_person", "key") { try $0.service.person(key: "cheng-che", name: nil, library: nil) },
        PayloadScenario("akashic_person", "name") { try $0.service.person(key: nil, name: "Desc", library: nil) },
        PayloadScenario("akashic_venue", "key") { try $0.service.venue(key: "psychometrika") },
        PayloadScenario("akashic_venues", "all") { try $0.service.venues() },
        PayloadScenario("akashic_divergences", "all") { try $0.service.listDivergences() },
    ]

    // MARK: - work 的寫入面

    static let entries: [PayloadScenario] = [
        PayloadScenario("akashic_set_status", "set") { try $0.service.setStatus(citekey: firstEntry, status: "reading") },
        PayloadScenario("akashic_set_status", "clear") {
            _ = try $0.service.setStatus(citekey: firstEntry, status: "reading")
            return try $0.service.setStatus(citekey: firstEntry, status: nil, clear: true)
        },
        PayloadScenario("akashic_tag", "add") { try $0.service.tag(citekey: firstEntry, add: ["new-tag"], remove: ["identifiability"]) },
        PayloadScenario("akashic_link", "cites") { try $0.service.link(citekey: firstEntry, kind: "cites", add: ["desc2020"], remove: []) },
        PayloadScenario("akashic_create_entry", "plain") {
            try $0.service.createEntry(type: "periodical-article", title: "Created by the guard", authors: ["Guard Author"], date: "2026",
                                       fields: ["journaltitle": "Psychometrika"])
        },
        PayloadScenario("akashic_create_entry", "identifiers") {
            try $0.service.createEntry(type: "periodical-article", title: "With identifiers", authors: [], date: "2026", fields: [:],
                                       doi: ["10.1000/guard.1"], pmid: ["12345678"], isbn: nil)
        },
        PayloadScenario("akashic_update_entry", "remove_fields dry_run") {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: ["abstract=錯誤頁被當成摘要收下"], dryRun: true)
        },
        PayloadScenario("akashic_update_entry", "remove_fields apply") {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: ["abstract=錯誤頁被當成摘要收下"], dryRun: false)
        },
        PayloadScenario("akashic_update_entry", "add_sources dry_run") {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, addSources: [try $0.storeDigest()], dryRun: true)
        },
        PayloadScenario("akashic_update_entry", "add_sources apply") {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, addSources: [try $0.storeDigest()], dryRun: false)
        },
        PayloadScenario("akashic_update_entry", "remove_sources") {
            let d = try $0.storeDigest()
            _ = try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, addSources: [d], dryRun: false)
            $0.commit()
            return try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, removeSources: ["\(d)=這份不是這篇"], dryRun: false)
        },
        PayloadScenario("akashic_store_source", "file") { try $0.storedSourceReceipt() },
        PayloadScenario("akashic_enrich", "dry_run") {
            try $0.service.enrich(proposals: [.init(citekey: "desc2020", fields: ["abstract": "補上的摘要"])],
                                  dryRun: true, includeAbsentAuthors: false, itemLimit: 20)
        },
        PayloadScenario("akashic_enrich", "apply with provenance") {
            let digest = try $0.storeDigest()
            return try $0.service.enrich(
                proposals: [.init(citekey: "desc2020", fields: ["abstract": "補上的摘要"], date: "2020", authors: ["Some One"],
                                  sourceDigest: digest, sourceURL: "https://example.org/x", sourceRetrieved: "2026-09-29",
                                  sourceStatus: 200)],
                dryRun: false, includeAbsentAuthors: true, itemLimit: 20)
        },
        PayloadScenario("akashic_enrich", "ambiguous and not found") {
            try $0.service.enrich(proposals: [.init(citekey: "no-such-key", fields: ["abstract": "x"]),
                                              .init(doi: "10.1000/none", fields: ["abstract": "y"])],
                                  dryRun: true, includeAbsentAuthors: false, itemLimit: 20)
        },
    ]

    // MARK: - library

    static let libraries: [PayloadScenario] = [
        PayloadScenario("akashic_libraries", "list", .array) {
            _ = try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: "d", citekey: nil,
                                         membership: .init(kind: "topic"))
            return try $0.service.libraries(action: "list", key: nil, name: nil, description: nil, citekey: nil)
        },
        PayloadScenario("akashic_libraries", "create") {
            try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: nil, citekey: nil,
                                     membership: .init(kind: "topic"))
        },
        PayloadScenario("akashic_libraries", "add") {
            _ = try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: nil, citekey: nil,
                                         membership: .init(kind: "topic"))
            return try $0.service.libraries(action: "add", key: "reading", name: nil, description: nil, citekey: firstEntry)
        },
        PayloadScenario("akashic_libraries", "remove") {
            _ = try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: nil, citekey: nil,
                                         membership: .init(kind: "topic"))
            _ = try $0.service.libraries(action: "add", key: "reading", name: nil, description: nil, citekey: firstEntry)
            return try $0.service.libraries(action: "remove", key: "reading", name: nil, description: nil, citekey: firstEntry)
        },
        PayloadScenario("akashic_libraries", "set-kind") {
            _ = try $0.service.libraries(action: "create", key: "psychometrika-all", name: "Psychometrika", description: nil, citekey: nil,
                                         membership: .init(kind: "topic"))
            $0.commit()   // set-kind 整值替換既有規則，要求 registry 檔已 commit
            return try $0.service.libraries(action: "set-kind", key: "psychometrika-all", name: nil, description: nil, citekey: nil,
                                            membership: .init(kind: "rule", venue: "psychometrika"))
        },
        PayloadScenario("akashic_libraries", "check") {
            _ = try $0.service.libraries(action: "create", key: "psychometrika-all", name: "Psychometrika", description: nil, citekey: nil,
                                         membership: .init(kind: "topic"))
            _ = try $0.service.libraries(action: "add", key: "psychometrika-all", name: nil, description: nil, citekey: firstEntry)
            $0.commit()
            _ = try $0.service.libraries(action: "set-kind", key: "psychometrika-all", name: nil, description: nil, citekey: nil,
                                         membership: .init(kind: "rule", venue: "psychometrika"))
            return try $0.service.libraries(action: "check", key: "psychometrika-all", name: nil, description: nil, citekey: nil)
        },
    ]

    // MARK: - person／organization 的建檔與更新

    static let persons: [PayloadScenario] = [
        PayloadScenario("akashic_add_person", "plain") {
            try $0.service.addPerson(key: "new-person", names: ["New Person"], orcid: "0000-0002-1825-0097", openalex: nil)
        },
        PayloadScenario("akashic_update_person", "dry_run") {
            try $0.service.updatePerson(key: "cheng-che", fields: ["note": "guard"], dryRun: true)
        },
        PayloadScenario("akashic_update_person", "apply") {
            try $0.service.updatePerson(key: "cheng-che", fields: ["note": "guard"], dryRun: false)
        },
    ]

    static let organizations: [PayloadScenario] = [
        PayloadScenario("akashic_add_organization", "plain") {
            try $0.service.addOrganization(key: "new-org", names: ["New Org"], parentKey: "global-research-institute", note: "n",
                                           ror: "https://ror.org/05dxps055")
        },
    ]

    // MARK: - 歧異記錄

    static let divergences: [PayloadScenario] = [
        PayloadScenario("akashic_record_divergence", "plain") {
            try $0.service.recordDivergence(question: "另兩筆是同一人嗎", candidates: ["cheng-che:person", "desc-solo:person"],
                                            judgement: nil, restsOn: [])
        },
        PayloadScenario("akashic_record_divergence", "with judgement") {
            let digest = try $0.storeDigest()
            return try $0.service.recordDivergence(question: "另兩筆是同一人嗎", candidates: ["cheng-che:person", "desc-solo:person"],
                                                   judgement: "同一人", restsOn: [digest], prefers: "cheng-che")
        },
        PayloadScenario("akashic_dismiss_divergence", "dry_run") {
            try $0.service.dismissDivergence(id: try $0.onlyDivergenceID(), reason: "候選記錯了", dryRun: true)
        },
        PayloadScenario("akashic_dismiss_divergence", "apply") {
            try $0.service.dismissDivergence(id: try $0.onlyDivergenceID(), reason: "候選記錯了", dryRun: false)
        },
    ]

    // MARK: - 匯入

    static let imports: [PayloadScenario] = [
        PayloadScenario("akashic_import_zotero", "created") {
            let z = try PayloadZoteroDB(dir: $0.dir)
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        PayloadScenario("akashic_import_zotero", "ambiguous source claims") {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            try $0.duplicateFirstZoteroEntry()
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        // #696 R1 verify：pull 拿掉的欄位與覆寫的未歸戶作者要出現在 MCP payload（authorsOverwritten／fieldsRemovedByPull）
        PayloadScenario("akashic_import_zotero", "pull overwrites") {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            var imported = try XCTUnwrap(try $0.store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
            imported.fields["note"] = "hand-added"
            imported.authors = [.literal("Someone Else")]
            imported.provenance?.zoteroHash = "stale"
            try $0.store.writeEntry(imported)
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        PayloadScenario("akashic_enrich_from_zotero", "dry_run") {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            let imported = try $0.store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }
            return try $0.service.enrichFromZotero(citekeys: [try XCTUnwrap(imported).citekey, "no-such-key"],
                                                   zoteroDb: z.url.path, libraryID: nil, dryRun: true)
        },
        PayloadScenario("akashic_enrich_from_zotero", "apply") {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            var imported = try XCTUnwrap(try $0.store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
            imported.fields["journaltitle"] = nil   // Zotero 有、store 缺——補值面才有東西補
            try $0.store.writeEntry(imported)
            return try $0.service.enrichFromZotero(citekeys: [imported.citekey], zoteroDb: z.url.path, libraryID: nil, dryRun: false)
        },
        PayloadScenario("akashic_import_wos", "created") {
            try $0.service.importWoS(path: try $0.woSFile(), csv: false, dryRun: false)
        },
        PayloadScenario("akashic_import_wos", "dry_run") {
            try $0.service.importWoS(path: try $0.woSFile(), csv: false, dryRun: true)
        },
    ]
}

extension PayloadWorld {
    func storedSourceReceipt() throws -> String {
        let f = dir.appendingPathComponent("receipt-\(UUID().uuidString).pdf")
        try Data("receipt".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        return try service.storeSource(path: f.path, mediaType: "application/pdf", retrieved: "2026-09-29T10:00:00+08:00",
                                       origin: "https://example.org/x.pdf", acquisition: "browser-download", note: nil)
    }

    func onlyDivergenceID() throws -> String {
        try XCTUnwrap(try store.load().divergences.first).id.uuidString
    }

    /// 為第一次匯入的那筆 Zotero entry 寫一筆同來源的複本——第二次匯入會回報 `ambiguousSourceClaims`。
    func duplicateFirstZoteroEntry() throws {
        let original = try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
        var twin = original
        twin.id = UUID()
        twin.citekey = "\(original.citekey)twin"
        try store.writeEntry(twin)
    }

    /// 一份最小的 WoS 匯出（tab-delimited）。
    func woSFile() throws -> String {
        let cols = ["Authors", "Article Title", "Publication Year", "Source Title", "DOI"]
        let row = ["Hsu, Y-F", "Weber Study", "2021", "JMP", "10.1/guard-\(UUID().uuidString.prefix(8))"]
        let url = dir.appendingPathComponent("wos-\(UUID().uuidString).txt")
        try ([cols.joined(separator: "\t"), row.joined(separator: "\t")]).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}

extension PayloadWorld {
    /// doctor 的非致命問題各來一個：per-record 警告（同一 venue 兩條 key 邊）、被隔離的檔、帶未知欄位的檔、
    /// 存檔審計（有 blob 沒有 index）、佈局殘留（空的 notes/）、已故而隸屬未結束的人。
    func dirtyStore() throws {
        var dup = Entry(id: UUID(), citekey: "dupedge2020", type: .periodicalArticle, title: "Two edges", date: "2020")
        dup.venues = [.key("psychometrika"), .key("psychometrika")]
        try store.writeEntry(dup)
        var late = Person(key: "late-one", names: PersonNames(variant: ["Late One"]))
        late.died = "2020"
        late.profile.affiliations = TimelineOf([TemporalValue(value: .literal("Some Institute"))])
        try store.writePerson(late)
        let entities = root.appendingPathComponent("entities")
        try Data("::: not yaml [".utf8).write(to: entities.appendingPathComponent("\(UUID().uuidString).yaml"))
        for name in try FileManager.default.contentsOfDirectory(atPath: entities.path) {
            let url = entities.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains("key: desc-solo") else { continue }
            try (text + "\nfuture-field: 1\n").write(to: url, atomically: true, encoding: .utf8)
        }
        _ = try storeDigest()
        try FileManager.default.removeItem(at: root.appendingPathComponent("sources/index.jsonl"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: false)   // 佈局殘留：空的 notes/
    }

    /// 兩筆同 citekey 的 work：致命的跨記錄問題，doctor 不重建 index。
    func duplicateCitekey() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "desc2020", type: .periodicalArticle, title: "Same citekey", date: "2020"))
    }
}
