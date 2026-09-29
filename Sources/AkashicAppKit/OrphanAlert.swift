import Foundation
import AkashicCore

/// 「拿掉已刪除的附加來源」按下按鈕那一刻，使用者在清單與對話框上看到並確認的那一組（#609）。
///
/// `seen` 是當時清單上的那一組來源鍵——動作當下磁碟上的那一組若與它不同就拒絕（拿掉的只能是使用者看到並確認的那一組，R1 verify）。
struct PendingRemoval: Equatable {
    let citekey: String
    let seen: [String]
    let sourcesLabel: String   // `Entry.displayOrphanedAdditionalSources` 的消毒投影
}

/// 裁決台②（`OrphanView`）會彈出的提示——**同一時間只有一個**（#684）。
///
/// 先前 `OrphanView` 疊了三個 `.alert`（確認、結果、失敗）各綁一個獨立的狀態，「確認」按鈕的動作在關掉自己的同時讓另外兩個
/// 之一亮起：兩個 `.alert` 修飾子在同一個 view 上互相搶著呈現，而 SwiftUI 對「一個提示的按鈕動作裡再彈另一個」沒有保證。
/// 三個 case 合成一個 enum、一個 `.alert`，標題與內容跟著 case 走。
enum OrphanAlert: Equatable {
    /// 等著使用者填理由並確認「拿掉」。
    case confirmRemoval(PendingRemoval)
    /// 拿掉成功的報告（理由全文在裡面）。
    case removed(String)
    /// 動作失敗的訊息。
    case failed(String)

    var title: String {
        switch self {
        case .confirmRemoval: return "拿掉已刪除的附加來源？"
        case .removed: return "已拿掉"
        case .failed: return "操作失敗"
        }
    }
}

/// `OrphanView` 的提示狀態：現在顯示的那一個，加上「下一個」。
///
/// **為什麼要有 `queued`**：SwiftUI 在提示的按鈕動作**之後**才把 `isPresented` 設成 false。確認提示的「拿掉」按鈕要在動作裡
/// 接著彈出結果或失敗的提示；若動作直接改成新的提示，緊接著而來的「關閉」會把它一起抹掉——使用者按了「拿掉」卻看不到結果。
/// 所以動作裡的 `show` 只把它排進 `queued`；關閉之後、下一個 runloop 再 `presentQueued()`，讓 `isPresented` 真的走一次 false → true。
///
/// 抽成值型別是為了能在沒有 SwiftUI 的測試裡驗轉換（`AkashicApp/` 的 UI 不在 SwiftPM 測試範圍）：view 只綁 `presented`。
struct OrphanAlertState: Equatable {
    /// 目前顯示的提示。
    private(set) var presented: OrphanAlert?
    /// 提示還在畫面上時被要求顯示的下一個；同時有好幾個時後來的取代先前的（每個動作只產生一個結果）。
    private(set) var queued: OrphanAlert?

    init() {}

    var isPresenting: Bool { presented != nil }
    var hasQueued: Bool { queued != nil }

    /// 要求顯示一個提示：畫面上沒有提示就立刻顯示，有就排在它後面（不取代它）。
    mutating func show(_ alert: OrphanAlert) {
        if presented == nil {
            presented = alert
        } else {
            queued = alert
        }
    }

    /// SwiftUI 已經關掉目前的提示（任何按鈕、或點外面）。`queued` 不動——它要等到關閉之後才輪到。
    mutating func dismissed() {
        presented = nil
    }

    /// 畫面上沒有提示而有排隊中的，就顯示它；否則什麼都不做。
    mutating func presentQueued() {
        guard presented == nil, let next = queued else { return }
        presented = next
        queued = nil
    }
}

extension OrphanModel {
    /// 跑一個動作；失敗就把錯誤放進提示。成功回 true。
    @discardableResult
    static func attempt(alert: inout OrphanAlertState, _ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            alert.show(.failed(displaySafeErrorMultiline(error)))
            return false
        }
    }

    /// 使用者在確認提示裡按了「拿掉」之後的全部狀態轉換：
    /// - 成功：理由已經進了結果報告，草稿清掉；結果排進提示（`.removed`）。
    /// - 失敗：草稿**保留**——最可能的失敗是記錄檔還沒 commit，commit 之後重開同一筆不必重打；錯誤排進提示（`.failed`）。
    ///
    /// 動作當下重新讀盤驗證形狀與「這一組」、確認記錄檔已 commit，都在 kit 層的 `removeOrphanedAdditionalSources`。
    func confirmRemoval(_ pending: PendingRemoval, draft: inout RemovalReasonDraft, alert: inout OrphanAlertState) {
        let reason = draft.text
        do {
            let report = try removeOrphanedAdditionalSources(citekey: pending.citekey, reason: reason, seen: pending.seen)
            draft.clearAfterSuccess()
            alert.show(.removed(report))
        } catch {
            alert.show(.failed(displaySafeErrorMultiline(error)))
        }
    }
}
