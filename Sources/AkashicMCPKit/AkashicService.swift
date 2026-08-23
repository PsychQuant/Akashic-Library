import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicZoteroImport
import AkashicWoSImport
import AkashicExport
import AkashicIndex
import AkashicQuery
import AkashicGraph

public enum ServiceError: Error, LocalizedError {
    case notFound(String)
    case invalid(String)
    /// #227 verify R2 C6：store 有讀不進來的檔時，「存在性」**無法判定**——這不是
    /// `notFound`（那是確定的否），拋錯類型與訊息前綴都不得宣稱不存在，否則依
    /// 錯誤種類或「找不到」字面分支的呼叫端（含 LLM）會把未知當成否。
    case undeterminable(String)

    public var errorDescription: String? {
        switch self {
        // #142 / #149 verify F3：what 由 throw 站點組裝並消毒 caller payload
        // （見 notFound(…) 各呼叫端的 displaySafe），此處**不再**消毒——displaySafe
        // 會跳脫反斜線本身、不 idempotent，兩層會把 \u{001B} 變成 \u{005C}u{001B}
        // 並讓外層 max 對已膨脹字串二次截斷。守衛（error-sink 規則 + throw 站點
        // 在掃描面內）保證新 throw 站點的 caller payload 都消毒。
        case .notFound(let what): return "找不到：\(what)"   // display-safe-exempt: what 由 throw 站點消毒（見上方註解）
        case .invalid(let why): return why
        case .undeterminable(let what): return "無法判定：\(what)"   // display-safe-exempt: 同 notFound——what 由 throw 站點消毒
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
        let hits = try engine.find(filter)
        if hits.isEmpty { try assertEmptinessIsDeterminable("search") }
        return try jsonString(hits.map(summaryDict))
    }

    public func getEntry(citekey: String) throws -> String {
        let load = try store.load()
        guard let entry = load.entries.first(where: { $0.citekey == citekey }) else {
            // 「查不到」與「讀不進來」是兩件事（#294 的同一條紀律）。
            if !load.quarantined.isEmpty {
                throw ServiceError.undeterminable(
                    "citekey「\(displaySafe(citekey, max: 200))」——store 另有 "
                    + "\(load.quarantined.count) 個檔 quarantined（可能是未遷移的舊形狀，"   // display-safe-exempt: count 是 Int
                    + "該 citekey 或許在其中）；見 akashic doctor")
            }
            throw ServiceError.notFound("citekey「\(displaySafe(citekey, max: 200))」")
        }
        var d = entryDict(entry)

        // **反向邊在這裡加，不在 `entryDict` 裡**（#260）。
        //
        // `entryDict` 的職責是「這筆 entry 身上**存了**什麼」；反向邊依
        // `entity-backlink-completeness` 是**現算不儲存**的。分在兩個函式，讓那條
        // 紀律在程式碼結構上看得見——而不是靠註解說「這幾個鍵是算出來的」。
        //
        // 兩條衍生鏈**都已存在**（`QueryEngine` 走 SQLite 的 `relations` 表），修法
        // 純粹是接線。這與該規則失敗史的原句同形：「衍生鏈完整，但只有 MCP 接上去」。
        let engine = try freshEngine()

        // `citedBy` ＝ 封閉列舉第 2 條邊（`cites`）的反向。
        let citedBy = try engine.citedBy(entry.citekey)
        if !citedBy.isEmpty {
            d["citedBy"] = citedBy.map { displaySafe($0.citekey, max: 200) }.sorted()
        }

        // `related` 是**對稱邊**（封閉列舉第 3 條）。規則明文：「存在 entry 側是
        // **約定**、非推導」——所以只顯示本側的那一半是實作巧合，不是語意。
        // `QueryEngine.related(to:)` 的 SQL 已同時查兩個方向，直接用。
        //
        // 覆蓋 `entryDict` 寫入的單向 `related`：兩者同名而後者是完整集合，留兩個鍵
        // 會讓消費端得猜哪個才算數。
        let related = try engine.related(to: entry.citekey)
        var akashic = (d["akashic"] as? [String: Any]) ?? [:]
        if related.isEmpty {
            akashic.removeValue(forKey: "related")
        } else {
            akashic["related"] = related.map { displaySafe($0.citekey, max: 200) }.sorted()
        }
        if !akashic.isEmpty { d["akashic"] = akashic }

        return try jsonString(d)
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
        if result.isEmpty { try assertEmptinessIsDeterminable("relations") }
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
                let names = missing.sorted().map { displaySafe($0, max: 200) }.joined(separator: ", ")
                // 與 `person()` 完全同型（#294）：**指名的 citekey 查無，而 store 另有
                // 讀不進來的檔——存在性無法判定**。先前一律擲 `notFound`，依 error kind
                // 分支的呼叫端會把「或許在 quarantine 裡」當成「確定不存在」。
                if !load.quarantined.isEmpty {
                    throw ServiceError.undeterminable(
                        "citekeys：\(names)——store 另有 \(load.quarantined.count) 個檔 "   // display-safe-exempt: names 在上方建構時已逐項 displaySafe(max: 200)；displaySafe 不冪等，再包一次會逃脫反斜線自身。count 是 Int
                        + "quarantined（可能是未遷移的舊形狀，該 citekey 或許在其中）；"
                        + "見 akashic doctor")
                }
                throw ServiceError.notFound("citekeys：\(names)")   // display-safe-exempt: 同上——names 已逐項 displaySafe
            }
        }
        // 未指名 citekey（匯出全庫）而結果為空——同一條紀律的列表面。
        if citekeys == nil, entries.isEmpty { try assertEmptinessIsDeterminable("export") }
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
        case "bib":
            // #326：APA7 完整性報告。MCP 沒有 stderr 通道（CLI 走那裡），所以報告以
            // biblatex 註解（`%`）前置——輸出仍是合法 `.bib`，而 LLM 消費端看得到缺漏。
            // 兩面**載體不同、能力相同**，屬 `mcp-cli-parity` 允許的有記錄差異
            // （同 `resolve-people` 的兩面契約差異）。
            let report = BibExport.apa7Report(entries: entries, people: load.people)
            var header = ""
            for issue in report.issues {
                header += "% [\(issue.severity.rawValue.uppercased())] "
                    + "\(displaySafe(issue.citekey, max: 200)): "
                    + "\(displaySafe(issue.message, max: 300))\n"
            }
            if !report.uncheckedCitekeys.isEmpty {
                header += "% note: \(report.uncheckedCitekeys.count) 筆的 entry type "   // display-safe-exempt: Int
                    + "不在 APA7 必要欄位表內，未經檢查（見 #325）\n"
            }
            if !header.isEmpty { header += "\n" }
            return try safe(header + BibExport.bibFile(entries: entries, people: load.people))
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
                    || person.names.all.contains { $0.lowercased().contains(q) }
            }
        }
        let dicts = people.map { person -> [String: Any] in
            // #227：讀取面的 "names" 維持**聯集**（舊 names 欄位本來就是聯集）——
            // 讀取契約零變更；指定資訊的呈現面另計（非本 change 範圍）。
            var d: [String: Any] = ["key": displaySafe(person.key, max: 200),
                                    "names": person.names.all.map { displaySafe($0, max: 200) }]
            // #219：與 person() 的 personDict 同待遇——orcid/openalex 雖有寫入面
            // 格式驗證，讀取面仍一律消毒（同一 payload 進 MCP tool result 與 CLI）
            if let orcid = person.orcid { d["orcid"] = displaySafe(orcid, max: 200) }
            if let openalex = person.openalex { d["openalex"] = displaySafe(openalex, max: 200) }
            if !person.unknownFields.isEmpty {   // #31：同 entryDict，只給 key
                d["unknownFields"] = person.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
            }
            return d
        }
        if dicts.isEmpty { try assertEmptinessIsDeterminable("people") }
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
        // #263：健康事實的**單一來源**是 `StoreHealth`——App 的健康總覽讀同一個型別。
        // 先前 App 完全不呼叫本函式、六個數字自己算，那是第三條獨立實作路徑（會分岔），
        // 而非 doctor 的子集（只會少）。
        //
        // rebuild 與其後的統計**仍是本函式的職責**——`doctor()` 不是唯讀的，那正是
        // App 不能直接呼叫它的原因（每次刷新都重建 index 不可接受）。
        let health = store.health(from: load)
        let cross = health.crossRecordIssues
        let fatalCross = health.fatalCrossRecordIssues
        if !cross.isEmpty {
            d["crossRecordIssues"] = [
                "count": cross.count,
                "first": cross.prefix(20).map {
                    ["severity": $0.severity == .error ? "error" : "warning",
                     "message": displaySafe($0.message, max: 300)]
                },
            ] as [String: Any]
        }
        // #416：per-entry 驗證。先前這一族只有 CLI 的 `validate` 看得到——`doctor()`
        // 與 App 面各 0，而落差裡有一條是 **error** 級（citekey 不符 pattern）。
        // 邏輯單一路徑在 `StoreHealth`；此處只渲染（同 `sources` 的既有形狀）。
        // 截斷 20 則與 `crossRecordIssues` 同——MCP 輸出進 LLM context，呼叫端無法
        // 在收到後丟棄已付的代價（#236 的既有威脅模型）。`count` 送分母讓消費端
        // 判斷得出「我看到的是不是全部」。
        let perRec = health.perRecordIssues
        if !perRec.isEmpty {
            d["recordIssues"] = [
                "count": perRec.count,
                "errors": perRec.filter { $0.issue.severity == .error }.count,
                "first": perRec.prefix(20).map {
                    ["severity": $0.issue.severity == .error ? "error" : "warning",
                     "kind": $0.kind,
                     "key": displaySafe($0.owner, max: 200),
                     "message": displaySafe($0.issue.message, max: 300)]
                },
            ] as [String: Any]
        }
        // #107：佈局殘留（報告不動手刪）。與 CLI 同：排在 fatal 早退之前——
        // 重複 citekey 的 store 正是最需要看清全貌的時候。
        let residue = health.layoutResidue
        if !residue.isEmpty {
            d["layoutResidue"] = residue.map { displaySafe($0, max: 300) }
        }
        // #224：blob ↔ index 一致性（audit 邏輯單一路徑在 SourceStore；此處只渲染）。
        // 四類皆空才不出現——沉默即健康；有事必須說（audit sidecar 的腐爛全靠這裡可見）。
        // audit 自身失敗不得吞掉整份報告（d 到最後才序列化——中途 throw 連已算好的
        // crossRecordIssues 都會消失，MCP 面比 CLI 面更慘；verify reg F1 實測）。
        if let srcAudit = health.sourcesAudit {
            if !srcAudit.orphanBlobs.isEmpty || !srcAudit.danglingEntries.isEmpty
                || !srcAudit.malformedLines.isEmpty || !srcAudit.unreadableShards.isEmpty {
                d["sources"] = [
                    "orphanBlobs": srcAudit.orphanBlobs,          // digest 形（StoreKey 同級安全字元）
                    "danglingIndexEntries": srcAudit.danglingEntries,
                    "malformedIndexLines": srcAudit.malformedLines,
                    "unreadableShards": srcAudit.unreadableShards.map { displaySafe($0, max: 120) },
                ] as [String: Any]
            }
        }
        if let auditError = health.sourcesAuditError {
            d["sourcesAuditError"] = auditError   // display-safe-exempt: StoreHealth 已 displaySafe
        }
        // #76：divergence 計數無條件給（0 也是資訊）；同樣在 fatal 早退之前。
        d["divergences"] = health.divergenceCount
        if !health.quarantined.isEmpty {
            // R11（R10-verify M19）：reason 含 Yams 展開的逐字檔案內容且不截斷——
            // MCP 情境下是直接灌進 LLM context 的無上限未信任字串。
            d["quarantined"] = health.quarantined.map {
                ["file": displaySafe($0.file, max: 300), "reason": displaySafe($0.reason, max: 512)]
            }
        }
        // #23 tolerant-preserve：較新 schema 的檔案可用但應提示升級
        if !health.unknownFieldFiles.isEmpty {
            d["unknownFieldFiles"] = health.unknownFieldFiles.map { displaySafe($0, max: 200) }
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
        d["unresolvedAuthorLiterals"] = health.unresolvedAuthorLiterals
        d["orphaned"] = health.orphanedCitekeys.map { displaySafe($0, max: 200) }
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
    /// 存一份 source 的位元組（#264）。
    ///
    /// `SourceStore.storeSource` 的寫入面防護在 #224 就完成了（換行守衛、O_APPEND、
    /// index 過閘、腐壞拒寫），但**全樹零 production 呼叫端**——「存一份 source」這個
    /// 能力先前只有寫 Swift 的人做得到。與 #206 對匯入面的判準同形：能不能做，不該
    /// 取決於使用者會不會寫 script。
    ///
    /// ## D1：收檔案路徑，不收 stdin、不收 base64
    ///
    /// MCP 面沒有 stdin，所以 stdin 會讓兩面分岔成不同輸入形狀；base64 把二進位塞進
    /// JSON 會膨脹 4/3 倍且整份進 LLM context（`export` 的既有威脅模型，#165）。
    /// 檔案路徑兩面都成立，也與 `akashic_files` 的既有形狀一致。
    ///
    /// ## D2：`retrieved` 必填，入口不填 `now()`
    ///
    /// 它的語意是「呼叫端**何時取得**這份內容」，不是「何時存進來」。自動填會讓
    /// 「三個月前抓的檔案今天才入庫」給出錯誤答案。
    ///
    /// ## D3：`exclusionVerified` 只回報，不重複判斷
    ///
    /// `SourceStore` 已在寫入前用 git 自身的忽略判定確認、未生效即拒寫
    /// （`replace-endnote-and-zotero`：「不得為了任何便利放寬它」）。入口自己再判一次
    /// 會製造兩處會分岔的判斷，而這道閘是**承重**的。
    public func storeSource(path: String, mediaType: String, retrieved: String,
                            origin: String, acquisition: String,
                            note: String? = nil) throws -> String {
        // 必填欄位**具名**拒絕——「參數不足」不告訴呼叫端該補哪個。
        for (label, value) in [("mediaType", mediaType), ("retrieved", retrieved),
                               ("origin", origin), ("acquisition", acquisition)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServiceError.invalid("\(label) 不可為空")   // display-safe-exempt: label 是編譯期字面
            }
        }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            throw ServiceError.invalid("讀不到 \(displaySafe(path, max: 800))")
        }
        // SourceStore 擲出的錯（index 腐壞、排除未驗證）**原樣往上傳**，不吞——那些是
        // 承重的 fail-closed 判斷，包裝過會弄丟指路訊息。
        let receipt = try store.storeSource(
            data, provenance: LibraryStore.SourceProvenance(
                mediaType: mediaType, retrieved: retrieved, origin: origin,
                acquisition: acquisition, note: note))

        var d: [String: Any] = [
            "digest": receipt.digest,                       // display-safe-exempt: SHA-256 十六進位，由本 binary 計算
            "exclusionVerified": receipt.exclusionVerified,  // display-safe-exempt: Bool
            "indexEntryCreated": receipt.indexEntryCreated,  // display-safe-exempt: Bool
        ]
        // **冪等早退時交來卻沒被寫入的敘述必須可見**（`lossless-intake`「丟棄必須可見」）。
        // 回的是**呼叫端這次交來**的內容，不是既有條目的——後者無法讓呼叫端分辨
        // 「早已記過」與「你這份敘述沒被寫入」。
        if let discarded = receipt.discardedProvenance {
            var dp: [String: Any] = [
                "mediaType": displaySafe(discarded.mediaType, max: 200),
                "retrieved": displaySafe(discarded.retrieved, max: 200),
                "origin": displaySafe(discarded.origin, max: 800),
                "acquisition": displaySafe(discarded.acquisition, max: 800),
            ]
            if let n = discarded.note { dp["note"] = displaySafe(n, max: 800) }
            d["discardedProvenance"] = dp
        }
        return try jsonString(d)
    }

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
                // #227 verify R-4／R2 C6：「查不到」與「讀不進來」是兩件事（entity-
                // backlink-completeness 執行細節 4）。store 有 quarantined 檔時，
                // 存在性**無法判定**——擲 undeterminable（不是 notFound），錯誤類型
                // 與「無法判定」前綴讓機器與人都不會把未知當成否。
                if !load.quarantined.isEmpty {
                    throw ServiceError.undeterminable(
                        "person「\(displaySafe(key, max: 200))」——store 另有 "
                        + "\(load.quarantined.count) 個檔 quarantined（可能是未遷移的舊形狀，"
                        + "該 key 或許在其中）；見 akashic doctor / migrate-person-identity")
                }
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
                personDict["names"] = record.names.all.map { displaySafe($0, max: 200) }
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
                // **verdict 是掛在這筆記錄上的邊（第 13 條）——檢視就要看得到**（#270）。
                // resolver 沉底段按建構只列仍可觀測的配對；stale 的（rename 前、entry 已刪、
                // literal 已移位）在這裡才有列舉面。observed/stale 判定：holder entry 仍存在
                // 且該 literal 仍出現在其作者列 → observed；否則 stale。
                let (vs, malformed) = ResolutionLedger.verdicts(references: record.references)
                personDict["verdicts"] = vs.map { v -> [String: Any] in
                    let observed: Bool = {
                        guard v.holderKind == .work,
                              let e = load.entries.first(where: { $0.citekey == v.holder })
                        else { return v.holderKind != .work }   // org 族：不對 entry 判 stale
                        return e.authors.contains { if case .literal(let s) = $0 { return s == v.literal }; return false }
                    }()
                    return ["kind": v.kind.rawValue,   // display-safe-exempt: VerdictKind 是封閉列舉 rawValue
                            "holder_kind": v.holderKind.rawValue,   // display-safe-exempt: 同上
                            "holder": displaySafe(v.holder, max: 200),
                            "literal": displaySafe(v.literal, max: 200),
                            "rule": displaySafe(v.rule, max: 200),
                            "state": observed ? "observed" : "stale"]
                }
                if !malformed.isEmpty {
                    personDict["verdictMalformed"] = malformed.map { displaySafe($0, max: 300) }
                }
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
                    // #323：團體作者**不計入 person 的著作數**——這個計數餵的是
                    // people 搜尋的 publications 欄位，把 organization 算進去會讓
                    // 某個人的著作數包含他沒參與的團體掛名。
                    case .organization: break
                    case .literal(let s):
                        if s.lowercased().contains(needle) { seenLiterals.insert(s) }
                    }
                }
                for k in seenKeys { keyPubCount[k, default: 0] += 1 }
                for s in seenLiterals { literalCounts[s, default: 0] += 1 }
            }
            var candidates: [[String: Any]] = []
            for p in load.people where p.names.all.contains(where: { $0.lowercased().contains(needle) })
                || p.key.lowercased().contains(needle) {
                candidates.append(["person_key": displaySafe(p.key, max: 200),
                                   "names": p.names.all.map { displaySafe($0, max: 200) },
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
            // R3 C6 缺口：name 查找是回清單不擲錯的契約——但零候選 + quarantine 非空
            // 時，「空清單」是無法判定不是否。additive 欄位把不確定性說出來。
            if capped.isEmpty, !load.quarantined.isEmpty {
                out["quarantined"] = load.quarantined.count
                out["note"] = "零候選但 store 有 \(load.quarantined.count) 個檔 quarantined"
                    + "（可能是未遷移的舊形狀）——該名字或許在其中，存在性無法判定；"
                    + "見 akashic doctor / migrate-person-identity"
            }
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

    public func setStatus(citekey: String, status: String?, clear: Bool = false) throws -> String {
        // #258：三態守衛住 service——CLI 與 MCP 共用同一份判準（單一實作路徑，
        // entity-backlink 執行細節 2）。守衛原只在 CLI 側（#219），MCP schema 卻寫
        // 「省略＝清除」——LLM 產 JSON、省略即 valid 的那個面恰無守衛，DA 實測
        // 靜默清空成功。從此省略不再有語意：要嘛給 status、要嘛顯式 clear。
        switch (status, clear) {
        case (nil, false):
            throw ServiceError.invalid("要嘛給 status，要嘛給 clear——省略不是清除（#258）")
        case (.some, true):
            throw ServiceError.invalid("status 與 clear 互斥")
        default:
            break
        }
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
        // #258 同形第二例：MCP 零參數原是 no-op 成功、CLI 拒絕——契約收斂到拒絕
        //（守衛同樣下沉 service，兩面共用）
        guard !add.isEmpty || !remove.isEmpty else {
            throw ServiceError.invalid("add 與 remove 至少要給一個")
        }
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
    ///
    /// reject=["citekey:index", …] → 對候選寫 `resolution-rejected` verdict（#232
    /// design D6）——entry **不動**。apply 在改寫 entry 的同一動作內寫
    /// `resolution-confirmed`。兩者都是顯式人為動作；無 rowID 不發生任何寫入。
    ///
    /// **apply 與 reject 的組合呼叫是兩段式**（#272 解禁；原 verify DA (a) 禁令）：
    /// v1 禁組合是因為兩腿以同一 stale 快照寫同批 person 檔互相蓋寫。解禁的三前置
    /// 由構造滿足——(1) reject 腿**完整提交**（含 rebuild）後，(2) apply 腿以遞迴
    /// 呼叫重新 load＋重解析（rejected 集合已含剛寫入的否決、候選表重推導），
    /// (3) 回應按腿分段（`legs.reject`／`legs.apply`），apply 腿的錯誤被收容進
    /// `legs.apply.error`——reject 已提交的事實不會被 apply 的失敗掩蓋。
    /// 剛被 reject 腿否決的 apply id 以 `skippedBecauseRejected` 回報（不是錯誤——
    /// LLM 一次 triage 常兩邊都點到同一列）。單腿呼叫回應形狀**不變**。
    public func resolvePeople(apply: [String]?, reject: [String]? = nil,
                              confirmTiers: [String]? = nil,
                              judge: [String]? = nil,
                              refute: [String]? = nil) throws -> String {
        // 判定（change `per-work-judged-authorship`）：與 apply／reject 是**不同種類的
        // 主張**——後兩者作用在 resolver 提名出來的候選上，判定作用在一個由呼叫端
        // 指名的作者位（提名器可能根本沒提名它，例如歧義列）。因此走獨立分支、
        // 提早返回，不與兩腿協調邏輯糾纏。
        if let specs = judge, !specs.isEmpty {
            return try judgeAuthorships(specs, kind: .confirmed)
        }
        // 否決是判定的**鏡像**，不是 reject 的變體：既有 `reject` 只吃 resolver 提名出來的
        // 候選，歧義列一律 notFound。而對共用 literal 來說「不是他」才是絕大多數的答案。
        if let specs = refute, !specs.isEmpty {
            return try judgeAuthorships(specs, kind: .rejected)
        }
        if let ap = apply, !ap.isEmpty, let rj = reject, !rj.isEmpty {
            func parsed(_ s: String) throws -> [String: Any] {
                (try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
            }
            // 腿 1：reject 完整提交（失敗即整體 throw——什麼都還沒動到 apply）。
            // R3-fix R4-1：跨腿協調用 **內部未截斷的配對**（rowID＋personKey，經
            // inout 回傳），不用 JSON 回音——回音經 displaySafe 截斷（max 200），
            // 超長 citekey 會讓比對失效、重演 R2-1 全滅（`rename` 收 210 字元
            // citekey，一個出貨命令之遙）。配對級比對同時修 L1：同列
            // 「reject A＋apply B（pinned）」不再誤標 skipped——B 進 apply 腿，
            // 在寫入後快照上重解析、成立則落地。
            var rejectedRows: [(rowID: String, personKey: String)] = []
            let rejectDict = try parsed(resolvePeopleCore(apply: nil, reject: rj,
                                                          rejectedRowsOut: &rejectedRows))
            func splitID(_ id: String) -> (row: String, person: String?) {
                let parts = id.split(separator: ":").map(String.init)
                return parts.count >= 3 ? ("\(parts[0]):\(parts[1])", parts[2]) : (id, nil)
            }
            func isRejected(_ id: String) -> Bool {
                let (row, person) = splitID(id)
                return rejectedRows.contains {
                    $0.rowID == row && (person == nil || person == $0.personKey)
                }
            }
            let applyIDs = ap.filter { !isRejected($0) }
            let skipped = ap.filter { isRejected($0) }
            // 腿 2：在寫入後的新快照上跑（遞迴呼叫從 store.load() 重來）
            var applyDict: [String: Any]
            if applyIDs.isEmpty {
                applyDict = ["applied": [String]()]
            } else {
                do {
                    applyDict = try parsed(try resolvePeople(apply: applyIDs, reject: nil, confirmTiers: confirmTiers))
                } catch {
                    applyDict = [
                        "error": displaySafe(String(describing: error), max: 512),
                        "note": "reject 腿已提交（見 legs.reject）——本錯誤只屬 apply 腿",
                    ]
                }
            }
            if !skipped.isEmpty {
                applyDict["skippedBecauseRejected"] = skipped.map { displaySafe($0, max: 200) }
            }
            return try jsonString(["legs": ["reject": rejectDict, "apply": applyDict]])
        }
        var ignored: [(rowID: String, personKey: String)] = []
        return try resolvePeopleCore(apply: apply, reject: reject,
                                     confirmTiers: confirmTiers, rejectedRowsOut: &ignored)
    }

    /// 單腿本體（R4-1 抽出）。`rejectedRowsOut`：reject 腿實際否決的配對
    /// （**未截斷**的 rowID＋personKey）——combined 分支的跨腿協調吃這個，
    /// 不吃經消毒截斷的 JSON 回音。
    /// 逐篇判定（change `per-work-judged-authorship`）。
    ///
    /// 收 `<citekey>:<authorIndex>:<personKey>=<judgement>`，**以第一個 `=` 切**
    /// ——judgement 是自由文字，本來就可能含等號。
    ///
    /// **literal 由 store 讀、不由呼叫端提供**：少一個能打錯的欄位，且天然強制
    /// 「該位置現在是一個 literal」——已歸戶的位置在讀取階段就被擋下。
    ///
    /// **先全部驗證再寫**：任一筆不合法即整體 throw，零副作用。半批寫入對「判定」
    /// 這種需要逐筆負責的動作是錯的預設——使用者無從知道哪幾筆進去了。
    private func judgeAuthorships(_ specs: [String],
                                  kind: ResolutionLedger.VerdictKind) throws -> String {
        let isConfirm = kind == .confirmed
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        guard storeFormat >= 8 else {
            throw ServiceError.invalid(
                "judgement 要寫 resolution-confirmed verdict，需要 store format ≥ 8"
                + "（本 store 是 \(storeFormat)）")   // display-safe-exempt: storeFormat 是 Int
        }
        let load = try store.load()
        let byCitekey = Dictionary(load.entries.map { ($0.citekey, $0) },
                                   uniquingKeysWith: { _, last in last })
        let byKey = Dictionary(load.people.map { ($0.key, $0) },
                               uniquingKeysWith: { a, _ in a })

        // ── 全部解析 + 驗證（此段不寫任何東西）──
        var pairings: [JudgedPairing] = []
        var skipped: [(id: String, why: String)] = []
        var seen = Set<String>()
        for spec in specs {
            guard let eq = spec.firstIndex(of: "=") else {
                throw ServiceError.invalid(
                    "判定「\(displaySafe(spec, max: 200))」缺少 `=`——格式是 "
                    + "citekey:authorIndex:personKey=判定理由")
            }
            let id = String(spec[..<eq])
            let judgement = String(spec[spec.index(after: eq)...])
            let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let idx = Int(parts[1]) else {
                throw ServiceError.invalid(
                    "判定 id「\(displaySafe(id, max: 200))」不是三段形 "
                    + "citekey:authorIndex:personKey")
            }
            let (citekey, personKey) = (parts[0], parts[2])
            guard seen.insert(id).inserted else {
                throw ServiceError.invalid(
                    "判定 id「\(displaySafe(id, max: 200))」重複——同一個作者位不得在一次"
                    + "呼叫裡判兩次（兩句 judgement 只有一句會留下）")
            }
            guard byKey[personKey] != nil else {
                throw ServiceError.notFound("person「\(displaySafe(personKey, max: 200))」")
            }
            // ── 以下三項是 store **狀態**不符，不是輸入語法錯 ──
            // spec：「that pairing SHALL be skipped … SHALL NOT abort the remaining
            // pairings」。與 `apply` 既有三道守衛同語意：一筆過期的判定不該讓其餘九筆
            // 進不去，但也**不得靜默**——每一筆略過都具名回報。
            guard let entry = byCitekey[citekey] else {
                skipped.append((id, "work「\(displaySafe(citekey, max: 200))」不存在"))
                continue
            }
            guard entry.authors.indices.contains(idx) else {
                skipped.append((id, "作者索引 \(idx) 超出範圍（0…\(entry.authors.count - 1)）"))   // display-safe-exempt: idx／count 是 Int
                continue
            }
            // 否決**不動 entry**，所以「該位置已歸戶」對它不是障礙——已歸戶的位置
            // 仍可留下「另一個候選不是他」的判定。只有歸戶路徑需要這道守衛。
            var literal: String
            if case let .literal(l) = entry.authors[idx] {
                literal = l
            } else if case let .key(k) = entry.authors[idx], !isConfirm {
                // 已歸戶：literal 已不在 entry 上，改由該位置的既有 verdict 取
                // ——取不到就略過，不猜。
                guard let recovered = load.people.first(where: { $0.key == k })?
                        .references.compactMap({ r -> String? in
                            guard let v = r.value,
                                  v.hasPrefix("work:\(citekey) :: ") else { return nil }
                            return String(v.dropFirst("work:\(citekey) :: ".count))
                        }).first
                else {
                    skipped.append((id, "該作者位已歸戶且找不到原 literal——無從否決"))
                    continue
                }
                literal = recovered
            } else {
                skipped.append((id, "該作者位已經歸戶——判定不覆寫既有歸戶；"
                                    + "要改判請先否決既有 verdict"))
                continue
            }
            guard let p = JudgedPairing(citekey: citekey, authorIndex: idx,
                                        literal: literal, personKey: personKey,
                                        judgement: judgement) else {
                throw ServiceError.invalid(
                    "判定「\(displaySafe(id, max: 200))」的 judgement 是空白"
                    + "——judgement 是「憑什麼這樣判」的紀錄，沒有它的配對與猜測無法區分")
            }
            pairings.append(p)
        }

        // ── 寫入（entry → person verdict → rebuild）──
        var wroteEntries = 0
        if isConfirm {
            let updated = PersonResolver.apply(pairings, to: load.entries)
            for e in updated where !load.entries.contains(where: { $0 == e }) {
                try store.writeEntry(e)
                wroteEntries += 1
            }
        }
        var grouped: [String: Person] = [:]
        for p in pairings {
            guard var person = grouped[p.personKey] ?? byKey[p.personKey] else {
                throw ServiceError.notFound("person「\(displaySafe(p.personKey, max: 200))」")
            }
            ResolutionLedger.appendIfAbsent(ResolutionLedger.record(judged: p, kind: kind),
                                            to: &person.references)
            grouped[p.personKey] = person
        }
        for key in grouped.keys.sorted() { try store.writePerson(grouped[key]!) }
        _ = try? LibraryIndex(store: store).rebuild()

        return try jsonString([
            isConfirm ? "judged" : "refuted": pairings.map { p -> [String: Any] in
                ["id": "\(displaySafe(p.citekey, max: 200)):\(p.authorIndex):"   // display-safe-exempt: authorIndex 是 Int
                    + "\(displaySafe(p.personKey, max: 200))",
                 "literal": displaySafe(p.literal, max: 300),
                 "judgement": displaySafe(p.judgement, max: 800)]
            },
            "skipped": skipped.map {
                ["id": displaySafe($0.id, max: 200), "why": $0.why]   // display-safe-exempt: why 由本函式組裝，內含值已消毒
            },
            "entriesRewritten": wroteEntries,
            "personsRewritten": grouped.count,
        ])
    }

    private func resolvePeopleCore(apply: [String]?, reject: [String]?,
                                   confirmTiers: [String]? = nil,
                                   rejectedRowsOut: inout [(rowID: String, personKey: String)]) throws -> String {
        let load = try store.load()
        // #232 design D5：已否決配對從 verdict references 現算（never stored），
        // resolver 在候選生成層排除**恰為**該配對——同 literal 他 entry 照提。
        let rejectedPairings = ResolutionLedger.rejectedPairings(people: load.people)
        // #303 design D3：confirmed 配對同源現算——confirmed-elsewhere tier 的資料源
        let confirmedPairings = ResolutionLedger.confirmedPairings(people: load.people)
        let report = PersonResolver.resolve(entries: load.entries, people: load.people,
                                            rejected: rejectedPairings,
                                            confirmed: confirmedPairings)
        let candidates = report.candidates
        // R1-fix B8：id 釘 person——`citekey:authorIndex` 不含 key，而 apply/reject
        // 在**新的一次解析**上憑 id 找候選：confirmed-elsewhere 讓提名成為 apply 的
        // 不動點後，兩次呼叫之間同一位置的提名可能改指**別人**，舊 id 會安靜套到
        // 新對象上。列出的 id 自此為三段 `citekey:authorIndex:personKey`；apply/reject
        // 收兩段（legacy，僅當該位置的提名仍唯一存在）或三段（釘住——person 不符
        // 即拒絕並指名兩造）。StoreKey 文法無冒號，三段切分無歧義。
        let withIDs = candidates.map { c -> (id: String, candidate: ResolutionCandidate) in
            (c.pinnedID, c)   // 複合鍵與 pin 都住在型別上（#236 R4／R3-5）
        }
        let byID = Dictionary(withIDs.map { ($0.id, $0.candidate) }, uniquingKeysWith: { first, _ in first })
        let byRowID = Dictionary(candidates.map { ($0.rowID, $0) }, uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(load.people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        /// id → 候選（B8 的唯一解析點）。三段：byID 直查，miss 時若同位置存在
        /// 不同 person 的提名 → 顯式「提名已改指」錯誤；兩段：legacy 直查 rowID。
        func candidate(for id: String) throws -> ResolutionCandidate {
            if let c = byID[id] { return c }
            let parts = id.split(separator: ":")
            if parts.count == 3 {
                let rowID = "\(parts[0]):\(parts[1])"
                if let now = byRowID[rowID] {
                    throw ServiceError.invalid(
                        "候選 id「\(displaySafe(id, max: 200))」的提名已改指："
                        + "該位置現在提名的是「\(displaySafe(now.personKey, max: 200))」"
                        + "（tier \(now.tier.rawValue)）——重新列出候選後再決定")   // display-safe-exempt: tier.rawValue 封閉 enum
                }
            } else if parts.count == 2, let c = byRowID[id] {
                return c   // legacy 兩段形——位置仍有唯一提名時等價於未釘
            }
            throw ServiceError.notFound("候選 id「\(displaySafe(id, max: 200))」（先不帶 apply 列出候選）")
        }

        /// rowID 去重（保序）——LLM 消費端送重複 id 相當合理，而重複 id 曾把
        /// 同一配對的 verdict 寫成 N 筆、計數灌水 N 倍（verify F/S-6）。
        func dedupe(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.filter { seen.insert($0).inserted }
        }

        // #232 verify NEW-2：verdict 需要 store format ≥ 8（writePerson 的 v8 gate
        // 是硬閘；這裡提前判是為了給對的錯誤形狀）。markerless legacy store 視同 1。
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1

        // reject（design D6）：**先驗證全部 rowID 再寫**；寫入 per-item 收容
        // （R7/M21 紀律——半批失敗要能對帳），rebuild 永遠嘗試（R9/M8）。
        if let rejectIDs = reject, !rejectIDs.isEmpty {
            // reject 的全部目的就是寫 verdict——format 不足時整個動作不可用，硬擋
            guard storeFormat >= 8 else {
                throw ServiceError.invalid(
                    "resolution verdict 需要 store format ≥ 8（本 store 是 \(storeFormat)）——"   // display-safe-exempt: storeFormat 是 Int
                    + "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 "
                    + "format: 改成 8")
            }
            let chosen = try dedupe(rejectIDs).map { try candidate(for: $0) }   // B8：釘 person
            // R4-1 協調用未截斷配對；R5：賦值移到寫入迴圈後（此處清空）——
            // 寫入失敗的配對不算「已否決」，讓同列 apply 被標 skipped 是假理由
            rejectedRowsOut = []
            // 同 person 多筆 verdict 收攏成一次寫入——writePerson 是整檔改寫。
            // appendIfAbsent：寫入邊界冪等，store 永不持有重複 verdict。
            var grouped: [String: Person] = [:]
            var rejectedByPerson: [String: [ResolutionCandidate]] = [:]
            for c in chosen {
                guard var p = grouped[c.personKey] ?? byKey[c.personKey] else {
                    throw ServiceError.notFound("person「\(displaySafe(c.personKey, max: 200))」")
                }
                ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                    .rejected, holderKind: .work, holder: c.citekey, literal: c.literal,
                    rule: ResolutionLedger.personRule(for: c.tier),
                    statement: "resolve reject：使用者否決此配對"), to: &p.references)
                grouped[c.personKey] = p
                rejectedByPerson[c.personKey, default: []].append(c)
            }
            var rejectWriteFailed: [String: String] = [:]
            for key in grouped.keys.sorted() {
                do { try store.writePerson(grouped[key]!) } catch {
                    rejectWriteFailed[displaySafe(key, max: 200)] =
                        displaySafe(String(describing: error), max: 512)
                }
            }
            // R5：協調配對在寫入之後、以落地者為準（過濾 rejectWriteFailed）
            let landed = chosen.filter { rejectWriteFailed[displaySafe($0.personKey, max: 200)] == nil }
            rejectedRowsOut = landed.map { ($0.rowID, $0.personKey) }
            var result: [String: Any] = [
                // 不誇報：只列 verdict 真的落地的配對（R8 紀律）
                // R4-8 三段 pinned 形；R5 raw 不截斷——citekey/personKey 受 load 端
                // StoreKey quarantine 把關（列表 id 同一 exempt 理由），截斷會讓
                // 超長 citekey 的回音 id 不可重用
                "rejected": landed.map { "\($0.citekey):\($0.authorIndex):\($0.personKey)" },   // display-safe-exempt: StoreKey 受 quarantine 把關（#171）
                "personsRewritten": grouped.count - rejectWriteFailed.count,
            ]
            if !rejectWriteFailed.isEmpty { result["rejectWriteFailed"] = rejectWriteFailed }
            do {
                try LibraryIndex(store: store).rebuild()
            } catch {
                throw ServiceError.invalid(
                    "index rebuild 失敗：\(displaySafe(String(describing: error), max: 512))"
                    + "（本批已改寫 \(grouped.count - rejectWriteFailed.count) 筆 person；"
                    + "rejectWriteFailed \(rejectWriteFailed.count) 筆）")   // display-safe-exempt: 計數是 Int；error 已 displaySafe
            }
            return try jsonString(result)
        }
        guard let selected = apply else {
            // **#231：回應形狀由「候選陣列」改為物件。** 歧義（同一 literal 對到 2+ 人）
            // 先前與「沒人匹配」走同一條 continue，完全不留痕跡——而它才是需要人判斷的
            // 那個。陣列沒有地方放它，所以形狀必須改；`Server.swift` 的 tool description
            // 同步更新。

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
                let allNames = p?.names.all ?? []
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
                    // #303：碰撞發生在哪個提名層（initials 碰撞 ≠ exact 同名）
                    "tier": a.tier.rawValue,   // display-safe-exempt: 封閉 enum rawValue
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
            // #232 design D7：三態計數（derived, never stored）。counts 掛在每個
            // 候選列上（該列所屬 rule 的計數——v1 恰一類 author-name-exact），
            // pendingTotal 頂層可見（censoring 不可隱藏）。**無比率欄位**——校準
            // 報計數不報比率，形狀上就不給（WoS/Crossref 不獨立，比率邀請貝氏相乘）。
            // R1-fix B2：pending 依候選自己的 tier-rule 分桶——四 tier 的待判量
            // 各自可見，不混進 exact 的校準史
            let activeTriples = candidates.map { c in
                (pairing: ResolutionPairing(holderKind: .work, holder: c.citekey,
                                            literal: c.literal, judgedKey: c.personKey),
                 rule: ResolutionLedger.personRule(for: c.tier))
            }
            let countsByRule = ResolutionLedger.counts(
                people: load.people, candidates: activeTriples)
            func countsJSON(_ rule: String) -> [String: Any] {
                let c = countsByRule[rule] ?? (confirmed: 0, rejected: 0, pending: 0)
                return ["confirmed": c.confirmed, "rejected": c.rejected, "pending": c.pending]
            }
            var candidateRows: [[String: Any]] = []
            var candidateBytes = 0
            var candidatesDropped = 0
            for pair in withIDs.prefix(Self.candidateLimit) {
                let row: [String: Any] = [
                    "id": pair.id,   // display-safe-exempt: 三段形 "<citekey>:<index>:<personKey>"——citekey 與 personKey 都受 load 端 StoreKey quarantine 把關（#171／R3-5）
                    "citekey": displaySafe(pair.candidate.citekey, max: 200),
                    "authorIndex": pair.candidate.authorIndex,
                    "literal": displaySafe(pair.candidate.literal, max: 400),
                    "personKey": displaySafe(pair.candidate.personKey, max: 200),
                    "reason": displaySafe(pair.candidate.reason, max: 400),
                    // #303 design D4：提名層（additive）——rawValue 是封閉四值的固定字面
                    "tier": pair.candidate.tier.rawValue,   // display-safe-exempt: 封閉 enum rawValue，非 store 衍生
                    "counts": countsJSON(ResolutionLedger.personRule(for: pair.candidate.tier)),
                ]
                let cost = Self.jsonBytes(row)
                guard candidateBytes + cost <= Self.candidateByteBudget else {
                    candidatesDropped += 1
                    continue
                }
                candidateBytes += cost
                candidateRows.append(row)
            }
            // 已否決**獨立成段、不隱藏**（design D7，verify 修訂）：曾把沉底列附進
            // `candidates` 陣列——列數超過文件宣稱的上限、`candidateTotal` 小於
            // 陣列長度、且沉底列沒有 id/reason 鍵（消費端無條件讀就炸）。改為
            // 頂層 `rejected` 陣列：candidates 形狀均勻、各自的 *Total 誠實。
            // **預算獨立**——先前共用候選預算且「沉底者先被擠掉」，等於最可能被
            // 截斷的正是記載人類決定的那段（verify DA (c)）。
            // 名單由 `observedRejections` 給——CLI 面用同一個來源（mcp-cli-parity）。
            // 同 entry 同 literal 的每個作者位置各一列（verify C-4）。
            let sunkAll = ResolutionLedger.observedRejections(people: load.people,
                                                              entries: load.entries)
            var rejectedRows: [[String: Any]] = []
            var rejectedBytes = 0
            var rejectedRowsDropped = 0
            for sunk in sunkAll.prefix(Self.candidateLimit) {
                let row: [String: Any] = [
                    "citekey": displaySafe(sunk.citekey, max: 200),
                    "authorIndex": sunk.authorIndex,
                    "literal": displaySafe(sunk.literal, max: 400),
                    "personKey": displaySafe(sunk.judgedKey, max: 200),
                    "verdict": "rejected",   // display-safe-exempt: 常數
                    "counts": countsJSON(sunk.rule),   // 該列**自己的** rule 的計數（verify S-4）
                ]
                let cost = Self.jsonBytes(row)
                guard rejectedBytes + cost <= Self.candidateByteBudget else {
                    rejectedRowsDropped += 1
                    continue
                }
                rejectedBytes += cost
                rejectedRows.append(row)
            }
            rejectedRowsDropped += max(0, sunkAll.count - Self.candidateLimit)
            // malformed verdict **必須可見**（lossless-intake「丟棄必須可見」；
            // verify G）：一筆解析不了的 verdict 既不計數也不抑制——不報出來，
            // 「判定壞了」與「沒判過」就成了同一個觀察。store 閘已拒收新寫入的
            // malformed；這裡涵蓋手改檔與他庫匯入。
            let malformedAll = ResolutionLedger.malformedVerdicts(people: load.people)
            let verdictMalformed = malformedAll.prefix(20).map { displaySafe($0, max: 300) }
            // 第四種丟棄：`people[ref]["names"]` 的 `prefix(2)`（#236 R4）。先前只算
            // 三軸（rows／refs／candidates），於是一個「每人五個異名、全部只送兩個」
            // 的回應仍宣稱 `truncated: false`——旗標按**自己的定義**說謊（下方 :745
            // 寫的是「整個回應……任一被截都算」），與 R3 抓到的 candidates 同型。
            let anyNamesDropped = refKeys.contains { (byKey[$0]?.names.all.count ?? 0) > Self.namesPerPerson }
            let truncated = report.ambiguities.count > Self.ambiguityLimit
                || anyRefsTruncated
                || droppedRows > 0
                || anyNamesDropped
            // 零候選 + 有 quarantine ＝ 無法判定（#294）。本 payload 已有
            // `candidateRowsDropped`／`rejectedTotal` 這類「我看到的是不是全部」的
            // 欄位——同一條紀律，只是先前漏了「讀不進來」這個來源。
            if candidateRows.isEmpty { try assertEmptinessIsDeterminable("resolve-people") }
            var payload: [String: Any] = [
                "candidates": candidateRows,
                "candidateRowsDropped": candidatesDropped,
                // 已否決獨立成段（排在 candidates 之後的閱讀順序由 tool description
                // 交代）；rejectedTotal 給分母——「我看到的是不是全部」需要它。
                "rejected": rejectedRows,
                "rejectedTotal": sunkAll.count,
                "rejectedRowsDropped": rejectedRowsDropped,
                // 未處理量頂層可見（design D7）——「還沒查」是 censoring，藏起來
                // 會讓計數看起來比實際完整。
                "pendingTotal": countsByRule.values.reduce(0) { $0 + $1.pending },
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
                    || candidatesDropped > 0
                    || rejectedRowsDropped > 0
                    || malformedAll.count > verdictMalformed.count,
                "candidateTotal": withIDs.count,
                "ambiguityTotal": report.ambiguities.count,
            ]
            // 缺席即「沒有 malformed」——空陣列不佔 payload（同 orcid 缺席不輸出的慣例）
            if !verdictMalformed.isEmpty {
                payload["verdictMalformed"] = Array(verdictMalformed)
                payload["verdictMalformedTotal"] = malformedAll.count
            }
            return try jsonString(payload)
        }
        let chosen = try selected.map { try candidate(for: $0) }   // B8：釘 person
        // #307：寬鬆 tier 的顯式承認——per-id 顯式不等於 tier 覺察（id 可手構、
        // 可從舊列表複製），apply 集含寬鬆 tier 候選時該 tier 必須列在
        // confirm_tiers，否則整批拒絕（零寫入）並指名缺席 tier。exact 免承認。
        let acknowledged = Set((confirmTiers ?? []).compactMap { ResolutionTier(rawValue: $0) })
        if let bad = (confirmTiers ?? []).first(where: { ResolutionTier(rawValue: $0) == nil }) {
            throw ServiceError.invalid(
                "confirm_tiers「\(displaySafe(bad, max: 60))」不是提名層——合法值："
                + ResolutionTier.allCases.map(\.rawValue).joined(separator: " / "))
        }
        let unacknowledged = Set(chosen.map(\.tier))
            .subtracting([.exact]).subtracting(acknowledged)
        if !unacknowledged.isEmpty {
            let need = unacknowledged.map(\.rawValue).sorted().joined(separator: "、")
            throw ServiceError.invalid(
                "apply 集含寬鬆提名層（\(need)）——請在 confirm_tiers 列出以顯式承認"   // display-safe-exempt: 封閉 enum rawValue
                + "（寬鬆層 apply 前必查證；exact 免承認）")
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
        // #232 design D6：apply 的**同一動作**內寫 resolution-confirmed——只寫
        // entry 改寫成功的那些（誇報 verdict 比漏寫更糟：ledger 會宣稱一次沒有
        // 發生的歸戶）。verdict 落在被判定的 person 上，經既有 writePerson 閘。
        var confirmWriteFailed: [String: String] = [:]
        var confirmGrouped: [String: Person] = [:]
        // format < 8 的 store：apply 照常歸戶（那是它既有的職責），confirmed verdict
        // **跳過並在回應揭露**——把基本歸戶綁死在格式遷移上是錯的耦合，但跳過不說
        // 就是 ledger 靜默少記（verify NEW-2 的降級要 loud）。
        let verdictsSkippedNote: String? = storeFormat >= 8 ? nil :
            "store format \(storeFormat) < 8——resolution-confirmed 未記錄；"
            + "全部 binary 升級後把 store.yaml 的 format: 改成 8，之後的 apply 會記錄 verdict"
        for c in chosen where writeFailed[c.citekey] == nil && verdictsSkippedNote == nil {
            guard var p = confirmGrouped[c.personKey] ?? byKey[c.personKey] else {
                // 候選的 personKey 恆來自 load.people——走到這裡是內部不變式破了，
                // 靜默 continue 會吞掉一筆該寫的 verdict（verify GAP-12）
                throw ServiceError.notFound("person「\(displaySafe(c.personKey, max: 200))」")
            }
            ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                .confirmed, holderKind: .work, holder: c.citekey, literal: c.literal,
                rule: ResolutionLedger.personRule(for: c.tier),
                statement: "resolve apply：使用者確認歸戶"), to: &p.references)
            confirmGrouped[c.personKey] = p
        }
        for key in confirmGrouped.keys.sorted() {
            do { try store.writePerson(confirmGrouped[key]!) } catch {
                confirmWriteFailed[displaySafe(key, max: 200)] =
                    displaySafe(String(describing: error), max: 512)
            }
        }
        // R9（R8-verify M8）：rebuild 擲錯不得吞掉 writeFailed 報告
        do {
            try LibraryIndex(store: store).rebuild()
        } catch {
            // R10（R9-verify L17）：附已改寫數——operator 才能對帳磁碟狀態。
            // confirmWriteFailed 一併列（verify GAP-11——漏了它，rebuild 失敗那次
            // 「verdict 沒落地」的報告就整個消失）。
            throw ServiceError.invalid(
                "index rebuild 失敗：\(displaySafe(String(describing: error), max: 512))（本批已改寫 \(written) 檔；writeFailed \(writeFailed.count) 筆：\(writeFailed.map { "\(displaySafe($0.key, max: 200))（\($0.value)）" }.sorted().joined(separator: "; "))；confirmWriteFailed \(confirmWriteFailed.count) 筆：\(confirmWriteFailed.keys.sorted().joined(separator: "、"))）")   // display-safe-exempt: written 是 Int；writeFailed 值與 confirmWriteFailed 鍵在插入時已 displaySafe（不冪等，不再包）
        }
        // R8（R7-verify L15）：applied 不誇報——排除寫入失敗的候選
        // R3-1 附帶：applied 回音同列表三段 pinned 形；R5 raw 不截斷（同 rejected
        // 回音理由——StoreKey 受 quarantine 把關）
        let appliedActual = chosen.filter { writeFailed[$0.citekey] == nil }
            .map { "\($0.citekey):\($0.authorIndex):\($0.personKey)" }   // display-safe-exempt: StoreKey 受 quarantine 把關（#171）
        var result: [String: Any] = ["applied": appliedActual, "entriesRewritten": written]
        // subscript 賦值建字典——**不用** `Dictionary(uniqueKeysWithValues:)`：
        // displaySafe 截斷非單射，兩個共 200 字元前綴的合法 citekey 會碰撞成同鍵，
        // uniqueKeysWithValues 對重複鍵是 SIGTRAP（verify S-2；#236 R2 同型）。
        if !writeFailed.isEmpty {
            var safe: [String: String] = [:]
            // 值在插入時已 displaySafe——不再包（displaySafe 不冪等）；只消毒原始 key
            for (k, v) in writeFailed { safe[displaySafe(k, max: 200)] = v }
            result["writeFailed"] = safe
        }
        // verdict 寫入失敗**獨立回報**——entry 已改寫成功、只有 confirmed ref 沒落地
        // 的狀態必須可見（靜默會讓 ledger 少算一筆已發生的歸戶）。
        if !confirmWriteFailed.isEmpty { result["confirmWriteFailed"] = confirmWriteFailed }
        if let note = verdictsSkippedNote, !chosen.isEmpty {
            result["verdictsSkipped"] = note   // display-safe-exempt: 常數模板 + Int
        }
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
        // #325 階段二：type 是封閉列舉。**這是新資料入口**——LLM 呼叫端給的字串
        // 若不在值域，必須當場拒絕並列出值域，否則它會反覆猜。
        guard let workType = WorkType(rawValue: type) else {
            throw ServiceError.invalid(
                "type「\(displaySafe(type, max: 80))」不在封閉列舉"
                + "（\(WorkType.domainDescription)）")   // display-safe-exempt: 由 allCases 生成，編譯期常量
        }
        var entry = Entry(id: UUID(), citekey: citekey, type: workType, title: title,
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
        // #227：add_person 產生的是尚未指定對外名字的記錄——全部進 variant，
        // authorized 留空（指定是人的判斷，不由建檔機械偽造）。
        let person = Person(key: key, names: PersonNames(variant: names),
                            orcid: orcid, openalex: openalex)
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

    /// 逐筆 Zotero 補值的 MCP 面（#340）。
    ///
    /// 與 CLI `enrich-from-zotero` 走同一條 `ZoteroEnrichment.plan`——對映邏輯
    /// 只有一份（`entity-backlink-completeness` 執行細節 2）。
    ///
    /// **parity 判準的直接套用**：#206 的原話是「能不能無損匯入，不該取決於使用者
    /// 會不會寫 script」，#290 把它鏡像到 `import-wos`。同一句話在這裡是「能不能把
    /// 一筆跌破下限的記錄補回下限，不該取決於使用者用的是 MCP 還是 CLI」。
    ///
    /// **#298 的閘刻意不在這一面**：那個閘擋的是「篩選式批次寫入未指名目標」，
    /// 而本 tool 收的是**逐筆顯式指名**的 citekey 清單——與 `resolve-people` 的
    /// tier 閘同型不對稱（`mcp-cli-parity` 已載明）。
    public func enrichFromZotero(citekeys: [String], zoteroDb: String?,
                                 libraryID: Int?, dryRun: Bool) throws -> String {
        guard !citekeys.isEmpty else {
            throw ServiceError.invalid("citekeys 不得為空——本 tool 刻意不提供「全部」的寫法")
        }
        let path = ((zoteroDb ?? "~/Zotero/zotero.sqlite") as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw ServiceError.notFound("zotero.sqlite：\(displaySafe(path, max: 300))")
        }
        let load = try store.load()
        let read = try ZoteroReader.readItems(dbPath: path, libraryID: libraryID)
        let plan = ZoteroEnrichment.plan(entries: load.entries, items: read.items,
                                         citekeys: citekeys)

        var byCitekey: [String: Entry] = [:]
        for e in load.entries { byCitekey[e.citekey] = e }
        var written: [String] = []
        var writeFailed: [String: String] = [:]
        if !dryRun {
            for a in plan.additions {
                guard let entry = byCitekey[a.citekey] else { continue }
                do {
                    try store.writeEntry(ZoteroEnrichment.applied(a, to: entry))
                    written.append(a.citekey)
                } catch {
                    writeFailed[a.citekey] = String(describing: error)
                }
            }
            if !written.isEmpty { try LibraryIndex(store: store).rebuild() }
        }

        // 四類「沒補到」全部回報。只回可補的那一半，會讓「查過、上游沒有」與
        // 「根本沒查」在輸出上變成同一件事（`lossless-intake` 執行細節 3）。
        var d: [String: Any] = [
            "dryRun": dryRun,
            "additions": plan.additions.sorted { $0.citekey < $1.citekey }.map { a -> [String: Any] in
                var one: [String: Any] = [
                    "citekey": displaySafe(a.citekey, max: 200),
                    "addedFields": Dictionary(uniqueKeysWithValues: a.addedFields.map {
                        (displaySafe($0.key, max: 80), displaySafe($0.value, max: 512))
                    }),
                ]
                if let dt = a.addedDate { one["addedDate"] = displaySafe(dt, max: 200) }
                return one
            },
            "unchanged": plan.unchanged.sorted().map { displaySafe($0, max: 200) },
            "noProvenance": plan.noProvenance.sorted().map { displaySafe($0, max: 200) },
            "zoteroMissing": plan.zoteroMissing.sorted().map { displaySafe($0, max: 200) },
            "notInStore": plan.notInStore.sorted().map { displaySafe($0, max: 200) },
        ]
        if !dryRun { d["written"] = written.sorted().map { displaySafe($0, max: 200) } }
        if !writeFailed.isEmpty {
            d["writeFailed"] = Dictionary(uniqueKeysWithValues: writeFailed.map {
                (displaySafe($0.key, max: 200), displaySafe($0.value, max: 512))
            })
        }
        return try jsonString(d)
    }

    /// WoS 匯入的 MCP 面（#290——#259 CLI-only 盤點唯一「需要」格；#206 鏡像：
    /// 無損匯入不該取決於面）。與 CLI `import-wos` 走 `WoSImport.run` 同一路徑：
    /// 具名對映＋殘餘收集、idempotent（citekey＋內容）、conflicts 不覆寫、
    /// enriched 只多不少、`droppedColumns` 可見（規則 §3）。
    ///
    /// `path` 是 **server 本機路徑**（stdio 同機前提，與 `importZotero` 一致），
    /// 不是內容上傳。
    public func importWoS(path: String, csv: Bool, dryRun: Bool) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw ServiceError.notFound("WoS 匯出檔：\(displaySafe(expanded, max: 300))")
        }
        let text = try String(contentsOf: URL(fileURLWithPath: expanded), encoding: .utf8)
        try store.ensureLayout()
        let report = try WoSImport.run(text: text, store: store,
                                       separator: csv ? "," : "\t", dryRun: dryRun)
        // rebuild 擲錯不得吞掉整份 import report（同 importZotero 的 R10 裁決）
        if !dryRun, !report.created.isEmpty {
            do {
                try LibraryIndex(store: store).rebuild()
            } catch {
                throw ServiceError.invalid(
                    "index rebuild 失敗：\(displaySafe(String(describing: error), max: 512))"
                    + "（本趟 import 已落地：created \(report.created.count)、"
                    + "enriched \(report.enriched.count)）")
            }
        }
        var d: [String: Any] = [
            "dryRun": dryRun,
            "created": report.created.map { displaySafe($0, max: 200) },
            "unchanged": report.unchanged.map { displaySafe($0, max: 200) },
            "enriched": report.enriched.map { displaySafe($0, max: 200) },
            "conflicts": report.conflicts.map { displaySafe($0, max: 200) },
        ]
        if !report.aliasGroups.isEmpty {
            d["aliasGroups"] = report.aliasGroups.map { g in g.map { displaySafe($0, max: 200) } }
        }
        if !report.skippedRows.isEmpty {
            d["skippedRows"] = report.skippedRows.map { displaySafe($0, max: 300) }
        }
        if !report.droppedColumns.isEmpty {
            // 欄位名是第三方字串——鍵值都消毒（同 importZotero 的 residualFields 慣例）
            d["droppedColumns"] = Dictionary(uniqueKeysWithValues:
                report.droppedColumns.map { (displaySafe($0.key, max: 200), $0.value) })
        }
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

    /// 空結果 + 有 quarantined 檔 ＝ **無法判定**，不是「沒有」（#294）。
    ///
    /// `person()`／`venue()` 早有這條紀律（#227 verify R-4／R2 C6）：單筆查無時若
    /// store 另有讀不進來的檔，擲 `undeterminable` 而非 `notFound`。本函式把同一條
    /// 紀律推廣到**列表面**——它們先前把「讀不進來」折成「空」，於是
    /// `akashic people` 回「無 person 記錄」、MCP 回 `[]` + `isError:false`，
    /// **LLM 消費端會據此斷言 library 是空的**。
    ///
    /// 依 `entity-backlink-completeness` 執行細節 4：「『這個人零篇著作』與『查不到
    /// 這個人』是兩件事……折成同一個輸出會讓使用者無法分辨。」
    ///
    /// **只在結果為空時呼叫**——判準需要 quarantine 計數而 `load()` 有成本，非空
    /// 路徑因此零開銷。
    ///
    /// ## 誠實邊界：非空但不完整的情況本函式不管
    ///
    /// 回傳 500 筆而另有 3 筆讀不進來時，結果是**不完整**（而非誤導），本函式放行。
    /// 要讓那個情況也可見需要在 payload 加欄位——四面都回 JSON 字串，附註文字會破壞
    /// 解析，而加欄位會動 published MCP contract。那是另一個範圍的裁決，已在 #294
    /// 的結案摘要具名交出，不在此靜默略過。
    func assertEmptinessIsDeterminable(_ what: String) throws {
        let load = try store.load()
        guard load.quarantined.isEmpty else {
            throw ServiceError.undeterminable(
                "\(what)——查詢結果為空，但 store 另有 \(load.quarantined.count) 個檔 "   // display-safe-exempt: what 是呼叫端的編譯期字面（"search"／"people"／…），非 store 衍生；count 是 Int
                + "quarantined（可能是未遷移的舊形狀，答案或許在其中）；"
                + "見 akashic doctor")
        }
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
            "type": entry.type.rawValue,   // display-safe-exempt: 封閉列舉的 rawValue，編譯期常量（#325）
            "title": displaySafe(entry.title, max: 800),
            "authors": entry.authors.map { author -> [String: String] in
                switch author {
                case .key(let k): return ["key": displaySafe(k, max: 200)]
                // #323：團體作者。key 受 StoreKey 約束但仍消毒——與 person key 同待遇
                case .organization(let k): return ["organization": displaySafe(k, max: 200)]
                // literal 是 Zotero 匯入的第三方原文——掃描器對 case 行的短變數
                // 值是盲點（見 DisplaySinkCoverageTests doc），此站點靠人工 + 測試釘
                case .literal(let s): return ["literal": displaySafe(s, max: 400)]
                }
            },
            // fields 的**值**是 biblatex 第三方內容（journal、booktitle…）——與 title
            // 同源；**鍵**同樣是第三方輸入（import-wos 殘餘收集會照收未知欄位名），且
            // 是 load-time quarantine 唯一不檢查的裸格（#219 verify D3：citekey／
            // libraries 有 StoreKey 閘門，欄位鍵兩層皆空）——鍵值都要包。碰撞處置：
            // 消毒後兩個不同鍵可能撞同一字串，先依原始鍵排序再取第一個，避免
            // uniqueKeysWithValues trap 且結果決定性。
            "fields": Dictionary(
                entry.fields.sorted { $0.key < $1.key }
                    .map { (displaySafe($0.key, max: 200), displaySafe($0.value, max: 800)) },
                uniquingKeysWith: { first, _ in first }),
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
        // libraries 刻意**不**包 displaySafe（#219 verify D4 探針證實安全）：load-time
        // quarantine 以 StoreKey.pattern 逐項驗證，結構上容不下控制字元／bidi；包了
        // 反而讓 key 被跳脫成不再等於 registry key 的字串，--json 消費者對不上 registry
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

    // MARK: - Venue（#304）

    /// venue 檢視：記錄＋刊名沿革＋**文章編年 list**（依年升冪；裁決五a）。
    /// 空集合顯式報零篇（零篇 ≠ 查無——entity-backlink 執行細節 4）；store 有
    /// quarantined 檔且查無時擲 undeterminable（同 person 的 #227 紀律）。
    public func venue(key rawKey: String) throws -> String {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ServiceError.invalid("key 不可為空白") }
        let load = try store.load()
        guard let record = load.venues.first(where: { $0.key == key }) else {
            if !load.quarantined.isEmpty {
                throw ServiceError.undeterminable(
                    "venue「\(displaySafe(key, max: 200))」——store 另有 "
                    + "\(load.quarantined.count) 個檔 quarantined；見 akashic doctor")
            }
            throw ServiceError.notFound("venue「\(displaySafe(key, max: 200))」")
        }
        let engine = try freshEngine()
        let works = try engine.venueWorks(key: key)
        var d: [String: Any] = [
            "key": displaySafe(key, max: 200),
            "type": record.type.rawValue,
            // 沿革：時間軸各段（序列化順序；四個時間欄位全帶——#218 R2 的教訓）
            "names": record.names.inSerializationOrder.map { seg -> [String: Any] in
                var n: [String: Any] = ["value": displaySafe(seg.value, max: 200)]
                if let st = seg.range.start { n["start"] = displaySafe(st, max: 40) }
                if let en = seg.range.end { n["end"] = displaySafe(en, max: 40) }
                if seg.range.endedUnknown { n["ended"] = true }   // display-safe-exempt: Bool
                if !seg.range.attested.isEmpty {
                    n["attested"] = seg.range.attested.map { displaySafe($0, max: 40) }
                }
                return n
            },
            // 編年（依年升冪；QueryEngine 排序）——空陣列也要出現（零篇是答案不是缺席）
            "works": works.map { w -> [String: Any] in
                var e: [String: Any] = ["citekey": displaySafe(w.citekey, max: 200),
                                        "title": displaySafe(w.title, max: 500)]
                if let y = w.year { e["year"] = y }   // display-safe-exempt: Int
                return e
            },
            "workCount": works.count,   // display-safe-exempt: Int
        ]
        if !record.authorized.isEmpty {
            d["authorized"] = record.authorized.map { displaySafe($0, max: 200) }
        }
        if let note = record.note { d["note"] = displaySafe(note, max: 500) }
        if !record.unknownFields.isEmpty {
            d["unknownFields"] = record.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
        }
        return try jsonString(d)
    }

    /// venue 列舉（key／type／顯示名／文章數）。
    public func venues() throws -> String {
        let load = try store.load()
        let engine = try freshEngine()
        let rows = try load.venues.sorted { $0.key < $1.key }.map { v -> [String: Any] in
            ["key": displaySafe(v.key, max: 200),
             "type": v.type.rawValue,
             "name": displaySafe(v.displayName, max: 200),
             "workCount": try engine.venueWorks(key: v.key).count]   // display-safe-exempt: Int
        }
        return try jsonString(["venues": rows, "count": rows.count])   // display-safe-exempt: Int
    }

    /// venue 單筆建檔（同 addPerson 形：寫入面封閉例外、key 已存在拒絕）。
    /// names 全部進時間軸（無時間段）；authorized 留空——指定是人的判斷。
    public func addVenue(key: String, names: [String], type rawType: String,
                         note: String? = nil) throws -> String {
        guard let vtype = VenueType(rawValue: rawType) else {
            throw ServiceError.invalid(
                "type「\(displaySafe(rawType, max: 60))」不在封閉列舉（\(VenueType.domainDescription)）")   // display-safe-exempt: domainDescription 由 VenueType.allCases 的 rawValue 組成，那些是 Swift 原始碼裡的識別字（編譯期常量），不含使用者資料
        }
        let load = try store.load()
        guard !load.venues.contains(where: { $0.key == key }) else {
            throw ServiceError.invalid("venue key「\(displaySafe(key, max: 200))」已存在")
        }
        let venue = Venue(key: key, type: vtype,
                          names: Timeline(names.map { TemporalValue(value: $0) }),
                          note: note)
        try store.writeVenue(venue)
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["key": key, "type": vtype.rawValue,
                               "names": names.map { displaySafe($0, max: 200) }])
    }

    /// venue 異名補寫（#306）——**append 語意**：`addNames` 只附加不重複的
    /// variant（整組替換是 R3F-2 教訓的 footgun，本入口在設計上排除它）；
    /// `note`／`type` 為替換語意（可選）。沿革補全直接擴大 resolve-venues
    /// 的 exact 命中面（resolver 對沿革各段都配對）。
    public func updateVenue(key: String, addNames: [String]?,
                            note: String?, type rawType: String?) throws -> String {
        let load = try store.load()
        guard var venue = load.venues.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("venue「\(displaySafe(key, max: 200))」")
        }
        var added: [String] = []
        if let names = addNames {
            let existing = Set(venue.names.entries.map(\.value))
            for n in names where !n.trimmingCharacters(in: .whitespaces).isEmpty {
                guard !existing.contains(n), !added.contains(n) else { continue }
                venue.names = Timeline(venue.names.entries + [TemporalValue(value: n)])
                added.append(n)
            }
        }
        if let rawType {
            guard let vtype = VenueType(rawValue: rawType) else {
                throw ServiceError.invalid(
                    "type「\(displaySafe(rawType, max: 60))」不在封閉列舉（\(VenueType.domainDescription)）")   // display-safe-exempt: domainDescription 由 VenueType.allCases 的 rawValue 組成，那些是 Swift 原始碼裡的識別字（編譯期常量），不含使用者資料
            }
            venue.type = vtype
        }
        if let note { venue.note = note }
        try store.writeVenue(venue)
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["key": key,
                               "namesAdded": added.map { displaySafe($0, max: 200) },
                               "namesTotal": venue.names.entries.count])
    }

    /// venue 消歧（resolve-people 契約形，#304）：無參數＝列候選與歧義；
    /// apply＝literal 升格 key＋confirmed verdict；reject＝rejected verdict；
    /// apply+reject 同呼叫＝兩段式（reject 先完整提交，apply 以新快照重解析）。
    public func resolveVenues(apply: [String]?, reject: [String]? = nil,
                              repoint: [String]? = nil, demote: [String]? = nil) throws -> String {
        // **降格：把誤升的 key 邊變回 literal**（#418 的第二半）。
        //
        // `repoint` 只改得到**既有**的 venue。若正確答案是「現有的都不對」——那個刊名
        // 根本還沒建檔——就回不去了。而 `literal-first-then-key` 說 literal 是**誠實
        // 狀態**不是壞掉的 key，所以「退回誠實狀態」必須是可能的，否則「誤可逆」
        // 這個承諾只兌現了一半。
        if let dm = demote, !dm.isEmpty {
            return try demoteVenues(dm)
        }
        // **改指：歸錯戶的退路**（#418）。`apply` 只做 literal → key 的升格，所以一條
        // 已經是 key 的邊在此之前**改不回來**——person 域有 `resolve-divergence`，
        // venue 域沒有，而 `literal-first-then-key` 的整套論證建立在「誤可逆」上。
        //
        // 三段式 id `citekey:venueIndex:newKey`，與 `resolve-people` 的
        // `citekey:authorIndex:personKey` 同形（#303）。
        //
        // **失敗語意分兩類，與 `judge` 同**（#386）：輸入語法錯或前提不符 → **整批拒絕、
        // 零寫入**（下面先全部解析完才動手）；成功則兩側都留 verdict。
        if let rp = repoint, !rp.isEmpty {
            return try repointVenues(rp)
        }
        if let ap = apply, !ap.isEmpty, let rj = reject, !rj.isEmpty {
            func parsed(_ s: String) throws -> [String: Any] {
                (try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
            }
            let rejectDict = try parsed(try resolveVenues(apply: nil, reject: rj))
            let justRejected = Set(rejectDict["rejected"] as? [String] ?? [])
            let applyIDs = ap.filter { !justRejected.contains($0) }
            let skipped = ap.filter { justRejected.contains($0) }
            var applyDict: [String: Any]
            if applyIDs.isEmpty {
                applyDict = ["applied": [String]()]
            } else {
                do { applyDict = try parsed(try resolveVenues(apply: applyIDs, reject: nil)) }
                catch {
                    applyDict = ["error": displaySafe(String(describing: error), max: 512),
                                 "note": "reject 腿已提交——本錯誤只屬 apply 腿"]
                }
            }
            if !skipped.isEmpty {
                applyDict["skippedBecauseRejected"] = skipped.map { displaySafe($0, max: 200) }
            }
            return try jsonString(["legs": ["reject": rejectDict, "apply": applyDict]])
        }
        let load = try store.load()
        let rejectedPairings = ResolutionLedger.rejectedPairings(venues: load.venues)
        let report = VenueResolver.resolve(entries: load.entries, venues: load.venues,
                                           rejected: rejectedPairings)
        let byID = Dictionary(report.candidates.map { ($0.rowID, $0) },
                              uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(load.venues.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func dedupe(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.filter { seen.insert($0).inserted }
        }
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        if let rejectIDs = reject, !rejectIDs.isEmpty {
            guard storeFormat >= 11 else {
                throw ServiceError.invalid(
                    "venue verdict 需要 store format ≥ 11（本 store 是 \(storeFormat)）")   // display-safe-exempt: Int
            }
            let chosen = try dedupe(rejectIDs).map { id -> VenueResolutionCandidate in
                guard let c = byID[id] else {
                    throw ServiceError.notFound("候選 id「\(displaySafe(id, max: 200))」（先不帶 apply 列出候選）")
                }
                return c
            }
            var grouped: [String: Venue] = [:]
            for c in chosen {
                guard var v = grouped[c.venueKey] ?? byKey[c.venueKey] else {
                    throw ServiceError.notFound("venue「\(displaySafe(c.venueKey, max: 200))」")
                }
                ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                    .rejected, holderKind: .work, holder: c.citekey, literal: c.literal,
                    rule: ResolutionLedger.venueRule,
                    statement: "resolve reject：使用者否決此配對"), to: &v.references)
                grouped[c.venueKey] = v
            }
            var writeFailed: [String: String] = [:]
            for key in grouped.keys.sorted() {
                do { try store.writeVenue(grouped[key]!) } catch {
                    writeFailed[displaySafe(key, max: 200)] =
                        displaySafe(String(describing: error), max: 512)
                }
            }
            var result: [String: Any] = [
                "rejected": chosen.filter { writeFailed[displaySafe($0.venueKey, max: 200)] == nil }
                    .map { $0.rowID },
                "venuesRewritten": grouped.count - writeFailed.count,   // display-safe-exempt: Int
            ]
            if !writeFailed.isEmpty { result["rejectWriteFailed"] = writeFailed }
            try LibraryIndex(store: store).rebuild()
            return try jsonString(result)
        }
        guard let selected = apply, !selected.isEmpty else {
            return try jsonString([
                "candidates": report.candidates.map { c -> [String: Any] in
                    ["id": c.rowID,
                     "citekey": displaySafe(c.citekey, max: 200),
                     "literal": displaySafe(c.literal, max: 200),
                     "venueKey": displaySafe(c.venueKey, max: 200),
                     "reason": displaySafe(c.reason, max: 400)]
                },
                "ambiguities": report.ambiguities.map { m -> [String: Any] in
                    ["id": m.rowID,
                     "citekey": displaySafe(m.citekey, max: 200),
                     "literal": displaySafe(m.literal, max: 200),
                     "venueKeys": m.venueKeys.map { displaySafe($0, max: 200) }]
                },
                "note": "apply 帶候選 id 升格；reject 帶候選 id 否決（verdict 落 venue 記錄）",
            ] as [String: Any])
        }
        guard storeFormat >= 11 else {
            throw ServiceError.invalid(
                "venue 歸戶需要 store format ≥ 11（本 store 是 \(storeFormat)）")   // display-safe-exempt: Int
        }
        let chosen = try dedupe(selected).map { id -> VenueResolutionCandidate in
            guard let c = byID[id] else {
                throw ServiceError.notFound("候選 id「\(displaySafe(id, max: 200))」（先不帶 apply 列出候選）")
            }
            return c
        }
        let updatedEntries = VenueResolver.apply(chosen, to: load.entries)
        let changed = zip(load.entries, updatedEntries).filter { $0.0 != $0.1 }.map(\.1)
        for entry in changed { try store.writeEntry(entry) }
        // confirmed verdict 落被判定的 venue 記錄（第 13 條邊的 venue 面）
        var grouped: [String: Venue] = [:]
        for c in chosen {
            guard var v = grouped[c.venueKey] ?? byKey[c.venueKey] else { continue }
            ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                .confirmed, holderKind: .work, holder: c.citekey, literal: c.literal,
                rule: ResolutionLedger.venueRule,
                statement: "resolve apply：alias 完全命中，使用者確認"), to: &v.references)
            grouped[c.venueKey] = v
        }
        for key in grouped.keys.sorted() { try store.writeVenue(grouped[key]!) }
        try LibraryIndex(store: store).rebuild()
        return try jsonString([
            "applied": chosen.map { $0.rowID },
            "entriesRewritten": changed.count,   // display-safe-exempt: Int
            "venuesRewritten": grouped.count,    // display-safe-exempt: Int
        ] as [String: Any])
    }

    /// `resolve-venues --repoint` 的實作（#418）。
    ///
    /// **先全部解析、再一次寫入**：任何一筆前提不符就整批拒絕、零寫入。部分寫入會讓
    /// 使用者面對一個「有些改了有些沒改」的中間態，而那正是改指這種操作最不該有的
    /// ——它本來就是在修一個錯誤歸戶。
    private func repointVenues(_ ids: [String]) throws -> String {
        let load = try store.load()
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        guard storeFormat >= 11 else {
            throw ServiceError.invalid(
                "venue 改指需要 store format ≥ 11（本 store 是 \(storeFormat)）")   // display-safe-exempt: Int
        }
        let venueKeys = Set(load.venues.map(\.key))
        var byCitekey = Dictionary(load.entries.map { ($0.citekey, $0) }, uniquingKeysWith: { a, _ in a })

        struct Move { let citekey: String; let index: Int; let from: String; let to: String }
        var moves: [Move] = []
        var seen = Set<String>()
        for raw in ids where seen.insert(raw).inserted {
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let idx = Int(parts[1]), idx >= 0 else {
                throw ServiceError.invalid(
                    "改指 id「\(displaySafe(raw, max: 200))」不是 citekey:venueIndex:newKey 形")
            }
            let (citekey, newKey) = (parts[0], parts[2])
            guard let entry = byCitekey[citekey] else {
                throw ServiceError.notFound("work「\(displaySafe(citekey, max: 200))」")
            }
            guard idx < entry.venues.count else {
                throw ServiceError.invalid(
                    "work「\(displaySafe(citekey, max: 200))」只有 \(entry.venues.count) 個 venue 邊，"   // display-safe-exempt: Int
                    + "index \(idx) 越界")   // display-safe-exempt: Int
            }
            guard case let .key(oldKey) = entry.venues[idx] else {
                throw ServiceError.invalid(
                    "work「\(displaySafe(citekey, max: 200))」的第 \(idx) 個 venue 邊還是 literal"   // display-safe-exempt: Int
                    + "——那要用 --apply 升格，不是改指")
            }
            guard venueKeys.contains(newKey) else {
                throw ServiceError.notFound("venue「\(displaySafe(newKey, max: 200))」")
            }
            // 改指到自己＝no-op（冪等；重跑同一個 id 不累積 verdict）
            guard oldKey != newKey else { continue }
            moves.append(Move(citekey: citekey, index: idx, from: oldKey, to: newKey))
        }
        guard !moves.isEmpty else {
            return try jsonString(["repointed": [String](), "entriesRewritten": 0,
                                   "venuesRewritten": 0,
                                   "note": "沒有實際變更（改指到自己是 no-op）"] as [String: Any])
        }

        for m in moves {
            var e = byCitekey[m.citekey]!
            e.venues[m.index] = .key(m.to)
            byCitekey[m.citekey] = e
        }
        let touched = Set(moves.map(\.citekey))
        for ck in touched.sorted() { try store.writeEntry(byCitekey[ck]!) }

        // **兩側都留 verdict**：新的 confirmed、舊的 rejected。少了 rejected，
        // 下次提名會把同一個配對再提出來（`ResolutionLedger.rejectedPairings` 讀的正是它）。
        var venuesByKey = Dictionary(load.venues.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for m in moves {
            let literal = byCitekey[m.citekey]!.title
            if var to = venuesByKey[m.to] {
                ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                    .confirmed, holderKind: .work, holder: m.citekey, literal: literal,
                    rule: ResolutionLedger.venueRule,
                    statement: "resolve repoint：由「\(displaySafe(m.from, max: 120))」改指而來，使用者裁定"),
                    to: &to.references)
                venuesByKey[m.to] = to
            }
            if var from = venuesByKey[m.from] {
                ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                    .rejected, holderKind: .work, holder: m.citekey, literal: literal,
                    rule: ResolutionLedger.venueRule,
                    statement: "resolve repoint：改指到「\(displaySafe(m.to, max: 120))」，此配對經裁定為誤"),
                    to: &from.references)
                venuesByKey[m.from] = from
            }
        }
        let changedVenues = Set(moves.flatMap { [$0.from, $0.to] })
        for k in changedVenues.sorted() { try store.writeVenue(venuesByKey[k]!) }
        try LibraryIndex(store: store).rebuild()
        return try jsonString([
            "repointed": moves.map { "\(displaySafe($0.citekey, max: 200)):\($0.index):\(displaySafe($0.to, max: 200))" },
            "entriesRewritten": touched.count,        // display-safe-exempt: Int
            "venuesRewritten": changedVenues.count,   // display-safe-exempt: Int
        ] as [String: Any])
    }

    /// `resolve-venues --demote` 的實作（#418）。
    ///
    /// **literal 從 verdict 取回，不從 venue 的名字猜**：`--apply` 寫的
    /// `resolution-confirmed` 的 value 逐字帶著原本的 literal（`<kind>:<key> :: <literal>`
    /// 文法，`entity-backlink-completeness` 第 13 條邊）。所以降格是**無損**的。
    ///
    /// 解析走 `ResolutionLedger.verdicts`——那是**唯一**的讀端解析器，自己再寫一個
    /// 就是第二份會分岔的規格。
    ///
    /// **沒有 verdict 可依據時拒絕，不得拿顯示名頂替**：顯示名不是那筆記錄原本寫的字
    /// （實例：WoS 的 `PSYCHOMETRIKA` vs 正式刊名 `Psychometrika`），用它會安靜改寫
    /// 書目資料——那正是 `lossless-intake` 在防的。
    private func demoteVenues(_ ids: [String]) throws -> String {
        let load = try store.load()
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        guard storeFormat >= 11 else {
            throw ServiceError.invalid(
                "venue 降格需要 store format ≥ 11（本 store 是 \(storeFormat)）")   // display-safe-exempt: Int
        }
        var byCitekey = Dictionary(load.entries.map { ($0.citekey, $0) }, uniquingKeysWith: { a, _ in a })
        var venuesByKey = Dictionary(load.venues.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        struct Demotion { let citekey: String; let index: Int; let venueKey: String; let literal: String }
        var plan: [Demotion] = []
        var seen = Set<String>()
        for raw in ids where seen.insert(raw).inserted {
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let idx = Int(parts[1]), idx >= 0 else {
                throw ServiceError.invalid(
                    "降格 id「\(displaySafe(raw, max: 200))」不是 citekey:venueIndex 形")
            }
            let citekey = parts[0]
            guard let entry = byCitekey[citekey] else {
                throw ServiceError.notFound("work「\(displaySafe(citekey, max: 200))」")
            }
            guard idx < entry.venues.count else {
                throw ServiceError.invalid(
                    "work「\(displaySafe(citekey, max: 200))」只有 \(entry.venues.count) 個 venue 邊，"   // display-safe-exempt: Int
                    + "index \(idx) 越界")   // display-safe-exempt: Int
            }
            guard case let .key(vkey) = entry.venues[idx] else {
                throw ServiceError.invalid(
                    "work「\(displaySafe(citekey, max: 200))」的第 \(idx) 個 venue 邊已經是 literal")   // display-safe-exempt: Int
            }
            guard let venue = venuesByKey[vkey] else {
                throw ServiceError.notFound("venue「\(displaySafe(vkey, max: 200))」")
            }
            // **原 literal 從 confirmed verdict 取回**——走唯一解析器。
            let (verdicts, _) = ResolutionLedger.verdicts(references: venue.references)
            guard let hit = verdicts.first(where: {
                $0.kind == .confirmed && $0.holderKind == .work && $0.holder == citekey
            }) else {
                throw ServiceError.invalid(
                    "venue「\(displaySafe(vkey, max: 200))」上找不到 work「\(displaySafe(citekey, max: 200))」"
                    + "的 confirmed verdict——原 literal 無從取回。"
                    + "不拿 venue 的顯示名頂替：那不是這筆記錄原本寫的字，用它會安靜改寫書目資料")
            }
            plan.append(Demotion(citekey: citekey, index: idx, venueKey: vkey, literal: hit.literal))
        }

        for d in plan {
            var e = byCitekey[d.citekey]!
            e.venues[d.index] = .literal(d.literal)
            byCitekey[d.citekey] = e
        }
        let touched = Set(plan.map(\.citekey))
        for ck in touched.sorted() { try store.writeEntry(byCitekey[ck]!) }

        // **留 rejected**：少了它，下一輪 `--apply` 會把同一個配對再提名一次，
        // 而使用者剛剛才說它是錯的（`ResolutionLedger.rejectedPairings` 讀的正是它）。
        for d in plan {
            guard var v = venuesByKey[d.venueKey] else { continue }
            ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                .rejected, holderKind: .work, holder: d.citekey, literal: d.literal,
                rule: ResolutionLedger.venueRule,
                statement: "resolve demote：退回 literal，此配對經裁定為誤"), to: &v.references)
            venuesByKey[d.venueKey] = v
        }
        let changedVenues = Set(plan.map(\.venueKey))
        for k in changedVenues.sorted() { try store.writeVenue(venuesByKey[k]!) }
        try LibraryIndex(store: store).rebuild()
        return try jsonString([
            "demoted": plan.map { "\(displaySafe($0.citekey, max: 200)):\($0.index)" },
            "entriesRewritten": touched.count,        // display-safe-exempt: Int
            "venuesRewritten": changedVenues.count,   // display-safe-exempt: Int
        ] as [String: Any])
    }

    // MARK: - Organization MCP 面（#304 parity 移轉）

    /// org 單筆建檔（addPerson 形；parent 選填、以 key 指涉——literal parent 由
    /// bootstrap 面處理，單筆面收窄為已知 parent）。
    public func addOrganization(key: String, names: [String],
                                parentKey: String? = nil, note: String? = nil) throws -> String {
        let load = try store.load()
        guard !load.organizations.contains(where: { $0.key == key }) else {
            throw ServiceError.invalid("organization key「\(displaySafe(key, max: 200))」已存在")
        }
        if let pk = parentKey, !load.organizations.contains(where: { $0.key == pk }) {
            throw ServiceError.notFound("parent organization「\(displaySafe(pk, max: 200))」")
        }
        var org = Organization(key: key,
                               names: Timeline(names.map { TemporalValue(value: $0) }),
                               id: UUID())
        if let pk = parentKey {
            org.parents = TimelineOf([TemporalValue(value: .key(pk))])
        }
        org.note = note
        try store.writeOrganization(org)
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["key": key, "names": names.map { displaySafe($0, max: 200) }])
    }

    /// org 消歧（OrgResolver 包裝；apply/reject 與 verdict 紀律同 venue 面）。
    /// 候選 id 格式 `<holderKey>:<literal 前 40 字>` 不穩定，故用 rowID 慣例：
    /// holder key + literal 的複合（OrgResolver 未定義 rowID——這裡以
    /// `<holderKey>::<literal>` 為 id，冒號雙分隔避開 key 內容）。
    public func resolveOrganizations(apply: [String]?, reject: [String]? = nil) throws -> String {
        let load = try store.load()
        let rejected = ResolutionLedger.rejectedPairings(organizations: load.organizations)
        let report = OrgResolver.resolve(people: load.people,
                                         organizations: load.organizations,
                                         rejected: rejected, entries: load.entries)
        // #378：`.work` 的 key 是 citekey，而同一筆可以有多個團體作者位——
        // 少了索引，兩個位置會共用同一個 id 而無法分別 apply。
        // 這兩行**刻意不消毒**：rowID 產的是 apply 的回程把手，呼叫端要逐字送回來，
        // 消毒會讓它對不上（且 `displaySafe` 不冪等——二次呼叫會逃脫自己的反斜線）。
        // 控制字元由 JSON 編碼處理；CLI 面的人可讀輸出走 `label(…)`，那裡有消毒。
        func rowID(_ c: OrgResolutionCandidate) -> String {
            if case let .work(citekey, i) = c.holder { return "\(citekey)[\(i)]::\(c.literal)" }   // display-safe-exempt: 回程把手須逐字
            return "\(c.holder.key)::\(c.literal)"   // display-safe-exempt: 同上（本行語意與 #378 前相同——先前寫成隱式 return 而未被守衛看見）
        }
        let byID = Dictionary(report.candidates.map { (rowID($0), $0) },
                              uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(load.organizations.map { ($0.key, $0) },
                               uniquingKeysWith: { a, _ in a })
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        func dedupe(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.filter { seen.insert($0).inserted }
        }
        if let rejectIDs = reject, !rejectIDs.isEmpty {
            guard storeFormat >= 8 else {
                throw ServiceError.invalid(
                    "resolution verdict 需要 store format ≥ 8（本 store 是 \(storeFormat)）")   // display-safe-exempt: Int
            }
            let chosen = try dedupe(rejectIDs).map { id -> OrgResolutionCandidate in
                guard let c = byID[id] else {
                    throw ServiceError.notFound("候選 id「\(displaySafe(id, max: 200))」（先不帶 apply 列出候選）")
                }
                return c
            }
            var grouped: [String: Organization] = [:]
            for c in chosen {
                guard var o = grouped[c.orgKey] ?? byKey[c.orgKey] else {
                    throw ServiceError.notFound("organization「\(displaySafe(c.orgKey, max: 200))」")
                }
                let holderKind: ProvenanceReference.VerdictHolderKind =
                    { if case .person = c.holder { return .person } else { return .org } }()
                ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                    .rejected, holderKind: holderKind, holder: c.holder.key, literal: c.literal,
                    rule: ResolutionLedger.orgRule,
                    statement: "resolve reject：使用者否決此配對"), to: &o.references)
                grouped[c.orgKey] = o
            }
            for key in grouped.keys.sorted() { try store.writeOrganization(grouped[key]!) }
            try LibraryIndex(store: store).rebuild()
            return try jsonString(["rejected": chosen.map { rowID($0) },
                                   "organizationsRewritten": grouped.count] as [String: Any])   // display-safe-exempt: Int
        }
        guard let selected = apply, !selected.isEmpty else {
            return try jsonString([
                "candidates": report.candidates.map { c -> [String: Any] in
                    ["id": rowID(c),
                     "holder": displaySafe(c.holder.key, max: 200),
                     "literal": displaySafe(c.literal, max: 200),
                     "orgKey": displaySafe(c.orgKey, max: 200)]
                },
                "ambiguities": report.ambiguities.map { m -> [String: Any] in
                    ["holder": displaySafe(m.holder.key, max: 200),
                     "literal": displaySafe(m.literal, max: 200),
                     "orgKeys": m.orgKeys.map { displaySafe($0, max: 200) }]
                },
                "note": "apply 帶候選 id 歸戶；reject 帶候選 id 否決",
            ] as [String: Any])
        }
        let chosen = try dedupe(selected).map { id -> OrgResolutionCandidate in
            guard let c = byID[id] else {
                throw ServiceError.notFound("候選 id「\(displaySafe(id, max: 200))」（先不帶 apply 列出候選）")
            }
            return c
        }
        let applied = OrgResolver.apply(chosen, to: load.people,
                                        organizations: load.organizations,
                                        entries: load.entries)
        for p in applied.people { try store.writePerson(p) }
        for o in applied.organizations { try store.writeOrganization(o) }
        // #378：作者位歸戶會改寫 entry
        for e in applied.entries where !load.entries.contains(where: { $0 == e }) {
            try store.writeEntry(e)
        }
        // confirmed verdicts
        var grouped: [String: Organization] = [:]
        let byKeyAfter = Dictionary((applied.organizations.isEmpty ? load.organizations : applied.organizations)
            .map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for c in chosen {
            guard var o = grouped[c.orgKey] ?? byKeyAfter[c.orgKey] ?? byKey[c.orgKey] else { continue }
            // **窮盡 switch，不是兩路判斷**（#378）：原本是
            // `if case .person … else return .org`，而 `.work` 會被靜默算成 `.org`
            // ——verdict 的 kind 屬配對身分（person／org key 可合法同名，見
            // `ResolutionPairing` 的 doc），算錯會讓否決比對永遠對不上。
            let holderKind: ProvenanceReference.VerdictHolderKind = {
                switch c.holder {
                case .person: return .person
                case .organization: return .org
                case .work: return .work
                }
            }()
            ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                .confirmed, holderKind: holderKind, holder: c.holder.key, literal: c.literal,
                rule: ResolutionLedger.orgRule,
                statement: "resolve apply：org name 完全命中，使用者確認"), to: &o.references)
            grouped[c.orgKey] = o
        }
        for key in grouped.keys.sorted() { try store.writeOrganization(grouped[key]!) }
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["applied": chosen.map { rowID($0) },
                               "peopleRewritten": applied.people.count,        // display-safe-exempt: Int
                               "organizationsRewritten": grouped.count] as [String: Any])   // display-safe-exempt: Int
    }

    func jsonString(_ obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
