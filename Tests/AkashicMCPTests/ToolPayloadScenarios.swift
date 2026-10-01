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
    /// 這個情境**最後那一次呼叫**傳的引數對應到哪些 MCP 參數（#700）。`action=create` 表示那個參數的某一個值；
    /// 覆蓋判定只看 `=` 之前的參數名。前置的呼叫（先建一筆、先 apply 一次）不算。
    ///
    /// 這是**宣告**：情境直接呼叫 `AkashicService`、不經 MCP 的引數解碼，守衛驗得到「參數名在真 binary 的 schema 裡」，
    /// 驗不到「情境真的傳了它」。
    let params: Set<String>
    let run: (PayloadWorld) throws -> String

    init(_ tool: String, _ leg: String, _ expects: Kind = .object, params: [String] = [],
         run: @escaping (PayloadWorld) throws -> String) {
        self.tool = tool; self.leg = leg; self.expects = expects; self.params = Set(params); self.run = run
    }
}

/// 全部情境。每個工具至少一條主要的腿；一個工具有多種回應形狀時（乾跑／實跑、各寫入腿）每種形狀一個情境。
/// 每個情境在 `params` 宣告它走的 MCP 參數：工具的每個參數都要有情境宣告，或在 `ToolPayloadLegs.unexercised` 寫理由（#700）。
///
/// **做不到的腿**（守衛沒有涵蓋，見報告）：
/// - `akashic_files` 的 `use`：切換 session 的 active store，需要 registry；`list` 有涵蓋。
/// - 需要外部網路或使用者本機資料的分支：本檔全部用本機 fixture，不打網路。
enum ToolPayloadScenarios {
    static let all: [PayloadScenario] = reading + entries + libraries + persons + venues + organizations + divergences + imports + resolvePeople + resolveVenues + resolveOrganizations + s2

    private static let firstEntry = "cheng2025identifiability"

    // MARK: - 讀取面

    static let reading: [PayloadScenario] = [
        PayloadScenario("akashic_search", "journal", .array, params: ["journal"]) { try $0.service.search(journal: "Psychometrika") },
        PayloadScenario("akashic_get_entry", "citekey", params: ["citekey"]) { try $0.service.getEntry(citekey: firstEntry) },
        PayloadScenario("akashic_get_entry", "with identifiers", params: ["citekey"]) {
            let made = try $0.object(try $0.service.createEntry(type: "periodical-article", title: "With identifiers", authors: [], date: "2026",
                                                                fields: [:], doi: ["10.1000/guard.2"], pmid: ["87654321"], isbn: nil))
            return try $0.service.getEntry(citekey: try XCTUnwrap(made["citekey"] as? String))
        },
        PayloadScenario("akashic_relations", "cites", .array, params: ["citekey", "kind"]) { try $0.service.relations(citekey: firstEntry, kind: "cites") },
        PayloadScenario("akashic_graph", "mermaid", .text, params: ["focus", "depth", "format"]) { try $0.service.graph(focus: firstEntry, depth: 1, format: "mermaid") },
        PayloadScenario("akashic_export", "bib", .text, params: ["format"]) { try $0.service.export(citekeys: nil, format: "bib") },
        PayloadScenario("akashic_export", "csl-json", .array, params: ["format"]) { try $0.service.export(citekeys: nil, format: "csl-json") },
        PayloadScenario("akashic_people", "all", .array) { try $0.service.people(query: nil) },
        PayloadScenario("akashic_doctor", "report") { try $0.service.doctor() },
        PayloadScenario("akashic_doctor", "owner", params: ["owner"]) { try $0.service.recordIssueDetail(owner: "person:cheng-che") },
        PayloadScenario("akashic_doctor", "owner with issues", params: ["owner"]) {
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
        PayloadScenario("akashic_files", "list", params: ["action=list"]) { try $0.service.files(action: "list", key: nil) },
        PayloadScenario("akashic_person", "key", params: ["key"]) { try $0.service.person(key: "cheng-che", name: nil, library: nil) },
        PayloadScenario("akashic_person", "name", params: ["name"]) { try $0.service.person(key: nil, name: "Desc", library: nil) },
        // #700 R1 verify 第 3、26 則：`person.orcid`（有 ORCID 才出現）與 `person.unknownFields`（帶較新 schema 欄位才出現）先前沒有情境產生，
        // 說明拿掉它們守衛照綠。`cheng-che` 兩個都沒有，所以另建一個帶 ORCID 與未知欄位的人。
        PayloadScenario("akashic_person", "key with orcid and unknown fields", params: ["key"]) {
            try $0.store.writePerson(Person(key: "orcid-unknown", names: ["Orcid Unknown"],
                                            orcid: try XCTUnwrap(ORCID("0000-0002-1825-0097")),
                                            unknownFields: [UnknownField(key: "future-field", raw: "future-field: 1\n")]))
            return try $0.service.person(key: "orcid-unknown", name: nil, library: nil)
        },
        PayloadScenario("akashic_venue", "key", params: ["key"]) { try $0.service.venue(key: "psychometrika") },
        PayloadScenario("akashic_venues", "all") { try $0.service.venues() },
        PayloadScenario("akashic_divergences", "all") { try $0.service.listDivergences() },
    ]

    // MARK: - work 的寫入面

    static let entries: [PayloadScenario] = [
        PayloadScenario("akashic_set_status", "set", params: ["citekey", "status"]) { try $0.service.setStatus(citekey: firstEntry, status: "reading") },
        PayloadScenario("akashic_set_status", "clear", params: ["citekey", "clear"]) {
            _ = try $0.service.setStatus(citekey: firstEntry, status: "reading")
            return try $0.service.setStatus(citekey: firstEntry, status: nil, clear: true)
        },
        PayloadScenario("akashic_tag", "add", params: ["citekey", "add", "remove"]) { try $0.service.tag(citekey: firstEntry, add: ["new-tag"], remove: ["identifiability"]) },
        PayloadScenario("akashic_link", "cites", params: ["citekey", "kind", "add", "remove"]) { try $0.service.link(citekey: firstEntry, kind: "cites", add: ["desc2020"], remove: ["olsson1979maximum"]) },
        PayloadScenario("akashic_create_entry", "plain", params: ["type", "title", "authors", "date", "fields"]) {
            try $0.service.createEntry(type: "periodical-article", title: "Created by the guard", authors: ["Guard Author"], date: "2026",
                                       fields: ["journaltitle": "Psychometrika"])
        },
        PayloadScenario("akashic_create_entry", "identifiers", params: ["type", "title", "date", "doi", "pmid", "isbn"]) {
            try $0.service.createEntry(type: "periodical-article", title: "With identifiers", authors: [], date: "2026", fields: [:],
                                       doi: ["10.1000/guard.1"], pmid: ["12345678"], isbn: ["9780306406157"])
        },
        PayloadScenario("akashic_update_entry", "remove_fields dry_run", params: ["citekey", "remove_fields", "dry_run"]) {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: ["abstract=錯誤頁被當成摘要收下"], dryRun: true)
        },
        PayloadScenario("akashic_update_entry", "remove_fields apply", params: ["citekey", "remove_fields", "dry_run"]) {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: ["abstract=錯誤頁被當成摘要收下"], dryRun: false)
        },
        PayloadScenario("akashic_update_entry", "add_sources dry_run", params: ["citekey", "add_sources", "dry_run"]) {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, addSources: [try $0.storeDigest()], dryRun: true)
        },
        PayloadScenario("akashic_update_entry", "add_sources apply", params: ["citekey", "add_sources", "dry_run"]) {
            try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, addSources: [try $0.storeDigest()], dryRun: false)
        },
        PayloadScenario("akashic_update_entry", "remove_sources", params: ["citekey", "remove_sources", "dry_run"]) {
            let d = try $0.storeDigest()
            _ = try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, addSources: [d], dryRun: false)
            $0.commit()
            return try $0.service.updateEntry(citekey: firstEntry, removeFields: nil, removeSources: ["\(d)=這份不是這篇"], dryRun: false)
        },
        // #700：四條腿各一個情境——remove_zotero_sources 先前沒有（tools/list 的參數對不上情境時守衛才看得到它）
        PayloadScenario("akashic_update_entry", "remove_zotero_sources dry_run", params: ["citekey", "remove_zotero_sources", "dry_run"]) {
            try $0.zoteroSourcedEntry()
            return try $0.service.updateEntry(citekey: "zotero2020", removeFields: nil, removeZoteroSources: ["1:PRIM0001=主來源記錯了"],
                                              dryRun: true)
        },
        PayloadScenario("akashic_store_source", "file", params: ["path", "media_type", "retrieved", "origin", "acquisition", "note"]) { try $0.storedSourceReceipt() },
        PayloadScenario("akashic_enrich", "dry_run", params: ["proposals", "dry_run"]) {
            try $0.service.enrich(proposals: [.init(citekey: "desc2020", fields: ["abstract": "補上的摘要"])],
                                  dryRun: true, includeAbsentAuthors: false, itemLimit: 20)
        },
        PayloadScenario("akashic_enrich", "apply with provenance", params: ["proposals", "dry_run", "include_absent_authors"]) {
            let digest = try $0.storeDigest()
            return try $0.service.enrich(
                proposals: [.init(citekey: "desc2020", fields: ["abstract": "補上的摘要"], date: "2020", authors: ["Some One"],
                                  sourceDigest: digest, sourceURL: "https://example.org/x", sourceRetrieved: "2026-09-29",
                                  sourceStatus: 200)],
                dryRun: false, includeAbsentAuthors: true, itemLimit: 20)
        },
        PayloadScenario("akashic_enrich", "ambiguous and not found", params: ["proposals", "dry_run"]) {
            try $0.service.enrich(proposals: [.init(citekey: "no-such-key", fields: ["abstract": "x"]),
                                              .init(doi: "10.1000/none", fields: ["abstract": "y"])],
                                  dryRun: true, includeAbsentAuthors: false, itemLimit: 20)
        },
        // #700：items[] 的各個鍵要有情境產生才守得到——來源齊備（provenancePlanned）、值補了而 reference 刻意不寫
        // （provenanceOmitted：authors 一律）、來源只給 digest（provenanceSkipped）、ISSN 一律拒（refused）。
        PayloadScenario("akashic_enrich", "dry_run provenance states", params: ["proposals", "dry_run", "include_absent_authors"]) {
            let digest = try $0.storeDigest()
            try $0.store.writeEntry(Entry(id: UUID(), citekey: "noauth2020", type: .periodicalArticle, title: "No byline yet"))
            return try $0.service.enrich(
                proposals: [.init(citekey: "desc2021", fields: ["abstract": "補上的摘要"], sourceDigest: digest,
                                  sourceURL: "https://example.org/x", sourceRetrieved: "2026-09-30", sourceStatus: 200),
                            .init(citekey: "noauth2020", authors: ["Some One"], sourceDigest: digest,
                                  sourceURL: "https://example.org/y", sourceRetrieved: "2026-09-30", sourceStatus: 200),
                            .init(citekey: "olsson1979maximum", fields: ["issn": "0033-3123"], sourceDigest: digest)],
                dryRun: true, includeAbsentAuthors: true, itemLimit: 20)
        },
        // #700 R1 verify 第 3 則：`items[].provenanceNotWritten`（實跑、來源齊備、那一筆寫入失敗）與 `items[].partial`（識別碼部分解析）
        // 先前沒有情境產生，說明拿掉它們守衛照綠。寫入失敗用既有的做法（`EnrichServiceTests`）：把目的檔設成 immutable——rename 過去會被拒，
        // 那一筆進 writeFailed、reference 沒寫進去；情境結束前還原旗標，世界的暫存目錄才刪得掉。
        PayloadScenario("akashic_enrich", "apply with a write failure", params: ["proposals", "dry_run"]) {
            let digest = try $0.storeDigest()
            let target = try XCTUnwrap(try $0.store.load().entries.first { $0.citekey == "desc2021" })
            let url = $0.store.entityURL(id: target.id)
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)
            defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path) }
            return try $0.service.enrich(
                proposals: [.init(citekey: "desc2021", fields: ["abstract": "寫不進去的摘要"], sourceDigest: digest,
                                  sourceURL: "https://example.org/z", sourceRetrieved: "2026-10-01", sourceStatus: 200)],
                dryRun: false, includeAbsentAuthors: false, itemLimit: 20)
        },
        // 多值的 isbn 欄位：一個解得出、一個解不出 → 值進結構化欄位、原字串一併留在 fields，該筆帶 partial
        PayloadScenario("akashic_enrich", "dry_run partial identifier", params: ["proposals", "dry_run"]) {
            try $0.service.enrich(proposals: [.init(citekey: "desc2021", fields: ["isbn": "9780306406157 not-an-isbn"])],
                                  dryRun: true, includeAbsentAuthors: false, itemLimit: 20)
        },
    ]

    // MARK: - library

    static let libraries: [PayloadScenario] = [
        PayloadScenario("akashic_libraries", "list", .array, params: ["action=list"]) {
            _ = try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: "d", citekey: nil,
                                         membership: .init(kind: "topic"))
            return try $0.service.libraries(action: "list", key: nil, name: nil, description: nil, citekey: nil)
        },
        PayloadScenario("akashic_libraries", "create", params: ["action=create", "key", "name", "description", "kind"]) {
            try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: "d", citekey: nil,
                                     membership: .init(kind: "topic"))
        },
        PayloadScenario("akashic_libraries", "add", params: ["action=add", "key", "citekey"]) {
            _ = try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: nil, citekey: nil,
                                         membership: .init(kind: "topic"))
            return try $0.service.libraries(action: "add", key: "reading", name: nil, description: nil, citekey: firstEntry)
        },
        PayloadScenario("akashic_libraries", "remove", params: ["action=remove", "key", "citekey"]) {
            _ = try $0.service.libraries(action: "create", key: "reading", name: "Reading", description: nil, citekey: nil,
                                         membership: .init(kind: "topic"))
            _ = try $0.service.libraries(action: "add", key: "reading", name: nil, description: nil, citekey: firstEntry)
            return try $0.service.libraries(action: "remove", key: "reading", name: nil, description: nil, citekey: firstEntry)
        },
        PayloadScenario("akashic_libraries", "set-kind", params: ["action=set-kind", "key", "kind", "venue"]) {
            _ = try $0.service.libraries(action: "create", key: "psychometrika-all", name: "Psychometrika", description: nil, citekey: nil,
                                         membership: .init(kind: "topic"))
            $0.commit()   // set-kind 整值替換既有規則，要求 registry 檔已 commit
            return try $0.service.libraries(action: "set-kind", key: "psychometrika-all", name: nil, description: nil, citekey: nil,
                                            membership: .init(kind: "rule", venue: "psychometrika"))
        },
        PayloadScenario("akashic_libraries", "check", params: ["action=check", "key"]) {
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
        PayloadScenario("akashic_add_person", "plain", params: ["key", "names", "orcid", "openalex"]) {
            try $0.service.addPerson(key: "new-person", names: ["New Person"], orcid: "0000-0002-1825-0097", openalex: "A5023888391")
        },
        PayloadScenario("akashic_update_person", "dry_run", params: ["key", "fields", "dry_run"]) {
            try $0.service.updatePerson(key: "cheng-che", fields: ["note": "guard"], dryRun: true)
        },
        PayloadScenario("akashic_update_person", "apply", params: ["key", "fields", "dry_run"]) {
            try $0.service.updatePerson(key: "cheng-che", fields: ["note": "guard"], dryRun: false)
        },
    ]

    static let organizations: [PayloadScenario] = [
        PayloadScenario("akashic_add_organization", "plain", params: ["key", "names", "parent_key", "note", "ror"]) {
            try $0.service.addOrganization(key: "new-org", names: ["New Org"], parentKey: "global-research-institute", note: "n",
                                           ror: "https://ror.org/05dxps055")
        },
        // #557：authorize（含一個不在 names 的、一個空白項）；第二個情境指定一個已退役的名字（authorizedNotCurrent）。沒有 unauthorize（拿掉了）
        // #564：authorize 的 judgement 必填、rests_on 可省略（這個情境帶一個）
        PayloadScenario("akashic_update_organization", "authorize", params: ["key", "authorize", "judgement", "rests_on"]) {
            try $0.service.updateOrganization(key: "global-research-institute", authorize: ["GRI", " "],
                                              judgement: "所方正式名稱", restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_update_organization", "authorize-retired", params: ["key", "authorize", "judgement"]) {
            try $0.service.store.writeOrganization(Organization(key: "former-institute", names: Timeline([
                TemporalValue(value: "Institute of Statistics", range: DateRange(start: "1960", end: "1993")),
                TemporalValue(value: "Institute of Statistical Science", range: DateRange(start: "1993"))]), id: UUID()))
            return try $0.service.updateOrganization(key: "former-institute", authorize: ["Institute of Statistics"], judgement: "沿革名稱")
        },
    ]

    // MARK: - 歧異記錄

    static let divergences: [PayloadScenario] = [
        PayloadScenario("akashic_record_divergence", "plain", params: ["question", "candidates"]) {
            try $0.service.recordDivergence(question: "另兩筆是同一人嗎", candidates: ["cheng-che:person", "desc-solo:person"],
                                            judgement: nil, restsOn: [])
        },
        PayloadScenario("akashic_record_divergence", "with judgement", params: ["question", "candidates", "judgement", "rests_on", "prefers"]) {
            let digest = try $0.storeDigest()
            return try $0.service.recordDivergence(question: "另兩筆是同一人嗎", candidates: ["cheng-che:person", "desc-solo:person"],
                                                   judgement: "同一人", restsOn: [digest], prefers: "cheng-che")
        },
        PayloadScenario("akashic_dismiss_divergence", "dry_run", params: ["id", "reason", "dry_run"]) {
            try $0.service.dismissDivergence(id: try $0.onlyDivergenceID(), reason: "候選記錯了", dryRun: true)
        },
        PayloadScenario("akashic_dismiss_divergence", "apply", params: ["id", "reason", "dry_run"]) {
            try $0.service.dismissDivergence(id: try $0.onlyDivergenceID(), reason: "候選記錯了", dryRun: false)
        },
    ]

    // MARK: - 匯入

    static let imports: [PayloadScenario] = [
        PayloadScenario("akashic_import_zotero", "created", params: ["zotero_db"]) {
            let z = try PayloadZoteroDB(dir: $0.dir)
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        PayloadScenario("akashic_import_zotero", "ambiguous source claims", params: ["zotero_db"]) {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            try $0.duplicateFirstZoteroEntry()
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        // #696 R1 verify：pull 拿掉的欄位與覆寫的未歸戶作者要出現在 MCP payload（authorsOverwritten／fieldsRemovedByPull）
        PayloadScenario("akashic_import_zotero", "pull overwrites", params: ["zotero_db"]) {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            var imported = try XCTUnwrap(try $0.store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
            imported.fields["note"] = "hand-added"
            imported.authors = [.literal("Someone Else")]
            imported.provenance?.zoteroHash = "stale"
            try $0.store.writeEntry(imported)
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        // #611：新建的條目與既有的一筆共用 DOI——照建，並記一筆歧異提名（doiNominations）
        PayloadScenario("akashic_import_zotero", "doi nomination", params: ["zotero_db"]) {
            let z = try PayloadZoteroDB(dir: $0.dir, doi: "10.1017/psy.2025.1")
            var main = try XCTUnwrap(try $0.store.load().entries.first { $0.citekey == "cheng2025identifiability" })
            main.doi = [try XCTUnwrap(DOI("10.1017/psy.2025.1"))]
            try $0.store.writeEntry(main)
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        // #611 R1 verify：共用同一個 DOI 的 work 超過門檻——一對都不記、報一列 groupTooLarge（groupSize），並帶 doiNominationsUnrecorded
        PayloadScenario("akashic_import_zotero", "doi nomination group too large", params: ["zotero_db"]) {
            let z = try PayloadZoteroDB(dir: $0.dir, doi: "10.1017/psy.2025.1")
            for n in 1...10 {   // DOINomination.maxGroupSize（這個 target 不依賴 AkashicZoteroImport）：加上這一趟新建的那一筆 ＝ 11 > 10
                var e = Entry(id: UUID(), citekey: String(format: "wos2025n%02d", n), type: .periodicalArticle, title: "WoS \(n)")
                e.doi = [try XCTUnwrap(DOI("10.1017/psy.2025.1"))]
                try $0.store.writeEntry(e)
            }
            return try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
        },
        PayloadScenario("akashic_enrich_from_zotero", "dry_run", params: ["citekeys", "zotero_db", "dry_run"]) {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            let imported = try $0.store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }
            return try $0.service.enrichFromZotero(citekeys: [try XCTUnwrap(imported).citekey, "no-such-key"],
                                                   zoteroDb: z.url.path, libraryID: nil, dryRun: true)
        },
        PayloadScenario("akashic_enrich_from_zotero", "apply", params: ["citekeys", "zotero_db", "dry_run"]) {
            let z = try PayloadZoteroDB(dir: $0.dir)
            _ = try $0.service.importZotero(zoteroDb: z.url.path, libraryID: nil)
            var imported = try XCTUnwrap(try $0.store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
            imported.fields["journaltitle"] = nil   // Zotero 有、store 缺——補值面才有東西補
            try $0.store.writeEntry(imported)
            return try $0.service.enrichFromZotero(citekeys: [imported.citekey], zoteroDb: z.url.path, libraryID: nil, dryRun: false)
        },
        PayloadScenario("akashic_import_wos", "created", params: ["path", "dry_run"]) {
            try $0.service.importWoS(path: try $0.woSFile(), csv: false, dryRun: false)
        },
        PayloadScenario("akashic_import_wos", "dry_run", params: ["path", "dry_run"]) {
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
                                       origin: "https://example.org/x.pdf", acquisition: "browser-download", note: "guard receipt")
    }

    /// 一筆記著主來源與附加來源的 work（`remove_zotero_sources` 的對象）。
    func zoteroSourcedEntry() throws {
        var e = Entry(id: UUID(), citekey: "zotero2020", type: .periodicalArticle, title: "From Zotero", date: "2020")
        e.provenance = Provenance(zoteroKey: "PRIM0001", zoteroVersion: 5, libraryID: 1)
        e.additionalProvenance = [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)]
        try store.writeEntry(e)
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
