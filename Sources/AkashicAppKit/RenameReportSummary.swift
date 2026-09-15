import Foundation
import AkashicCore
import AkashicStoreIO

/// `RenameReport` 的人可讀摘要——**nonisolated 純函式**（顯式標記，不靠 package 的預設隔離：本 package 是
/// swift-tools 5.9、無 `defaultIsolation` 設定，bare enum 本來就 nonisolated，但寫出來讓意圖由編譯器守），住在 View 之外：`AppStateError` 的
/// `errorDescription`（同步、任意呼叫端）與 `EntryDetailView` 的回執都用它。model 不得依賴 View
/// （#465 verify Codex R2：`LocalizedError` 綁到 MainActor 隔離的 `View` 型別在嚴格並行下會變 error）。
///
/// **標籤**與 CLI `rename` 的三行逐字相同（「relations 已遷移」「歧異候選已遷移」「消解判定已遷移」）；
/// **三處刻意不同**：零筆說零而 CLI 省略（GUI 沒有 scrollback，回執沉默會讓「沒有連帶改寫」與「App 沒
/// 告訴我」不可分辨——這與 `ContentView` 健康區塊的「沉默即健康」是**不同語意**：那是被動儀表板，
/// 這是動作回執，不要為了一致性統一）、只列前五筆但計數保留（alert 不是清單）、分隔符用「、」。
///
/// 每個 key 套 `displaySafe(max: 200)`——與 CLI 同一立場：這些值經 load 端 `StoreKey` 把關
/// （relations 是 citekey、verdict 是 person／venue key）或是 UUID（歧異候選），結構上載不了控制
/// 字元，但 `StoreKey` 不約束長度，且「同一份資料兩種待遇，遲早有人照沒消毒的那個抄」
/// （`AkashicService` 對同類值的既有裁決）。`DisplaySinkCoverageTests` 對本型別結構上不可見
/// （三元隱式 return、無 tainted token，#485）。
enum RenameReportSummary {
    /// 回執：第一行「✓ old → new」——alert 要說出改成了什麼，否則與一次不編輯的點擊同形（DA-2）。
    nonisolated static func receipt(_ r: RenameReport, from old: String, to new: String) -> String {
        "✓ \(displaySafe(old, max: 200)) → \(displaySafe(new, max: 200))\n" + lines(r)
    }

    /// 三類連帶改寫各一行。
    nonisolated static func lines(_ r: RenameReport) -> String {
        func line(_ label: String, _ xs: [String]) -> String {
            let shown = xs.prefix(5).map { displaySafe($0, max: 200) }.joined(separator: "、")
            return xs.isEmpty ? "\(label)：0 筆"
                              : "\(label)：\(xs.count) 筆（\(shown)\(xs.count > 5 ? "…" : "")）"
        }
        /// 迴送 store 字串（verdict value、judgement）的列用性質式逃脫——與 CLI 的 `displaySafeInvisible(max: 1_000)` 同一種消毒
        func storeLine(_ label: String, _ xs: [String]) -> String {
            let shown = xs.prefix(5).map { displaySafeInvisible($0, max: 200) }.joined(separator: "、")
            return xs.isEmpty ? "\(label)：0 筆"
                              : "\(label)：\(xs.count) 筆（\(shown)\(xs.count > 5 ? "…" : "")）"
        }
        /// `HolderRecord` 專用：`describedSafely` **已經**消毒過，不得再過一次 `line`
        /// ——`displaySafe` 不冪等（它逃脫反斜線自身，二次呼叫把 `\u{0009}` 變成
        /// `\u{005C}u{0009}`）。用 overload 而不是註解：註解攔不住下一個人把它併回去。
        func holderLine(_ label: String, _ xs: [HolderRecord]) -> String {
            let shown = xs.prefix(5).map(\.describedSafely).joined(separator: "、")   // display-safe-exempt: describedSafely 內已套 displaySafe(max: 200)
            return xs.isEmpty ? "\(label)：0 筆"
                              : "\(label)：\(xs.count) 筆（\(shown)\(xs.count > 5 ? "…" : "")）"
        }
        return [line("relations 已遷移", r.relationsRewritten),
                line("歧異候選已遷移", r.divergenceCandidatesRewritten),
                holderLine("消解判定已遷移", r.verdictValuesRewritten),
                // #495：收攏丟棄的列。**與上面三行不同，這裡的元素是敘述不是 key**
                // （`<kind>「<持有記錄>」：<field> <遷移前的原值>——丟棄 <來源>`），所以 200 字的截斷
                // 會比在 key 上更常真的截到。alert 本來就只是提示，完整清單看 CLI `rename`。
                // 以性質逃脫（R15；R14 verify security 第 7 列：這一列迴送 verdict 的 value 與人寫的 judgement，列舉式
                // `displaySafe` 不逃脫 ZWSP／VS／TAG——兩列逐像素相同而訊息說「丟棄了哪一筆」）
                storeLine("verdict 收攏丟棄", r.verdictsCollapsed)]
            .joined(separator: "\n")
        // #497：有 quarantine 檔時多一行警語。**只在非空時加**——「0 個未掃描」對 GUI
        // 是雜訊，而上面四行的「零筆說零」語意不同：那是回執（做了什麼），這是邊界
        // （有什麼沒看）。沒有邊界時不必說有邊界。
        + (r.quarantinedNotScanned.isEmpty ? ""
           : "\n⚠ \(r.quarantinedNotScanned.count) 個 quarantine 檔未掃描——其中若有 verdict 指向舊鍵，不會被遷移")
    }
}
