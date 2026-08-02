import Foundation
import AkashicCore

public enum StoreIOError: Error, LocalizedError, Equatable {
    case invalidKey(String, String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey(let kind, let value):
            return "\(kind)「\(value)」不符合 \(StoreKey.pattern)，拒絕寫入"
        }
    }
}

public struct QuarantinedFile: Equatable {
    public var file: String
    public var reason: String

    public init(file: String, reason: String) {
        self.file = file
        self.reason = reason
    }
}

public struct LibraryLoad {
    public var entries: [Entry]
    public var people: [Person]
    /// Library registry（#13 membership views）；成員關係在各 entry 的 akashic.libraries
    public var libraries: [Library]
    public var quarantined: [QuarantinedFile]
    /// 含未知欄位（較新 schema 寫入）的檔案清單——#23 tolerant-preserve 的可見性面，
    /// doctor / validate 據此提示升級 binary。R6（L20）：由 load() 以**實際檔名**
    /// 填入（與 quarantined 同慣例）——先前用 key 合成 `.yaml` 檔名，`.YAML` 等
    /// 大小寫別名會被報成不存在的路徑。
    public var unknownFieldFiles: [String]

    public init(entries: [Entry] = [], people: [Person] = [],
                libraries: [Library] = [], quarantined: [QuarantinedFile] = [],
                unknownFieldFiles: [String] = []) {
        self.entries = entries
        self.people = people
        self.libraries = libraries
        self.quarantined = quarantined
        self.unknownFieldFiles = unknownFieldFiles
    }
}

/// 檔案為本的 library 存取層。canonical 是 entries/ 與 people/ 的 YAML；
/// .akashic/ 是可重建衍生物。所有寫入走 atomic（temp + rename）。
public final class LibraryStore {
    public let root: URL

    public var entriesDir: URL { root.appendingPathComponent("entries") }
    public var peopleDir: URL { root.appendingPathComponent("people") }
    public var librariesDir: URL { root.appendingPathComponent("libraries") }
    public var notesDir: URL { root.appendingPathComponent("notes") }
    /// #35：統一的 canonical 目錄。**分類不進路徑**——work / person / organization 與
    /// article / book 是同一個軸上的值，沒有理由前者當目錄、後者當欄位。檔名是不變的
    /// UUID，所以改 citekey 不再需要搬檔案。
    public var entitiesDir: URL { root.appendingPathComponent("entities") }

    public var akashicDir: URL { root.appendingPathComponent(".akashic") }

    /// registry key（`~/.akashic/config.yaml` 的 `files:` 鍵）。nil＝未註冊 store。
    public let key: String?
    let environment: [String: String]

    /// 衍生 index 的位置（#37）。
    ///
    /// - **已註冊 store**（有 registry key）→ `~/.akashic/index/<key>.sqlite`，在
    ///   store root **之外**。理由見 `AkashicHome.indexDirectory`；核心是「store
    ///   root 正是會進 Dropbox / git 的東西，而同步樹裡的 live SQLite 是已知的
    ///   毀檔風險（partial write、conflict copy）」。
    /// - **未註冊 store**（`--library <path>` 直指，多見於測試與一次性檢查）→
    ///   回落 in-store `.akashic/index.sqlite`。那種 store 不在 registry 的治理
    ///   範圍內，強行給它 home 內的位置反而要發明命名規則。
    ///
    /// 雙軌但各自合理：**有 key 就用 key，沒 key 就跟著 store**。
    public var indexURL: URL {
        if let key {
            return AkashicHome.indexURL(forKey: key, environment: environment)
        }
        return akashicDir.appendingPathComponent("index.sqlite")
    }

    public init(root: URL, key: String? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.root = root
        self.key = key
        self.environment = environment
    }

    public func ensureLayout() throws {
        let fm = FileManager.default
        for dir in [root, entitiesDir, entriesDir, peopleDir, librariesDir, notesDir, akashicDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // #24：新建的 store 自我聲明格式。既有檔不覆寫（可能是較新版本寫的）。
        try StoreVersion.writeIfAbsent(root: root)
    }

    /// #35：format 2 的檔案位置——**檔名是不變的 UUID**，所以改 citekey 不搬檔案。
    public func entityURL(id: UUID) -> URL {
        entitiesDir.appendingPathComponent("\(id.uuidString).yaml")
    }

    /// 這個 store 是否已遷移到 entities/ 佈局（#35）。
    ///
    /// 判準是 **store format**，不是「entities/ 目錄存不存在」——目錄可能因為
    /// `ensureLayout` 或半途中斷而存在卻是空的，用它當判準會讓寫入端在遷移完成前
    /// 就開始往新位置寫，產生兩個佈局並存的爛攤子。
    public var usesEntitiesLayout: Bool {
        ((try? StoreVersion.read(root: root)) ?? 1) >= 2
    }

    public func entryURL(citekey: String) -> URL {
        entriesDir.appendingPathComponent("\(citekey).yaml")
    }

    public func personURL(key: String) -> URL {
        peopleDir.appendingPathComponent("\(key).yaml")
    }

    public func libraryURL(key: String) -> URL {
        librariesDir.appendingPathComponent("\(key).yaml")
    }

    /// Library registry 寫入（#13）：metadata-only；key 走 StoreKey write-time 驗證。
    /// entry 的 membership（akashic.libraries）由 writeEntry 一併驗證。
    @discardableResult
    public func writeLibrary(_ library: Library) throws -> URL {
        guard StoreKey.isValid(library.key) else {
            throw StoreIOError.invalidKey("library key", library.key)
        }
        // pre-v1.2 store（無 libraries/）也能直接建 library——目錄缺就補
        try FileManager.default.createDirectory(at: librariesDir, withIntermediateDirectories: true)
        let yaml = try LibraryYAML.encode(library)
        let dest = libraryURL(key: library.key)
        // exclusive-create：registry 無 update 路徑，並發 create 不得靜默互吃
        try atomicWrite(yaml, to: dest, mustCreate: true)
        return dest
    }

    @discardableResult
    public func writeEntry(_ entry: Entry) throws -> URL {
        // write-time key 驗證：不合格式的 citekey 絕不進檔名（path traversal 防護）
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
        // membership keys（#13）同樣 write-time 驗證——不進路徑，但保 index/query 語意乾淨
        for key in entry.akashic.libraries where !StoreKey.isValid(key) {
            throw StoreIOError.invalidKey("akashic.libraries key", key)
        }
        // membership 是集合語意：重複 key 拒寫（list 計數/index 去重的上游保證）
        guard Set(entry.akashic.libraries).count == entry.akashic.libraries.count else {
            throw StoreIOError.invalidKey("akashic.libraries（重複）",
                                          entry.akashic.libraries.joined(separator: ","))
        }
        let yaml = try EntryYAML.encode(entry)
        // #35：format 2 走 entities/<uuid>.yaml，legacy 走 entries/<citekey>.yaml
        let dest = usesEntitiesLayout ? entityURL(id: entry.id) : entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// exclusive-create 版 writeEntry：目的檔已存在（含檢查後才出現的並發寫入）
    /// 一律擲錯，絕不靜默覆蓋。rename 的目的檔寫入走這條，關掉 check-then-write
    /// 之間的 TOCTOU 覆寫視窗（moveItem 對既存目的檔是原子性拒絕）。
    @discardableResult
    public func writeEntryExclusive(_ entry: Entry) throws -> URL {
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
        let yaml = try EntryYAML.encode(entry)
        let dest = usesEntitiesLayout ? entityURL(id: entry.id) : entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest, mustCreate: true)
        return dest
    }

    @discardableResult
    public func writePerson(_ person: Person) throws -> URL {
        guard StoreKey.isValid(person.key) else {
            throw StoreIOError.invalidKey("person key", person.key)
        }
        let yaml = try PersonYAML.encode(person)
        let dest = usesEntitiesLayout ? entityURL(id: person.id) : personURL(key: person.key)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// 掃描整個 library。schema 不合的檔案進 quarantined 報告，不靜默略過、
    /// 也不讓單一壞檔中斷整批載入。
    public func load() throws -> LibraryLoad {
        // #24：refuse-if-newer 必須在**逐檔 decode 之前**。等到 decode 現場才發現
        // 不對，使用者拿到的是一堆難解的 per-file 錯誤，而不是一句「請升級 binary」。
        try StoreVersion.check(root: root)
        var result = LibraryLoad()

        // #35：entities/ 是 format 2 的 canonical 目錄。**與 legacy 並存讀取**——
        // 遷移是一次性動作，但舊佈局的 store（含別人的 clone、未遷移的備份）必須照樣讀。
        for url in try yamlFiles(in: entitiesDir) {
            let name = "entities/\(url.lastPathComponent)"
            do {
                let text = try readUTF8(url)
                let stem = url.deletingPathExtension().lastPathComponent
                // 檔名即身分：stem 必須是合法 UUID 且與記錄的 id 相符。
                // 不符時 quarantine——那代表有人手動改了檔名或 id，兩者都會讓引用錯位。
                guard let stemUUID = UUID(uuidString: stem) else {
                    result.quarantined.append(QuarantinedFile(
                        file: name, reason: "entities/ 的檔名必須是 UUID，實得「\(stem)」"))
                    continue
                }
                switch try EntityKind.peek(text) {
                case .person:
                    let person = try PersonYAML.decode(text)
                    guard person.id == stemUUID else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "檔名 UUID 與 person.id「\(person.id.uuidString)」不符"))
                        continue
                    }
                    guard StoreKey.isValid(person.key) else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "person key「\(person.key)」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !person.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
                    result.people.append(person)
                case .work:
                    let entry = try EntryYAML.decode(text)
                    guard entry.id == stemUUID else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "檔名 UUID 與 entry.id「\(entry.id.uuidString)」不符"))
                        continue
                    }
                    guard StoreKey.isValid(entry.citekey) else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "citekey「\(entry.citekey)」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if let bad = entry.akashic.libraries.first(where: { !StoreKey.isValid($0) }) {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "akashic.libraries 含不合法 key「\(bad)」"))
                        continue
                    }
                    var e2 = entry
                    var seen = Set<String>()
                    e2.akashic.libraries = entry.akashic.libraries.filter { seen.insert($0).inserted }
                    if !entry.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
                    result.entries.append(e2)
                }
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: name,
                    reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }

        for url in try yamlFiles(in: entriesDir) {
            do {
                let entry = try EntryYAML.decode(try readUTF8(url))
                // 語意驗證：decode 成功但 key 不合法／與檔名不符 → quarantine。
                // 畸形 citekey 一旦進入 library，之後任何 entryURL 組合（rename 刪除、
                // orphan trash）都是 path traversal 面；檔名不符則造成重複 entry 與錯位刪除。
                let stem = url.deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(entry.citekey) else {
                    result.quarantined.append(QuarantinedFile(
                        file: "entries/\(url.lastPathComponent)",
                        reason: "citekey「\(entry.citekey)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == entry.citekey else {
                    result.quarantined.append(QuarantinedFile(
                        file: "entries/\(url.lastPathComponent)",
                        reason: "檔名 stem「\(stem)」與 citekey「\(entry.citekey)」不符"))
                    continue
                }
                // membership 語意驗證（#13 verify）：畸形 key 的 entry 之後任何衍生層
                // 寫入都會被 writeEntry 拒絕（看似可讀、實則鎖死）；重複 key 使計數失真
                if let bad = entry.akashic.libraries.first(where: { !StoreKey.isValid($0) }) {
                    result.quarantined.append(QuarantinedFile(
                        file: "entries/\(url.lastPathComponent)",
                        reason: "akashic.libraries key「\(bad)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                // 純重複（格式合法）→ auto-dedupe 保序（DA 裁決：quarantine 對可用性
                // 過重；集合語意有唯一無歧義修法）。注意：去重在 load 即完成、屬靜默
                // 正規化——validate() 的重複警告只對未正規化的記憶體物件（寫前 lint）有效。
                var entry2 = entry
                var seen = Set<String>()
                entry2.akashic.libraries = entry.akashic.libraries.filter { seen.insert($0).inserted }
                if !entry2.unknownFields.isEmpty || !entry2.akashic.unknownFields.isEmpty {
                    result.unknownFieldFiles.append("entries/\(url.lastPathComponent)")
                }
                result.entries.append(entry2)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "entries/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        for url in try yamlFiles(in: peopleDir) {
            do {
                let person = try PersonYAML.decode(try readUTF8(url))
                let stem = url.deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(person.key) else {
                    result.quarantined.append(QuarantinedFile(
                        file: "people/\(url.lastPathComponent)",
                        reason: "person key「\(person.key)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == person.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: "people/\(url.lastPathComponent)",
                        reason: "檔名 stem「\(stem)」與 person key「\(person.key)」不符"))
                    continue
                }
                if !person.unknownFields.isEmpty {
                    result.unknownFieldFiles.append("people/\(url.lastPathComponent)")
                }
                result.people.append(person)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "people/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        for url in try yamlFiles(in: librariesDir) {
            do {
                let library = try LibraryYAML.decode(try readUTF8(url))
                let stem = url.deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(library.key) else {
                    result.quarantined.append(QuarantinedFile(
                        file: "libraries/\(url.lastPathComponent)",
                        reason: "library key「\(library.key)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == library.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: "libraries/\(url.lastPathComponent)",
                        reason: "檔名 stem「\(stem)」與 library key「\(library.key)」不符"))
                    continue
                }
                if !library.unknownFields.isEmpty {
                    result.unknownFieldFiles.append("libraries/\(url.lastPathComponent)")
                }
                result.libraries.append(library)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "libraries/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        result.entries.sort { $0.citekey < $1.citekey }
        result.people.sort { $0.key < $1.key }
        result.libraries.sort { $0.key < $1.key }
        result.unknownFieldFiles.sort()
        return result
    }

    // MARK: - Internals

    private func yamlFiles(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        // 副檔名比對大小寫不敏感：macOS 檔案系統多為 case-insensitive，
        // `.YAML` 檔是寫入目的檔的別名，必須被枚舉（否則連 quarantine 都進不了）
        return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "yaml" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readUTF8(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// temp 檔寫在同一目錄 + rename 取代——中斷不留半寫檔。
    /// dest 不存在時 `replaceItemAt` 的行為在 Apple docs 未保證（實測可行），
    /// 防禦性改走 moveItem——兩條路徑都是同目錄 rename、同等原子性。
    /// mustCreate = true 時強制走 moveItem——目的檔已存在會原子性擲錯，
    /// 不進 replaceItemAt 的覆蓋分支（exclusive-create 語意）。
    private func atomicWrite(_ content: String, to dest: URL, mustCreate: Bool = false) throws {
        let fm = FileManager.default
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: false, encoding: .utf8)
        do {
            if !mustCreate && fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}

public struct RenameReport: Equatable {
    /// relations 有引用被改寫的 citekeys。
    public var relationsRewritten: [String]

    public init(relationsRewritten: [String] = []) {
        self.relationsRewritten = relationsRewritten
    }
}

extension LibraryStore {
    /// citekey rename（#4）：驗證 → 搬檔 → 全庫 relations 遷移 → 舊檔刪除。
    /// UUID 不變（雙 ID 的 rename 承諾至此真正成立）。呼叫端負責 reindex。
    @discardableResult
    /// 改 citekey 並遷移全庫 relations。
    ///
    /// **中斷恢復語意（#29，明確化）**——三個階段各有不同的中斷後果：
    ///
    /// | 中斷點 | 磁碟狀態 | 恢復方式 |
    /// |---|---|---|
    /// | pre-encode 預檢失敗 | **完全未動** | 修好那筆記錄再跑一次 |
    /// | 寫新檔／遷移 relations 途中 | 新舊檔並存、部分 relations 已指向新 key | 重跑同一個 rename：目的檔已存在會擲錯，需先手動刪新檔；或改為 rename 回去 |
    /// | 刪舊檔前 | 新舊檔並存、relations 全部已遷移 | 手動刪舊檔即可（新檔是完整的） |
    ///
    /// **設計選擇：先寫後刪**。中斷時頂多多一份檔案，**永遠不丟資料**。反過來
    /// （先刪後寫）在同一個中斷點會直接失去記錄。多一份檔案由 `doctor` 的重複
    /// citekey 檢查可見（#7b 的跨記錄驗證），失去記錄則無從發現。
    ///
    /// **為什麼 relations 遷移途中不做 per-entry 續跑**（與 import 的策略相反）：
    /// import 的每一筆是獨立的，跳過一筆只損失那一筆；rename 的每一筆都是**同一個
    /// 語意動作的一部分**，跳過一筆會留下「一半指向舊 key、一半指向新 key」的
    /// 不一致，比整個中止更難修。pre-encode 預檢已經把可預期的失敗（encode canary）
    /// 移到動磁碟之前，剩下的只有磁碟層錯誤——那種情況下中止是對的。
    public func renameEntry(from oldKey: String, to newKey: String) throws -> RenameReport {
        // oldKey 與 newKey 對稱驗證：oldKey 之後會進 entryURL 組刪除路徑，
        // 磁碟上若有畸形 citekey（load() 已 quarantine，此處縱深防禦）絕不可放行
        guard StoreKey.isValid(oldKey) else {
            throw StoreIOError.invalidKey("citekey", oldKey)
        }
        guard StoreKey.isValid(newKey) else {
            throw StoreIOError.invalidKey("citekey", newKey)
        }
        // 目的檔不可存在——含 quarantined 檔與 case-insensitive 別名。
        // #35：format 2 的檔名是 UUID 而非 citekey，這個檢查不適用（目的檔就是來源檔）；
        // 「新 citekey 是否已被別的記錄佔用」改由下面的全庫檢查負責。
        if !usesEntitiesLayout,
           FileManager.default.fileExists(atPath: entryURL(citekey: newKey).path) {
            throw StoreIOError.invalidKey("citekey（目的檔已存在）", newKey)
        }
        let load = try store_loadForRename()
        guard var entry = load.entries.first(where: { $0.citekey == oldKey }) else {
            throw StoreIOError.invalidKey("citekey（來源不存在）", oldKey)
        }
        // #35：檔名不再是 citekey，所以「新 citekey 沒被佔用」不再由檔案系統天然保證。
        // 沒有這個檢查，format 2 會安靜地產生兩筆同 citekey 的記錄。
        if usesEntitiesLayout,
           load.entries.contains(where: { $0.citekey == newKey && $0.id != entry.id }) {
            throw StoreIOError.invalidKey("citekey（已被其他記錄使用）", newKey)
        }

        // 1. 寫新檔（先寫後刪，中斷時頂多多一份檔案，不丟資料）。
        //    exclusive-create：檢查後才出現的並發目的檔會在此擲錯，不被靜默覆蓋。
        //    自身 relations 的 self-reference 也在此一併遷移。
        entry.citekey = newKey
        entry.akashic.relations.cites =
            entry.akashic.relations.cites.map { $0 == oldKey ? newKey : $0 }
        entry.akashic.relations.related =
            entry.akashic.relations.related.map { $0 == oldKey ? newKey : $0 }
        // 2. 全庫 relations 遷移對象（cites/related 引用舊 citekey → 新，
        //    同一陣列的所有出現全部替換；UUID 引用不動）
        var toRewrite: [Entry] = []
        for var other in load.entries where other.citekey != oldKey {
            let cites = other.akashic.relations.cites.map { $0 == oldKey ? newKey : $0 }
            let related = other.akashic.relations.related.map { $0 == oldKey ? newKey : $0 }
            if cites != other.akashic.relations.cites
                || related != other.akashic.relations.related {
                other.akashic.relations.cites = cites
                other.akashic.relations.related = related
                toRewrite.append(other)
            }
        }
        // R6（M9）：encode 自 v1.3 起可 throw（canary fail-closed）。動磁碟前先
        // 對所有要寫的 entry 做 encode 預檢——任何一筆不可寫就整個 rename 不動，
        // 避免中途 throw 留下 relations 半遷移的多檔撕裂。
        _ = try EntryYAML.encode(entry)
        for other in toRewrite { _ = try EntryYAML.encode(other) }
        // 3. 寫記錄本身。
        //
        // **#35：format 2 下 rename 不搬檔案。** 檔名是 UUID，而 rename 不改 UUID——
        // 改的是 citekey 這個「稱呼」。所以目的檔就是來源檔，原地覆寫即可；用
        // exclusive-create 反而會撞上「目的檔已存在」（那是它自己）。
        //
        // 這是 entities 佈局最直接的好處：**改稱呼不再是一次多檔搬移**，
        // 也就沒有「新舊並存」這個中斷態要處理（見本函式開頭的表格）。
        if usesEntitiesLayout {
            try writeEntry(entry)
        } else {
            try writeEntryExclusive(entry)
        }
        var rewritten: [String] = []
        for other in toRewrite {
            try writeEntry(other)
            rewritten.append(other.citekey)
        }
        // 4. 刪舊檔（僅 legacy 佈局——format 2 沒有舊檔，見上）
        if !usesEntitiesLayout {
            try FileManager.default.removeItem(at: entryURL(citekey: oldKey))
        }
        return RenameReport(relationsRewritten: rewritten.sorted())
    }

    private func store_loadForRename() throws -> LibraryLoad {
        try load()
    }
}

// MARK: - 跨記錄驗證（#7b）

public extension LibraryLoad {
    /// 跨記錄的一致性檢查——**單筆 `validate()` 看不到的那一層**。
    ///
    /// 每個 `Entry.validate()` / `Person.validate()` 只看自己，所以「兩筆 entry 用了
    /// 同一個 UUID」「作者的 `.key` 指向不存在的 person」這類問題**結構上不可能**在單筆
    /// 驗證中被發現。它們的後果也不是立刻可見的：重複 UUID 讓 index 的 `PRIMARY KEY`
    /// 靜默丟掉其中一筆（查詢少一筆但不報錯），懸空的 `.key` 讓 person 頁面永遠是空的。
    ///
    /// **檔名 ↔ citekey 一致性不在這裡**——`load()` 已經在讀取時 quarantine 不符的檔，
    /// 走到這裡的記錄都已對齊。
    func crossRecordIssues() -> [ValidationIssue] {
        var out: [ValidationIssue] = []

        func duplicates<T: Hashable>(_ values: [T]) -> [T] {
            var seen = Set<T>(), dup = Set<T>()
            for v in values { if !seen.insert(v).inserted { dup.insert(v) } }
            return Array(dup)
        }

        for u in duplicates(entries.map(\.id)).sorted(by: { $0.uuidString < $1.uuidString }) {
            let keys = entries.filter { $0.id == u }.map { displaySafe($0.citekey, max: 200) }.sorted()
            out.append(ValidationIssue(
                severity: .error,
                message: "UUID \(u.uuidString) 被 \(keys.count) 筆 entry 共用（\(keys.joined(separator: ", "))）"
                       + "——index 的 PRIMARY KEY 會靜默丟掉其中一筆"))
        }
        for k in duplicates(entries.map(\.citekey)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "citekey「\(displaySafe(k, max: 200))」重複"))
        }
        for k in duplicates(people.map(\.key)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "person key「\(displaySafe(k, max: 200))」重複"))
        }
        for k in duplicates(libraries.map(\.key)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "library key「\(displaySafe(k, max: 200))」重複"))
        }

        // 參照存在性。**warning 不是 error**：懸空參照讓畫面少東西，但不毀資料，
        // 而且解析中途（resolve-people 尚未 apply）本來就會有——擋下反而卡住工作流。
        let personKeys = Set(people.map(\.key))
        var danglingAuthors: [String: Set<String>] = [:]
        for e in entries {
            for a in e.authors {
                if case let .key(k) = a, !personKeys.contains(k) {
                    danglingAuthors[k, default: []].insert(e.citekey)
                }
            }
        }
        for (k, cites) in danglingAuthors.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "作者 key「\(displaySafe(k, max: 200))」沒有對應的 people 檔"
                       + "（\(cites.count) 筆引用，如 \(displaySafe(cites.sorted().first ?? "", max: 200))）"))
        }

        let libraryKeys = Set(libraries.map(\.key))
        var danglingLibs: [String: Int] = [:]
        for e in entries {
            for l in e.akashic.libraries where !libraryKeys.contains(l) {
                danglingLibs[l, default: 0] += 1
            }
        }
        for (l, n) in danglingLibs.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "akashic.libraries 的「\(displaySafe(l, max: 200))」沒有對應的 registry 檔"
                       + "（\(n) 筆引用）"))
        }
        return out
    }
}
