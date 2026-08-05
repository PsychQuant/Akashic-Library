import Foundation
import Observation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// App 的中心狀態：載入/篩選/衍生層編輯/rename。
/// 寫入邊界與 MCP 相同（衍生層 + rename + orphan 裁決）；寫後 reload + reindex。
@Observable
public final class AppState {
    /// #18 多檔案：switchFile 時重指（session-scoped；不寫 config）。
    public private(set) var root: URL
    /// registry key（#101）。**與 root 同生共死**——它決定衍生 index 住哪裡
    /// （已註冊 → `~/.akashic/index/<key>.sqlite`；nil → in-store `.akashic/`）。
    ///
    /// 曾經 App 只保留 root、丟掉 key，於是它對**已註冊**的 store 也走 keyless 路徑：
    /// 每次寫入後的 `reindexAndReload()` 會在 store root 內重建一份 in-store index，
    /// 而 CLI / MCP 讀的是 `index/<key>.sqlite`——同一個 store 兩份索引各自為政，且
    /// 使用者刪掉 `.akashic/` 之後只要開 App 編輯一次就長回來。
    public private(set) var storeKey: String?
    let configURL: URL
    /// config 的 files registry（App 端唯讀視圖；load() 時同步刷新）。
    public private(set) var availableFiles: [RegisteredFile] = []

    public private(set) var entries: [Entry] = []
    public private(set) var people: [Person] = []
    /// Library registry（#13 membership views）
    public private(set) var libraries: [Library] = []
    public private(set) var quarantined: [QuarantinedFile] = []
    /// #31：含未知欄位（較新 binary 寫入）的檔案清單。與 quarantined 並列而非合併——
    /// 語意完全不同：quarantined 是「這個檔壞了、沒載入」，unknown-field 是
    /// 「這個檔**正常載入且完整保留**，只是本 binary 看不懂其中一部分」。
    /// 合併會讓使用者以為資料出事了。
    public private(set) var unknownFieldFiles: [String] = []
    /// 每次 load() 遞增。App 層 model（People/Quarantine/Graph）以此為
    /// re-create 訊號，外部變更（FileWatcher reload）才會反映到快取清單。
    public private(set) var reloadCount: Int = 0
    /// 最近一次外部變更同步的時間（FileWatcher 觸發）。UI 以此顯示
    /// 「外部變更已同步」提示——App 是 write-through 模型（沒有草稿緩衝），
    /// 外部覆蓋不會遺失使用者輸入，但要讓使用者知道畫面剛被外部更新。
    public private(set) var lastExternalSyncAt: Date?

    public var searchText: String = ""
    public var filterType: String?
    public var filterTag: String?
    public var filterJournal: String?
    /// 選定的 library view（#13）；nil＝全集
    public var filterLibrary: String?
    /// People 裁決台 session 內 skip 的候選 id（`citekey:authorIndex`）。
    /// 放這裡（session 生命週期）而非 PeopleResolveModel——model 會被
    /// `.task(id: reloadCount)` 重建，集合放 model 內會在每次 reload 後歸零。
    public var skippedPeopleCandidates = Set<String>()

    /// 環境變數視圖（#101）。**存在的唯一理由是可測試性**：已註冊 store 的 index 位置由
    /// `AKASHIC_HOME` 決定，若這裡寫死 `ProcessInfo.processInfo.environment`，任何測試只要
    /// 帶 key 就會去重建**使用者真實的** `~/.akashic/index/<key>.sqlite`。
    /// （這不是假想——本欄位正是在 #101 verify 時被這樣打中一次才補上的。）
    let environment: [String: String]

    public init(root: URL, key: String? = nil,
                configURL: URL = AkashicConfig.defaultURL,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.root = root
        self.storeKey = key
        self.configURL = configURL
        self.environment = environment
    }

    public struct RegisteredFile: Identifiable, Equatable {
        public var key: String
        public var path: String
        public var isCurrent: Bool
        public var id: String { key }
    }

    /// 切換到 registry 內另一個檔案：重指 root、清空 per-universe 狀態、整批重載。
    /// 互不相通——filter/搜尋/skip 集合對新 universe 無意義，一律歸零。
    public func switchFile(key: String) throws {
        let config = try AkashicConfig.read(from: configURL)
        guard let path = config.files[key] else {
            throw AppStateError.unknownFile(key)
        }
        let newRoot = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard LibraryStore.isLibraryRoot(newRoot) else {
            throw AppStateError.notALibrary(path)
        }
        let oldRoot = root
        let oldKey = storeKey
        root = newRoot
        storeKey = key          // #101：key 與 root 同生共死，回滾時一併還原
        searchText = ""
        filterType = nil
        filterTag = nil
        filterJournal = nil
        filterLibrary = nil
        skippedPeopleCandidates = []
        do {
            try load()
        } catch {
            // rollback：root 標籤與資料不可分離（verify R1 MEDIUM）——
            // 新 universe 載入失敗就回到舊 universe，best-effort 重載舊快照
            root = oldRoot
            storeKey = oldKey
            try? load()
            throw error
        }
    }

    var store: LibraryStore { LibraryStore(root: root, key: storeKey, environment: environment) }

    // MARK: - 載入與統計

    public func load() throws {
        let loaded = try store.load()
        entries = loaded.entries
        people = loaded.people
        libraries = loaded.libraries
        quarantined = loaded.quarantined
        unknownFieldFiles = loaded.unknownFieldFiles
        // registry 同步刷新（config 讀不到→空清單；App 不因 config 壞而擋 load）
        if let config = try? AkashicConfig.read(from: configURL) {
            availableFiles = config.files.keys.sorted().map {
                RegisteredFile(key: $0, path: config.files[$0]!, isCurrent: $0 == config.current)
            }
        } else {
            availableFiles = []
        }
        reloadCount += 1
    }

    /// FileWatcher 的 reload 入口：同 load()，另外蓋上外部同步時戳。
    public func externalReload() throws {
        try load()
        lastExternalSyncAt = Date()
    }

    public var unresolvedLiteralCount: Int {
        entries.reduce(0) { count, entry in
            count + entry.authors.filter { if case .literal = $0 { return true } else { return false } }.count
        }
    }

    public var orphanedEntries: [Entry] {
        entries.filter { $0.provenance?.orphanedAt != nil }
    }

    public var filteredEntries: [Entry] {
        entries.filter { entry in
            if let type = filterType, entry.type != type { return false }
            if let tag = filterTag, !entry.akashic.tags.contains(tag) { return false }
            if let journal = filterJournal,
               entry.fields["journaltitle"]?.lowercased() != journal.lowercased() { return false }
            if let library = filterLibrary,
               !entry.akashic.libraries.contains(library) { return false }
            let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            if !query.isEmpty {
                let haystack = ([entry.citekey, entry.title]
                    + entry.authors.map(\.displayName)).joined(separator: "\n").lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }
    }

    // MARK: - 衍生層編輯（寫檔 + reload + reindex）

    public func setStatus(citekey: String, status: String?) throws {
        try mutate(citekey) { $0.akashic.status = status }
    }

    public func addTag(citekey: String, tag: String) throws {
        try mutate(citekey) {
            if !$0.akashic.tags.contains(tag) { $0.akashic.tags.append(tag) }
        }
    }

    public func removeTag(citekey: String, tag: String) throws {
        try mutate(citekey) { $0.akashic.tags.removeAll { $0 == tag } }
    }

    /// #15：把 entry 加進 library。
    ///
    /// **與 `addTag` 的關鍵差異：library key 必須指向 registry 裡存在的項。**
    /// tag 是自由字串（打錯只是多一個沒人用的 tag），library key 是**參照**——
    /// 打錯會產生懸空成員關係：entry 說它屬於某個 library，而那個 library 不存在。
    /// `#7b` 的跨記錄驗證會把它報成 warning，但更好的做法是**一開始就不讓它發生**。
    /// 所以這裡 fail-loud，UI 端則只提供選單而非自由輸入。
    public func addToLibrary(citekey: String, libraryKey: String) throws {
        guard libraries.contains(where: { $0.key == libraryKey }) else {
            throw AppStateError.unknownLibrary(libraryKey)
        }
        try mutate(citekey) {
            if !$0.akashic.libraries.contains(libraryKey) {
                $0.akashic.libraries.append(libraryKey)
                $0.akashic.libraries.sort()   // 穩定順序——避免 diff 噪音
            }
        }
    }

    /// 移出 library。**不檢查 registry 存在性**——要能把懸空的成員關係清掉，
    /// 而那正是 registry 已經沒有該 library 的情況。
    public func removeFromLibrary(citekey: String, libraryKey: String) throws {
        try mutate(citekey) { $0.akashic.libraries.removeAll { $0 == libraryKey } }
    }

    /// 這個 entry 還沒加入的、registry 裡有的 library（供 UI 出選單）。
    public func availableLibraries(for citekey: String) -> [Library] {
        let joined = Set(entries.first { $0.citekey == citekey }?.akashic.libraries ?? [])
        return libraries.filter { !joined.contains($0.key) }.sorted { $0.key < $1.key }
    }

    public func addRelation(citekey: String, kind: RelationKind, target: String) throws {
        try mutate(citekey) {
            switch kind {
            case .cites:
                if !$0.akashic.relations.cites.contains(target) { $0.akashic.relations.cites.append(target) }
            case .related:
                if !$0.akashic.relations.related.contains(target) { $0.akashic.relations.related.append(target) }
            }
        }
    }

    public func removeRelation(citekey: String, kind: RelationKind, target: String) throws {
        try mutate(citekey) {
            switch kind {
            case .cites: $0.akashic.relations.cites.removeAll { $0 == target }
            case .related: $0.akashic.relations.related.removeAll { $0 == target }
            }
        }
    }

    public func rename(from oldKey: String, to newKey: String) throws {
        _ = try store.renameEntry(from: oldKey, to: newKey)
        try reindexAndReload()
    }

    public enum RelationKind {
        case cites, related
    }

    // MARK: - Internals

    func mutate(_ citekey: String, _ change: (inout Entry) -> Void) throws {
        // 從磁碟重讀最新版本再 patch——記憶體快照可能落後外部工具（CLI/MCP/
        // Zotero pull）最多一個 FileWatcher debounce 視窗；用舊快照整筆寫回
        // 會把外部剛更新的書目層（title/authors/fields）蓋回舊值（lost update）。
        guard var entry = try store.load().entries.first(where: { $0.citekey == citekey }) else {
            throw StoreIOError.invalidKey("citekey（不存在）", citekey)
        }
        change(&entry)
        try store.writeEntry(entry)
        try reindexAndReload()
    }

    func reindexAndReload() throws {
        _ = try LibraryIndex(store: store).rebuild()
        try load()
    }
}

public enum AppStateError: Error, LocalizedError {
    case unknownFile(String)
    case notALibrary(String)
    /// #15：library key 是**參照**不是自由字串——加進不存在的 library 會產生懸空成員關係。
    case unknownLibrary(String)

    public var errorDescription: String? {
        switch self {
        case .unknownLibrary(let key):
            return "library「\(displaySafe(key, max: 200))」不在 registry 裡"
                 + "——先用 akashic library create 建立，或從清單挑一個既有的"
        case .unknownFile(let key): return "檔案 key「\(key)」未註冊於 config"
        case .notALibrary(let path): return "「\(path)」不是 Akashic library（缺 entries/）"
        }
    }
}
