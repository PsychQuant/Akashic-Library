import SwiftUI
import AkashicStoreIO

/// 側欄「記錄」Section（#487）：per-record warning 的計數與具名家族——死 verdict（#464）、本機缺承重存檔（#453）、
/// venue verdict 預算（#499）……。**獨立的閘**：由呼叫端以 `RecordIssuesSummary?` 決定出不出現，不掛在「健康」Section 的
/// `hasFindings` 下（那個布林依 #416 只計 error，故意不讓 warning 亮燈）。
///
/// **每個計數的值都經 `summary.lowerBound`**（R19 D57、R20 D59；R18 verify Codex 第 3 列）：每筆記錄至多 20 則進來，有記錄被截時
/// `記錄層問題`／`其中 error`（訊息則數）與各家族的計數都是下限、前綴「≥」，並多一列「被截的記錄」說有幾筆——doctor 面自 R18 起說得出
/// 這件事，App 面到 R19 才說；`RecordIssuesSummaryTests` 以反射取名冊、以源碼掃描釘住每個計數都在 `value:` 的位置經過它。
///
/// 窄輸入：只收 `RecordIssuesSummary`（值型別、幾個整數一個字串——列數見 `RecordIssuesSummary`，這裡刻意不複述），`AppState` 的其他變化不會讓本 view 失效
/// （`swiftui-specialist`：pass views only the data they read）。完整逐行仍是 CLI `validate` 的職責。
struct RecordIssuesSection: View {
    let summary: RecordIssuesSummary

    var body: some View {
        Section("記錄") {
            LabeledContent("記錄層問題", value: summary.lowerBound(summary.total))
                .help(summary.help)
            if summary.errors > 0 {
                LabeledContent("其中 error", value: summary.lowerBound(summary.errors))
                    .help("error 級的 per-record 問題也算進上方「健康」的 hasFindings；warning 不算。")
            }
            if summary.contradictoryVerdicts > 0 {
                LabeledContent("矛盾 verdict", value: summary.lowerBound(summary.contradictoryVerdicts))
                    .help("同一 owner 對同一配對同時持有 confirmed 與 rejected（#486）。決定哪一個才對、刪掉另一個——"
                          + "目前沒有工具面，手改 YAML。")
            }
            if summary.deadVerdicts > 0 {
                LabeledContent("死 verdict", value: summary.lowerBound(summary.deadVerdicts))
                    .help("resolution verdict 指向一個沒有載入的 holder（#464）。先看 quarantine 清單；"
                          + "其餘指向一條漏了遷移的退役路徑——在持有記錄的 references 更新或刪掉那筆 verdict。")
            }
            if summary.danglingSources > 0 {
                LabeledContent("本機缺承重存檔", value: summary.lowerBound(summary.danglingSources))
                    .help("provenance 指向的 digest 本機 sources/ 沒有（#453）。sources/ 不進 git，"
                          + "其他 clone 上的數字會不同；從持有它的機器同步 sources/。")
            }
            if summary.venueVerdictBudget > 0 {
                LabeledContent("venue verdict 逼近預算", value: summary.lowerBound(summary.venueVerdictBudget))
                    .help("這本刊的 resolution verdict 數達 decode 硬預算的一半（#499）。"
                          + "處置是重開第 13 條邊的規模化裁決，不要只放寬預算。")
            }
            if summary.orphanedSplitVerdicts > 0 {
                LabeledContent("拆分後的孤兒 verdict", value: summary.lowerBound(summary.orphanedSplitVerdicts))
                    .help("verdict 判的 literal 已被那筆 work 的拆分記錄退役（#450）。"
                          + "對拆出的各段重新消歧，然後在持有記錄的 references 更新或刪掉這筆 verdict。")
            }
            if summary.contradictedRemovalRecords > 0 {
                LabeledContent("移除記錄與作者位矛盾", value: summary.lowerBound(summary.contradictedRemovalRecords))
            }
            if summary.duplicateVenueEdges > 0 {
                LabeledContent("同一 venue 多條 key 邊", value: summary.lowerBound(summary.duplicateVenueEdges))
                    .help("一筆 work 有兩條以上 key 邊指向同一 venue（#554 D28）。配對只能由一條邊實例化，"
                          + "resolve-venues 的 repoint／demote 對它會拒絕；在 YAML 裡刪掉多餘的邊（移除面：#572）。")
            }
            if summary.confirmedLiteralAmbiguities > 0 {
                LabeledContent("同一 work 多個 confirmed literal", value: summary.lowerBound(summary.confirmedLiteralAmbiguities))
                    .help("某本刊對同一筆 work 持有兩個以上 confirmed literal（#554 D36；正規化後不同、或只差位元組）。"
                          + "verdict 不帶 index，demote／repoint 對那筆 work 會被拒（D23）；在 venue 的 YAML 裡留一筆。")
            }
            if summary.staleSplitRecords > 0 {
                LabeledContent("拆分記錄各段都不在", value: summary.lowerBound(summary.staleSplitRecords))
                    .help("一筆拆分記錄的各段沒有任何一段仍是作者位（#450）。"
                          + "確認作者位是否被改寫；記錄保留供 un-split（#513），不要刪。")
            }
            if summary.cappedRecords > 0 {
                LabeledContent("被截的記錄", value: "\(summary.cappedRecords)")
                    .help("有 \(summary.cappedRecords) 筆記錄的 per-record 問題超過每筆 20 則的上限（#554 R18 D54）——"
                          + "上方的計數一律以下限呈現（≥；未必每一族都受影響）。完整逐行：akashic validate")
            }
        }
    }
}
