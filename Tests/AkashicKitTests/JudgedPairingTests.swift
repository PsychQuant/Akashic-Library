import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// 逐篇判定的寫入路徑（change `per-work-judged-authorship`；spec person-resolution）。
///
/// 判定與提名是兩件事（`.claude/rules/identity-is-judged-not-matched.md`）：提名是 recall，
/// 由字串鍵產生；判定是 precision，由名字**以外**的證據支撐，而本檔測的是「判定有地方寫」。
final class JudgedPairingTests: XCTestCase {

    // MARK: - 1.1 judgement 必填

    /// spec: `A judged pairing SHALL resolve one occurrence and SHALL carry its judgement`
    /// —— scenario「A judged pairing without judgement text is rejected」。
    ///
    /// 空白 judgement 建構不出來，而不是建得出來但被檢查擋下：judgement 是「為什麼這樣判」
    /// 的紀錄，少了它的配對與猜測無法區分，所以那個狀態在型別層就不該存在
    /// （同 `AmbiguousMatch.init?` 對少於兩個 key 的既有形狀）。
    func testBlankJudgementIsNotConstructible() {
        for blank in ["", " ", "\t", "\n", "  \n \t "] {
            XCTAssertNil(
                JudgedPairing(citekey: "w1", authorIndex: 0,
                              literal: "C-H Chen", personKey: "chun-houh-chen",
                              judgement: blank),
                "judgement 為空白（\(blank.debugDescription)）時不得建構得出來")
        }
    }

    /// 非空 judgement 建得出來，且原文逐字保留（不 trim 掉內部空白、不改寫）。
    func testNonBlankJudgementIsPreservedVerbatim() {
        let text = "論文在該作者位登記的機構為 Institute of Statistical Science, Academia Sinica"
        let p = JudgedPairing(citekey: "chen2006decision", authorIndex: 5,
                              literal: "C.-H. Chen", personKey: "chun-houh-chen",
                              judgement: text)
        XCTAssertEqual(p?.judgement, text)
    }

    // MARK: - 1.4 型別保證：歧義沒有單數的 personKey

    /// **反面斷言**：`AmbiguousMatch` 不具備單數成員 `personKey`，所以它結構上
    /// conform 不了 `AuthorPairing`，也就傳不進 `apply`。
    ///
    /// 這條測的不是「我們記得別傳」，是「**傳不進去**」——既有的兩桶設計
    /// （`ResolutionReport` 的 candidates／ambiguities 分欄）用同一件事讓
    /// 「不小心 apply 一個歧義」寫不出來，本協定沿用它。
    ///
    /// 手法同既有的 `Mirror(reflecting:).children` 型別反射守衛：人工清單會與型別分岔，
    /// 反射不會。**若有人日後給 `AmbiguousMatch` 加上 `personKey`**（例如
    /// `personKeys.first` 的便利存取），這條會紅——那正是要攔的那一刻。
    func testAmbiguousMatchHasNoSingularPersonKey() {
        let m = AmbiguousMatch(entryID: UUID(), citekey: "w1", authorIndex: 0,
                               literal: "C-H Chen",
                               personKeys: ["chen-hsin-chen", "chun-houh-chen"],
                               tier: .initials)
        XCTAssertNotNil(m, "兩個 key 應建得出歧義")
        let labels = Mirror(reflecting: m!).children.compactMap(\.label)
        XCTAssertFalse(labels.contains("personKey"),
                       "AmbiguousMatch 不得有單數 personKey——有了就 conform 得了 "
                       + "AuthorPairing，「不小心 apply 一個歧義」就從**寫不出來**"
                       + "降級成**要記得別寫**。實際欄位：\(labels)")
        XCTAssertTrue(labels.contains("personKeys"),
                      "複數 personKeys 應仍在（歧義的『是哪一個』尚未決定）")
    }

    // MARK: - 1.5 apply 吃得下判定

    private func work(_ citekey: String, authors: [Author]) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T")
        e.authors = authors
        return e
    }

    /// spec: `A judged pairing SHALL resolve one occurrence and SHALL carry its judgement`
    /// —— scenario「A judged pairing resolves the named author position」的寫入半邊。
    func testApplyAcceptsJudgedPairing() {
        let e = work("chen2006decision", authors: [.literal("Someone Else"),
                                                   .literal("C.-H. Chen")])
        let j = JudgedPairing(citekey: "chen2006decision", authorIndex: 1,
                              literal: "C.-H. Chen", personKey: "chun-houh-chen",
                              judgement: "該作者位登記機構為統計所")!
        let out = PersonResolver.apply([j], to: [e])
        XCTAssertEqual(out.first?.authors,
                       [.literal("Someone Else"), .key("chun-houh-chen")])
    }

    /// spec: `A judged pairing SHALL be applied only when the named position still holds
    /// the named literal` —— scenario「The named position no longer holds the named literal」。
    ///
    /// 守衛是既有的三道之一，本測證明泛型化**沒有把它放寬**。
    func testApplySkipsWhenPositionNoLongerHoldsThatLiteral() {
        let e = work("w1", authors: [.literal("Someone Else"), .literal("C.-H. Chen")])
        let stale = JudgedPairing(citekey: "w1", authorIndex: 0,
                                  literal: "C.-H. Chen", personKey: "chun-houh-chen",
                                  judgement: "計畫時 index 0 是它，現在不是")!
        XCTAssertEqual(PersonResolver.apply([stale], to: [e]).first?.authors, e.authors,
                       "位置對不上就不動")
    }

    /// 索引越界與 citekey 不存在同樣不寫入（既有守衛的其餘兩道）。
    func testApplySkipsOutOfRangeIndexAndUnknownCitekey() {
        let e = work("w1", authors: [.literal("C.-H. Chen")])
        let oor = JudgedPairing(citekey: "w1", authorIndex: 9, literal: "C.-H. Chen",
                                personKey: "chun-houh-chen", judgement: "索引越界")!
        let unknown = JudgedPairing(citekey: "nope", authorIndex: 0, literal: "C.-H. Chen",
                                    personKey: "chun-houh-chen", judgement: "citekey 不存在")!
        XCTAssertEqual(PersonResolver.apply([oor, unknown], to: [e]).first?.authors, e.authors)
    }
}
