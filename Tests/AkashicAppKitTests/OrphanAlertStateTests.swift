import XCTest
@testable import AkashicAppKit

/// #684：`OrphanView` 的提示只有一個 `.alert`，狀態轉換在 `OrphanAlertState`。UI 本身不在 SwiftPM 測試範圍，所以能測的
/// 是轉換：什麼時候顯示、什麼時候排隊、關掉之後下一個怎麼輪到——尤其是「按鈕動作裡產生下一個提示，緊接著的關閉不得把它抹掉」
/// 這條（先前三個獨立 `.alert` 的疊法沒有任何東西守著它）。
final class OrphanAlertStateTests: XCTestCase {
    private let pending = PendingRemoval(citekey: "partial2020", seen: ["5:K2"], sourcesLabel: "5:K2")

    func testStartsWithNothingPresentedOrQueued() {
        let s = OrphanAlertState()
        XCTAssertNil(s.presented)
        XCTAssertNil(s.queued)
        XCTAssertFalse(s.isPresenting)
        XCTAssertFalse(s.hasQueued)
    }

    /// 畫面上沒有提示：立刻顯示（例如刪除失敗時的錯誤、開確認提示）。
    func testShowWhenIdlePresentsImmediately() {
        var s = OrphanAlertState()
        s.show(.failed("錯誤"))
        XCTAssertEqual(s.presented, .failed("錯誤"))
        XCTAssertNil(s.queued)
        XCTAssertTrue(s.isPresenting)
    }

    /// 提示還在畫面上（動作在確認提示的按鈕裡）：新的排在後面，**不取代**目前這個。
    func testShowWhilePresentingQueuesInsteadOfReplacing() {
        var s = OrphanAlertState()
        s.show(.confirmRemoval(pending))
        s.show(.removed("報告"))
        XCTAssertEqual(s.presented, .confirmRemoval(pending), "目前的提示不能被動作裡的 show 換掉——換掉會讓確認提示在使用者還沒關它時就變成別的")
        XCTAssertEqual(s.queued, .removed("報告"))
        XCTAssertTrue(s.hasQueued)
    }

    /// **這條是整個型別存在的理由**：SwiftUI 在按鈕動作之後才把 isPresented 設成 false（`dismissed()`）。動作裡排進去的下一個提示
    /// 不得被那次關閉抹掉，並且要等關閉之後才輪到（`presentQueued()`）。
    func testDismissalAfterAButtonActionDoesNotEraseTheQueuedFollowUp() {
        var s = OrphanAlertState()
        s.show(.confirmRemoval(pending))
        // 使用者按「拿掉」：按鈕動作先跑……
        s.show(.removed("報告"))
        // ……然後 SwiftUI 關掉確認提示
        s.dismissed()
        XCTAssertNil(s.presented, "確認提示已關；結果提示還沒顯示（等下一個 runloop，讓 isPresented 走一次 false → true）")
        XCTAssertEqual(s.queued, .removed("報告"), "排隊中的沒有被關閉抹掉")
        s.presentQueued()
        XCTAssertEqual(s.presented, .removed("報告"))
        XCTAssertNil(s.queued)
        s.dismissed()
        XCTAssertNil(s.presented)
        XCTAssertFalse(s.hasQueued)
    }

    func testFailureFollowsTheSamePath() {
        var s = OrphanAlertState()
        s.show(.confirmRemoval(pending))
        s.show(.failed("記錄檔還沒 commit"))
        s.dismissed()
        s.presentQueued()
        XCTAssertEqual(s.presented, .failed("記錄檔還沒 commit"))
    }

    /// 按「取消」：沒有下一個，回到什麼都沒有。
    func testCancelReturnsToIdle() {
        var s = OrphanAlertState()
        s.show(.confirmRemoval(pending))
        s.dismissed()
        s.presentQueued()
        XCTAssertNil(s.presented)
        XCTAssertNil(s.queued)
    }

    /// 同時有好幾個排隊：後來的取代先前的（每個動作只產生一個結果，最新的才是使用者要看的）。
    func testALaterQueuedAlertReplacesAnEarlierOne() {
        var s = OrphanAlertState()
        s.show(.confirmRemoval(pending))
        s.show(.failed("第一個"))
        s.show(.removed("第二個"))
        XCTAssertEqual(s.queued, .removed("第二個"))
    }

    /// `presentQueued` 只在畫面上沒有提示、而且有排隊中的時候才動——其餘一律 no-op（`.onChange` 可能多次觸發它）。
    func testPresentQueuedIsANoOpUnlessSomethingIsWaitingForAFreeScreen() {
        var s = OrphanAlertState()
        s.presentQueued()
        XCTAssertEqual(s, OrphanAlertState(), "沒有排隊中的：不變")
        s.show(.confirmRemoval(pending))
        s.show(.removed("報告"))
        s.presentQueued()
        XCTAssertEqual(s.presented, .confirmRemoval(pending), "畫面上還有提示：不得搶先換掉它")
        XCTAssertEqual(s.queued, .removed("報告"))
    }

    /// 三種提示的標題不同、且跟著 case 走——單一 `.alert` 靠它決定標題。
    /// #684 R1 verify 第 19／21 列：垃圾桶的失敗發生在 `confirmationDialog` 的按鈕裡——那個對話框不是 `OrphanAlertState` 的一部分，
    /// 「畫面上有沒有提示」答「沒有」，但它正在關閉。這時要排隊、不能立刻顯示；對話框關掉之後 view 才 `presentQueued()`。
    func testShowAfterDismissalQueuesEvenWhenNoAlertIsPresented() {
        var s = OrphanAlertState()
        s.showAfterDismissal(.failed("移到垃圾桶失敗"))
        XCTAssertNil(s.presented, "對話框正在關閉：不立刻顯示")
        XCTAssertEqual(s.queued, .failed("移到垃圾桶失敗"))
        s.presentQueued()
        XCTAssertEqual(s.presented, .failed("移到垃圾桶失敗"), "對話框關掉之後輪到它")
        XCTAssertNil(s.queued)
    }

    func testEachCaseHasItsOwnTitle() {
        let titles = [OrphanAlert.confirmRemoval(pending), .removed("r"), .failed("e")].map(\.title)
        XCTAssertEqual(titles, ["拿掉已刪除的附加來源？", "已拿掉", "操作失敗"])
        XCTAssertEqual(Set(titles).count, 3)
    }
}
