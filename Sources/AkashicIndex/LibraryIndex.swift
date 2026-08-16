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
    public static func isCurrent(indexPath: URL, expectedRoot: URL,
                                 expectedIncarnation: String? = nil) -> Bool {
        // **整體 fail-safe**（#129 verify F3/C7）：index 是衍生物，任何讀取失敗
        // （非 SQLite 檔、Dropbox conflict copy、截斷寫入）都是「stale、重建」，
        // 不是往上炸——半 throw 半 swallow 的舊形狀讓 conflict copy 直接殺掉指令。
        // 若底層是持續性 I/O 問題，rebuild 自己會失敗並往上拋，不會靜默循環。
        guard FileManager.default.fileExists(atPath: indexPath.path) else { return false }
        guard let db = try? SQLiteDB(path: indexPath.path, readOnly: true),
              let rows = try? db.query("PRAGMA user_version") else { return false }
        let version = (rows.first?["user_version"] as? Int).map(Int32.init) ?? 0
        guard version == schemaVersion else { return false }
        // schema 相符 → 身分表必在（同一次 rebuild 寫入）。查不到＝手工拼裝的
        // 假 index，一樣 stale。
        guard let row = (try? db.query("SELECT store_root, store_id FROM index_identity"))?
            .first, let stamped = row["store_root"] as? String else { return false }
        guard stamped == canonicalRootPath(expectedRoot) else { return false }
        // #130：化身比對。**缺席一律視為未知並退回路徑比對**——既有 index 與既有
        // store 都沒有這個欄位／檔案，讓缺席等於「不符」會把全部既有 index 判 stale
        // （一次全庫重建，且每次呼叫都重來，因為新 index 也只在 store 有 id 時才寫）。
        //
        // 而 `nil` 不會誤信：真正的保護在**檔名**（index 檔名帶化身前綴），這一欄
        // 是縱深防禦，擋的是人工改名。兩者缺席時退回今日的純路徑行為，不是退步。
        let stampedID = (row["store_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let expectedIncarnation, let stampedID else { return true }
        return stampedID == expectedIncarnation
    }

    /// stale（版本或**身分**不符）就 rebuild；current 則 no-op。回傳是否 rebuild 過。
    @discardableResult
    public func ensureCurrent() throws -> Bool {
        if Self.isCurrent(indexPath: store.indexURL, expectedRoot: store.root,
                          expectedIncarnation: store.incarnation) { return false }
        _ = try rebuild()
        return true
    }

    /// canonical path（standardized + symlink 解析；輸入是 URL，`URL.path` 永遠
    /// 不以 `~` 開頭——tilde 展開屬收 String 的那一版）。
    /// 與 PR #121 的 `AkashicConfig.canonicalPath(String)` 同語意——merge 後應統一
    /// 為一個 helper（差異即 bug）；`..`＋symlink 的組合兩種求值順序在 macOS
    /// Foundation 實測同果（守衛測試釘住）。
    ///
    /// **誠實邊界（#129 verify C1）**：canonical path 是**位置**不是**化身**——
    /// 同路徑同 key 的「store 重生」（刪掉重建）會拿到同一個 canonical path、
    /// 通過身分比對。要分辨化身需要 store 自帶的 incarnation id（follow-up）。
    static func canonicalRootPath(_ root: URL) -> String {
        root.standardizedFileURL.resolvingSymlinksInPath().path
    }

    @discardableResult
    public func rebuild() throws -> IndexStats {
        // **重建前提：root 得像一個 store**（#129 verify F1/F2 的配對）。身分比對
        // 讓 path flap（symlink 目標消失、volume unmount、CloudStorage 重掛）觸發
        // 重建，而 load() 對不可達的 root 會「成功地」回 0 筆——好 index 被一份
        // 蓋著正確身分戳記的**空 index** 取代，此後永遠自認 current。「可重建」
        // 不等於「有人會發現它壞了」（同檔 #7(a) 的教訓）；unmount 是暫時的，
        // 拒絕重建讓舊 index 留在原地，remount 後一切如常。
        guard LibraryStore.isLibraryRoot(store.root) else {
            throw IndexError.rootNotALibrary(store.root.path)
        }
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
            // #130：`store_id` 是**縱深防禦**——主要保護在檔名（index 檔名帶化身
            // 前綴，換掉的 store 的 index 根本不叫這個名字）。這一欄擋的是人工
            // 改名。可空：既有 store 沒有 incarnation 檔。
            "CREATE TABLE index_identity(only_row INT PRIMARY KEY CHECK (only_row = 1), store_root TEXT NOT NULL, store_id TEXT, built_at TEXT NOT NULL, entry_count INT NOT NULL)",
            "PRAGMA user_version = 3",   // = schemaVersion；同步遞增
        ] {
            try db.execute(sql)
        }
        try db.execute("INSERT INTO index_identity VALUES (1,?,?,?,?)",
                       bind: [Self.canonicalRootPath(store.root),
                              // 空字串＝缺席。**不用 SQL NULL** 是為了不動共用的
                              // `SQLiteDB` bind 層（它目前只認 Int/Int64/Double/String）
                              // ——在一個講化身的 change 裡改低階綁定會混進不相干的風險。
                              store.incarnation ?? "",
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
            // #227：index 是搜尋用衍生層——收**全部**名字（authorized + variant），
            // 檢索不因指定與否而異。
            try db.execute("INSERT INTO people VALUES (?,?)",
                           bind: [person.key, person.names.all.joined(separator: "\n")])
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

public enum IndexError: Error, LocalizedError, Equatable {
    /// #129 verify F1/F2：root 不像一個 store（unmount／path flap／打錯路徑）時
    /// 拒絕重建——寫出一份身分正確的空 index 比留著舊 index 更糟。
    case rootNotALibrary(String)

    public var errorDescription: String? {
        switch self {
        case .rootNotALibrary(let path):
            return "「\(displaySafe(path, max: 300))」不是 Akashic library（缺 entities/ 與 entries/）"
                 + "——拒絕重建 index。若這是暫時的（磁碟未掛載／同步中），恢復後重試即可；"
                 + "舊 index 原封未動。"
        }
    }
}
