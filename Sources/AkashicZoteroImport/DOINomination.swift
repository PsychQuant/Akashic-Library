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
    /// 封閉四值。
    public enum Status: String, Equatable {
        /// 這一趟寫下一筆新的歧異記錄。
        case recorded
        /// 已有一筆 work 歧異記錄的候選同時含這兩筆（同一組，或更大的一組）——不重寫：重寫會換掉 question，
        /// 而那筆記錄可能已經帶著人補上的判斷（`recordDivergence` 對「無判斷的重錄」本來就拒絕）。
        case alreadyRecorded
        /// 其中一筆無法唯一定位（`unlocatableCitekeys`：citekey 重複、與另一筆共用 id、檔案寫入時會被拒，
        /// 或這一趟寫入之後留下兩份）——不點名它：歧異記錄以 citekey 指涉候選，指不到唯一一筆的 key 會讓合併猜。
        case unlocatable
        /// 寫入被拒或擲錯（legacy 佈局、store format < 5、候選 key 不合 `StoreKey` 等）；原因在 `error`。
        case failed
    }

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

    public init(created: String, other: String, dois: [String], status: Status,
                divergenceID: UUID? = nil, error: String? = nil) {
        self.created = created
        self.other = other
        self.dois = dois
        self.status = status
        self.divergenceID = divergenceID
        self.error = error
    }
}

/// `ZoteroImporter` 在一趟匯入的所有寫入完成之後呼叫（#611）。
enum DOITwinNomination {
    /// 寫進歧異記錄的那句話。**不寫 citekey**：合併與改名會改寫候選的 key（`resolveDivergence` 遷移其他歧異記錄的候選），
    /// question 不跟著改，寫進去的 citekey 會過期；兩筆是誰由 candidates 說。DOI 是 `DOI.normalized`（形狀已驗、不含不可見字元）。
    static func question(dois: [String]) -> String {
        "Zotero 匯入新建的一筆 work 與另一筆 work 共用 DOI \(dois.joined(separator: "、"))：兩筆是同一篇作品嗎？"   // display-safe-exempt: dois：DOI.normalized，形狀已驗、不含不可見字元
            + "DOI 相等只是提名——勘誤與原文共用 DOI，一筆作品也可以有多個 DOI；判定與合併走 resolve-divergence。"
    }

    /// - Parameters:
    ///   - load: 這一趟開頭的載入（既有的歧異記錄、其餘形狀，以及 `unlocatableCitekeys` 的三類）。
    ///   - current: 這一趟寫完之後的 work（id → entry）：載入快照加上每一次成功的寫入。
    ///   - createdIDs: 這一趟新建且寫入成功的 work。
    ///   - legacyCopyCitekeys: 這一趟寫入後留下 legacy 拷貝的 work（#705）——兩份並存，同樣無法唯一定位。
    /// - Returns: 依 (created, other) 排序的列。
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
        // 記錄路徑讀的 store 現況：寫完之後的 work，歧異記錄隨寫隨加（同一趟稍後的一對要看得到前面寫的）。
        var snapshot = load
        snapshot.entries = finalEntries
        var seenPairs = Set<[String]>()
        var rows: [DOINomination] = []
        for n in created.sorted(by: { $0.citekey < $1.citekey }) {
            var shared: [String: Set<String>] = [:]   // 另一筆的 citekey → 共用的 DOI
            for d in Set(n.canonicalDOIs.map(\.normalized)) {
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
                } else if let covering = coveringRecord(pair, in: snapshot.divergences) {
                    row.status = .alreadyRecorded
                    row.divergenceID = covering.id
                } else {
                    do {
                        let d = try store.recordDivergence(question: question(dois: row.dois),
                                                           candidates: pair.map { (key: $0, shape: EntityKind.work) },
                                                           judgement: nil, restsOn: [], against: snapshot)
                        snapshot.divergences.append(d)
                        row.divergenceID = d.id
                    } catch {
                        row.status = .failed
                        row.error = displaySafeError(error, max: 4_096)
                    }
                }
                rows.append(row)
            }
        }
        return rows
    }

    /// 候選同時含這一對的 work 歧異記錄：先找同一組（決定性 id 相同），再找更大的一組（依 id 排序取第一筆，結果不隨載入順序變）。
    /// 更小的一組不存在——一對已是最小的候選組。
    static func coveringRecord(_ pair: [String], in divergences: [Divergence]) -> Divergence? {
        let exact = DeterministicUUID.forDivergence(candidateKeys: pair)
        if let d = divergences.first(where: { $0.id == exact }) { return d }
        let wanted = Set(pair)
        return divergences
            .filter { $0.shape == .work && Set($0.candidates.map(\.key)).isSuperset(of: wanted) }
            .min { $0.id.uuidString < $1.id.uuidString }
    }
}
