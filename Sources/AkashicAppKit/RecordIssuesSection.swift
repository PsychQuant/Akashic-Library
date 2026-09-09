import SwiftUI
import AkashicStoreIO

/// 側欄「記錄」Section（#487）：per-record warning 的計數與三個具名家族——死 verdict（#464）、本機缺承重存檔（#453）、
/// venue verdict 預算（#499）。**獨立的閘**：由呼叫端以 `RecordIssuesSummary?` 決定出不出現，不掛在「健康」Section 的
/// `hasFindings` 下（那個布林依 #416 只計 error，故意不讓 warning 亮燈）。
///
/// 窄輸入：只收 `RecordIssuesSummary`（值型別、五個整數一個字串），`AppState` 的其他變化不會讓本 view 失效
/// （`swiftui-specialist`：pass views only the data they read）。完整逐行仍是 CLI `validate` 的職責。
struct RecordIssuesSection: View {
    let summary: RecordIssuesSummary

    var body: some View {
        Section("記錄") {
            LabeledContent("記錄層問題", value: "\(summary.total)")
                .help(summary.help)
            if summary.errors > 0 {
                LabeledContent("其中 error", value: "\(summary.errors)")
                    .help("error 級的 per-record 問題也算進上方「健康」的 hasFindings；warning 不算。")
            }
            if summary.deadVerdicts > 0 {
                LabeledContent("死 verdict", value: "\(summary.deadVerdicts)")
                    .help("resolution verdict 指向一個沒有載入的 holder（#464）。先看 quarantine 清單；"
                          + "其餘指向一條漏了遷移的退役路徑——在持有記錄的 references 更新或刪掉那筆 verdict。")
            }
            if summary.danglingSources > 0 {
                LabeledContent("本機缺承重存檔", value: "\(summary.danglingSources)")
                    .help("provenance 指向的 digest 本機 sources/ 沒有（#453）。sources/ 不進 git，"
                          + "其他 clone 上的數字會不同；從持有它的機器同步 sources/。")
            }
            if summary.venueVerdictBudget > 0 {
                LabeledContent("venue verdict 逼近預算", value: "\(summary.venueVerdictBudget)")
                    .help("這本刊的 resolution verdict 數達 decode 硬預算的一半（#499）。"
                          + "處置是重開第 13 條邊的規模化裁決，不要只放寬預算。")
            }
            if summary.orphanedSplitVerdicts > 0 {
                LabeledContent("拆分後的孤兒 verdict", value: "\(summary.orphanedSplitVerdicts)")
                    .help("verdict 判的 literal 已被那筆 work 的拆分記錄退役（#450）。"
                          + "對拆出的各段重新消歧，然後在持有記錄的 references 更新或刪掉這筆 verdict。")
            }
            if summary.contradictedRemovalRecords > 0 {
                LabeledContent("移除記錄與作者位矛盾", value: "\(summary.contradictedRemovalRecords)")
            }
            if summary.staleSplitRecords > 0 {
                LabeledContent("拆分記錄各段都不在", value: "\(summary.staleSplitRecords)")
                    .help("一筆拆分記錄的各段沒有任何一段仍是作者位（#450）。"
                          + "確認作者位是否被改寫；記錄保留供 un-split（#513），不要刪。")
            }
        }
    }
}
