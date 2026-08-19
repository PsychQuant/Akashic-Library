import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #161 的核心產出是五個 `display*` 投影——而它們**零測試覆蓋**（verify 181-1）。
///
/// 席位把五個投影全部拆掉 `displaySafe(`、直接回傳原字串 → **1027 條全綠**。
/// `DisplaySafeTests` 驗的是 `displaySafe` 函式本身，證明不了投影接上了它。
///
/// 守衛也接不住：`candidate.displayLiteral` 這個運算式**不含** `.literal`
/// （大寫 L），`taintedTokens` 對不上——**投影的命名本身讓 token 清單失效**。
final class DisplayProjectionTests: XCTestCase {
    private let hostile = "ev\u{1B}[31m\u{202E}il"

    private func assertSanitised(_ s: String, _ what: String) {
        XCTAssertFalse(s.contains("\u{1B}"), "\(what)：raw ESC 進 SwiftUI Text")
        XCTAssertFalse(s.contains("\u{202E}"), "\(what)：raw U+202E（RTL override）")
    }

    /// `literal` 是 Zotero 匯入的作者原文，而它出現在**破壞性動作的確認畫面**。
    func testResolutionCandidateProjections() {
        let c = ResolutionCandidate(citekey: "k2020", authorIndex: 0, literal: hostile,
                                    personKey: "che-cheng", reason: hostile, tier: .exact)
        assertSanitised(c.displayLiteral, "displayLiteral")
        assertSanitised(c.displayReason, "displayReason")
        assertSanitised(c.displayCitekey, "displayCitekey")
    }

    func testEntryProjections() {
        let e = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: hostile)
        assertSanitised(e.displayTitle, "displayTitle")
        assertSanitised(e.displayTitleOrCitekey, "displayTitleOrCitekey")
        // title 為空時退回 citekey——那過 load 端 quarantine，不需消毒
        let empty = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: "")
        XCTAssertEqual(empty.displayTitleOrCitekey, "k2020")
        // **只含控制字元的 title 不是 isEmpty**，仍要走消毒分支
        let ctrl = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: "\u{202E}")
        assertSanitised(ctrl.displayTitleOrCitekey, "只含控制字元的 title")
    }

    /// **第六個投影**（#161 verify 181-7）。它是**為了修 181-4 而在加入這個測試檔
    /// 的同一個 commit 裡新增**的，而測試只覆蓋原本那五個——只把它的 `displaySafe`
    /// 拆掉，1032 條全綠。
    ///
    /// 諷刺處：本檔 docstring 第一句就是「#161 的核心產出是五個投影——而它們零
    /// 測試覆蓋」。投影從五個變六個，測試沒跟上。
    func testEntryDisplayAuthorsIsSanitised() {
        var e = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: "t")
        e.authors = [.literal(hostile), .key("che-cheng")]
        assertSanitised(e.displayAuthors, "displayAuthors")
        XCTAssertTrue(e.displayAuthors.contains("che-cheng"), "非 literal 的部分照常呈現")
    }

    func testLibraryProjections() {
        let l = Library(key: "main", name: hostile)
        assertSanitised(l.displayName, "displayName")
        assertSanitised(l.displayNameOrKey, "displayNameOrKey")
        XCTAssertEqual(Library(key: "main", name: "").displayNameOrKey, "main")
    }

    func testQuarantinedFileProjections() {
        let q = QuarantinedFile(file: hostile, reason: hostile)
        assertSanitised(q.displayFile, "displayFile")
        assertSanitised(q.displayReason, "displayReason")
    }

    /// **`Author.displayName` 是一個 `display*` 前綴、卻不消毒的屬性**（181-4）。
    ///
    /// 它對 `.literal` 原樣回傳 Zotero 作者原文——與裁決台上剛包起來的
    /// `ResolutionCandidate.literal` **同源**（後者就是從 `entry.authors` 的
    /// `.literal` 取出來的）。而 `Adjudication.swift` 那條「View 一律用 `display*`」
    /// 的規矩，現在多了一個**會騙人的對象**：比 #161 說的「規矩存在、對象不存在」
    /// 更糟。
    ///
    /// 本測試**記錄現況**（它確實不消毒），並把這個矛盾釘在可見處。修法屬另案
    /// （改名或加消毒版），因為 `displayName` 有非顯示的消費端。
    func testAuthorDisplayNameIsNotSanitisedAndThatIsTheProblem() {
        let a = Author.literal(hostile)
        XCTAssertTrue(a.displayName.contains("\u{202E}"),
                      "現況：Author.displayName 不消毒。若哪天它開始消毒了，"
                      + "把這條改成 assertFalse 並拿掉 #161 的那條 follow-up")
    }
}
