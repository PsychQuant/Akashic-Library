import Foundation
import AkashicCore
import AkashicStoreIO

/// Zotero 匯入**新建**的 work 與另一筆 work 共用 DOI 時寫下的歧異提名——一列是一對（#611）。
///
/// 使用者 2026-10-01 裁決：「照建，並自動記一筆歧異提名」。#605 讓同一篇作品在另一個 library 以**同一個 zotero key**
/// 出現時掛成附加來源；key 不同、只有 DOI 相同時，匯入照常新建一筆，攣生要事後才被看見。現在新建之後當場記一筆
/// divergence（work 形狀、**沒有判斷**），交給既有的攣生合併流程（`resolve-divergence`、`akashic-merge-twins`）判定。
///
/// **DOI 相等只是提名，不是同一性證據**（`identity-is-judged-not-matched`「識別碼終結指涉，不終結描述」）：勘誤與原文
/// 共用 DOI、一筆作品可以有多個 DOI（#394）。所以匯入者**不**合併、**不**掛附加來源、**不**填 judgement／prefers——
/// 那是判定，屬 `resolve-divergence`。這一步是程式寫的提名（recall），`two-kinds-of-edits` 的「提名（程式）→ 判定（AI）」。
public struct DOINomination: Equatable {
    /// 封閉五值。
    public enum Status: String, Equatable {
        /// 這一趟寫下一筆新的歧異記錄。
        case recorded
        /// 已有一筆 work 歧異記錄的候選同時含這兩筆（同一組，或更大的一組）——不重寫：重寫會換掉 question，
        /// 而那筆記錄可能已經帶著人補上的判斷（`recordDivergence` 對「無判斷的重錄」本來就拒絕）。
        case alreadyRecorded
        /// 其中一筆無法唯一定位（`unlocatableCitekeys`：citekey 重複、與另一筆共用 id、檔案寫入時會被拒，
        /// 或這一趟寫入之後留下兩份）——不點名它：歧異記錄以 citekey 指涉候選，指不到唯一一筆的 key 會讓合併猜。
        case unlocatable
        /// 寫入被拒或擲錯（legacy 佈局、store format < 5、候選 key 不合 `StoreKey`、歧異記錄的 id 已被另一種形狀占用等）；原因在 `error`。
        case failed
        /// 一個 DOI 被超過 `DOITwinNomination.maxGroupSize` 筆 work 共用（這一趟新建的加上其餘的）：**這個 DOI 一對都沒記**，
        /// 改報一列（`dois` 是那一個 DOI、`groupSize` 是共用它的 work 數、`created` 是其中這一趟新建的 citekey 最小的一筆、`other` 為空）。
        /// 一對一筆會寫 C(k,2) 筆記錄（#611 R1 verify 第 5 列：k=80 → 3,160 筆、10 秒），而一個 DOI 被這麼多筆共用幾乎必是書或資料集的概念 DOI，
        /// 逐對提名沒有資訊量。（一對同時共用另一個沒超過門檻的 DOI 時，那一對仍由那個 DOI 的群組提名。）
        case groupTooLarge

        /// 這一列的歧異記錄是否已在 store 裡（`recorded`／`alreadyRecorded`）；其餘三種**沒有記**——提名只在新建時觸發，
        /// 重新匯入不會再提名，只能人工補記（`record-divergence`）。
        public var isInStore: Bool { self == .recorded || self == .alreadyRecorded }
    }

    /// 一個 DOI 最多被這麼多筆 work 共用時才逐對提名；超過就一對都不記、改報一列 `groupTooLarge`（#611 R1 verify 第 5 列）。
    /// 10 筆最多 45 對。live store 的 16 個共用組全部恰好 2 筆（2026-10-01 實測），門檻離現實資料很遠、只擋批次貼入與書／資料集的概念 DOI。
    public static let maxGroupSize = 10

    /// 這一趟新建的那一筆。
    public var created: String
    /// 與它共用 DOI 的另一筆（既有的，或同一趟也新建的）。
    public var other: String
    /// 兩筆共用的 DOI（`DOI.normalized`，排序）。
    public var dois: [String]
    public var status: Status
    /// `recorded`／`alreadyRecorded`：那筆歧異記錄的 id；其餘為 nil。
    public var divergenceID: UUID?
    /// `failed` 的原因（**已消毒**——`displaySafeError` 產出；輸出端只截）。
    public var error: String?
    /// `groupTooLarge`：共用那個 DOI 的 work 數；其餘為 nil。
    public var groupSize: Int?

    public init(created: String, other: String, dois: [String], status: Status,
                divergenceID: UUID? = nil, error: String? = nil, groupSize: Int? = nil) {
        self.created = created
        self.other = other
        self.dois = dois
        self.status = status
        self.divergenceID = divergenceID
        self.error = error
        self.groupSize = groupSize
    }
}

extension ImportReport {
    /// **沒有記下來**的提名（`unlocatable`／`failed`／`groupTooLarge`）（#611 R1 verify 第 9 列）。提名只在新建時觸發，重新匯入不會再提名，
    /// 所以這幾對只能人工補記——CLI 為此以非零結束、MCP payload 帶 `doiNominationsUnrecorded`。
    public var unrecordedDOINominations: [DOINomination] { doiNominations.filter { !$0.status.isInStore } }
}

/// `ZoteroImporter` 在一趟匯入的所有寫入完成之後呼叫（#611）。
enum DOITwinNomination {
    /// 寫進歧異記錄的那句話。**不寫 citekey**：合併與改名會改寫候選的 key，question 不跟著改，寫進去的 citekey 會過期；兩筆是誰由 candidates 說。
    /// DOI 是 `DOI.normalized`（形狀已驗、不含不可見字元）。
    static func question(dois: [String]) -> String {
        "Zotero 匯入新建的一筆 work 與另一筆 work 共用 DOI \(dois.joined(separator: "、"))：兩筆是同一篇作品嗎？"   // display-safe-exempt: dois：DOI.normalized，形狀已驗、不含不可見字元
            + "DOI 相等只是提名——勘誤與原文共用 DOI，一筆作品也可以有多個 DOI；判定與合併走 resolve-divergence。"
    }

    /// - Parameters:
    ///   - load: 這一趟開頭的載入（既有的歧異記錄、其餘形狀，以及 `unlocatableCitekeys` 的三類）。
    ///   - current: 這一趟寫完之後的 work（id → entry）：載入快照加上每一次成功的寫入。
    ///   - createdIDs: 這一趟新建且寫入成功的 work。
    ///   - legacyCopyCitekeys: 這一趟寫入後留下 legacy 拷貝的 work（#705）——兩份並存，同樣無法唯一定位。
    /// - Returns: 依 (created, other) 排序的列；`groupTooLarge` 的列（每個 DOI 一列）依 DOI 排在其後。
    static func nominate(store: LibraryStore, load: LibraryLoad, current: [UUID: Entry],
                         createdIDs: [UUID], legacyCopyCitekeys: Set<String>) -> [DOINomination] {
        let created = createdIDs.compactMap { current[$0] }
        guard created.contains(where: { !$0.canonicalDOIs.isEmpty }) else { return [] }
        // 寫完之後的全部 work。以載入的清單為底（**不以 `current` 的值為底**：`current` 以 id 為鍵，共用 id 的兩筆在那裡只剩一筆，
        // 而那兩筆正是要報成無法定位的），同一筆這一趟改寫過的換成改寫後的版本（DOI 可能被 pull 改了），再加上新建的。
        var finalEntries: [Entry] = load.entries.map { e in
            if let now = current[e.id], now.citekey == e.citekey { return now }
            return e
        }
        finalEntries += created
        var byDOI: [String: [Entry]] = [:]
        for e in finalEntries {
            for d in Set(e.canonicalDOIs.map(\.normalized)) { byDOI[d, default: []].append(e) }
        }
        let unlocatable = load.entries.unlocatableCitekeys.union(legacyCopyCitekeys)
        let createdIDSet = Set(created.map(\.id))

        // 群組過大的 DOI：一對都不記（見 `Status.groupTooLarge`）。只看含這一趟新建的組——沒有新建的組不觸發提名。
        var rows: [DOINomination] = []
        var tooLarge = Set<String>()
        for (doi, members) in byDOI.sorted(by: { $0.key < $1.key })
        where members.count > DOINomination.maxGroupSize && members.contains(where: { createdIDSet.contains($0.id) }) {
            tooLarge.insert(doi)
            let firstCreated = members.filter { createdIDSet.contains($0.id) }.map(\.citekey).min() ?? ""
            rows.append(DOINomination(created: firstCreated, other: "", dois: [doi], status: .groupTooLarge,
                                      groupSize: members.count))
        }

        // 記錄路徑要的兩樣東西都**只建一次**（#611 R1 verify 第 5 列）：候選存在的 key 集合（這一趟寫完之後的 work），
        // 與涵蓋判斷用的索引（載入的歧異記錄，隨寫隨加——同一趟稍後的一對要看得到前面寫的）。
        var snapshot = load
        snapshot.entries = finalEntries
        let pool = DivergenceCandidatePool(snapshot)
        var covered = WorkDivergenceIndex(load.divergences)
        var seenPairs = Set<[String]>()
        var pairRows: [DOINomination] = []
        for n in created.sorted(by: { $0.citekey < $1.citekey }) {
            var shared: [String: Set<String>] = [:]   // 另一筆的 citekey → 共用的 DOI
            for d in Set(n.canonicalDOIs.map(\.normalized)) where !tooLarge.contains(d) {
                for o in byDOI[d] ?? [] where o.id != n.id && o.citekey != n.citekey {
                    shared[o.citekey, default: []].insert(d)
                }
            }
            for (other, dois) in shared.sorted(by: { $0.key < $1.key }) {
                let pair = [n.citekey, other].sorted()
                guard seenPairs.insert(pair).inserted else { continue }   // 同一趟兩筆新建的：只從一邊記一次
                var row = DOINomination(created: n.citekey, other: other, dois: dois.sorted(), status: .recorded)
                if unlocatable.contains(other) || unlocatable.contains(n.citekey) {
                    row.status = .unlocatable
                } else if let covering = covered.covering(pair) {
                    row.status = .alreadyRecorded
                    row.divergenceID = covering.id
                } else {
                    do {
                        let d = try store.recordDivergence(question: question(dois: row.dois),
                                                           candidates: pair.map { (key: $0, shape: EntityKind.work) },
                                                           judgement: nil, restsOn: [], against: pool)
                        covered.add(d)
                        row.divergenceID = d.id
                    } catch {
                        // 寫入被拒時再讀一次磁碟：這一趟進行期間別的程序可能已經記下了這一對（甚至帶著判斷）。那一筆**已經在 store 裡**，
                        // 記錄路徑對「無判斷的重錄」的拒絕（不得抹掉判斷）對匯入沒有意義——匯入不是要重錄它，是要確認它在。
                        // 報成 failed 會讓 CLI 以 1 結束、摘要叫人手記一筆已經存在的記錄（#611 R2 verify 第 36 列）。
                        if let now = store.divergenceOnDisk(id: DeterministicUUID.forDivergence(candidateKeys: pair)),
                           WorkDivergenceIndex.covers(now, pair) {
                            covered.add(now)
                            row.status = .alreadyRecorded
                            row.divergenceID = now.id
                        } else {
                            row.status = .failed
                            row.error = displaySafeError(error, max: 4_096)
                        }
                    }
                }
                pairRows.append(row)
            }
        }
        return pairRows + rows
    }
}

/// 涵蓋判斷用的索引：這一趟開頭載入的歧異記錄，加上這一趟寫的（#611 R1 verify 第 1／5／21 列）。
///
/// 先前每一對都掃一遍全部既有歧異記錄、並為每一筆建一個 `Set`——成本是 O(D) 次配置再乘以對數（DA 實測 k=40 的一個 DOI：1.36 秒、
/// k=80：10.2 秒，每翻倍約 ×7.5）。現在依「work 形狀記錄的候選 key」建索引，一對的查詢只看含其中一個 key 的那幾筆。
///
/// **只有 work 形狀的記錄算涵蓋**——包括同一個 id 的那一筆：歧異記錄的 id 只雜湊候選 key、不含形狀，所以 person 的 `{a, b}` 與
/// work 的 `{a, b}` 同 id。先前「同一組」那個分支只比 id、不看形狀，把別種形狀的記錄當成已涵蓋這一對 work，提名就靜默消失了。
/// 那個 id 被別種形狀占用時，這一對不算已涵蓋；接著寫的時候記錄路徑會拒絕（不覆寫原記錄，`divergenceIdHeldByOtherCandidates`），
/// 報成 `failed`。
struct WorkDivergenceIndex {
    private var byID: [UUID: Divergence] = [:]
    private var workByKey: [String: [Divergence]] = [:]

    init(_ divergences: [Divergence]) {
        for d in divergences { add(d) }
    }

    mutating func add(_ d: Divergence) {
        if byID[d.id] == nil { byID[d.id] = d }
        guard d.candidates.allSatisfy({ $0.shape == .work }) else { return }
        for k in Set(d.candidates.map(\.key)) { workByKey[k, default: []].append(d) }
    }

    /// 候選同時含這一對的 **work 形狀**歧異記錄：先找同一組（決定性 id 相同，且是 work 形狀），再找更大的一組（依 id 排序取第一筆，
    /// 結果不隨載入順序變）。更小的一組不存在——一對已是最小的候選組。
    func covering(_ pair: [String]) -> Divergence? {
        if let d = byID[DeterministicUUID.forDivergence(candidateKeys: pair)], Self.covers(d, pair) { return d }
        guard let first = pair.first else { return nil }
        return (workByKey[first] ?? []).filter { Self.covers($0, pair) }.min { $0.id.uuidString < $1.id.uuidString }
    }

    /// 這筆記錄是不是涵蓋這一對的 **work 形狀**記錄：**每一個**候選都是 work，且候選 key 含這一對。
    /// （先前只看 `d.shape`＝第一個候選的形狀；歧異記錄允許混合形狀，第一個是 work、後面混著 person 的記錄在 key 恰好相同時會被當成涵蓋——
    /// #611 R2 verify 第 46 列。）
    static func covers(_ d: Divergence, _ pair: [String]) -> Bool {
        d.candidates.allSatisfy { $0.shape == .work } && Set(d.candidates.map(\.key)).isSuperset(of: Set(pair))
    }
}
