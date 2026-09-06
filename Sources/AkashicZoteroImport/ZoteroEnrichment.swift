import Foundation
import AkashicCore

/// 逐筆、**只補不存在的鍵**的 Zotero 補值（#340）——**`AddOnlyEnrichment` 的 adapter**（#458）。
///
/// ## 為什麼不用既有的 `import-zotero`
///
/// `ZoteroImporter` 是 **pull**：Zotero 是上游，`applyBiblatexFields` **整份替換**
/// `fields`、重設 `type`、覆寫未歸戶的 literal 作者。那個語意對「同步一個由 Zotero
/// 維護的書目」是對的（`lossless-intake` 記載了兩個 importer 方向相反是刻意的），
/// 但用來修跌破下限的記錄時，它的作用半徑是**整個 store**、而且會蓋掉人工補過的值。
///
/// ## 政策只有一份，在 `AddOnlyEnrichment`
///
/// 本型別只做三步：找 item → 以既有對映（`ZoteroMapping.mappedFields`／`normalizedDate`）
/// 產 `Proposal` → 委派 core。欄位政策（只補不存在的鍵、`issn` 拒、識別碼三態、`date`
/// 空才補、作者旗標）**全部住在 core 的 doc 裡**，這裡刻意不複製一份會分岔的副本。
/// #458 之前政策寫在這個檔案裡；搬走後 `ZoteroEnrichmentTests`（本 change 當下 22 支）零改動即為等價的驗收。
///
/// ## 誠實邊界
///
/// 「Zotero 也沒有」與「補了」是兩個不同的結果，**必須分開回報**。折成同一個輸出
/// 會讓使用者無法分辨「查過了、上游真的沒有」與「根本沒查到這筆」——那正是
/// `lossless-intake` 執行細節 3 說的「靜默是最糟的形式」。
public enum ZoteroEnrichment {

    /// 一筆記錄的補值計畫——`AddOnlyEnrichment.Outcome` 加上 citekey 的 adapter 形。
    /// `addedFields` 與 `addedDate` 皆空的不會出現在這裡（那筆走 `unchanged`）。
    public struct Addition: Equatable {
        public let citekey: String
        /// biblatex 欄位名 → 值。只含**原本不存在**的鍵。
        public let addedFields: [String: String]
        /// 原本 `date` 為 nil／空、而 Zotero 有值時的補值（已過 `DateNormalizer`）。
        public let addedDate: String?
        /// 原本 `authors` **完全為空**、而 Zotero 有作者時的補值（一律 `.literal`，#340）。
        /// 空陣列＝沒有補（`authors` 非空，或呼叫端未開旗標）。
        public let addedAuthors: [Author]
        /// 補進**結構化**識別碼欄位的值（#394 verify）——不走 `addedFields`。
        public let addedDOIs: [DOI]
        public let addedPMIDs: [PMID]
        public let addedISBNs: [ISBN]
        /// Zotero 給了識別碼但**刻意不採用**的理由（citekey 級，逐條具名）。
        public let refusedIdentifiers: [String]
        /// **部分成功**：一部分 token 解得出並已採用，其餘形狀不認得（#394 verify R9）。
        /// 刻意**不**併進 `refusedIdentifiers`——那個欄位的契約是「刻意不採用」。
        public let partiallyParsedIdentifiers: [String]

        public init(citekey: String, addedFields: [String: String], addedDate: String?,
                    addedAuthors: [Author] = [],
                    addedDOIs: [DOI] = [], addedPMIDs: [PMID] = [], addedISBNs: [ISBN] = [],
                    refusedIdentifiers: [String] = [],
                    partiallyParsedIdentifiers: [String] = []) {
            self.citekey = citekey
            self.addedFields = addedFields
            self.addedDate = addedDate
            self.addedAuthors = addedAuthors
            self.addedDOIs = addedDOIs
            self.addedPMIDs = addedPMIDs
            self.addedISBNs = addedISBNs
            self.refusedIdentifiers = refusedIdentifiers
            self.partiallyParsedIdentifiers = partiallyParsedIdentifiers
        }

        fileprivate init(citekey: String, outcome o: AddOnlyEnrichment.Outcome) {
            self.init(citekey: citekey, addedFields: o.addedFields, addedDate: o.addedDate,
                      addedAuthors: o.addedAuthors,
                      addedDOIs: o.addedDOIs, addedPMIDs: o.addedPMIDs, addedISBNs: o.addedISBNs,
                      refusedIdentifiers: o.refused, partiallyParsedIdentifiers: o.partial)
        }

        fileprivate var outcome: AddOnlyEnrichment.Outcome {
            AddOnlyEnrichment.Outcome(addedFields: addedFields, addedDate: addedDate,
                                      addedAuthors: addedAuthors,
                                      addedDOIs: addedDOIs, addedPMIDs: addedPMIDs, addedISBNs: addedISBNs,
                                      refused: refusedIdentifiers, partial: partiallyParsedIdentifiers)
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
        /// **只有被拒絕的識別碼、沒有任何可補值**的 citekey（#394 verify）。
        /// 與 `unchanged` 分開：那一類是「Zotero 給不出缺著的欄位」，這一類是
        /// 「Zotero 給了，而我們**刻意不收**」——兩者在輸出上不可混為一談。
        public var refusedOnly: [Addition] = []

        public init() {}

        /// 落在每一類的 citekey 總數。用於後置條件斷言。
        public var accountedCitekeys: [String] {
            additions.map(\.citekey) + refusedOnly.map(\.citekey)
                + unchanged + noProvenance + zoteroMissing + notInStore
        }
    }

    /// 算出補值計畫。**純函式、不寫檔**——套用由呼叫端做，dry-run 與 apply 因此
    /// 讀的是同一份計畫（`entity-backlink-completeness` 執行細節 2 的同一條實作路徑）。
    public static func plan(entries: [Entry],
                            items: [ZoteroItem],
                            citekeys: [String],
                            includeAbsentAuthors: Bool = false) -> Result {
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
        var proposals: [AddOnlyEnrichment.Proposal] = []
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
            // **對映邏輯只有一份**：借 pull 的對映算出 Zotero 這筆會產生什麼，交給 core
            // 從中只取缺著的鍵。自己重寫一份對映＝兩份會分岔的規格。
            let fields = ZoteroMapping.mappedFields(from: item)
            let date = ZoteroMapping.normalizedDate(from: item)
            let authors = item.authors.map(\.display)
            // core 對「什麼都沒提」的提案整批拒絕（那是呼叫端的語法錯）；Zotero item 若真的
            // 一個欄位都沒給，這筆的意思是「上游也沒有」，直接歸 `unchanged`。
            let offersAnything = !fields.isEmpty || !(date ?? "").isEmpty
                || authors.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard offersAnything else { result.unchanged.append(citekey); continue }
            proposals.append(.init(citekey: citekey, fields: fields, date: date, authors: authors))
        }

        guard !proposals.isEmpty else { return result }
        let core: AddOnlyEnrichment.Result
        do {
            core = try AddOnlyEnrichment.plan(entries: entries, proposals: proposals,
                                              includeAbsentAuthors: includeAbsentAuthors)
        } catch {
            // 結構上不可達：每筆提案恰有 citekey、鍵來自 `mappedFields`（已正規化且無撞鍵）、
            // 空提案在上面就歸了 `unchanged`。若真的擲出，寧可大聲失敗也不把一批 citekey 歸錯類。
            preconditionFailure("ZoteroEnrichment 產出的提案被 AddOnlyEnrichment 拒絕：\(error)")
        }
        for item in core.items {
            let ck = proposals[item.proposalIndex].citekey!
            let o = item.outcome
            switch item.category {
            case .added:
                result.additions.append(Addition(citekey: ck, outcome: o))
            case .skipped where o.partial.isEmpty:
                result.unchanged.append(ck)
            case .skipped, .rejected:
                // 只有被拒的識別碼、或只有部分成功而沒有任何可補值——與 `unchanged` 分開，
                // 那一類的語意是「Zotero 給不出缺著的欄位」，對這兩種為假。
                result.refusedOnly.append(Addition(citekey: ck, addedFields: [:], addedDate: nil,
                                                   refusedIdentifiers: o.refused,
                                                   partiallyParsedIdentifiers: o.partial))
            case .ambiguous, .notFound:
                // citekey 定位不會 ambiguous；notFound 在上面的 `byCitekey` 已先擋掉。
                preconditionFailure("citekey 定位的提案不該落在 \(item.category)：\(ck)")
            }
        }
        return result
    }

    /// 把一筆補值套進 entry，回傳**新的** entry（不 mutate 傳入者）——委派 core 的
    /// `applied`，保守側紀律（既有值一律不動）在那裡。
    public static func applied(_ addition: Addition, to entry: Entry) -> Entry {
        AddOnlyEnrichment.applied(addition.outcome, to: entry)
    }
}
