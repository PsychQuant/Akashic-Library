import Foundation
import AkashicCore
import AkashicStoreIO

/// App 側欄「記錄」區塊的純模型摘要（#487）。
///
/// `SidebarView` 的「健康」Section 閘在 `hasFindings`，而它依 #416 只計 per-record 的 **error**——warning 一族是
/// 編目品質提示，不該讓一份健康的 store 常態亮燈。代價是三族 per-record warning（#464 死 verdict、#453 本機缺
/// 承重存檔、#499 venue verdict 預算）在 App 上完全看不到，而 CLI `validate` 逐行、MCP `doctor` 進 `recordIssues`
/// 都有。本型別是它們在 App 面的入口：**獨立的閘**（有任何 per-record 問題才出現）、不改 `hasFindings` 的語意。
///
/// 住在 View 之外（與 `RenameReportSummary` 同形）：`AkashicApp/` 的 UI 不在 SwiftPM 測試範圍，能測的部分要最大化；
/// View 只收這個值型別的窄輸入（`swiftui-specialist` 的 narrow-inputs 規則）。
struct RecordIssuesSummary: Equatable {
    /// per-record **訊息**總數（error ＋ warning；概括句也是一則）——有記錄被截時是問題數的下限（R19 verify requirements 第 5 列：這裡曾寫「問題總數」）。
    let total: Int
    /// 其中 error 級的——它們本來就讓 `hasFindings` 亮，這裡只是讓兩個區塊的數字對得起來。
    let errors: Int
    /// 具名家族的計數（各自有 `StoreHealth` 的單一前綴定義）。#450 加兩族：拆分後的孤兒 verdict、
    /// 拆分記錄各段全不在——CLI／MCP 有計數而 App 沒有，就是 #453 那條「一面有計數另一面沒有」的分岔。
    let deadVerdicts: Int
    /// #486 的矛盾 verdict——R20 才進 App（R19 verify DA 第 12 列：`StoreHealth.contradictoryVerdicts` 全樹零消費，doctor 與 App 兩面
    /// 都沒有這一族，而 rename 剛能製造它）。
    let contradictoryVerdicts: Int
    /// #554 D64 的重複判定記錄（R23）——同一記錄對同一配對 ≥2 筆同 field 的 verdict：rename 自 D62 起原樣帶到新鍵、下一次合併收成一筆。
    let duplicateVerdictRecords: Int
    let danglingSources: Int
    let venueVerdictBudget: Int
    let orphanedSplitVerdicts: Int
    let staleSplitRecords: Int
    let contradictedRemovalRecords: Int
    /// #554 配對唯一性的兩半（R11 D28 同一 venue 多條 key 邊、R14 D36 同一 work 多個 confirmed literal）——R15 補家族
    /// （R14 verify regression 第 22 列：三面計數不得分岔）。
    let duplicateVenueEdges: Int
    let confirmedLiteralAmbiguities: Int
    /// 被截的記錄數（R18 D54；以記錄計，R19 D56）——家族計數是下限（每筆記錄至多 20 則），這個數字說「還有」。
    let cappedRecords: Int
    /// `.help` 用：前幾則訊息（`displaySafe`，每則截斷），加一句指向 CLI validate——它不加這裡的預覽截斷，但受求值上限的六族
    /// 每筆記錄至多 20 則、三面共有（R24 D66；R25 D70：R24 寫成「每筆記錄每族」，對五族以外為假；R26 D72：R25 寫「五族」漏掉 person 近重複），
    /// 所以不寫「完整」。
    let help: String

    /// 計數的呈現（R19 D57、R20 D59；R18 verify Codex 第 3 列：`cappedRecords` 到得了這裡卻沒有任何 View 消費它，側欄的家族計數仍是裸數字）：
    /// 有**任何**記錄被截時，`total`／`errors`（訊息則數——被截掉的正是 error 級訊息，R19 verify logic 第 7 列、regression 第 3 列）與
    /// 每個家族的計數都是下限，前綴「≥」；沒有記錄被截時計數精確、照印。閘是全域的：一筆記錄被截就讓未受影響的家族也帶「≥」——
    /// 「≥ n」對精確值仍為真，方向保守，help 文案說「未必每一族都受影響」（R19 verify regression 第 6 列，不寫成因果）。
    func lowerBound(_ n: Int) -> String { cappedRecords > 0 ? "≥ \(n)" : "\(n)" }

    /// 全為零時回 nil——**沉默即健康**（側欄「較新欄位」0 時不顯示的既有慣例）。
    nonisolated init?(health: StoreHealth, previewLimit: Int = 5) {
        let issues = health.perRecordIssues
        guard !issues.isEmpty else { return nil }
        total = issues.count
        errors = issues.filter { $0.issue.severity == .error }.count
        deadVerdicts = health.deadVerdicts.count
        contradictoryVerdicts = health.contradictoryVerdicts.count
        duplicateVerdictRecords = health.duplicateVerdictRecords.count
        danglingSources = health.danglingSources.count
        venueVerdictBudget = health.venueVerdictBudgetWarnings.count
        orphanedSplitVerdicts = health.orphanedSplitVerdicts.count
        staleSplitRecords = health.staleSplitRecords.count
        contradictedRemovalRecords = health.contradictedRemovalRecords.count
        duplicateVenueEdges = health.duplicateVenueEdges.count
        confirmedLiteralAmbiguities = health.confirmedLiteralAmbiguities.count
        cappedRecords = health.cappedRecords.count
        let preview = issues.prefix(previewLimit).map {
            // 訊息在 validate 裡已逐項消毒；只截不逃（R16；R15 verify 第 16 列：`displaySafe` 不冪等，160 把家族前綴之後的正文截光）
            "\($0.issue.severity == .error ? "✗" : "⚠") \($0.kind) \(displaySafe($0.owner, max: 80))：\(displaySafeClipOnly($0.issue.message, max: 300))"   // display-safe-exempt: 只截不逃（具名函式，R17），理由見上
        }
        let more = issues.count > previewLimit ? "\n…另 \(issues.count - previewLimit) 則" : ""
        help = preview.joined(separator: "\n") + more
             + "\n逐則列出：akashic validate（不加這裡的預覽截斷；組合式的六族——venue 名字內容、venue 近重複、person 近重複、重複 venue 邊、"
             + "confirmed literal、重複判定記錄——每筆記錄至多 \(Entry.perRecordWarningCap) 則、以「\(Entry.perRecordCapSummaryPrefix)」概括；"
             + "其餘家族每筆 reference／配對／記錄各一則、無上限；三面同）"
    }
}
