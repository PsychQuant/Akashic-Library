import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicSQLite

public struct IndexStats: Equatable {
    public var entries: Int
    public var people: Int
    public var relations: Int

    public init(entries: Int, people: Int, relations: Int) {
        self.entries = entries
        self.people = people
        self.relations = relations
    }
}

/// index 重建器。index 是可全刪重建的衍生物——canonical 永遠是 entries/ 與 people/ 的 YAML。
///
/// 位置由 `store.indexURL` 決定，**不是**固定的 `.akashic/index.sqlite`（#37）：
/// 已註冊 store 走 `~/.akashic/index/<key>.sqlite`，未註冊才回落 in-store。
public struct LibraryIndex {
    /// index schema 版本（#13 verify）：加表/改欄位時遞增。
    /// 舊 binary 建的 index 撞新查詢（如 entry_libraries）會 no such table——
    /// 讀端先 isCurrent 檢查、stale 就 rebuild，不靠 mtime。
    /// **3**＝新增 `index_identity`（#122）：bump 讓所有無身分戳記的舊 index
    /// 判 stale、升級後第一次使用自動重建一次。
    public static let schemaVersion: Int32 = 3

    let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    /// index 是否 current：schema 版本相符 **且** 身分戳記指向同一個 store（#122）。
    ///
    /// 只看版本的病（皆實測過）：被誤寫的空 index 版本對就永不重建（#101 R2 DA）；
    /// registry 路徑被重新利用（舊 store 刪、新 store 同 key）時，`index/<key>.sqlite`
    /// 是**別的 store**建的，版本照樣點頭（#121 verify (c)）——查詢一直吃錯的資料
    /// 且無訊號。身分比對用 canonical path：tilde／symlink／`/var` 前綴的路徑別名
    /// 不是別的 store。
    public static func isCurrent(indexPath: URL, expectedRoot: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: indexPath.path) else { return false }
        let db = try SQLiteDB(path: indexPath.path, readOnly: true)
        let rows = try db.query("PRAGMA user_version")
        let version = (rows.first?["user_version"] as? Int).map(Int32.init) ?? 0
        guard version == schemaVersion else { return false }
        // schema 相符 → 身分表必在（同一次 rebuild 寫入）。查不到＝手工拼裝的
        // 假 index，一樣 stale。
        guard let stamped = (try? db.query("SELECT store_root FROM index_identity"))?
            .first?["store_root"] as? String else { return false }
        return stamped == canonicalRootPath(expectedRoot)
    }

    /// stale（版本或**身分**不符）就 rebuild；current 則 no-op。回傳是否 rebuild 過。
    @discardableResult
    public func ensureCurrent() throws -> Bool {
        if try Self.isCurrent(indexPath: store.indexURL, expectedRoot: store.root) { return false }
        _ = try rebuild()
        return true
    }

    /// canonical path（tilde 展開 + standardized + symlink 解析）。
    /// 與 registry 反查（#105/#121 的 `AkashicConfig.canonicalPath`）同語意——
    /// 兩者 merge 後應統一為一個 helper（差異即 bug）。
    static func canonicalRootPath(_ root: URL) -> String {
        URL(fileURLWithPath: (root.path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    @discardableResult
    public func rebuild() throws -> IndexStats {
        let load = try store.load()

        // 全刪重建：舊 index 直接移除，避免 schema 演化殘留
        // #37：index 不一定住在 akashicDir——已註冊 store 走 ~/.akashic/index/<key>.sqlite，
        // 該目錄不由 ensureLayout 建（它只管 store root 內的佈局）。一律建 indexURL 的父目錄。
        try FileManager.default.createDirectory(
            at: store.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // #7(a)：**先建到 temp、成功才 atomic 換位**。原本是先刪後建——rebuild 中途
        // 失敗（磁碟滿、病態檔擲錯、程序被殺）會留下一個空的／半套的 index，而查詢端
        // 看不出差別，只會安靜地回錯的答案。index 雖可重建，但「可重建」不等於「有人
        // 會發現它壞了」。
        let finalURL = store.indexURL
        let tmpURL = finalURL.deletingLastPathComponent()
            .appendingPathComponent(".\(finalURL.lastPathComponent).rebuild-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: tmpURL)
        // 失敗時清掉 temp——半套檔留在 index 目錄會累積且看起來像真的 index。
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let db = try SQLiteDB(path: tmpURL.path, readOnly: false)

        for sql in [
            """
            CREATE TABLE entries(
                uuid TEXT PRIMARY KEY, citekey TEXT UNIQUE, type TEXT, title TEXT,
                year INT, journal TEXT, status TEXT, orphaned INT)
            """,
            "CREATE TABLE authors(entry_uuid TEXT, position INT, person_key TEXT, literal TEXT)",
            "CREATE TABLE tags(entry_uuid TEXT, tag TEXT)",
            "CREATE TABLE entry_libraries(entry_uuid TEXT, library_key TEXT)",
            "CREATE TABLE relations(from_uuid TEXT, kind TEXT, target TEXT)",
            "CREATE TABLE people(key TEXT PRIMARY KEY, names TEXT)",
            "CREATE INDEX idx_authors_entry ON authors(entry_uuid)",
            "CREATE INDEX idx_authors_key ON authors(person_key)",
            "CREATE INDEX idx_tags_entry ON tags(entry_uuid)",
            "CREATE INDEX idx_entry_libraries_key ON entry_libraries(library_key)",
            "CREATE INDEX idx_relations_from ON relations(from_uuid)",
            "CREATE INDEX idx_relations_target ON relations(target)",
            // #122：身分戳記——這份 index 是誰的、何時建的、當時多少筆
            "CREATE TABLE index_identity(store_root TEXT NOT NULL, built_at TEXT NOT NULL, entry_count INT NOT NULL)",
            "PRAGMA user_version = 3",   // = schemaVersion；同步遞增
        ] {
            try db.execute(sql)
        }
        try db.execute("INSERT INTO index_identity VALUES (?,?,?)",
                       bind: [Self.canonicalRootPath(store.root),
                              ISO8601DateFormatter().string(from: Date()),
                              load.entries.count])

        var relationCount = 0
        try db.execute("BEGIN")
        for entry in load.entries {
            try db.execute(
                "INSERT INTO entries VALUES (?,?,?,?,?,?,?,?)",
                bind: [
                    entry.id.uuidString, entry.citekey, entry.type, entry.title,
                    entry.date.flatMap(Self.extractYear),
                    entry.fields["journaltitle"],
                    entry.akashic.status,
                    entry.provenance?.orphanedAt == nil ? 0 : 1,
                ])
            for (i, author) in entry.authors.enumerated() {
                switch author {
                case .key(let k):
                    try db.execute("INSERT INTO authors VALUES (?,?,?,NULL)",
                                   bind: [entry.id.uuidString, i, k])
                case .literal(let s):
                    try db.execute("INSERT INTO authors VALUES (?,?,NULL,?)",
                                   bind: [entry.id.uuidString, i, s])
                }
            }
            for tag in entry.akashic.tags {
                try db.execute("INSERT INTO tags VALUES (?,?)", bind: [entry.id.uuidString, tag])
            }
            for libraryKey in Set(entry.akashic.libraries) {   // 防禦性去重（上游已保證，fragile invariant 加固）
                try db.execute("INSERT INTO entry_libraries VALUES (?,?)",
                               bind: [entry.id.uuidString, libraryKey])
            }
            for cite in entry.akashic.relations.cites {
                try db.execute("INSERT INTO relations VALUES (?,'cites',?)",
                               bind: [entry.id.uuidString, cite])
                relationCount += 1
            }
            for rel in entry.akashic.relations.related {
                try db.execute("INSERT INTO relations VALUES (?,'related',?)",
                               bind: [entry.id.uuidString, rel])
                relationCount += 1
            }
        }
        for person in load.people {
            try db.execute("INSERT INTO people VALUES (?,?)",
                           bind: [person.key, person.names.joined(separator: "\n")])
        }
        try db.execute("COMMIT")
        db.closeForHandoff()   // 換位前必須關閉——SQLite 對已開啟檔案的搬移無定義行為

        // atomic 換位。`replaceItemAt` 在同一 volume 上是 rename(2)，查詢端永遠看到
        // 「舊的完整 index」或「新的完整 index」，沒有中間態。目的檔不存在時
        // `replaceItemAt` 會失敗，退回直接 move。
        let fm = FileManager.default
        if fm.fileExists(atPath: finalURL.path) {
            _ = try fm.replaceItemAt(finalURL, withItemAt: tmpURL)
        } else {
            try fm.moveItem(at: tmpURL, to: finalURL)
        }
        // SQLite 的 -wal / -shm 屬於舊 index，換位後是孤兒且會讓新 index 讀到舊狀態。
        for suffix in ["-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: finalURL.path + suffix))
        }

        return IndexStats(entries: load.entries.count, people: load.people.count,
                          relations: relationCount)
    }

    static func extractYear(_ date: String) -> Int? {
        guard let range = date.range(of: "[0-9]{4}", options: .regularExpression) else { return nil }
        return Int(date[range])
    }
}
