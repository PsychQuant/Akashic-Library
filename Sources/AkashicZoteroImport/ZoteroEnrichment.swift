import Foundation
import AkashicCore

/// 逐筆、**只補不存在的鍵**的 Zotero 補值（#340）。
///
/// ## 為什麼不用既有的 `import-zotero`
///
/// `ZoteroImporter` 是 **pull**：Zotero 是上游，`applyBiblatexFields` **整份替換**
/// `fields`、重設 `type`、覆寫未歸戶的 literal 作者。那個語意對「同步一個由 Zotero
/// 維護的書目」是對的（`lossless-intake` 記載了兩個 importer 方向相反是刻意的），
/// 但用來修 90 筆跌破下限的記錄時，它的作用半徑是**整個 store**、而且會蓋掉人工補過
/// 的值。
///
/// 本型別走另一條紀律，與 `import-wos` 的 `enriched` 同形：
///
/// - **只加原本不存在的鍵**。既有值一個都不動——人工修改過的值不得被洗掉。
/// - **不動 `type` / `title` / `authors` / `venues` / `attachments`**。它們各自有
///   自己的裁決路徑（`resolve-people`／`resolve-venues`／#325 的遷移），補值不越界。
/// - **作用半徑由呼叫端逐筆指名**。沒有篩選式批次掃蕩，所以 #298 那個「破壞性
///   `--apply` 未指名目標」的風險形狀在這裡不存在。
///
/// ## 誠實邊界
///
/// 「Zotero 也沒有」與「補了」是兩個不同的結果，**必須分開回報**。折成同一個輸出
/// 會讓使用者無法分辨「查過了、上游真的沒有」與「根本沒查到這筆」——那正是
/// `lossless-intake` 執行細節 3 說的「靜默是最糟的形式」。
public enum ZoteroEnrichment {

    /// 一筆記錄的補值計畫。`addedFields` 與 `addedDate` 皆空的不會出現在這裡
    /// （那筆走 `unchanged`）。
    public struct Addition: Equatable {
        public let citekey: String
        /// biblatex 欄位名 → 值。只含**原本不存在**的鍵。
        public let addedFields: [String: String]
        /// 原本 `date` 為 nil／空、而 Zotero 有值時的補值（已過 `DateNormalizer`）。
        public let addedDate: String?

        public init(citekey: String, addedFields: [String: String], addedDate: String?) {
            self.citekey = citekey
            self.addedFields = addedFields
            self.addedDate = addedDate
        }
    }

    /// 逐筆結果的封閉分類。**每一筆指名的 citekey 必落在恰好一類**——
    /// `plan` 的後置條件由 `ZoteroEnrichmentTests` 機械檢查，不靠作者記得。
    public struct Result: Equatable {
        /// 有東西可補的。
        public var additions: [Addition] = []
        /// 找到了 Zotero item，但它給不出任何**缺著的**欄位。
        public var unchanged: [String] = []
        /// store 記錄沒有 `provenance.zotero_key`——無從查起。
        public var noProvenance: [String] = []
        /// 有 `zotero_key` 但 Zotero 端查無此 item（已刪或不在這個 library）。
        public var zoteroMissing: [String] = []
        /// 指名的 citekey 不在 store 裡。
        public var notInStore: [String] = []

        public init() {}

        /// 落在每一類的 citekey 總數。用於後置條件斷言。
        public var accountedCitekeys: [String] {
            additions.map(\.citekey) + unchanged + noProvenance + zoteroMissing + notInStore
        }
    }

    /// 算出補值計畫。**純函式、不寫檔**——套用由呼叫端做，dry-run 與 apply 因此
    /// 讀的是同一份計畫（`entity-backlink-completeness` 執行細節 2 的同一條實作路徑）。
    public static func plan(entries: [Entry],
                            items: [ZoteroItem],
                            citekeys: [String]) -> Result {
        var byCitekey: [String: Entry] = [:]
        for e in entries { byCitekey[e.citekey] = e }

        // 身分＝(libraryID, key) 複合鍵，與 `ZoteroImporter` 同（#3）；legacy 記錄
        // 缺 library_id 時退回裸 key。
        var byComposite: [String: ZoteroItem] = [:]
        var byBareKey: [String: ZoteroItem] = [:]
        for item in items {
            byComposite["\(item.libraryID):\(item.key)"] = item
            byBareKey[item.key] = item
        }

        var result = Result()
        for citekey in citekeys {
            guard let entry = byCitekey[citekey] else {
                result.notInStore.append(citekey); continue
            }
            guard let prov = entry.provenance, !prov.zoteroKey.isEmpty else {
                result.noProvenance.append(citekey); continue
            }
            let item: ZoteroItem?
            if let lid = prov.libraryID {
                item = byComposite["\(lid):\(prov.zoteroKey)"] ?? byBareKey[prov.zoteroKey]
            } else {
                item = byBareKey[prov.zoteroKey]
            }
            guard let item else {
                result.zoteroMissing.append(citekey); continue
            }

            // **對映邏輯只有一份**：借 `applyBiblatexFields` 算出 Zotero 這筆
            // 會產生什麼，再從中只取缺著的鍵。自己重寫一份對映＝兩份會分岔的規格。
            var probe = Entry(id: UUID(), citekey: "probe", type: .webpage, title: "")
            ZoteroMapping.applyBiblatexFields(from: item, to: &probe)

            var added: [String: String] = [:]
            for (k, v) in probe.fields where !v.isEmpty {
                if entry.fields[k] == nil { added[k] = v }
            }
            var addedDate: String?
            if (entry.date ?? "").isEmpty, let d = probe.date, !d.isEmpty {
                addedDate = d
            }

            if added.isEmpty && addedDate == nil {
                result.unchanged.append(citekey)
            } else {
                result.additions.append(
                    Addition(citekey: citekey, addedFields: added, addedDate: addedDate))
            }
        }
        return result
    }

    /// 把一筆補值套進 entry，回傳**新的** entry（不 mutate 傳入者）。
    ///
    /// 只碰 `fields` 的缺鍵與空的 `date`。斷言式防呆：若 `addition` 含一個
    /// entry 已經有值的鍵，這裡**跳過它**而不是覆寫——計畫與套用之間若有落差
    /// （例如 plan 之後 store 被改過），保守側是不動既有值。
    public static func applied(_ addition: Addition, to entry: Entry) -> Entry {
        var out = entry
        for (k, v) in addition.addedFields where out.fields[k] == nil {
            out.fields[k] = v
        }
        if (out.date ?? "").isEmpty, let d = addition.addedDate { out.date = d }
        return out
    }
}
