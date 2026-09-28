import Foundation

/// per-record 上限的兩種模式（#581）。
///
/// 組合式的六族——venue 名字內容、venue 的 names／authorized／variant 近重複、person 近重複、同一 venue 多條 key 邊、
/// 同一 work 多個 confirmed literal、重複的判定記錄——在**產生訊息**那一步每筆記錄至多列 `Entry.perRecordWarningCap` 則、
/// 其餘一句 `Entry.perRecordCapSummaryPrefix` 概括。那是讀取路徑對未信任 store 內容的界限：`validate`／`akashic_doctor`／App
/// 對整份 store 跑，而一筆記錄的組合數（配對、組）可以遠超它的資料項數。
///
/// `.full` 是**單筆記錄的完整明細**（CLI `validate --owner`、MCP `akashic_doctor` 的 `owner`）：對**一筆**放寬列出上限不重開那個洞
/// ——呼叫端已經指名要那一筆，輸出的上界是那一筆自己的組合數，不是整份 store 的總和。被截的明細在這之前沒有任何出口，只能讀 YAML
/// （#581；`replace-endnote-and-zotero` 第 4 條：能力缺口不得靠 workaround 帶過）。
///
/// **不放寬的三樣**（寫在這裡，不讓「完整明細」被讀成「沒有任何上限」）：
/// 1. **求值上限**——venue 名字近重複與 person 近重複的組內 5,000 對、整筆 100,000 對。那是 CPU 的界限不是列出的界限，
///    觸頂時的那句概括仍會出現、並說出幾組沒評估。
/// 2. **訊息內部的列舉上限**——近重複一組列 3 對、confirmed literal 一則列 5 個拼法、`IndexList` 列 10 個索引。它們描述的是
///    同一則訊息，不是被截掉的訊息；每一則都說出了總數。
/// 3. **面的呈現上限**——MCP 面仍受位元組預算約束（輸出進 LLM context），以 `total`／`truncated` 揭露。
public enum PerRecordListing: Equatable, Sendable {
    /// 預設：每筆記錄每族至多 `Entry.perRecordWarningCap` 則，其餘一句概括。
    case capped
    /// 單筆記錄的完整明細：不套每筆的列出上限。
    case full

    /// 每筆記錄每族最多列幾則。`.full` 沒有列出上限。
    public var cap: Int {
        switch self {
        case .capped: return Entry.perRecordWarningCap
        case .full: return Int.max
        }
    }

    /// 概括句裡說明列出上限的那一段。`.full` 下仍會出現的概括句只剩求值上限那幾類，這一段要說「沒有列出上限」
    /// ——照抄「每筆記錄最多列 20 組」在完整明細裡是一句假話。
    public func listingClause(unit: String) -> String {
        switch self {
        case .capped: return "每筆記錄最多列 \(Entry.perRecordWarningCap) \(unit)"   // display-safe-exempt: Entry.perRecordWarningCap 是 Int 常量；unit 是呼叫端字面量
        case .full: return "單筆完整明細不套每筆 \(Entry.perRecordWarningCap) \(unit)的列出上限"   // display-safe-exempt: Entry.perRecordWarningCap 是 Int 常量；unit 是呼叫端字面量
        }
    }
}
