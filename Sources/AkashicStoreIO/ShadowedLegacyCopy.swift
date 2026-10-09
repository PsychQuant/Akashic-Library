import Foundation
import AkashicCore

/// #709：index 重建略過的一份 legacy 拷貝——同一筆記錄一份在 `entities/<id>.yaml`、一份還在 `entries/`／`people/`。
///
/// 使用者 2026-09-30 裁決：index 重建遇到這種兩份，以 `entities/` 那份為準、略過 legacy 拷貝並回報。先前兩份一起進 index：
/// work 撞 `entries.citekey` UNIQUE（或 `uuid` PRIMARY KEY），整次重建失敗——寫入後會重建 index 的呼叫因此全部以錯誤收場，
/// 連不相干記錄的寫入也一樣；person 以 key 為主鍵、`INSERT OR IGNORE` 留下列舉順序的第一筆（#670），改名留下的舊 key 則另成一列。
///
/// 代價（使用者看過）：有人手改過 legacy 那份時，index 看不到那次修改，只剩 validate 的 #641 警告。
public struct ShadowedLegacyCopy: Equatable, Sendable {
    public let kind: LegacyCopyLeft.Kind
    /// legacy 那份的 citekey（work）或 person key——改名留下的拷貝是**舊**鍵。**原始值**，輸出端消毒。
    public let key: String
    public let id: UUID
    /// legacy 檔相對 store root 的路徑（load 實際讀到的那個檔）。**原始值**，輸出端消毒。
    public let legacyFile: String

    public init(kind: LegacyCopyLeft.Kind, key: String, id: UUID, legacyFile: String) {
        self.kind = kind; self.key = key; self.id = id; self.legacyFile = legacyFile
    }

    /// index 取的那一份。
    public var entitiesFile: String { "entities/\(id.uuidString).yaml" }
}

/// 計畫讀到的一筆無法唯一定位的記錄（#709，使用者 2026-10-09 裁決 2）。
public struct UnlocatablePlanRecord: Hashable, Sendable {
    public let kind: LegacyCopyLeft.Kind
    /// citekey（work）或 person key。**原始值**，輸出端消毒。
    public let key: String

    public init(kind: LegacyCopyLeft.Kind, key: String) { self.kind = kind; self.key = key }
}

/// 一個 bootstrap 計畫讀到、而讓 `--apply` 整批拒絕的記錄（`LibraryLoad.planBlockers`）。
public struct BootstrapPlanBlockers: Equatable, Sendable {
    /// load 標出的 legacy 拷貝（計畫讀到的種類）。
    public let copies: [ShadowedLegacyCopy]
    /// 計畫讀到的種類中無法唯一定位、而不在任何一對拷貝裡的記錄，依 (kind, key) 排序、不重複。
    public let unlocatable: [UnlocatablePlanRecord]

    public init(copies: [ShadowedLegacyCopy], unlocatable: [UnlocatablePlanRecord]) {
        self.copies = copies; self.unlocatable = unlocatable
    }

    public var isEmpty: Bool { copies.isEmpty && unlocatable.isEmpty }
}

/// 三個 bootstrap 的計畫各讀哪幾種記錄（#709 第四次 verify；使用者 2026-10-09 裁決 1）。封閉三列，不得依性質相似類推——新的寫入候選面要自己加一列、
/// 寫出它讀哪幾種記錄。附註、`bootstrap-people --json` 的兩個計數與 `--apply` 的拒絕都只看這幾種（`LibraryLoad.planBlockers`）。
public enum BootstrapPlanSource: Sendable {
    /// 作者 literal 來自 entries；person 記錄（含 person 的拷貝）進 `existing`——已用的 key、已知的名字——與否決／確認史。
    ///
    /// ~~person 拷貝只會讓候選少一個（保守側），不在計畫裡~~：#709 b36 verify（MEDIUM 1、3）以真 binary 否掉，三條反例——拷貝帶 entities/ 那份沒有的否決記錄，
    /// 本該「與既有 person 寬鬆共鍵、先消歧」的名字被放行建檔；拷貝多一個名字，那個 literal 被當成已存在、既不是候選也不在 pending；內容相同的改名拷貝
    /// 讓舊 key 留在已用的 key 裡，`--apply` 寫出的新 key 多一個 `-2` 後綴、拷貝刪掉之後也改不回來。所以 person 拷貝的影響可以往三個方向走，
    /// 使用者 2026-10-09 裁決：person 拷貝也算，有就拒絕。
    case people
    /// 刊名 literal 只來自 entries（`VenueBootstrap.result(entries:existing:)`）。
    case venues
    /// 機構名來自 person 的隸屬 literal 與 entries 的團體作者 literal（`OrgBootstrap.result`）——兩種都讀。organization 沒有 legacy 拷貝。
    case organizations

    public var kinds: Set<LegacyCopyLeft.Kind> {
        switch self {
        case .venues: return [.work]
        case .people, .organizations: return [.work, .person]
        }
    }

    public var command: String {
        switch self {
        case .people: return "bootstrap-people"
        case .venues: return "bootstrap-venues"
        case .organizations: return "bootstrap-organizations"
        }
    }
}

extension LibraryLoad {
    /// load 標出的 legacy 拷貝（`fileSituation.shadowedLegacyFile`），依 (kind, key) 排序。`withoutShadowedLegacyCopies` 拿掉的就是這些
    /// （`LibraryIndex.rebuild` 把這份清單放進 `IndexStats.skippedLegacyCopies`）；`crossRecordIssues` 也從這裡認出這一對。
    public var shadowedLegacyCopies: [ShadowedLegacyCopy] {
        let works = entries.compactMap { e in
            e.fileSituation.shadowedLegacyFile.map { ShadowedLegacyCopy(kind: .work, key: e.citekey, id: e.id, legacyFile: $0) }
        }
        let persons = people.compactMap { p in
            p.fileSituation.shadowedLegacyFile.map { ShadowedLegacyCopy(kind: .person, key: p.key, id: p.id, legacyFile: $0) }
        }
        return (works + persons).sorted { ($0.kind.rawValue, $0.key, $0.legacyFile) < ($1.kind.rawValue, $1.key, $1.legacyFile) }
    }

    /// 以 `entities/` 那份為準的讀取視圖（#709，使用者 2026-10-01 把裁決從 index 延伸到匯出與 App）：拿掉 legacy 拷貝，其餘不動。
    /// **過濾只有這一處**——index 重建（`LibraryIndex.rebuild`）、三個匯出面（MCP `akashic_export`、CLI `export-bib`、
    /// `export-tables`）與 App 的 `AppState.load` 都呼叫它，不各自寫一份 `filter`。其餘呼叫端只拿它算**讀數**（doctor 的普查、
    /// library 的成員數、DOI 命中、`akashic people`、`view show`……，清單在 `mcp-cli-parity` 的 #709 段）。
    ///
    /// **逐筆的可寫性不因過濾而改變**：拿掉拷貝之後，留下的那一份在完整的 load 上若無法唯一定位（#627／#641——一般的寫入留下的一對
    /// 共用 citekey；改名留下的一對共用 id），在這個視圖上也要無法唯一定位，否則以這個視圖定位寫入的消費端（App 的裁決台）會放行
    /// CLI／MCP 拒絕的寫入。所以那一份若沒有自己的 `unwritableReason`，補上一句說出是哪份拷貝擋著它；判準是「完整 load 上無法唯一定位、
    /// 過濾後卻可以」，不是另一條規則。改名留下的 **person** 一對裡，entities/ 那份在完整的 load 上本來就寫得進去（`unlocatablePersonKeys`
    /// 刻意不收「共用 id」），視圖上也一樣。
    ///
    /// **批次的結果會變**（#709 第三次 verify）：上面那句只對逐筆成立。一個以批次為單位拒絕的寫入者，若用這個視圖規劃寫入集合，legacy 拷貝
    /// 從集合裡消失——`authorize-names` 先前就是靠 legacy 那份被算進寫入集合而整批拒絕，R2 改用視圖之後改名留下拷貝的 person 從拒絕變成寫入。
    /// 所以**寫入候選面與依據判定**（三個 bootstrap、`authorize-names`、library 規則的依據）看完整的 load，不用這個視圖——使用者 2026-10-05
    /// 裁決（#709）：不把「以 entities/ 為準」延伸到寫入候選面，寫入一律看完整資料，視圖只用在讀數；計畫讀到拷貝時三個 bootstrap 的
    /// `--apply` 整批拒絕（`refuseApplyWithPlanBlockers`）。
    ///
    /// 驗證（validate、doctor 的 `crossRecordIssues`、App 的健康總覽）**不**用這個視圖——它們要照舊看到兩份並存。
    public func withoutShadowedLegacyCopies() -> LibraryLoad {
        let shadowed = shadowedLegacyCopies
        guard !shadowed.isEmpty else { return self }
        var out = self
        out.entries = entries.filter { $0.fileSituation.shadowedLegacyFile == nil }
        out.people = people.filter { $0.fileSituation.shadowedLegacyFile == nil }

        let blockedWorks = entries.unlocatableCitekeys, stillBlockedWorks = out.entries.unlocatableCitekeys
        for i in out.entries.indices where out.entries[i].fileSituation.unwritableReason == nil {
            let e = out.entries[i]
            guard blockedWorks.contains(e.citekey), !stillBlockedWorks.contains(e.citekey) else { continue }
            let files = shadowed.filter { $0.kind == .work && ($0.id == e.id || $0.key == e.citekey) }.map(\.legacyFile)
            out.entries[i].fileSituation.unwritableReason = Self.keptCopyReason(files)
        }
        let blockedPeople = people.unlocatablePersonKeys, stillBlockedPeople = out.people.unlocatablePersonKeys
        for i in out.people.indices where out.people[i].fileSituation.unwritableReason == nil {
            let p = out.people[i]
            guard blockedPeople.contains(p.key), !stillBlockedPeople.contains(p.key) else { continue }
            let files = shadowed.filter { $0.kind == .person && ($0.id == p.id || $0.key == p.key) }.map(\.legacyFile)
            out.people[i].fileSituation.unwritableReason = Self.keptCopyReason(files)
        }
        return out
    }

    /// 一個 bootstrap 計畫讀到、而讓它的 `--apply` 整批拒絕的記錄（#709）：load 標出的 legacy 拷貝 ∪ 計畫來源種類中無法唯一定位的記錄，
    /// 只看流進該命令的那幾種（`BootstrapPlanSource.kinds`）。附註、`bootstrap-people --json` 的兩個計數與 `--apply` 的拒絕都由這裡算——判準只有這一份。
    ///
    /// - 拷貝：#709 第四次 verify（MEDIUM 1、3，LOW 11）讓附註只數計畫讀到的種類；使用者 2026-10-09 裁決 1 讓 `bootstrap-people` 也讀 person 拷貝。
    /// - 無法唯一定位（使用者 2026-10-09 裁決 2，b36 verify MEDIUM 4）：只認 load 的拷貝標記時，兩個 legacy 檔共用 id、或 entities/ 與 legacy 同 citekey
    ///   而 id 不同，計數同樣加倍，乾跑沒有附註、`--apply` 寫入之後才以 index 的 UNIQUE 失敗收場。條件與 `authorize-names` 的現行判準一致：works 問
    ///   `unlocatableCitekeys`、people 問 `unlocatablePersonKeys`（各自的封閉類別寫在那裡，這裡不另寫一份）。同一對拷貝的兩份本來就無法唯一定位，
    ///   已經在 `copies` 說了，不重複列。
    public func planBlockers(_ source: BootstrapPlanSource) -> BootstrapPlanBlockers {
        let copies = shadowedLegacyCopies.filter { source.kinds.contains($0.kind) }
        let pairIDs = Set(copies.map { "\($0.kind.rawValue):\($0.id.uuidString)" })
        var found = Set<UnlocatablePlanRecord>()
        if source.kinds.contains(.work) {
            let keys = entries.unlocatableCitekeys
            for e in entries where keys.contains(e.citekey) && !pairIDs.contains("work:\(e.id.uuidString)") {
                found.insert(UnlocatablePlanRecord(kind: .work, key: e.citekey))
            }
        }
        if source.kinds.contains(.person) {
            let keys = people.unlocatablePersonKeys
            for p in people where keys.contains(p.key) && !pairIDs.contains("person:\(p.id.uuidString)") {
                found.insert(UnlocatablePlanRecord(kind: .person, key: p.key))
            }
        }
        return BootstrapPlanBlockers(copies: copies,
                                     unlocatable: found.sorted { ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key) })
    }

    /// 寫入候選面（三個 bootstrap）乾跑的計畫附註：說出計畫讀到幾份拷貝與幾筆無法唯一定位的記錄、各自怎麼影響計畫、逐份點名（各至多 20），
    /// 說 `--apply` 會整批拒絕；都沒有時 nil。走 stdout（`print`），換行照常分行。已消毒（檔名與 key 逐項 `displaySafeInvisible`，其餘是常數字面與筆數）。
    ///
    /// 這些面看完整的 load（使用者 2026-10-05 裁決 1：寫入候選面一律看完整資料）。乾跑照常列出候選（2026-10-05 裁決 2）；`--apply` 由
    /// `refuseApplyWithPlanBlockers` 擋。
    public func planBlockersNote(_ source: BootstrapPlanSource) -> String? {
        let b = planBlockers(source)
        guard !b.isEmpty else { return nil }
        var lines = ["⚠ 計畫含 " + Self.blockerCounts(b) + "：本命令看完整的資料，下面的候選照常列出，--apply 會整批拒絕、零寫入（#709）"]
        if !b.copies.isEmpty {
            lines.append("  legacy 拷貝（同一筆記錄在 entities/ 也有一份）的內容也進計畫：")
            lines += Self.copyEffects(source, kinds: Set(b.copies.map(\.kind))).map { "    · " + $0 }
            lines.append("  " + Self.legacyCopiesRemedy + "：")
            lines += Self.limitedLines(b.copies.map {
                "    \(displaySafeInvisible($0.legacyFile, max: 300))（\($0.kind.rawValue)，entities/ 那份是 \($0.entitiesFile)）"   // display-safe-exempt: kind.rawValue 是常數；entitiesFile 由 UUID 組成
            }, unit: "份")
        }
        if !b.unlocatable.isEmpty {
            let reasons = Set(b.unlocatable.map(\.kind)).sorted { $0.rawValue < $1.rawValue }
                .map { $0 == .work ? "work：" + UnlocatableReason.work : "person：" + UnlocatableReason.person }.joined(separator: "；")
            lines.append("  無法唯一定位的記錄（\(reasons)）的內容也進計畫：重複的那幾筆讓計數加倍、寫入之後的 index 重建可能撞上 UNIQUE；"   // display-safe-exempt: reasons 由常數字面組成
                         + "只有一份而寫入時會被拒的，是還沒處理的 legacy 殘留。先修好再跑：")
            lines += Self.limitedLines(b.unlocatable.map {
                "    \($0.kind.rawValue)「\(displaySafeInvisible($0.key, max: 200))」"   // display-safe-exempt: kind.rawValue 是常數
            }, unit: "筆")
        }
        return lines.joined(separator: "\n")
    }

    /// 三個 bootstrap 的 `--apply`：計畫讀到 legacy 拷貝或無法唯一定位的記錄時整批拒絕、零寫入（使用者 2026-10-05 裁決 2、2026-10-09 裁決 1／2）。
    /// 先前只在輸出開頭印一行附註、之後照寫：附註的補救（先刪拷貝再跑）到達時寫入已經發生（#709 第四次 verify MEDIUM 5，LOW 6、13、15）。
    /// 判準與附註同一個：`planBlockers`——計畫沒讀到的種類不擋。
    ///
    /// **訊息不帶逐份清單**（b36 verify LOW 6、8、12、14）：錯誤走 CLI 的單行出口，換行被逃成字面 `\u{000A}`、整行在 400 處截斷——12 份拷貝時
    /// 只點名得到兩份，「至多 20 份」「…另 N 份」都到不了使用者。清單在乾跑的附註（stdout，照常分行）；這裡只說筆數、處置與去哪裡看。
    public func refuseApplyWithPlanBlockers(_ source: BootstrapPlanSource) throws {
        let b = planBlockers(source)
        guard !b.isEmpty else { return }
        var remedies: [String] = []
        if !b.copies.isEmpty { remedies.append("確認 entities/ 那份是新的之後刪掉 legacy 拷貝") }
        if !b.unlocatable.isEmpty { remedies.append("無法唯一定位的先修好") }
        let counts = Self.blockerCounts(b), remedy = remedies.joined(separator: "、")
        throw StoreIOError.invalidInput(
            what: "\(source.command) --apply",   // display-safe-exempt: source.command 是常數字面
            why: "計畫含 " + counts + "，計數與既有記錄都可能不準；整批拒絕、零寫入（#709）。"   // display-safe-exempt: counts 由 Int 與常數字面組成（blockerCounts）
               + "乾跑（不帶 --apply）逐份列出，akashic validate 逐筆說出原因；" + remedy + "，再跑")   // display-safe-exempt: remedy 由常數字面組成
    }

    /// 「N 份 legacy 拷貝、M 筆無法唯一定位的記錄」（沒有的那一半省略）——附註與拒絕共用。只含 Int 與常數字面。
    static func blockerCounts(_ b: BootstrapPlanBlockers) -> String {
        var parts: [String] = []
        if !b.copies.isEmpty { parts.append("\(b.copies.count) 份 legacy 拷貝") }   // display-safe-exempt: Int
        if !b.unlocatable.isEmpty { parts.append("\(b.unlocatable.count) 筆無法唯一定位的記錄") }   // display-safe-exempt: Int
        return parts.joined(separator: "、")
    }

    /// 拷貝對這個計畫的影響，一種一句——依計畫與拷貝的種類說實話（使用者 2026-10-09 裁決 1：先前那句「person 拷貝只會讓候選少一個」是假的）。只含常數字面。
    static func copyEffects(_ source: BootstrapPlanSource, kinds: Set<LegacyCopyLeft.Kind>) -> [String] {
        var out: [String] = []
        if kinds.contains(.work) {
            out.append("work 拷貝裡的 literal 也是候選，與 entities/ 那份相同的多算一次出現（可能越過 --min-occurrences）")
        }
        if kinds.contains(.person) {
            switch source {
            case .people:
                out.append("person 拷貝的 key、名字與否決／確認記錄也算數：多出的否決可能讓該先消歧的名字成為候選、多出的名字可能讓 literal "
                           + "被當成已存在而不列出、留著的舊 key 可能讓新 key 多一個後綴")
            case .organizations:
                out.append("person 拷貝裡的隸屬 literal 也是候選，與 entities/ 那份相同的多算一次出現")
            case .venues:
                break   // 不讀 person（`kinds`）
            }
        }
        return out
    }

    /// 刪拷貝的前提——兩份可能已經分岔（#705 第三次 verify 對 `LegacyCopyLeft.explanation` 的同一個前提）。
    static let legacyCopiesRemedy = "確認 entities/ 那份是新的之後刪掉 legacy 拷貝（akashic validate 逐筆列出），再跑"

    /// 至多 20 行，其餘一行概括。
    static func limitedLines(_ lines: [String], unit: String) -> [String] {
        var out = Array(lines.prefix(20))
        if lines.count > 20 { out.append("    …另 \(lines.count - 20) \(unit)") }   // display-safe-exempt: Int；unit 是呼叫端的常數字面
        return out
    }

    /// 已消毒（`unwritableReason` 的契約）。
    static func keptCopyReason(_ legacyFiles: [String]) -> String {
        "legacy 拷貝 " + legacyFiles.sorted().map { displaySafeInvisible($0, max: 300) }.joined(separator: "、")
            + " 還在（與這一筆同一個 id 或同一個 citekey）——刪掉它之前以 citekey／key 定位的寫入面拒絕寫入（#641、#709）"
    }
}

extension LibraryStore {
    /// 「同一筆記錄的 legacy 拷貝」的判準——**只有這一份**（#709）。讀它標的結果的：`LibraryLoad.withoutShadowedLegacyCopies`
    /// （index 重建、匯出、App）、#645 的記錄位元組、`crossRecordIssues`（這一對的 UUID／citekey／key 重複降為 warning、#641 警告補一句）。
    ///
    /// 判準：store 是 entities 佈局（format ≥ 2），一筆 work 從 `entries/` 讀進來（person 從 `people/`），而 `entities/` 讀進來的記錄裡有
    /// **同一種、同一個 id** 的一筆。只有這一對；其餘一律不標。
    ///
    /// **為什麼是 id**：
    /// - `entities/` 的檔名就是 id，load 已驗檔名與記錄的 id 相符——那一份是這個 id 在正典位置上的記錄。
    /// - #631 的搬移把 legacy 檔的內容改寫後寫進 `entities/<它的 id>.yaml`、再刪 legacy 檔；刪不掉時留下的正是**同一個 id** 的舊檔。
    ///   改名（`renameEntry`／`renamePerson`）不換 UUID，留下的舊檔 citekey／key 是改名前的——所以 citekey 或 key 會不同，id 不會。
    /// - 反過來，兩筆**不同**的記錄共用 citekey（或 person key）時 id 不同，不在此列：它們照舊是 `crossRecordIssues` 的 error，
    ///   work 那一對照舊讓 index 重建撞 UNIQUE——這條規則不替真的重複選一筆。
    ///
    /// **為什麼要同一種**：`entities/` 也住 organization、venue、divergence。work 與 person 共用一個 id 不是同一筆記錄
    /// （#631 的目的檔檢查把它當成「另一種記錄」拒絕）。
    ///
    /// **為什麼限 format ≥ 2**：format 1 的 `entries/`、`people/` 是正典位置、不是殘留（同 #641 的 `annotateFileSituations`）；
    /// 那種 store 裡若有 `entities/` 的檔，以它為準是反的。
    ///
    /// - Parameters:
    ///   - legacyEntryFiles／legacyPeopleFiles：`result.entries`／`result.people` 從第 `entitiesEntryCount`／`entitiesPeopleCount` 筆起
    ///     逐筆對應的 legacy 檔路徑（load 先讀 entities、再讀 legacy，排序之前呼叫）。
    static func markLegacyCopiesShadowedByEntities(_ result: inout LibraryLoad, format: Int,
                                                   entitiesEntryCount: Int, legacyEntryFiles: [String],
                                                   entitiesPeopleCount: Int, legacyPeopleFiles: [String]) {
        guard format >= 2 else { return }
        let entityWorkIDs = Set(result.entries.prefix(entitiesEntryCount).map(\.id))
        for (offset, file) in legacyEntryFiles.enumerated() {
            let i = entitiesEntryCount + offset
            if entityWorkIDs.contains(result.entries[i].id) { result.entries[i].fileSituation.shadowedLegacyFile = file }
        }
        let entityPersonIDs = Set(result.people.prefix(entitiesPeopleCount).map(\.id))
        for (offset, file) in legacyPeopleFiles.enumerated() {
            let i = entitiesPeopleCount + offset
            if entityPersonIDs.contains(result.people[i].id) { result.people[i].fileSituation.shadowedLegacyFile = file }
        }
    }
}
