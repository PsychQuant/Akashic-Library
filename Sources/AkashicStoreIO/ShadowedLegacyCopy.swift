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

extension LibraryLoad {
    /// load 標出的 legacy 拷貝（`fileSituation.shadowedLegacyFile`），依 (kind, key) 排序。index 重建略過的就是這些
    /// （`LibraryIndex.rebuild` 以同一個標記過濾，並把這份清單放進 `IndexStats.skippedLegacyCopies`）；
    /// validate 的 #641 警告也從這裡說出「index 以 entities/ 那份為準」。
    public var shadowedLegacyCopies: [ShadowedLegacyCopy] {
        let works = entries.compactMap { e in
            e.fileSituation.shadowedLegacyFile.map { ShadowedLegacyCopy(kind: .work, key: e.citekey, id: e.id, legacyFile: $0) }
        }
        let persons = people.compactMap { p in
            p.fileSituation.shadowedLegacyFile.map { ShadowedLegacyCopy(kind: .person, key: p.key, id: p.id, legacyFile: $0) }
        }
        return (works + persons).sorted { ($0.kind.rawValue, $0.key, $0.legacyFile) < ($1.kind.rawValue, $1.key, $1.legacyFile) }
    }
}

extension LibraryStore {
    /// 「同一筆記錄的 legacy 拷貝」的判準——**只有這一份**（#709）。index 重建、#645 的記錄位元組、validate 的 #641 警告都讀它標的結果。
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
