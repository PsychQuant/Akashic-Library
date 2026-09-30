import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import AkashicSQLite

/// `ToolPayloadKeyGuard` 的 fixture store：每個情境一份全新的世界，情境之間不互相污染。
///
/// 世界的內容是為了讓各工具**每一條主要的腿**都走得到、回得出結構化 payload：
/// 歧義的人名（列表與歧義條目）、未歸戶的作者位（拆分、移除、團體作者）、未歸戶的 venue 邊、
/// 未歸戶的機構隸屬，以及一筆歧異記錄。建好之後 commit——移除面一族要求被改的檔已在 git 裡。
final class PayloadWorld {
    let dir: URL
    let root: URL
    let home: URL
    let store: LibraryStore
    let service: AkashicService
    /// 樣板的目錄由 `removeTemplate()` 清；情境的世界在 deinit 清。
    private let removesDirectoryOnDeinit: Bool

    /// 建好並 commit 的樣板（每個情境從它複製一份，不必各自重建 fixture 與 git 歷史——88 個情境 × 每個約 0.4 秒會讓
    /// 這組測試單獨佔掉半分鐘）。`removeTemplate()` 在所有情境跑完後清掉。
    private static let template: Result<URL, Error> = Result {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("akashic-payload-template-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try PayloadWorld(dir: dir, seedingFromScratch: true)
        return dir.appendingPathComponent("library")
    }

    static func removeTemplate() {
        if case .success(let library) = template { try? FileManager.default.removeItem(at: library.deletingLastPathComponent()) }
    }

    convenience init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-payload-guard-\(UUID().uuidString)")
        try self.init(dir: dir, seedingFromScratch: false)
    }

    private init(dir: URL, seedingFromScratch: Bool) throws {
        let fm = FileManager.default
        self.dir = dir
        removesDirectoryOnDeinit = !seedingFromScratch
        root = dir.appendingPathComponent("library")
        home = dir.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let env = ["AKASHIC_HOME": home.path]   // index 不得落到使用者真實的 ~/.akashic（RealHomeSandboxGuard）
        store = LibraryStore(root: root, key: nil, environment: env)
        service = AkashicService(root: root, key: nil, environment: env)
        if seedingFromScratch {
            try store.ensureLayout()   // 也寫入 .gitignore 的 sources/ 排除區塊——`store_source` 的前置
            try StoreVersion.write(root: root, format: StoreVersion.supported)
            try seed()
            commit()
        } else {
            try fm.copyItem(at: try Self.template.get(), to: root)
        }
    }

    deinit { if removesDirectoryOnDeinit { try? FileManager.default.removeItem(at: dir) } }

    /// 把目前的 store 內容 commit 進 git（移除面一族的前置）。
    func commit() { StoreGitCommit.commitAll(root) }

    /// 每次呼叫回傳一個新的、已存進 `sources/` 的 digest（內容互異）。
    func storeDigest(_ text: String = "payload-guard-\(UUID().uuidString)") throws -> String {
        let f = dir.appendingPathComponent("in-\(UUID().uuidString).pdf")
        try Data(text.utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        let raw = try service.storeSource(
            path: f.path, mediaType: "application/pdf", retrieved: "2026-09-29T10:00:00+08:00",
            origin: "https://example.org/x.pdf", acquisition: "browser-download", note: "guard fixture")
        return try XCTUnwrap(try object(raw)["digest"] as? String)
    }

    /// 服務回應 → JSON 物件。
    func object(_ raw: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], raw)
    }

    private func seed() throws {
        // 人：一個已歸戶的作者、一個單一提名的、兩個同名（歧義）
        try store.writePerson(Person(key: "cheng-che", names: PersonNames(authorized: ["Che Cheng", "鄭澈"])))
        try store.writePerson(Person(key: "desc-solo", names: ["Desc Solo"]))
        try store.writePerson(Person(key: "desc-amb-1", names: ["Desc Same"]))
        try store.writePerson(Person(key: "desc-amb-2", names: ["Desc Same"]))
        // 機構隸屬（未歸戶的 literal）＋一個對得上的機構
        var member = Person(key: "iss-member", names: PersonNames(variant: ["Iss Member"]))
        member.profile.affiliations = TimelineOf([TemporalValue(value: .literal("Institute of Statistical Science"))])
        try store.writePerson(member)
        _ = try service.addOrganization(key: "institute-of-statistical-science", names: ["Institute of Statistical Science"])
        _ = try service.addOrganization(key: "global-research-institute", names: ["Global Research Institute"])

        var main = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                         title: "Identifiability of polychoric models",
                         authors: [.key("cheng-che"), .literal("Hau-Hung Yang")], date: "2025")
        main.fields["journaltitle"] = "Psychometrika"
        main.fields["abstract"] = "An abstract."
        main.akashic.tags = ["identifiability"]
        main.akashic.relations.cites = ["olsson1979maximum"]
        main.venues = [.literal("Psychometrika")]
        try store.writeEntry(main)
        var older = Entry(id: UUID(), citekey: "olsson1979maximum", type: .periodicalArticle,
                          title: "Maximum likelihood estimation", authors: [.literal("Ulf Olsson")], date: "1979")
        older.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(older)
        // 提名候選（Desc Solo 對到單一 person）與歧義（Desc Same 對到兩個）
        try store.writeEntry(Entry(id: UUID(), citekey: "desc2020", type: .periodicalArticle, title: "Desc one",
                                   authors: [.literal("Desc Same"), .literal("Desc Solo")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "desc2021", type: .periodicalArticle, title: "Desc two",
                                   authors: [.literal("Desc Solo")], date: "2021"))
        try store.writeEntry(Entry(id: UUID(), citekey: "split2020", type: .periodicalArticle, title: "Two in one",
                                   authors: [.literal("Alpha One and Beta Two")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "drop2020", type: .periodicalArticle, title: "No byline",
                                   authors: [.literal("No authorship indicated")], date: "2020"))
        var second = Entry(id: UUID(), citekey: "venue2020", type: .periodicalArticle, title: "Second Psychometrika work",
                           authors: [.key("cheng-che")], date: "2020")
        second.venues = [.literal("Psychometrika")]
        try store.writeEntry(second)
        try store.writeEntry(Entry(id: UUID(), citekey: "org2020", type: .periodicalArticle, title: "By an institute",
                                   authors: [.literal("Global Research Institute")], date: "2020"))
        // venue：刊名對得上 main 的 literal 邊
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"], type: "periodical")
        _ = try service.addVenue(key: "psychometrika-other", names: ["Psychometrika Other"], type: "periodical")
        // 歧異記錄
        _ = try service.recordDivergence(question: "兩筆是同一人嗎", candidates: ["desc-amb-1:person", "desc-amb-2:person"],
                                         judgement: nil, restsOn: [])
    }
}

/// 最小的 zotero.sqlite（schema 是 importer／enricher 會讀的那一組表；`ZoteroFixture` 住在 AkashicKitTests，這個 target 引用不到）。
struct PayloadZoteroDB {
    let url: URL

    /// `itemCount` 個 journalArticle：key 是 `KEYART01`…、都在 libraryID 1、共用同一位作者。`doi` 給了就掛在第一個條目上（#611）。
    init(dir: URL, itemCount: Int = 1, doi: String? = nil) throws {
        url = dir.appendingPathComponent("zotero.sqlite")
        let db = try SQLiteDB(path: url.path, readOnly: false)
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
        try db.execute("INSERT INTO fields VALUES (1,'title'),(2,'date'),(3,'publicationTitle'),(4,'DOI')")
        try db.execute("INSERT INTO creators VALUES (1,'Che','Cheng',0)")
        if let doi {
            try db.execute("INSERT INTO itemDataValues VALUES (99,?)", bind: [doi])
            try db.execute("INSERT INTO itemData VALUES (10,4,99)")
        }
        for n in 1...max(itemCount, 1) {
            let item = 9 + n
            try db.execute("INSERT INTO items VALUES (?,1,?,5,1)", bind: [item, String(format: "KEYART%02d", n)])
            let title = n == 1 ? "Identifiability of polychoric models" : "Article number \(n)"
            for (i, (field, value)) in [(1, title), (2, "2025-04-01"), (3, "Psychometrika")].enumerated() {
                let valueID = 100 + 3 * (n - 1) + i
                try db.execute("INSERT INTO itemDataValues VALUES (?,?)", bind: [valueID, value])
                try db.execute("INSERT INTO itemData VALUES (?,?,?)", bind: [item, field, valueID])
            }
            try db.execute("INSERT INTO itemCreators VALUES (?,1,1,0)", bind: [item])
        }
    }
}
