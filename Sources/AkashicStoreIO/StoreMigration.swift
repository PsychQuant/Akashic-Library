import Foundation
import AkashicCore

/// legacy（`entries/` + `people/`）→ `entities/<uuid>.yaml` 的一次性遷移（#35）。
///
/// ## 順序：先驗、再寫、後刪
///
/// 三個階段各自的中斷後果不同，而順序是刻意的：
///
/// | 階段 | 中斷後果 | 為什麼可接受 |
/// |---|---|---|
/// | 1. 載入 + 全量 pre-encode | **完全未動磁碟** | 任何一筆不可寫就整個遷移不開始 |
/// | 2. 寫 `entities/` | 新舊並存 | 重跑遷移即可（`entities/` 已有的跳過，idempotent） |
/// | 3. 刪 legacy + 寫 format 2 | 新舊並存但 format 已是 2 | 讀取端已經在讀 `entities/`；殘留的 legacy 檔由 doctor 的重複 citekey 檢查可見 |
///
/// **先寫後刪**：中斷時頂多多一份檔案，**永遠不丟資料**。反過來（先刪後寫）在同一個
/// 中斷點會直接失去記錄。這與 `renameEntry` 的取捨同源。
///
/// **pre-encode 全量預檢**是 #23 R6 的教訓：`encode` 自 v1.3 起可拒寫（canary
/// fail-closed），不預檢就會在遷移到一半時擲錯，留下半套佈局。
public enum StoreMigration {

    public struct Report: Equatable {
        public var entriesMoved: Int = 0
        public var peopleMoved: Int = 0
        /// 已經在 entities/ 的（重跑遷移時）。
        public var alreadyMigrated: Int = 0
        /// 遷移**前**就存在的 quarantine 檔——它們**不會被搬**，原地留在 legacy 目錄。
        public var quarantinedLeftBehind: [String] = []
    }

    public enum MigrationError: Error, LocalizedError {
        case alreadyAtFormat(Int)
        case quarantinedFilesPresent([String])
        /// 兩筆記錄映到同一個目的 UUID。**不遷移**——照做會讓後寫的覆蓋前寫的，
        /// 而兩份 legacy 都被刪，永久失去一筆。
        case duplicateDestination([String])
        /// 跨記錄問題（重複 citekey / person key）。遷移會把它們帶進新佈局。
        case crossRecordIssues([String])
        /// legacy 檔刪除失敗。**不 bump format**——bump 了會讓 store 進入
        /// 「index 永遠 rebuild 不了、migrate 又拒絕再跑」的死角。
        case legacyDeletionFailed([String])

        public var errorDescription: String? {
            switch self {
            case let .alreadyAtFormat(v):
                return "store 已經是 format \(v)，不需要遷移"   // display-safe-exempt: v 是 Int format 版本
            case let .duplicateDestination(keys):
                return """
                    有 \(keys.count) 組記錄會映到同一個目的檔——遷移中止。\
                    照做會讓後寫的覆蓋前寫的、而兩份來源都被刪除，**永久失去一筆**。\
                    先修好重複的 id / key：\(keys.prefix(5).map { displaySafe($0, max: 200) }.joined(separator: "、"))
                    """
            case let .crossRecordIssues(msgs):
                return """
                    store 有 \(msgs.count) 個跨記錄問題（重複 citekey / key）——遷移中止。\
                    搬過去只會把問題帶進新佈局：\(msgs.prefix(3).map { displaySafe($0, max: 300) }.joined(separator: "；"))
                    """
            case let .legacyDeletionFailed(files):
                return """
                    entities/ 已寫入，但有 \(files.count) 個 legacy 檔刪不掉，\
                    **store format 未 bump**（仍是 1，讀取端照舊佈局運作，資料一致）。\
                    手動刪掉它們之後重跑 akashic migrate：\
                    \(files.prefix(5).map { displaySafe($0, max: 300) }.joined(separator: "、"))
                    """
            case let .quarantinedFilesPresent(files):
                return """
                    有 \(files.count) 個檔案無法載入（quarantined），遷移中止——\
                    它們的內容讀不出來，搬過去只會把問題帶到新佈局並失去「哪個檔壞了」的線索。\
                    先用 akashic doctor 看清楚並修好：\
                    \(files.prefix(5).map { displaySafe($0, max: 200) }.joined(separator: "、"))\
                    \(files.count > 5 ? "…等 \(files.count) 個" : "")
                    """
            }
        }
    }

    /// 執行遷移。`dryRun` 時只回報會做什麼，不動磁碟。
    @discardableResult
    public static func toEntities(store: LibraryStore, dryRun: Bool = false) throws -> Report {
        let current = try StoreVersion.read(root: store.root)
        guard current < 2 else { throw MigrationError.alreadyAtFormat(current) }

        let load = try store.load()

        // **有 quarantine 就不遷移。** 那些檔的內容讀不出來，搬過去只會把問題帶進新佈局，
        // 而且會失去「它原本在哪、叫什麼」這個唯一的線索。
        guard load.quarantined.isEmpty else {
            throw MigrationError.quarantinedFilesPresent(load.quarantined.map(\.file))
        }

        // 跨記錄問題（重複 citekey / person key）——搬過去只會把問題帶進新佈局
        let cross = load.crossRecordIssues().filter { $0.severity == .error }
        guard cross.isEmpty else {
            throw MigrationError.crossRecordIssues(cross.map(\.message))
        }

        // **目的檔碰撞（verify CRITICAL）**：兩筆記錄映到同一個 UUID 時，照做會讓
        // 後寫的覆蓋前寫的、而兩份 legacy 都被刪 → 永久失去一筆。entry 的 id 由
        // crossRecordIssues 涵蓋，但 **entry.id 與 person 的衍生 id 相撞**不在它的
        // 範圍內（不同型別、不同集合），所以在這裡合起來檢查一次。
        var destSeen: [String: String] = [:]
        var collisions: [String] = []
        for e in load.entries {
            let d = e.id.uuidString
            if let prev = destSeen[d] { collisions.append("\(prev) ↔ \(e.citekey)（\(d)）") }
            destSeen[d] = e.citekey
        }
        for p in load.people {
            let d = p.id.uuidString
            if let prev = destSeen[d] { collisions.append("\(prev) ↔ \(p.key)（\(d)）") }
            destSeen[d] = p.key
        }
        guard collisions.isEmpty else {
            throw MigrationError.duplicateDestination(collisions)
        }

        var report = Report()
        let fm = FileManager.default

        // ── 階段 1：全量 pre-encode。任何一筆不可寫 → 整個遷移不開始 ──
        var payloads: [(url: URL, yaml: String, legacy: URL?)] = []
        for entry in load.entries {
            let dest = store.entityURL(id: entry.id)
            let legacy = store.entryURL(citekey: entry.citekey)
            if fm.fileExists(atPath: dest.path), !fm.fileExists(atPath: legacy.path) {
                report.alreadyMigrated += 1
                continue
            }
            // dest 已存在（半途中斷的殘留）→ 覆寫是對的：來源是 legacy，dest 只是
            // 上次寫到一半的產物。**但兩者同時存在時 load() 已經把它讀成兩筆**，
            // 而上面的 crossRecordIssues 檢查會先擋下來，所以走到這裡代表沒有衝突。
            payloads.append((dest, try EntryYAML.encode(entry),
                             fm.fileExists(atPath: legacy.path) ? legacy : nil))
            report.entriesMoved += 1
        }
        for person in load.people {
            let dest = store.entityURL(id: person.id)
            let legacy = store.personURL(key: person.key)
            if fm.fileExists(atPath: dest.path), !fm.fileExists(atPath: legacy.path) {
                report.alreadyMigrated += 1
                continue
            }
            payloads.append((dest, try PersonYAML.encode(person),
                             fm.fileExists(atPath: legacy.path) ? legacy : nil))
            report.peopleMoved += 1
        }

        if dryRun { return report }

        // ── 階段 2：寫 entities/ ──
        try fm.createDirectory(at: store.entitiesDir, withIntermediateDirectories: true)
        for p in payloads {
            try p.yaml.write(to: p.url, atomically: true, encoding: .utf8)
        }

        // ── 階段 3：刪 legacy，最後才 bump format ──
        // format 是最後一步：在它翻成 2 之前，讀取端仍把 legacy 當 canonical，
        // 所以前兩階段中斷時 store 仍是一致的舊佈局 + 一份多餘的 entities/。
        //
        // **刪除失敗不得吞掉（verify CRITICAL/HIGH）**：`try?` 加上無條件 bump 會讓
        // store 進入死角——雙佈局並存使 index 撞 UNIQUE constraint 永遠 rebuild 不了，
        // 而 format 已是 2 使 migrate 拒絕再跑。不 bump 的話讀取端仍照 format 1 運作，
        // 資料一致，人工刪掉殘留後重跑即可。
        var undeleted: [String] = []
        for p in payloads {
            guard let legacy = p.legacy else { continue }
            do { try fm.removeItem(at: legacy) }
            catch { undeleted.append(legacy.lastPathComponent) }
        }
        guard undeleted.isEmpty else {
            throw MigrationError.legacyDeletionFailed(undeleted)
        }
        try StoreVersion.write(root: store.root, format: 2)
        return report
    }

    // MARK: - format 2 → 3：補形狀標籤

    public struct LabelReport: Equatable {
        public var labelled: Int = 0
        /// 已經有標籤的（重跑遷移時）。
        public var alreadyLabelled: Int = 0
    }

    /// 把 `entities/` 下的每一筆記錄**重新編碼成目前的正典形式**，然後 bump 到
    /// `StoreVersion.supported`。
    ///
    /// 「重新編碼」一次涵蓋所有 non-additive 的表示變更，因為它們共用同一條 encode 路徑：
    /// 補上形狀裸標籤、移除冗餘的 `type: person`、把字串隸屬正規化成指涉或字面。
    /// 分成多趟只會讓同一批檔案被讀寫多次，而每一趟都是一次中斷風險。
    ///
    /// ## 為什麼補標籤要走完整的載入路徑
    ///
    /// 判斷一個既有檔是 work 還是 person，用的是**載入器自己的回退**
    /// （`EntityKind.peek(strict: false)` → 欄位組成）。不另寫一條私有推斷，因為遷移
    /// 正是最需要「驗到的」與「讀到的」一致的時刻——若兩者可能分歧，預檢就失去意義。
    ///
    /// ## 順序與 `toEntities` 同源
    ///
    /// 先全量預檢（每一筆都要能 decode 且能 encode），再逐檔寫，**最後**才 bump format。
    /// 中斷時 store 仍是 format 2、仍可被本 binary 以回退模式讀取，重跑即可完成。
    /// 已有標籤的檔跳過，因此重跑是冪等的。
    @discardableResult
    public static func toShapeLabels(store: LibraryStore, dryRun: Bool = false) throws -> LabelReport {
        let current = try StoreVersion.read(root: store.root)
        guard current < StoreVersion.supported else {
            throw MigrationError.alreadyAtFormat(current)
        }
        guard current >= 2 else {
            throw MigrationError.crossRecordIssues(
                ["store 仍是 format 1（legacy 佈局）。請先執行 entities 遷移，再補形狀標籤。"])
        }

        let load = try store.load()
        guard load.quarantined.isEmpty else {
            throw MigrationError.quarantinedFilesPresent(load.quarantined.map(\.file))
        }

        var report = LabelReport()
        let fm = FileManager.default

        // ── 階段 1：全量預檢。任何一筆不可寫 → 整個遷移不開始 ──
        var payloads: [(url: URL, yaml: String)] = []
        for entry in load.entries {
            let dest = store.entityURL(id: entry.id)
            guard fm.fileExists(atPath: dest.path) else { continue }
            let existing = try String(contentsOf: dest, encoding: .utf8)
            let yaml = try EntryYAML.encode(entry)
            if existing == yaml { report.alreadyLabelled += 1; continue }
            payloads.append((dest, yaml))
            report.labelled += 1
        }
        for person in load.people {
            let dest = store.entityURL(id: person.id)
            guard fm.fileExists(atPath: dest.path) else { continue }
            let existing = try String(contentsOf: dest, encoding: .utf8)
            let yaml = try PersonYAML.encode(person)
            if existing == yaml { report.alreadyLabelled += 1; continue }
            payloads.append((dest, yaml))
            report.labelled += 1
        }

        if dryRun { return report }

        // ── 階段 2：逐檔改寫（原地，非搬移，所以不需要刪除階段）──
        for p in payloads {
            try p.yaml.write(to: p.url, atomically: true, encoding: .utf8)
        }

        // ── 階段 3：最後才 bump ──
        // 在它翻成 3 之前，讀取端仍以回退模式運作，所以前兩階段中斷時 store 一致。
        try StoreVersion.write(root: store.root, format: StoreVersion.supported)
        return report
    }
}
