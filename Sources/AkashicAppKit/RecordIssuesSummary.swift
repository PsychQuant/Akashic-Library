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
    /// per-record 問題總數（error ＋ warning）。
    let total: Int
    /// 其中 error 級的——它們本來就讓 `hasFindings` 亮，這裡只是讓兩個區塊的數字對得起來。
    let errors: Int
    /// 具名家族的計數（各自有 `StoreHealth` 的單一前綴定義）。#450 加兩族：拆分後的孤兒 verdict、
    /// 拆分記錄各段全不在——CLI／MCP 有計數而 App 沒有，就是 #453 那條「一面有計數另一面沒有」的分岔。
    let deadVerdicts: Int
    let danglingSources: Int
    let venueVerdictBudget: Int
    let orphanedSplitVerdicts: Int
    let staleSplitRecords: Int
    let contradictedRemovalRecords: Int
    /// `.help` 用：前幾則訊息（`displaySafe`，每則截斷），加一句「完整逐行看 CLI validate」。
    let help: String

    /// 全為零時回 nil——**沉默即健康**（側欄「較新欄位」0 時不顯示的既有慣例）。
    nonisolated init?(health: StoreHealth, previewLimit: Int = 5) {
        let issues = health.perRecordIssues
        guard !issues.isEmpty else { return nil }
        total = issues.count
        errors = issues.filter { $0.issue.severity == .error }.count
        deadVerdicts = health.deadVerdicts.count
        danglingSources = health.danglingSources.count
        venueVerdictBudget = health.venueVerdictBudgetWarnings.count
        orphanedSplitVerdicts = health.orphanedSplitVerdicts.count
        staleSplitRecords = health.staleSplitRecords.count
        contradictedRemovalRecords = health.contradictedRemovalRecords.count
        let preview = issues.prefix(previewLimit).map {
            "\($0.issue.severity == .error ? "✗" : "⚠") \($0.kind) \(displaySafe($0.owner, max: 80))：\(displaySafe($0.issue.message, max: 160))"
        }
        let more = issues.count > previewLimit ? "\n…另 \(issues.count - previewLimit) 則" : ""
        help = preview.joined(separator: "\n") + more + "\n完整逐行：akashic validate"
    }
}
