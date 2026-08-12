import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicZoteroImport
import AkashicExport
import AkashicIndex
import AkashicQuery
import AkashicGraph

public enum ServiceError: Error, LocalizedError {
    case notFound(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        // #142 / #149 verify F3：what 由 throw 站點組裝並消毒 caller payload
        // （見 notFound(…) 各呼叫端的 displaySafe），此處**不再**消毒——displaySafe
        // 會跳脫反斜線本身、不 idempotent，兩層會把 \u{001B} 變成 \u{005C}u{001B}
        // 並讓外層 max 對已膨脹字串二次截斷。守衛（error-sink 規則 + throw 站點
        // 在掃描面內）保證新 throw 站點的 caller payload 都消毒。
        case .notFound(let what): return "找不到：\(what)"   // display-safe-exempt: what 由 throw 站點消毒（見上方註解）
        case .invalid(let why): return why
        }
    }
}

/// akashic-mcp 的 handler 核心（可測試、不含 MCP 佈線）。
/// 讀走 index（mtime stale 自動重建）；寫只碰衍生層，寫後重建 index。
public final class AkashicService {
    /// MCP 匯出的位元組上限（#171 verify 171-2 的附帶發現）。
    ///
    /// **CLI 沒有這個上限、MCP 有**，因為兩邊的下游不同：`export-bib > refs.bib`
    /// 收 200 MB 沒問題，MCP 的 tool result 進的是 LLM context，200 MB 會炸掉
    /// 任何 context 而且無從恢復。
    ///
    /// 超量的處置是**拒絕並指路**，不是截斷——截一半的 .bib 是壞掉的 .bib，
    /// 而它壞得很安靜（大括號不閉合，下游解析器才報錯）。8 MB 遠大於任何
    /// 正常書目庫（實測本 store 898 筆 ≈ 1.2 MB），小到不會毀掉 context。
    static let maxExportBytes = 8 * 1024 * 1024

    /// #18 多檔案：use 切換時重指（session-scoped）；store/index 為 computed，全部跟隨。
    private(set) var root: URL
    /// #37：index 位置取決於 registry key。與 root 同生命週期——`use` 切換時
    /// 兩者必須一起換，否則會用 A 的 index 查 B 的 store。nil＝未註冊（in-store 回落）。
    private(set) var storeKey: String?
    let configURL: URL
    /// #37：注入用——測試必須能把 index 導向假 home，否則會寫進使用者真實的
    /// `~/.akashic/index/`（`testFilesUseSwitchesUniverseCompletely` 實際踩到）。
    let environment: [String: String]

    /// `resolve_people` 歧義清單的上限（#231）。
    ///
    /// 與 `person()` 的候選上限（50）同值、同理由：**MCP 結果直灌 LLM context**，
    /// 而歧義筆數是 `O(出現次數)`，由 store 內容決定、無自然上界。verify 席用真 binary
    /// 實測：201 筆歧義未設限時產出 176 KB（約 44k tokens），單一次工具呼叫即可吃掉
    /// 整個 context。超出時回 `truncated: true` 與 `ambiguityTotal`，讓使用端知道
    /// 自己看到的不是全部——**靜默截斷會讓「沒有更多」與「沒給你更多」無法區分**。
    static let ambiguityLimit = 50
    /// `candidates` 的列數上限。**與 `ambiguityLimit` 同值但不同決定**（#236 R4）：
    /// 先前 candidates 直接借用上面那個常數，而它的 doc 講的是歧義清單——一個常數
    /// 承載兩個決定，日後為了其中一個調數字就會安靜地改到另一個。
    static let candidateLimit = 50
    /// 單筆歧義最多回幾個 person ref。同名的人數**無上界**（實測一筆歧義 60 人），
    /// 只限列數等於沒限 payload——見 `resolvePeople` 的三軸說明。
    static let refsPerAmbiguity = 20
    /// `people` 區塊最多幾筆。第三軸是「每筆多大」，由下方的 name 預算限制。
    static let peopleLimit = 60
    /// 歧義區塊的**位元組**預算（#236 R3）。
    ///
    /// 計數上限擋不住內容——`max:` 的單位是 scalar，而 `displaySafe` 逃脫後每個
    /// scalar 在 JSON 裡最多 9 bytes。實測：三軸計數上限都設了，最壞仍 125 KB。
    /// 位元組預算是唯一與內容無關的界。
    static let ambiguityByteBudget = 48 * 1024
    /// 每人最多送幾個異名。`names` 是**最弱**的區辨欄位（正規化後相同才會歧義），
    /// 而 `displaySafe` 是 8 倍膨脹器，所以壓得很低。
    ///
    /// 具名而非兩處各寫 `2`：預算估算（`personEntryBytes`）與實際輸出必須用同一個
    /// 數，否則預算會安靜地估錯——而估低正是讓位元組預算失效的那個方向。
    static let namesPerPerson = 2

    /// `candidates` 那一半的位元組預算（#236 R4 CRITICAL）。
    ///
    /// 先前它**只有列數上限、沒有位元組上限**，於是四軸都設好之後真 binary 仍吐出
    /// 281,919 bytes；而 `candidates[].id` 是 `"<citekey>:<index>"`、citekey 是原始
    /// store 內容而 `StoreKey.pattern` **沒有長度上限**——單一列實測 1,208,606 bytes。
    ///
    /// `id` 不能截斷：它是 `--apply` 要送回來的把手，截了就再也對不回去。所以改成
    /// **吃不下的整列不印**，並在 `candidateRowsDropped` 說出來——與 ambiguities 那
    /// 半同一種處置。代價是那筆候選在 MCP 這條路上套用不了（CLI 仍可），這比回一個
    /// 對不回去的 id、或回一個 1.2 MB 的 payload 誠實。
    static let candidateByteBudget = 48 * 1024

    /// 一個 JSON 值序列化後的**實際**位元組數。
    ///
    /// **不要手寫估算式。** 先前這裡是 `personEntryBytes`——一條手維護的加總；本輪
    /// 加了 `formerAffiliationEnd`／`formerAffiliationAttested`／`namesTotal` 卻沒同步
    /// 更新它，實測**低估達 5.9 倍**、48 KB 的預算被超出 15%（#236 R4 HIGH）。
    ///
    /// 估算式與被估的東西是**兩份會各自演化的規格**，而漂移是安靜的：預算看起來還在，
    /// 只是不再守住任何東西。直接量輸出的那一份就不可能漂——這是型別／結構層的解，
    /// 不是「記得同步更新」的紀律層的解。
    ///
    /// 包成陣列再量：任何 JSON 值都可序列化，多出的 2 bytes 是保守方向。
    static func jsonBytes(_ v: Any) -> Int {
        (try? JSONSerialization.data(withJSONObject: [v], options: []))?.count ?? 0
    }

    public init(root: URL, key: String? = nil, configURL: URL? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.root = root
        self.storeKey = key
        // configURL 與 environment 必須同源（#110，AppState 同款）——預設由
        // env-aware 的 AkashicHome 解析，而非寫死真實家目錄。
        self.configURL = configURL ?? AkashicHome.configURL(environment: environment)
        self.environment = environment
    }

    /// #37：index 位置取決於 registry key（`storeKey`；nil＝未註冊 → in-store 回落）。
    var store: LibraryStore { LibraryStore(root: root, key: storeKey, environment: environment) }

    // MARK: - 讀

    public func search(author: String? = nil, journal: String? = nil, tag: String? = nil,
                       type: String? = nil, yearFrom: Int? = nil, yearTo: Int? = nil,
                       library: String? = nil) throws -> String {
        let engine = try freshEngine()
        var filter = QueryFilter()
        filter.author = author
        filter.journal = journal
        filter.tag = tag
        filter.type = type
        filter.yearFrom = yearFrom
        filter.yearTo = yearTo
        filter.library = library
        return try jsonString(try engine.find(filter).map(summaryDict))
    }

    public func getEntry(citekey: String) throws -> String {
        let load = try store.load()
        guard let entry = load.entries.first(where: { $0.citekey == citekey }) else {
            throw ServiceError.notFound("citekey「\(displaySafe(citekey, max: 200))」")
        }
        return try jsonString(entryDict(entry))
    }

    public func relations(citekey: String, kind: String) throws -> String {
        let engine = try freshEngine()
        let result: [EntrySummary]
        switch kind {
        case "same-journal": result = try engine.sameJournal(as: citekey)
        case "same-author": result = try engine.sameAuthor(as: citekey)
        case "cites": result = try engine.cites(of: citekey)
        case "cited-by": result = try engine.citedBy(citekey)
        case "related": result = try engine.related(to: citekey)
        default:
            throw ServiceError.invalid("kind 必須是 same-journal / same-author / cites / cited-by / related")
        }
        return try jsonString(result.map(summaryDict))
    }

    public func graph(focus: String, depth: Int, format: String) throws -> String {
        try ensureFreshIndex()
        let builder = try GraphBuilder(indexPath: store.indexURL)
        let neighborhood = try builder.neighborhood(focus: focus, depth: depth)
        // 與 `export` 同一個邊界（#171 verify 171-4）：整份圖當 tool result 回 LLM，
        // 三個 renderer 的 escape 只管各自格式的 metacharacter，不管 C0／bidi。
        switch format {
        case "mermaid": return documentSafe(GraphRenderer.mermaid(neighborhood))
        case "dot": return documentSafe(GraphRenderer.dot(neighborhood))
        case "graphml": return documentSafe(GraphRenderer.graphml(neighborhood))
        default: throw ServiceError.invalid("format 必須是 mermaid / dot / graphml")
        }
    }

    public func export(citekeys: [String]?, format: String) throws -> String {
        let load = try store.load()
        var entries = load.entries
        if let wanted = citekeys {
            let wantedSet = Set(wanted)
            entries = entries.filter { wantedSet.contains($0.citekey) }
            let missing = wantedSet.subtracting(entries.map(\.citekey))
            guard missing.isEmpty else {
                throw ServiceError.notFound("citekeys：\(missing.sorted().map { displaySafe($0, max: 200) }.joined(separator: ", "))")
            }
        }
        // #165：**這是本 repo 最強的威脅模型**——匯出全文當 MCP tool result 直接進
        // LLM context。verify 席行為探針實測 `title`／`authors`／`fields` 裡的
        // raw ESC、U+202E、U+2028 **原樣通過** biblatex 層——它跳脫的是 TeX specials
        // （`{}` `\` `%` `&`），與 C0／bidi／LS-PS 是兩組**不相干的字元集**。
        // 「跳脫由 biblatex 層負責」這句話字面成立、實質全假。
        //
        // 消毒住**輸出邊界**而非 `BibExport`／`CSLExport`：同一份內容，去**檔案**
        // 時必須保真（消毒會破壞 .bib 的正確性，下游 BibTeX 引擎會壞），去**顯示**
        // 時必須消毒。CLI 的 `--output` 分支同理不消毒、stdout 分支消毒。
        //
        // **用 `documentSafe` 不用 `displaySafe`**（#171 verify 171-2）：後者跳脫
        // 反斜線（反偽造），而反斜線在 .bib 與 JSON 裡**是內容語法**——套上去會
        // 讓 `\\textit{}` 變 `\\u{005C}textit{}`、讓 JSON 的 `\\"` 變成不合法。
        //
        // **超量就拒絕，不截斷**（171-3）：截一半的文件是壞掉的文件，而 MCP 的
        // 回傳直接進 LLM context——200 MB 會炸掉任何 context。行長限制同樣拿掉：
        // `BibWriter` 一個欄位一行，abstract 是常態欄位，4000 上限會把它截成
        // 大括號不閉合的無效 .bib，且靜默。
        func safe(_ s: String) throws -> String {
            // **量消毒之後的長度**（#171 複驗 b′）：`documentSafe` 是 6 倍膨脹器
            // （實測 1 MB 全 ESC → 6 MB），量 `s` 會讓最壞情況真正進 context 的是
            // 48 MB 而不是 8 MB——「小到不會毀掉 context」在對抗性內容下不成立。
            let out = documentSafe(s)
            guard out.utf8.count <= Self.maxExportBytes else {
                // **指路只能指呼叫端真的有的旋鈕**（#171 複驗 b）：`akashic_export`
                // 的 schema 只有 `citekeys` 與 `format`——原本寫的 `--library`／`--tag`
                // 這裡不存在，而 MCP client 一般也跑不了 CLI。三個建議裡兩個是假的。
                throw ServiceError.invalid(
                    "匯出 \(out.utf8.count / 1024) KB 超過 MCP 上限 "   // display-safe-exempt: Int 算術
                    + "\(Self.maxExportBytes / 1024) KB（本庫 \(entries.count) 筆）"   // display-safe-exempt: Int
                    + "——tool result 進的是 LLM context。改傳 citekeys 分批匯出"
                    + "（本工具唯一的縮小方式）；要全庫請在終端跑 "
                    + "akashic export-bib --output <path>")
            }
            return out
        }
        switch format {
        case "bib": return try safe(BibExport.bibFile(entries: entries, people: load.people))
        case "csl-json":
            return try safe(CSLExport.cslJSON(entries: entries, people: load.people))
        default: throw ServiceError.invalid("format 必須是 bib / csl-json")
        }
    }

    public func people(query: String?) throws -> String {
        var people = try store.load().people
        if let q = query?.lowercased(), !q.isEmpty {
            people = people.filter { person in
                person.key.lowercased().contains(q)
                    || person.names.contains { $0.lowercased().contains(q) }
            }
        }
        let dicts = people.map { person -> [String: Any] in
            var d: [String: Any] = ["key": displaySafe(person.key, max: 200),
                                    "names": person.names.map { displaySafe($0, max: 200) }]
            if let orcid = person.orcid { d["orcid"] = orcid }
            if let openalex = person.openalex { d["openalex"] = openalex }
            if !person.unknownFields.isEmpty {   // #31：同 entryDict，只給 key
                d["unknownFields"] = person.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
            }
            return d
        }
        return try jsonString(dicts)
    }

    public func doctor() throws -> String {
        let load = try store.load()
        var d: [String: Any] = ["library": displaySafe(root.path, max: 800)]   // #164：與同 dict 其他值對齊

        // #35（鏡射 CLI doctor 的順序；#138 verify F1）：跨記錄檢查必須在 rebuild
        // **之前**。重複 citekey / person key 時 rebuild 會撞 UNIQUE constraint——
        // consumer 拿到的是 SQLite 內部錯誤，而不是「你有兩筆同 citekey 的記錄」。
        // 診斷工具在這種狀態下正是最該說話的時候，不是最該掛掉的時候。
        // severity 逐條攜帶（#138 verify F3）：✗/⚠ 之別在 CLI 面有、MCP 面就不能丟。
        let cross = load.crossRecordIssues()
        let fatalCross = cross.filter { $0.severity == .error }
        if !cross.isEmpty {
            d["crossRecordIssues"] = [
                "count": cross.count,
                "first": cross.prefix(20).map {
                    ["severity": $0.severity == .error ? "error" : "warning",
                     "message": displaySafe($0.message, max: 300)]
                },
            ] as [String: Any]
        }
        // #107：佈局殘留（報告不動手刪）。與 CLI 同：排在 fatal 早退之前——
        // 重複 citekey 的 store 正是最需要看清全貌的時候。
        let residue = try store.layoutResidue()
        if !residue.isEmpty {
            d["layoutResidue"] = residue.map { displaySafe($0, max: 300) }
        }
        // #224：blob ↔ index 一致性（audit 邏輯單一路徑在 SourceStore；此處只渲染）。
        // 三類皆空才不出現——沉默即健康；有事必須說（audit sidecar 的腐爛全靠這裡可見）。
        let srcAudit = try store.auditSourceIndex()
        if !srcAudit.orphanBlobs.isEmpty || !srcAudit.danglingEntries.isEmpty
            || !srcAudit.malformedLines.isEmpty {
            d["sources"] = [
                "orphanBlobs": srcAudit.orphanBlobs,          // digest 形（StoreKey 同級安全字元）
                "danglingIndexEntries": srcAudit.danglingEntries,
                "malformedIndexLines": srcAudit.malformedLines,
            ] as [String: Any]
        }
        // #76：divergence 計數無條件給（0 也是資訊）；同樣在 fatal 早退之前。
        d["divergences"] = load.divergences.count
        if !load.quarantined.isEmpty {
            // R11（R10-verify M19）：reason 含 Yams 展開的逐字檔案內容且不截斷——
            // MCP 情境下是直接灌進 LLM context 的無上限未信任字串。
            d["quarantined"] = load.quarantined.map {
                ["file": displaySafe($0.file, max: 300), "reason": displaySafe($0.reason, max: 512)]
            }
        }
        // #23 tolerant-preserve：較新 schema 的檔案可用但應提示升級
        if !load.unknownFieldFiles.isEmpty {
            d["unknownFieldFiles"] = load.unknownFieldFiles.map { displaySafe($0, max: 200) }
        }
        guard fatalCross.isEmpty else {
            d["entries"] = load.entries.count
            d["indexRebuilt"] = false
            d["note"] = "index 未重建——先修好 crossRecordIssues 內 severity=error 的重複"
            return try jsonString(d)
        }

        let stats = try LibraryIndex(store: store).rebuild()
        d["indexRebuilt"] = true
        d["entries"] = stats.entries
        d["people"] = stats.people
        d["relations"] = stats.relations
        d["unresolvedAuthorLiterals"] = load.entries.flatMap { entry in
            entry.authors.compactMap { if case .literal = $0 { return 1 } else { return nil } }
        }.count
        d["orphaned"] = load.entries.filter { $0.provenance?.orphanedAt != nil }
            .map { displaySafe($0.citekey, max: 200) }
        // #146：digest 形式的 source 殘留。**這一項是本檔案自己那條規矩的直接
        // 應用**——「CLI doctor 的普查面 MCP 也要有，同一個 store 不得從兩個
        // consumer 看到不同的事實」（#138 verify F3，見下方註解）。第一版只加了
        // CLI 側，席位實測 MCP 的 doctor 回傳裡完全沒有 digest 相關項，而同一份
        // store 的 CLI doctor 報 22。
        d["digestSources"] = ProvenanceMigration.residualDigestSources(load: load)
            .map { "\(displaySafe($0.record, max: 200)).\(displaySafe($0.field, max: 120))" }
            .sorted()
        // #81 / #82 / #67（#138 verify F3）：CLI doctor 的普查面 MCP 也要有——
        // 「同一個 store 不得從兩個 consumer 看到不同的事實」是本 change 的主旨。
        let nameGaps = load.recordsWithoutAuthorizedName()
        d["noAuthorizedName"] = [
            "people": nameGaps.people.count,
            "organizations": nameGaps.organizations.count,
            "firstPeople": nameGaps.people.prefix(10).map { displaySafe($0, max: 120) },
        ] as [String: Any]
        d["authorizedOnlyByCitationForm"] = load.recordsAuthorizedOnlyByCitationForm().count
        let deceasedOpen = load.recordsDeceasedWithOpenAffiliation()
        if !deceasedOpen.isEmpty {
            // 與 CLI 同：待人處理的工作清單，列全部不截斷
            d["deceasedWithOpenAffiliation"] = deceasedOpen.map { displaySafe($0, max: 120) }
        }
        return try jsonString(d)
    }

    /// #76：divergence 的 list-only 投影——「載入了幾筆、各是什麼」是可觀察性
    /// （#71 第 7 條自身的要求），與 doctor 計數同層。**不做**過濾與圖形化
    /// （那才是 #71 的「範圍外：歧異查詢或圖形化」）。
    public func listDivergences() throws -> String {
        let load = try store.load()
        return try jsonString([
            "count": load.divergences.count,
            "divergences": load.divergences
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { d in
                    [
                        "id": d.id.uuidString,
                        "question": displaySafe(d.question, max: 400),
                        "candidates": d.candidates.map {
                            ["key": displaySafe($0.key, max: 200), "shape": $0.shape.rawValue]   // display-safe-exempt: shape 是 EntityKind 的 enum rawValue，值域封閉
                        },
                        "hasJudgement": d.judgement != nil,
                    ] as [String: Any]
                },
        ])
    }

    // MARK: - 寫（衍生層 only）

    /// #18 多檔案：registry 檢視與 session 內切換（互不相通——切換即整個 universe 換掉）。
    /// use 不寫 config（server 是讀者；持久預設由 CLI file use 管）。
    public func files(action: String, key: String?) throws -> String {
        switch action {
        case "list":
            let config = try AkashicConfig.read(from: configURL)
            let list = config.files.keys.sorted().map { k -> [String: Any] in
                ["key": k,   // display-safe-exempt: registry key 受 StoreKey.isValid 雙重把關（AkashicConfig decode + FileCommands）
                 "path": displaySafe(config.files[k]!, max: 800),
                 "current": k == config.current]
            }
            // #171 複驗 (e)：**同一個函式的 `use` 分支已經包了** `displaySafe(root.path)`，
            // 同一個 dict 裡的 `path` 也包了——只有這兩個沒有。config.yaml 的 path
            // **值**是自由字串，只有 **key** 過 `StoreKey.isValid`（AkashicConfig:86），
            // 值只過 `cleanValue`（剝引號／inline comment，不碰控制字元）。
            var out: [String: Any] = ["files": list,
                                      "active_root": displaySafe(root.path, max: 800)]
            if let legacy = config.library { out["legacy_library"] = displaySafe(legacy, max: 800) }
            return try jsonString(out)
        case "use":
            guard let key, !key.isEmpty else {
                throw ServiceError.invalid("use 需要 key")
            }
            let config = try AkashicConfig.read(from: configURL)
            guard let path = config.files[key] else {
                let known = config.files.keys.sorted().joined(separator: ", ")
                throw ServiceError.notFound("檔案 key「\(displaySafe(key, max: 200))」（已註冊：\(known.isEmpty ? "無" : displaySafe(known, max: 400))）")
            }
            let newRoot = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard LibraryStore.isLibraryRoot(newRoot) else {
                throw ServiceError.invalid("「\(displaySafe(path, max: 300))」不是 Akashic library（缺 entries/ 目錄）")
            }
            root = newRoot
            storeKey = key          // #37：index 必須跟著切，否則用舊 store 的 index 查新 store
            return try jsonString(["active_root": displaySafe(root.path, max: 800),
                                   "key": key] as [String: Any])   // display-safe-exempt: key 受 StoreKey 約束
        default:
            throw ServiceError.invalid("未知 action「\(displaySafe(action, max: 120))」（list / use）")
        }
    }

    /// #14 人物檢索：person 聚合視圖。key 直查；模糊名回候選（絕不自動選）。
    /// key 與 name 互斥（同給擲錯）；空白輸入拒絕；候選上限 50。
    public func person(key rawKey: String?, name rawName: String?, library: String?) throws -> String {
        let key = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key, key.isEmpty { throw ServiceError.invalid("key 不可為空白") }
        if let name, name.isEmpty { throw ServiceError.invalid("name 不可為空白") }
        if key != nil && name != nil {
            throw ServiceError.invalid("key 與 name 互斥——擇一使用")
        }
        if let key {
            let load = try store.load()
            let record = load.people.first { $0.key == key }
            let engine = try freshEngine()
            // 存在性判準用全集（scoped 過濾不可誤報 notFound——person 可能只是不在該 library）
            let allPubs = try engine.personPublications(key: key, library: nil)
            guard record != nil || !allPubs.isEmpty else {
                throw ServiceError.notFound("person「\(displaySafe(key, max: 200))」")
            }
            let pubs = library == nil ? allPubs
                : try engine.personPublications(key: key, library: library)
            let co = try engine.coAuthors(of: key, library: library)
            // resolved 合著者的 name 給人讀的名字（people.names 首項），key 另放 person_key
            let nameByKey = Dictionary(uniqueKeysWithValues: load.people.map { ($0.key, $0.displayName(in: .latn)) })
            // #171 複驗 (g)：`record == nil` 但 `allPubs` 非空時（key 只出現在 entry 的
            // `.key(...)` 參照、沒有 person 記錄），呼叫端的字串原樣回吐——而同一個
            // 回應的 `publications[].authors` 裡那同一份字串是包了的。
            var personDict: [String: Any] = ["key": displaySafe(key, max: 200)]
            if let record {
                personDict["names"] = record.names.map { displaySafe($0, max: 200) }
                if !record.unknownFields.isEmpty {   // #31
                    personDict["unknownFields"] =
                        record.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
                }
                if let orcid = record.orcid { personDict["orcid"] = displaySafe(orcid, max: 200) }
                // **隸屬必須看得到**（#218 verify HIGH）。`profile.affiliations` 是
                // `entity-backlink-completeness` 封閉列舉的第 7 條，而且是**存在 person
                // 自己身上**的邊——連反向現算都不需要。先前這個聚合面沒有它，於是那條
                // 規則被它自己舉為範例的命令當天違反，README 的「隸屬哪裡」也沒有入口。
                //
                // `.key` 與 `.literal` **分開兩個欄位**，不折成一欄：未歸戶不得冒充
                // identity（同 `EntityRef` 的立場）。缺席即資訊——`RelationalExport`
                // 已記過這個理由：不需要「是否已歸戶」的旗標，兩個欄位可以互相矛盾，
                // 一個 sum type 不會。
                //
                // **`DateRange` 有四個欄位，四個都要帶**（#218 R2 verify HIGH，四個 lens
                // 獨立命中）。第一版只搬 `start`／`end`，於是：
                //
                //   start:2003, end:nil, ended:false（在職）      → {start:"2003"}
                //   start:2003, end:nil, ended:true （已離職）    → **逐位元組相同**
                //   attested:[2019,2021]（僅觀測點）              → {} 與「無時間資訊」同形
                //
                // `endedUnknown` 的 doc 指名的正是這個失效：「43 位退休 PI 只有『已退休』
                // 的事實、沒有年份——`end: nil` 的既有語意（進行中）會把整批算成現職」。
                // 而 `RelationalExport` 有輸出它（`ended_unknown` 欄、`affiliation_status
                // = retired`），所以漏掉等於讓兩個衍生面對同一筆記錄互相矛盾。
                //
                // **缺席看得出來，冒充看不出來** ——R1 的缺口是可見的，這一版若照舊
                // 就是對真人的假陳述，而且同時出現在 CLI 與直達 LLM 的 MCP 回應裡。
                //
                // 順序用 `inSerializationOrder` 而非 `sorted`：後者是**相等性比較器**，
                // `Temporal.swift:158` 逐字寫著「**不要拿它當序列化順序**（#69）」——
                // 它在無日期段上完全由 `value` 決勝（#69 的實例：主名被推到英文名之後）。
                let affs = record.profile.affiliations.inSerializationOrder.map { seg -> [String: Any] in
                    var d: [String: Any] = [:]
                    switch seg.value {
                    case .key(let k):     d["organization_key"] = displaySafe(k, max: 200)
                    case .literal(let s): d["literal"] = displaySafe(s, max: 200)
                    }
                    if let st = seg.range.start { d["start"] = displaySafe(st, max: 40) }
                    if let en = seg.range.end { d["end"] = displaySafe(en, max: 40) }
                    if seg.range.endedUnknown { d["ended"] = true }   // display-safe-exempt: Bool
                    if !seg.range.attested.isEmpty {
                        d["attested"] = seg.range.attested.map { displaySafe($0, max: 40) }
                    }
                    return d
                }
                // **空集合也要出現**（規則執行細節 4，同一輪剛把 co_authors 的省略判為 bug）：
                // 缺席時分辨不出「這個人沒有隸屬記錄」與「這個欄位掉了」。
                personDict["affiliations"] = affs
            }
            return try jsonString([
                "person": personDict,
                "publications": pubs.map(summaryDict),
                "co_authors": co.map { c -> [String: Any] in
                    var d: [String: Any] = ["count": c.count]
                    if let pk = c.personKey {
                        // #171 複驗 (f)：**下一行**的 `name` fallback 就是 `pk` 本身且包了，
                        // 同函式 :391 的另一個分支也包了。作者 key 讀寫兩端都沒有
                        // StoreKey 驗證——與 171-5(b) 的 `relations.cites` 完全同源。
                        d["person_key"] = displaySafe(pk, max: 200)
                        d["name"] = displaySafe(nameByKey[pk] ?? pk, max: 200)
                    } else {
                        d["name"] = displaySafe(c.name, max: 200)
                    }
                    return d
                },
            ] as [String: Any])
        }
        if let name {
            // 模糊名 → 候選清單（case-insensitive 子字串；單趟預算 pub counts；上限 50）
            let load = try store.load()
            let needle = name.lowercased()
            var keyPubCount: [String: Int] = [:]
            var literalCounts: [String: Int] = [:]
            for entry in load.entries {
                // per-entry 去重：publications 是「篇數」不是「掛名次數」
                //（同篇重複 author identity 只計一次，與 DISTINCT 語意對齊）
                var seenKeys = Set<String>()
                var seenLiterals = Set<String>()
                for author in entry.authors {
                    switch author {
                    case .key(let k): seenKeys.insert(k)
                    case .literal(let s):
                        if s.lowercased().contains(needle) { seenLiterals.insert(s) }
                    }
                }
                for k in seenKeys { keyPubCount[k, default: 0] += 1 }
                for s in seenLiterals { literalCounts[s, default: 0] += 1 }
            }
            var candidates: [[String: Any]] = []
            for p in load.people where p.names.contains(where: { $0.lowercased().contains(needle) })
                || p.key.lowercased().contains(needle) {
                candidates.append(["person_key": displaySafe(p.key, max: 200),
                                   "names": p.names.map { displaySafe($0, max: 200) },
                                   "publications": keyPubCount[p.key] ?? 0])   // display-safe-exempt: dict 查找，值是 Int 計數
            }
            for (literal, count) in literalCounts.sorted(by: { $0.key < $1.key }) {
                // #141 verify 實測：`literal` 是 Zotero 匯入的作者原字串（第三方最
                // 直接的來源），先前**裸送**進 MCP 回應。守衛沒抓到是因為 token 是
                // `.literal`（帶點）而這裡是裸變數名——正是 #141 記載的 bare-變數盲區。
                // 對照上方 :348 的 `person_key` 有消毒，同一個回應裡兩種待遇。
                candidates.append(["literal": displaySafe(literal, max: 200),
                                   "publications": count])
            }
            let capped = Array(candidates.prefix(50))
            var out: [String: Any] = ["candidates": capped]
            if candidates.count > 50 { out["truncated"] = true }
            return try jsonString(out)
        }
        throw ServiceError.invalid("person 需要 key 或 name 至少其一")
    }

    /// #13 多 library：registry 管理 + 成員操作（衍生層寫入邊界內）。
    public func libraries(action: String, key: String?, name: String?,
                          description: String?, citekey: String?) throws -> String {
        switch action {
        case "list":
            let load = try store.load()
            var counts: [String: Int] = [:]
            for entry in load.entries {
                for k in Set(entry.akashic.libraries) { counts[k, default: 0] += 1 }
            }
            return try jsonString(load.libraries.map { lib -> [String: Any] in
                var d: [String: Any] = ["key": displaySafe(lib.key, max: 200),
                                        "name": displaySafe(lib.name, max: 200),
                                        "members": counts[lib.key] ?? 0]   // display-safe-exempt: dict 查找，值是 Int 計數
                // #156 verify R4：library 的自由文字，與 name 同源（上面兩行已消毒）
                if let desc = lib.description {
                    d["description"] = displaySafe(desc, max: 800)
                }
                return d
            })
        case "create":
            guard let key, let name else {
                throw ServiceError.invalid("create 需要 key 與 name")
            }
            // 驗證先行：未驗證 key 不得進任何路徑組合（存在性 oracle 防護）
            guard StoreKey.isValid(key) else {
                throw ServiceError.invalid("library key「\(displaySafe(key, max: 200))」不符合 \(StoreKey.pattern)，拒絕寫入")   // display-safe-exempt: pattern 是常量
            }
            guard !FileManager.default.fileExists(atPath: store.libraryURL(key: key).path) else {
                throw ServiceError.invalid("library「\(displaySafe(key, max: 200))」已存在")
            }
            _ = try store.writeLibrary(Library(key: key, name: name, description: description))
            return try jsonString(["created": key])
        case "add", "remove":
            guard let key, let citekey else {
                throw ServiceError.invalid("\(displaySafe(action, max: 120)) 需要 key 與 citekey")
            }
            guard StoreKey.isValid(key) else {
                throw ServiceError.invalid("library key「\(displaySafe(key, max: 200))」不符合 \(StoreKey.pattern)")   // display-safe-exempt: pattern 是常量
            }
            let load = try store.load()
            // add 要求 registry 存在；remove 不要求——dangling membership（spec 允許）
            // 必須能用正式介面清理
            if action == "add", !load.libraries.contains(where: { $0.key == key }) {
                throw ServiceError.notFound("library「\(displaySafe(key, max: 200))」")
            }
            guard var entry = load.entries.first(where: { $0.citekey == citekey }) else {
                throw ServiceError.notFound("citekey「\(displaySafe(citekey, max: 200))」")
            }
            if action == "add" {
                if !entry.akashic.libraries.contains(key) { entry.akashic.libraries.append(key) }
            } else {
                entry.akashic.libraries.removeAll { $0 == key }
            }
            try writeAndReindex(entry)
            return try jsonString(["citekey": displaySafe(citekey, max: 200),
                                   "libraries": entry.akashic.libraries])
        default:
            throw ServiceError.invalid("未知 action「\(displaySafe(action, max: 120))」（list/create/add/remove）")
        }
    }

    public func setStatus(citekey: String, status: String?) throws -> String {
        var entry = try requireEntry(citekey)
        entry.akashic.status = status
        try writeAndReindex(entry)
        // #156 verify R5：**寫入 tool 自己的回應就吐原文**——攻擊路徑不是「寫進去
        // 再讀回來」，而是單一 MCP 來回：`akashic_set_status(status: "\u{1B}[31m…")`
        // 的回應直接把 raw ESC 送進 LLM context。比 `journal` 那條**更短**（那條還
        // 需要先毒化一份 Zotero 匯入）。而 `status` 的寫入路徑上**零格式驗證**
        // （全庫 grep `guard`/`throw`/`isValid`/`pattern` 對它零命中）。
        return try jsonString(["citekey": displaySafe(citekey, max: 200),
                               "status": status.map { displaySafe($0, max: 200) }
                                   ?? NSNull()] as [String: Any])
    }

    public func tag(citekey: String, add: [String], remove: [String]) throws -> String {
        var entry = try requireEntry(citekey)
        for t in add where !entry.akashic.tags.contains(t) {
            entry.akashic.tags.append(t)
        }
        entry.akashic.tags.removeAll { remove.contains($0) }
        try writeAndReindex(entry)
        // #156 verify R5：同 setStatus——`akashic_tag` 是 MCP 暴露的 tool，`tags`
        // 寫入路徑零驗證，回應直接吐原文。這是**同一個檔案裡的第三次同形**
        // （`literal`／`journal`／此處）：相鄰兩行，上面的 citekey 消毒了、下面的沒有。
        return try jsonString(["citekey": displaySafe(citekey, max: 200),
                               "tags": entry.akashic.tags.map { displaySafe($0, max: 200) }])
    }

    public func link(citekey: String, kind: String, add: [String], remove: [String]) throws -> String {
        var entry = try requireEntry(citekey)
        switch kind {
        case "cites":
            for t in add where !entry.akashic.relations.cites.contains(t) {
                entry.akashic.relations.cites.append(t)
            }
            entry.akashic.relations.cites.removeAll { remove.contains($0) }
        case "related":
            for t in add where !entry.akashic.relations.related.contains(t) {
                entry.akashic.relations.related.append(t)
            }
            entry.akashic.relations.related.removeAll { remove.contains($0) }
        default:
            throw ServiceError.invalid("kind 必須是 cites / related")
        }
        try writeAndReindex(entry)
        return try jsonString([
            "citekey": displaySafe(citekey, max: 200),
            // #171 verify 171-5(b)：`cites`／`related` 讀寫兩端**都沒有** StoreKey
            // 驗證（`load` 只驗 `citekey` 與 `libraries`，`writeEntry` 同樣），所以
            // 是完全自由的字串。實測 raw U+202E 經 `link()` 逐字回到 tool result。
            "cites": entry.akashic.relations.cites.map { displaySafe($0, max: 200) },
            "related": entry.akashic.relations.related.map { displaySafe($0, max: 200) },
        ] as [String: Any])
    }

    /// apply=nil → 只列候選；apply=["citekey:index", …] → 逐候選套用（#5 的 MCP 面）。
    public func resolvePeople(apply: [String]?) throws -> String {
        let load = try store.load()
        let report = PersonResolver.resolve(entries: load.entries, people: load.people)
        let candidates = report.candidates
        let withIDs = candidates.map { c -> (id: String, candidate: ResolutionCandidate) in
            (c.rowID, c)   // 複合鍵住在型別上（#236 R4）
        }
        guard let selected = apply else {
            // **#231：回應形狀由「候選陣列」改為物件。** 歧義（同一 literal 對到 2+ 人）
            // 先前與「沒人匹配」走同一條 continue，完全不留痕跡——而它才是需要人判斷的
            // 那個。陣列沒有地方放它，所以形狀必須改；`Server.swift` 的 tool description
            // 同步更新。
            let byKey = Dictionary(load.people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

            // ## 上限必須量對軸（#236 R2）
            //
            // 第一版只限**列數**（50）。席位實測：**一筆**歧義即可產出 **758 KB**，
            // 而回應同時聲稱 `truncated: false` / `ambiguityTotal: 1`——比完全沒有上限
            // 更糟，因為那個 `false` 是會被 LLM 消費端信任的斷言。
            //
            // payload 有**三個**成長軸，列數只是其中一個：
            //
            // 1. **列數**：O(歧義位置數)
            // 2. **列寬**：`personKeys` 長度 O(同名人數)，無上界（實測 60）
            // 3. **每筆 people 的大小**：`names` × `displaySafe`，而 displaySafe 是
            //    repo 自己文件化的 **8 倍膨脹器**——`max: 200` 可以輸出 1600 字元
            //
            // 三個都要限，而且 `truncated` 要反映**整個回應**、不只 ambiguities 陣列。
            // ## 預算按**列**分配，不按 key（#236 R3 CRITICAL）
            //
            // 第一版用全域排序後 `prefix(peopleLimit)` 取 key，再逐列 `compactMap` 查表。
            // 後果：排序落在 60 名之後的列**refs 全被丟光，而列照樣印出來**——實測
            // 50 列中 47 列 `personRefs: []`。一筆記錄說「這個名字對到 2+ 人、請你
            // 判斷」，然後列出零個人。
            //
            // 更危險的是**恰好剩一個 ref** 的列：LLM 讀起來像「已解析的唯一命中」，
            // 而那筆記錄標著「不可套用」。`AmbiguousMatch.init?` 拒絕 `count < 2` 正是
            // 為了讓這個狀態在型別層不可表達——而序列化邊界把它又造了出來。
            //
            // 修法：**逐列吃預算，吃不下就整列不印**（計入截斷）。一列的 refs 要嘛
            // 完整（至少 2 個）、要嘛整列不存在——不留「半截的歧義」。
            // 三軸的**列數／列寬／筆數**都是計數，而真正要守的是**位元組**。
            // `max:` 的單位是 scalar，但膨脹後每個 scalar 在 JSON 裡最多 9 bytes
            // （`\u{XXXX}` 再被 JSON 逃脫反斜線）——靜態算計數永遠追不上內容。
            // 實測：三軸都設了上限，最壞仍是 125 KB。所以**逐列累加實際位元組**，
            // 超過預算就停——這是唯一與內容無關的界。
            // 一筆 person 條目——**建一次，量測與輸出共用同一份**。先前是「估算式」
            // 與「輸出」兩份規格各自演化，本輪就漂了 5.9 倍（見 `jsonBytes`）。
            var entryCache: [String: [String: Any]] = [:]
            func personEntry(_ raw: String) -> [String: Any] {
                if let e = entryCache[raw] { return e }
                let p = byKey[raw]
                let allNames = p?.names ?? []
                var d: [String: Any] = [
                    "key": displaySafe(raw, max: 200),
                    // `names` 是**最弱**的區辨欄位（正規化後相同才會歧義），而 displaySafe
                    // 是 8 倍膨脹器，所以壓得很低。
                    "names": allNames.prefix(Self.namesPerPerson).map { displaySafe($0, max: 80) },
                ]
                // 丟了才報，而且報**總數**不報「丟了幾個」——使用端要判斷的是「我看到的
                // 是不是全部」，那需要分母。缺席即「沒丟」。
                if allNames.count > Self.namesPerPerson { d["namesTotal"] = allNames.count }
                // **缺席就不輸出**，不要送空字串——那會讓「沒有 ORCID」與「ORCID 是
                // 空字串」在 JSON 上不再有分別（同本檔 :185／:375 的慣例）。
                if let o = p?.orcid { d["orcid"] = displaySafe(o, max: 60) }
                if let o = p?.openalex { d["openalex"] = displaySafe(o, max: 60) }
                if let x = p?.died { d["died"] = displaySafe(x, max: 40) }
                // 只看 current 會讓「只有已結束隸屬」的人看起來毫無隸屬資訊。
                // `endedUnknown`(#63)／`attested`(#70) 被 `isOpen` 正確排除在現職外，
                // 但那不代表沒有資訊。三種過去狀態**各自有自己的欄位名**——把觀測點
                // 叫成 end 是捏造（#236 R4）。
                if let a = p?.profile.affiliations.current?.value {
                    d["currentAffiliation"] = displaySafe(a.displayName, max: 120)
                } else if let last = p?.profile.affiliations.latestPastSegment {
                    d["formerAffiliation"] = displaySafe(last.value.displayName, max: 120)
                    if let e = last.range.end { d["formerAffiliationEnd"] = displaySafe(e, max: 40) }
                    else if last.range.endedUnknown { d["formerAffiliationEnd"] = "unknown" }
                    else if let a = last.range.attested.max() { d["formerAffiliationAttested"] = displaySafe(a, max: 40) }
                }
                entryCache[raw] = d
                return d
            }
            func ambiguityRow(_ a: AmbiguousMatch, _ refs: [String]) -> [String: Any] {
                [
                    "entryID": a.entryID.uuidString,   // display-safe-exempt: UUID 的 uuidString 恆為 [0-9A-F-]
                    "citekey": displaySafe(a.citekey, max: 200),
                    "authorIndex": a.authorIndex,
                    "literal": displaySafe(a.literal, max: 400),
                    // ref 而非 key —— 見 `people` 的說明。送出的是**生成的** ref，
                    // store 衍生的 `personKeys` 只當查表鍵、不進輸出。
                    "personRefs": refs,   // display-safe-exempt: 生成的 ref（`p0`/`p1`…，恆為 [a-z0-9]）
                ]
            }

            var refByKey: [String: String] = [:]
            var rows: [(AmbiguousMatch, [String])] = []
            var droppedRows = 0
            var anyRefsTruncated = false
            var bytes = 0
            for a in report.ambiguities.prefix(Self.ambiguityLimit) {
                let wanted = Array(a.personKeys.prefix(Self.refsPerAmbiguity))
                if wanted.count < a.personKeys.count { anyRefsTruncated = true }
                let newKeys = wanted.filter { refByKey[$0] == nil }
                // 暫定 ref：與下方真正指派用同一條規則，讓量到的就是會送出去的那份
                var provisional = refByKey
                for (i, k) in newKeys.enumerated() { provisional[k] = "p\(refByKey.count + i)" }
                let cost = Self.jsonBytes(ambiguityRow(a, wanted.compactMap { provisional[$0] }))
                    + newKeys.reduce(0) { $0 + Self.jsonBytes(personEntry($1)) }
                guard refByKey.count + newKeys.count <= Self.peopleLimit,
                      bytes + cost <= Self.ambiguityByteBudget else {
                    droppedRows += 1   // 預算容不下這一列的**全部**候選 → 整列不印
                    continue
                }
                bytes += cost
                refByKey = provisional
                rows.append((a, wanted))
            }
            let shown = rows.map(\.0)
            let shownRefKeys = rows.map(\.1)
            let refKeys = refByKey.keys.sorted()

            // ## candidates 那一半也要位元組預算（#236 R4 CRITICAL）
            //
            // 先前只有列數上限。`id` 是 `"<citekey>:<index>"`，citekey 是原始 store
            // 內容而 `StoreKey.pattern` 沒有長度上限——單列實測 1,208,606 bytes。
            // `id` 不能截斷（那是 `--apply` 的把手），所以吃不下的**整列不印**。
            var candidateRows: [[String: Any]] = []
            var candidateBytes = 0
            var candidatesDropped = 0
            for pair in withIDs.prefix(Self.candidateLimit) {
                let row: [String: Any] = [
                    "id": pair.id,   // display-safe-exempt: 形如 "<citekey>:<index>"；citekey 受 load 端 StoreKey quarantine 把關（#171）
                    "citekey": displaySafe(pair.candidate.citekey, max: 200),
                    "authorIndex": pair.candidate.authorIndex,
                    "literal": displaySafe(pair.candidate.literal, max: 400),
                    "personKey": displaySafe(pair.candidate.personKey, max: 200),
                    "reason": displaySafe(pair.candidate.reason, max: 400),
                ]
                let cost = Self.jsonBytes(row)
                guard candidateBytes + cost <= Self.candidateByteBudget else {
                    candidatesDropped += 1
                    continue
                }
                candidateBytes += cost
                candidateRows.append(row)
            }
            // 第四種丟棄：`people[ref]["names"]` 的 `prefix(2)`（#236 R4）。先前只算
            // 三軸（rows／refs／candidates），於是一個「每人五個異名、全部只送兩個」
            // 的回應仍宣稱 `truncated: false`——旗標按**自己的定義**說謊（下方 :745
            // 寫的是「整個回應……任一被截都算」），與 R3 抓到的 candidates 同型。
            let anyNamesDropped = refKeys.contains { (byKey[$0]?.names.count ?? 0) > Self.namesPerPerson }
            let truncated = report.ambiguities.count > Self.ambiguityLimit
                || anyRefsTruncated
                || droppedRows > 0
                || anyNamesDropped
            return try jsonString([
                "candidates": candidateRows,
                "candidateRowsDropped": candidatesDropped,
                // **區辨欄位只送一次**（`people`），`ambiguities` 只帶 ref。先前每筆歧義
                // 都內嵌完整的 person 區塊——verify 席實測 201 筆產出 176 KB（約 44k
                // tokens），其中 201 份是同一區塊的逐字複本。MCP 結果直灌 LLM context，
                // 這是本 repo 明文的威脅模型（`TerminalOutputSafetyTests`：「MCP/LLM
                // context 的無上限灌注同型」）。
                //
                // ## 索引鍵是**不透明 ref**，不是消毒後的 person key
                //
                // 第一版用 `displaySafe(k)` 當 dictionary key —— **那會讓整個 MCP
                // process trap**（#236 R2，三個 lens 各自重現）：
                //
                // - `Dictionary(uniqueKeysWithValues:)` 對重複鍵是 **precondition
                //   failure（SIGTRAP）**，不是可捕捉的 error
                // - `displaySafe` 在 `max` 處截斷 → **非單射**
                // - `StoreKey.pattern` **沒有長度上限**
                //
                // 於是兩個共用 200 字元前綴的**合法** key 就能讓 server 崩潰，且只需
                // 兩次 `akashic_add_person` + 一筆 entry 即可觸發，之後每次呼叫都再崩。
                //
                // 根因是把**消毒函數當成識別函數**——`displaySafe` 的目的是安全顯示，
                // 不是保持區別，而這兩個目標在多對一的映射上直接衝突。ref 把兩者
                // 分開：ref 負責識別（生成即唯一），`key` 欄位負責顯示（消毒後）。
                //
                // 只為**實際回傳**的那些歧義建 `people`（`shown`），不是全部——否則
                // 上限只擋住較瘦的一半，而 `people` 條目比 `ambiguities` 條目肥。
                // 條目由上方的 `personEntry` 建（**量測與輸出同一份**），這裡只做
                // ref→條目的對應。ref 由生成器發，彼此必不同，故 `uniqueKeysWithValues`
                // 安全——用 `displaySafe(key)` 當鍵才會 trap。
                "people": Dictionary(uniqueKeysWithValues:
                    refKeys.map { (refByKey[$0]!, personEntry($0)) }),
                "ambiguityRowsDropped": droppedRows,
                "ambiguities": shown.enumerated().map { (i, a) in
                    ambiguityRow(a, shownRefKeys[i].compactMap { refByKey[$0] })
                },
                // **整個回應**的截斷旗標。任一軸被截都算——列數／每列 ref 數／異名數／
                // 位元組預算（兩半各自的），以及 candidates 的列數上限。
                // 每次漏算一軸，這個 `false` 就是一句會被 LLM 消費端信任的假話。
                "truncated": truncated
                    || withIDs.count > Self.candidateLimit
                    || candidatesDropped > 0,
                "candidateTotal": withIDs.count,
                "ambiguityTotal": report.ambiguities.count,
            ])
        }
        let byID = Dictionary(withIDs.map { ($0.id, $0.candidate) }, uniquingKeysWith: { first, _ in first })
        let chosen = try selected.map { id -> ResolutionCandidate in
            guard let c = byID[id] else {
                throw ServiceError.notFound("候選 id「\(displaySafe(id, max: 200))」（先不帶 apply 列出候選）")
            }
            return c
        }
        let applied = PersonResolver.apply(chosen, to: load.entries)
        var written = 0
        var writeFailed: [String: String] = [:]
        // R7（R6-verify M21）：per-item 收容——單筆 encode 拒寫不中斷批次、
        // index 照 rebuild、失敗照實回報
        for (before, after) in zip(load.entries, applied) where before != after {
            do {
                try store.writeEntry(after)
                written += 1
            } catch {
                writeFailed[after.citekey] = displaySafe(String(describing: error), max: 512)
            }
        }
        // R9（R8-verify M8）：rebuild 擲錯不得吞掉 writeFailed 報告
        do {
            try LibraryIndex(store: store).rebuild()
        } catch {
            // R10（R9-verify L17）：附已改寫數——operator 才能對帳磁碟狀態
            throw ServiceError.invalid(
                "index rebuild 失敗：\(displaySafe(String(describing: error), max: 512))（本批已改寫 \(written) 檔；writeFailed \(writeFailed.count) 筆：\(writeFailed.map { "\(displaySafe($0.key, max: 200))（\(displaySafe($0.value, max: 512))）" }.sorted().joined(separator: "; "))）")   // display-safe-exempt: written 是 Int；error 與 writeFailed 同行已 displaySafe
        }
        // R8（R7-verify L15）：applied 不誇報——排除寫入失敗的候選
        let appliedActual = chosen.filter { writeFailed[$0.citekey] == nil }
            .map { "\(displaySafe($0.citekey, max: 200)):\($0.authorIndex)" }
        var result: [String: Any] = ["applied": appliedActual, "entriesRewritten": written]
        if !writeFailed.isEmpty { result["writeFailed"] = Dictionary(uniqueKeysWithValues: writeFailed.map { (displaySafe($0.key, max: 200), displaySafe($0.value, max: 512)) }) }
        return try jsonString(result)
    }

    public func createEntry(type: String, title: String, authors: [String],
                            date: String?, fields: [String: String]) throws -> String {
        guard !type.trimmingCharacters(in: .whitespaces).isEmpty,
              !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ServiceError.invalid("type 與 title 不可為空")
        }
        let load = try store.load()
        // quarantined 檔 basename 佔住 citekey（Phase 1 合約：quarantined 檔永不被自動覆寫）
        var existing = Set(load.entries.map(\.citekey))
        for q in load.quarantined where q.file.hasPrefix("entries/") {
            let basename = String(q.file.dropFirst("entries/".count)).lowercased()
            if basename.hasSuffix(".yaml") {
                existing.insert(String(basename.dropLast(".yaml".count)))
            }
        }
        let family = authors.first.flatMap { $0.split(separator: " ").last.map(String.init) }
        let citekey = Citekey.generate(
            familyName: family, year: date, title: title, existing: existing)
        // 最後防線：目的檔已存在（含 quarantined/大小寫別名）→ 拒寫
        guard !FileManager.default.fileExists(atPath: store.entryURL(citekey: citekey).path) else {
            throw ServiceError.invalid("目的檔已存在：entries/\(displaySafe(citekey, max: 200)).yaml（可能是 quarantined 檔）")
        }
        var entry = Entry(id: UUID(), citekey: citekey, type: type, title: title,
                          authors: authors.map { .literal($0) }, date: date)
        // **鍵在這一層正規化，不在呼叫端**（#206 verify C1）。
        //
        // `Entry.fields` 的鍵**直接**成為匯出的 biblatex 欄位名，所以一個帶空格或
        // 數字開頭的鍵不是難看，是讓**整份** library 的 `export-bib` 產物 biber
        // 解析不了（實測：一筆壞鍵 → `biber --tool` 報 syntax error 且完全不產出檔）。
        //
        // 第一版只在 CLI 的 `.bib` 路徑做正規化，於是 **JSON 路徑與整個 MCP 面**
        // 都繞得過去——而 `akashic_create_entry` 正是 LLM 會呼叫的那支。修在 service
        // 是因為這裡是**兩個介面唯一的交會點**；補在任一呼叫端都會留下另一個洞。
        var normalized: [String: String] = [:]
        var rejectedKeys: [String] = []
        for key in fields.keys.sorted() {           // 排序 → 撞鍵時的勝者是決定性的
            guard let value = fields[key] else { continue }
            guard let k = FieldKey.normalized(key) else {
                rejectedKeys.append(key); continue   // 無法表達成合法欄位名
            }
            if normalized[k] != nil { rejectedKeys.append(key); continue }  // 正規化後撞鍵
            normalized[k] = value
        }
        // **不可表達的鍵一律拒寫，不靜默丟。**（#206 verify M1／規則 §3）
        // 丟一個欄位而不說，會讓「store 沒有這個欄位」與「來源沒給」變成同一個
        // 觀察——那兩件事事後完全無法區分，正是本 change 的規則要防的。
        guard rejectedKeys.isEmpty else {
            throw ServiceError.invalid(
                "以下欄位名無法表達成合法的 biblatex 欄位（或正規化後與其他欄位相撞），"
                + "已拒絕寫入整筆——請改名後重試："
                + rejectedKeys.map { displaySafe($0, max: 80) }.joined(separator: "、"))
        }
        entry.fields = normalized
        try writeAndReindex(entry)
        return try jsonString(["citekey": displaySafe(citekey, max: 200),
                               "id": entry.id.uuidString])
    }

    public func addPerson(key: String, names: [String], orcid: String?, openalex: String?) throws -> String {
        let load = try store.load()
        guard !load.people.contains(where: { $0.key == key }) else {
            throw ServiceError.invalid("person key「\(displaySafe(key, max: 200))」已存在")
        }
        // quarantined people 檔同樣受保護：目的檔存在即拒寫
        guard !FileManager.default.fileExists(atPath: store.personURL(key: key).path) else {
            throw ServiceError.invalid("people/\(displaySafe(key, max: 200)).yaml 已存在（可能是 quarantined 檔），不覆寫")
        }
        let person = Person(key: key, names: names, orcid: orcid, openalex: openalex)
        try store.writePerson(person)
        try LibraryIndex(store: store).rebuild()
        // #171 verify 171-5(c)：單一 MCP 來回把呼叫端字串原樣吐回 LLM context——
        // 這就是 #156 verify R5 在 `setStatus` 上認定為真洩漏並修掉的同一形狀。
        return try jsonString(["key": key, "names": names.map { displaySafe($0, max: 200) }])
    }

    /// #77 層次 2：MCP 面的歧異記錄入口。LLM 驅動的補完流程遇到同一性疑問時
    /// **當場記錄而非當場判斷**（#71 的診斷點）。candidates 格式與 CLI 一致
    /// （`key:shape`）。刻意**無** MCP 版 resolve——消歧含合併＋全庫改寫＋刪檔，
    /// tracked+clean 前提與人工確認屬 CLI／App 的互動面。
    public func recordDivergence(question: String, candidates: [String],
                                 judgement: String?, restsOn: [String],
                                 prefers: String? = nil) throws -> String {
        let parsed: [(key: String, shape: EntityKind)] = try candidates.map { spec in
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let shape = EntityKind(rawValue: parts[1]) else {
                throw ServiceError.invalid(
                    "候選格式為 `key:shape`（shape ∈ \(EntityKind.allCases.filter { $0 != .divergence }.map(\.rawValue).joined(separator: " / "))），得到「\(displaySafe(spec, max: 120))」")   // display-safe-exempt: EntityKind 是封閉列舉，rawValue 是編譯期字面量；spec 已 displaySafe
            }
            return (key: parts[0], shape: shape)
        }
        let d = try store.recordDivergence(question: question, candidates: parsed,
                                           judgement: judgement, restsOn: restsOn,
                                           prefers: prefers)
        return try jsonString([
            "id": d.id.uuidString,
            // 與 :233 的列表回應一致（那裡本來就 displaySafe）。key 受
            // StoreKey.isValid 約束成 [a-z0-9-]，本身載不了控制字元——但同一份資料
            // 在同一個檔案裡有兩種待遇，遲早有人照沒消毒的那個抄。
            "candidates": d.candidates.map { displaySafe($0.key, max: 200) },
            "hasJudgement": d.judgement != nil,
            // #75 對一：傾向回傳給呼叫端——它是消歧會據以比對的結構化欄位
            "prefers": d.judgement?.prefers.map { displaySafe($0, max: 200) } ?? NSNull(),
            "note": "記下判斷不等於消歧——合併請由人工跑 akashic resolve-divergence",
        ] as [String: Any])
    }

    public func importZotero(zoteroDb: String?, libraryID: Int?) throws -> String {
        let path = ((zoteroDb ?? "~/Zotero/zotero.sqlite") as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw ServiceError.notFound("zotero.sqlite：\(displaySafe(path, max: 300))")
        }
        try store.ensureLayout()
        let report = try ZoteroImporter(store: store)
            .run(zoteroDB: URL(fileURLWithPath: path), libraryID: libraryID)
        // R10（R9-verify M3/M5）：rebuild 擲錯不得吞掉整份 import report——
        // 磁碟滿等原因與 writeFailed 正相關，最需要報告的場景恰好最易被吞
        do {
            try LibraryIndex(store: store).rebuild()
        } catch {
            throw ServiceError.invalid(
                "index rebuild 失敗：\(displaySafe(String(describing: error), max: 512))（本趟 import 已落地：created \(report.created.count)、updated \(report.updated.count)、orphaned \(report.orphaned.count)；writeFailed \(report.writeFailed.count) 筆：\(report.writeFailed.keys.sorted().map { displaySafe($0, max: 200) }.joined(separator: ", "))）")
        }
        var d: [String: Any] = [
            "created": report.created.map { displaySafe($0, max: 200) },
            "updated": report.updated.map { displaySafe($0, max: 200) },
            "orphaned": report.orphaned.map { displaySafe($0, max: 200) },
            "orphanCleared": report.orphanCleared.map { displaySafe($0, max: 200) },
            "unchanged": report.unchanged,
            // #171 verify 171-5(d)：key 是 Zotero 未映射的欄位名＝第三方字串，
            // 而同一個 dict literal 裡其餘七個值全部消毒。
            // #206：欄位不再被丟棄，改以正規化後的原名入庫——鍵名跟著改，
            // 否則 MCP 面回給 LLM 的仍是「dropped」這個假訊號（verify H2）
            "residualFields": Dictionary(uniqueKeysWithValues:
                report.residualFields.map { (displaySafe($0.key, max: 200), $0.value) }),
            "unnormalizedDates": report.unnormalizedDates.map { displaySafe($0, max: 200) },
            "skippedLinkedAttachments": report.skippedLinkedAttachments,
        ]
        if !report.authorsPreserved.isEmpty { d["authorsPreserved"] = report.authorsPreserved.map { displaySafe($0, max: 200) } }
        if !report.quarantineConflicts.isEmpty { d["quarantineConflicts"] = report.quarantineConflicts.map { displaySafe($0, max: 200) } }
        if !report.writeFailed.isEmpty { d["writeFailed"] = Dictionary(uniqueKeysWithValues: report.writeFailed.map { (displaySafe($0.key, max: 200), displaySafe($0.value, max: 512)) }) }
        return try jsonString(d)
    }

    // MARK: - Internals

    func requireEntry(_ citekey: String) throws -> Entry {
        guard let entry = try store.load().entries.first(where: { $0.citekey == citekey }) else {
            throw ServiceError.notFound("citekey「\(displaySafe(citekey, max: 200))」")
        }
        return entry
    }

    func writeAndReindex(_ entry: Entry) throws {
        try store.writeEntry(entry)
        try LibraryIndex(store: store).rebuild()
    }

    /// index stale（entries/people 有更新 mtime 或 index 缺）→ 重建，再開 QueryEngine。
    func ensureFreshIndex() throws {
        // schema 版本 + store 身分先於 mtime（#13 verify、#122）：舊 binary 建的 index
        // 撞新查詢會 no such table；別的 store 建的 index（registry 路徑重新利用）
        // 內容整份是別人的
        if !LibraryIndex.isCurrent(indexPath: store.indexURL, expectedRoot: store.root) {
            try LibraryIndex(store: store).rebuild()
            return
        }
        let fm = FileManager.default
        let indexPath = store.indexURL.path
        let indexMtime = (try? fm.attributesOfItem(atPath: indexPath)[.modificationDate] as? Date) ?? nil
        guard let indexMtime else {
            try LibraryIndex(store: store).rebuild()
            return
        }
        var newest = Date.distantPast
        // #35：**entities/ 必須在掃描範圍內**——format 2 的 store 所有 canonical 都在
        // 那裡，漏掉它會讓 index 永遠被判為 current 而回答過期的查詢（verify CRITICAL）。
        for dir in [store.entitiesDir, store.entriesDir, store.peopleDir] {
            // 目錄自身 mtime 在檔案增刪時更新——外部刪檔靠這個偵測
            if let dirM = (try? fm.attributesOfItem(atPath: dir.path)[.modificationDate]) as? Date,
               dirM > newest {
                newest = dirM
            }
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for f in files {
                if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   m > newest {
                    newest = m
                }
            }
        }
        if newest > indexMtime {
            try LibraryIndex(store: store).rebuild()
        }
    }

    func freshEngine() throws -> QueryEngine {
        try ensureFreshIndex()
        return try QueryEngine(indexPath: store.indexURL)
    }

    func summaryDict(_ s: EntrySummary) -> [String: Any] {
        var d: [String: Any] = [
            // #164 第四方向抓到的：`type` 是 biblatex 型別，來自 Zotero 匯入的映射
            // ——值域**看起來**封閉，但 `Entry.validate()` 只驗「不可為空」，沒有
            // 白名單。與同一個 dict 裡已消毒的 citekey／title 同源。
            "citekey": displaySafe(s.citekey, max: 200),
            "type": displaySafe(s.type, max: 200),
            "title": displaySafe(s.title, max: 800),
            "authors": s.authors.map { displaySafe($0, max: 200) },
        ]
        if let year = s.year { d["year"] = year }   // display-safe-exempt: Int
        // #156 verify 156-15：`journal` 先前**裸送**。同一個檔案的 `entryDict` 自己
        // 寫著「fields 值是 biblatex 第三方內容（journal、booktitle…）——與 title
        // 同源」並在那裡消毒了——一處消毒、一處裸送，與 `bcd46d4` 剛修掉的
        // `["literal": literal]` 是同一個形狀。summaryDict 餵的是 publications／
        // search 回應，MCP 直達 LLM。
        if let journal = s.journal { d["journal"] = displaySafe(journal, max: 800) }
        return d
    }

    func entryDict(_ entry: Entry) -> [String: Any] {
        var d: [String: Any] = [
            "id": entry.id.uuidString,
            "citekey": displaySafe(entry.citekey, max: 200),
            "type": displaySafe(entry.type, max: 200),   // 同上（#164）
            "title": displaySafe(entry.title, max: 800),
            "authors": entry.authors.map { author -> [String: String] in
                switch author {
                case .key(let k): return ["key": displaySafe(k, max: 200)]
                // literal 是 Zotero 匯入的第三方原文——掃描器對 case 行的短變數
                // 值是盲點（見 DisplaySinkCoverageTests doc），此站點靠人工 + 測試釘
                case .literal(let s): return ["literal": displaySafe(s, max: 400)]
                }
            },
            // fields 值是 biblatex 第三方內容（journal、booktitle…）——與 title 同源
            "fields": entry.fields.mapValues { displaySafe($0, max: 800) },
        ]
        if let date = entry.date { d["date"] = displaySafe(date, max: 200) }
        if !entry.attachments.isEmpty {
            d["attachments"] = entry.attachments.map {
                [$0.kind.rawValue: displaySafe($0.path, max: 800)]
            }
        }
        if let prov = entry.provenance {
            // #171 verify 171-5(a)：與**下一行**的 `zotero_hash` 同一個 struct、同一個
            // 來源、同一個 dict——那行包了 displaySafe 而這行沒有。這正是本檔案已經
            // 記錄過三次的形狀（literal／journal／tags）：同資料兩種待遇。
            var p: [String: Any] = ["zotero_key": displaySafe(prov.zoteroKey, max: 200),
                                    "zotero_version": prov.zoteroVersion]
            if let lid = prov.libraryID { p["library_id"] = lid }   // display-safe-exempt: Int
            // #156 verify R4：Zotero 來源的字串（雖為 hash 形狀，但本 binary 未驗證
            // 它真的是 hash——那是 Zotero 寫進來的自由字串）
            if let hash = prov.zoteroHash {
                p["zotero_hash"] = displaySafe(hash, max: 200)
            }
            let iso = ISO8601DateFormatter()
            if let at = prov.importedAt { p["imported_at"] = iso.string(from: at) }
            if let at = prov.orphanedAt {
                p["orphaned"] = true
                p["orphaned_at"] = iso.string(from: at)
            }
            d["provenance"] = p
        }
        var akashic: [String: Any] = [:]
        // #156 verify R4：`tags` 是自由文字，且 **#133 起 LLM 可經 MCP 寫入**
        // ——來源面與 divergence 的 judgement 同級，優先於其他幾條
        if !entry.akashic.tags.isEmpty {
            akashic["tags"] = entry.akashic.tags.map { displaySafe($0, max: 200) }
        }
        if !entry.akashic.libraries.isEmpty { akashic["libraries"] = entry.akashic.libraries }
        if let status = entry.akashic.status { akashic["status"] = displaySafe(status, max: 200) }
        // 同 171-5(b)：`link()` 與 `entryDict()` 兩端都吐，兩端都要包。
        if !entry.akashic.relations.cites.isEmpty {
            akashic["cites"] = entry.akashic.relations.cites.map { displaySafe($0, max: 200) }
        }
        if !entry.akashic.relations.related.isEmpty {
            akashic["related"] = entry.akashic.relations.related.map { displaySafe($0, max: 200) }
        }
        d["akashic"] = akashic
        // #31：讀取面必須露出「這筆記錄有本 binary 不認得的欄位」。只給 key 不給值——
        // 值是未信任的逐字原文，灌進 LLM context 沒有意義且是注入面；key 足以讓使用者
        // 知道「這裡有東西、你的 binary 看不懂」並去升級。
        if !entry.unknownFields.isEmpty {
            d["unknownFields"] = entry.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
        }
        return d
    }

    func jsonString(_ obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
