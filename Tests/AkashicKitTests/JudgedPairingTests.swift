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

    // MARK: - 2.1 判定的 rule 字面值

    /// spec: `A judgement SHALL nominate the same literal elsewhere, with its provenance
    /// visible` —— 字面約束的半邊。
    ///
    /// 提名理由的弱血統揭露只逐字印出符合 `^[a-z][a-z-]{0,60}$` 的 rule，其餘一律代換成
    /// 「非標準rule」（防偽造揭露樣式）。判定的 rule 若不符，判定的來歷就**看不見**——
    /// 而看得見正是它存在的理由。
    func testJudgedRulePassesTheDisclosureLiteralCheck() {
        let r = ResolutionLedger.judgedRule
        XCTAssertNotNil(r.range(of: "^[a-z][a-z-]{0,60}$", options: .regularExpression),
                        "judgedRule「\(r)」不符揭露的字面約束，會被印成「非標準rule」")
    }

    /// 與既有 rule 字面值都不相撞——校準歷史分開計（同 orgRule／venueRule 的既有理由）。
    func testJudgedRuleIsDistinctFromEveryNominationRule() {
        let nomination = Set(ResolutionTier.allCases.map(ResolutionLedger.personRule(for:)))
            .union([ResolutionLedger.orgRule, ResolutionLedger.venueRule])
        XCTAssertFalse(nomination.contains(ResolutionLedger.judgedRule),
                       "judgedRule 不得與任何提名 rule 相同：\(nomination)")
    }

    /// **刻意不帶 `author-name-` 前綴**：該前綴的意思是「靠名字比對出來的」，
    /// 而判定不是。這條把那個設計意圖釘住——有人日後改成 `author-name-judged`
    /// 就會紅。
    func testJudgedRuleDoesNotClaimToBeANameMatch() {
        XCTAssertFalse(ResolutionLedger.judgedRule.hasPrefix("author-name-"),
                       "判定不是名字比對，rule 不得宣稱自己是")
    }

    // MARK: - 2.2 verdict 同時含操作者原文與 rule 尾註

    /// spec: `A judged pairing SHALL resolve one occurrence and SHALL carry its judgement`
    /// —— scenario「A judged pairing resolves the named author position」的 verdict 半邊。
    ///
    /// **建構函式住 `ResolutionLedger`**：該檔頭寫著「慣例單一來源——encode 與 decode
    /// 只住這裡」。CLI 與 MCP 各拼一次尾註，是兩份會分岔的規格。
    func testJudgedVerdictCarriesBothOperatorTextAndRuleTail() {
        let text = "該作者位登記機構為 Institute of Statistical Science, Academia Sinica"
        let j = JudgedPairing(citekey: "chen2006decision", authorIndex: 5,
                              literal: "C.-H. Chen", personKey: "chun-houh-chen",
                              judgement: text)!
        let ref = ResolutionLedger.record(judged: j)

        XCTAssertEqual(ref.field, ResolutionLedger.VerdictKind.confirmed.rawValue)
        guard case let .judgement(statement, restsOn) = ref.kind else {
            return XCTFail("判定必須寫成 judgement，實得 \(ref.kind)")
        }
        XCTAssertTrue(statement.contains(text), "操作者原文必須逐字在內：\(statement)")
        XCTAssertTrue(statement.contains("[rule: \(ResolutionLedger.judgedRule)]"),
                      "rule 尾註必須在：\(statement)")
        XCTAssertTrue(restsOn.isEmpty,
                      "#280：verdict 刻意不攜 rests-on，證據走被判 person 的 references")
    }

    /// verdict 的 value 用既有的配對文法（`work:<citekey> :: <literal>`），
    /// 這樣 `rejectedPairings`／`confirmedPairings` 的既有讀端不必改就認得判定。
    func testJudgedVerdictUsesTheExistingPairingGrammar() {
        let j = JudgedPairing(citekey: "w1", authorIndex: 0, literal: "C-H Chen",
                              personKey: "chun-houh-chen", judgement: "x")!
        let ref = ResolutionLedger.record(judged: j)
        let v = ref.value ?? ""
        XCTAssertTrue(v.contains("w1"), "value 應含 citekey：\(v)")
        XCTAssertTrue(v.contains("C-H Chen"), "value 應含 literal：\(v)")
    }

    // MARK: - 2.3 傳染：判定讓同 literal 在別篇浮出來

    private func person(_ key: String, names: [String]) -> Person {
        var p = Person(key: key)
        p.names = PersonNames(authorized: names, variant: [])
        return p
    }

    /// spec: `A judgement SHALL nominate the same literal elsewhere, with its provenance
    /// visible`。
    ///
    /// **為什麼傳染是對的**（設計曾反轉過一次）：不傳染的話，同 literal 的其他 occurrence
    /// 永遠停在歧義桶，**沒有任何東西指出「其中一列已經有人判過了」**。傳染讓它們浮出來，
    /// 而錯配由既有兩道機制擋住（CLI 裸 apply 拒絕非 exact 層、MCP 要求 per-id 顯式）。
    func testJudgementNominatesTheSameLiteralInAnotherWork() {
        let people = [person("chen-hsin-chen", names: ["Chen, Chen-Hsin"]),
                      person("chun-houh-chen", names: ["Chen, Chun-houh"])]
        let judged = work("w1", authors: [.literal("C-H Chen")])
        let other = work("w2", authors: [.literal("C-H Chen")])

        // 判定前：兩篇都是歧義（兩個 person 的 initials 鍵相撞）
        let before = PersonResolver.resolve(entries: [judged, other], people: people,
                                            rejected: [], confirmed: [:])
        XCTAssertEqual(before.candidates.count, 0)
        XCTAssertEqual(before.ambiguities.count, 2, "判定前兩篇都該是歧義")

        // w1 判給 chun-houh-chen，其 verdict 餵回 confirmed
        let j = JudgedPairing(citekey: "w1", authorIndex: 0, literal: "C-H Chen",
                              personKey: "chun-houh-chen",
                              judgement: "該作者位登記機構為統計所")!
        let pairing = ResolutionPairing(holderKind: .work, holder: j.citekey,
                                        literal: j.literal, judgedKey: j.personKey)
        let after = PersonResolver.resolve(
            entries: [PersonResolver.apply([j], to: [judged]).first!, other],
            people: people, rejected: [],
            confirmed: [pairing: ResolutionLedger.judgedRule])

        let w2 = after.candidates.filter { $0.citekey == "w2" }
        XCTAssertEqual(w2.count, 1, "w2 應因他處判定而被提名，實得 \(after.candidates)")
        XCTAssertEqual(w2.first?.tier, .confirmedElsewhere)
        XCTAssertEqual(w2.first?.personKey, "chun-houh-chen")
        XCTAssertTrue(w2.first?.reason.contains(ResolutionLedger.judgedRule) ?? false,
                      "提名理由必須逐字揭露判定的 rule（血統可見）：\(w2.first?.reason ?? "")")
    }

    // MARK: - 2.4 冪等

    /// spec: `A judged pairing SHALL be applied only when the named position still holds
    /// the named literal` —— scenario「Re-applying a judged pairing changes nothing」。
    func testReapplyingAJudgementChangesNothing() {
        let j = JudgedPairing(citekey: "w1", authorIndex: 0, literal: "C-H Chen",
                              personKey: "chun-houh-chen", judgement: "同上")!
        // entry 側：第二次因守衛「該位置仍是那個 literal」而成為 no-op
        let once = PersonResolver.apply([j], to: [work("w1", authors: [.literal("C-H Chen")])])
        let twice = PersonResolver.apply([j], to: once)
        XCTAssertEqual(twice.first?.authors, [.key("chun-houh-chen")])

        // verdict 側：appendIfAbsent 保證不重複附加
        var refs: [ProvenanceReference] = []
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(ResolutionLedger.record(judged: j),
                                                      to: &refs))
        XCTAssertFalse(ResolutionLedger.appendIfAbsent(ResolutionLedger.record(judged: j),
                                                       to: &refs))
        XCTAssertEqual(refs.count, 1, "同一筆判定不得留下兩筆 verdict")
    }

    // MARK: - 傳染的**邊界**：同 literal 指的是同一個字串

    /// 真實 store 上判定 `C.-H. Chen` 之後，`C-H Chen`（無句點）**沒有**被提名——
    /// 一開始看起來像 bug，查證後是正確行為：那是**不同的 literal**。
    ///
    /// 這條把邊界釘住，並記錄一個**既有的不對稱**：寬鬆 tier 的鍵空間把 `.` 映成 `-`
    /// （`LooseNameKey.cleanTokens` 的 doc 明寫 `y.-h.` 與 `y.h.` 同歸 `y-h`），
    /// 而 `confirmedElsewhere` 的傳染鍵走 `NameNormalization.matchingKey`，**不做**這件事。
    ///
    /// 兩者都說得通——傳染是較強的主張（「**這個字串**在他處被確認過」），保守是合理的。
    /// 但這個不對稱先前沒有任何測試或文件記載，本條補上。
    func testPropagationKeysOnTheExactLiteralNotItsPunctuationVariants() {
        XCTAssertNotEqual(NameNormalization.matchingKey("C.-H. Chen"),
                          NameNormalization.matchingKey("C-H Chen"),
                          "傳染鍵若把句點與連字號視為相同，判定會跨標點變體擴散——"
                          + "那是比目前更強的主張，需要顯式裁決而非默默發生")
        // 對照：寬鬆 tier 的鍵空間**確實**收斂這兩者
        XCTAssertFalse(LooseNameKey.initialsKeys("C.-H. Chen")
                        .isDisjoint(with: LooseNameKey.initialsKeys("C-H Chen")),
                       "initials 層應收斂標點變體（cleanTokens 把 . 映成 -）")
    }

    // MARK: - 第 7 節反向驗證補上的三個缺口

    /// spec: `A judged pairing SHALL resolve one occurrence and SHALL carry its judgement`
    /// —— 「SHALL NOT carry a nominating tier」那一句。
    ///
    /// 先前只是「碰巧沒有那個欄位」，沒有任何東西擋住日後有人為了方便加一個。
    /// tier 記的是「怎麼被提名的」，判定不是被提名出來的——給它 tier 會謊報來歷。
    func testJudgedPairingCarriesNoNominatingTier() {
        let j = JudgedPairing(citekey: "w1", authorIndex: 0, literal: "x",
                              personKey: "p", judgement: "why")!
        let labels = Mirror(reflecting: j).children.compactMap(\.label)
        XCTAssertFalse(labels.contains("tier"),
                       "判定不得帶提名層——那會謊報它的來歷。實際欄位：\(labels)")
        XCTAssertFalse(labels.contains("restsOn"),
                       "#280：verdict 不攜證據指標，證據住被判 person 的 references")
    }

    /// spec scenario「A judgement-derived nomination is not swept into a bare apply」。
    ///
    /// **這是整個設計賴以成立的安全性質**：判定會傳染（同 literal 在別篇以
    /// `confirmedElsewhere` 浮出），而傳染之所以安全，就是因為裸 apply 對非 exact 層
    /// 一律拒絕。先前完全沒有測試——反向驗證（第 7 節）才抓到。
    ///
    /// 這裡驗的是**判準本身**（tier != .exact 即屬寬鬆），CLI 的錯誤訊息由該層自己的
    /// 測試涵蓋；兩者合起來才是完整的那道閘。
    func testJudgementDerivedNominationCountsAsLooseTier() {
        let people = [person("chen-hsin-chen", names: ["Chen, Chen-Hsin"]),
                      person("chun-houh-chen", names: ["Chen, Chun-houh"])]
        let judged = work("w1", authors: [.literal("C-H Chen")])
        let other = work("w2", authors: [.literal("C-H Chen")])
        let j = JudgedPairing(citekey: "w1", authorIndex: 0, literal: "C-H Chen",
                              personKey: "chun-houh-chen", judgement: "機構證據")!
        let pairing = ResolutionPairing(holderKind: .work, holder: j.citekey,
                                        literal: j.literal, judgedKey: j.personKey)
        let after = PersonResolver.resolve(
            entries: [PersonResolver.apply([j], to: [judged]).first!, other],
            people: people, rejected: [],
            confirmed: [pairing: ResolutionLedger.judgedRule])

        let w2 = after.candidates.first { $0.citekey == "w2" }
        XCTAssertNotNil(w2)
        XCTAssertNotEqual(w2?.tier, .exact,
                          "判定衍生的提名**必須**落在寬鬆層——裸 apply 的閘判準正是 "
                          + "tier != .exact，落在 exact 就會被一發掃進去")
        XCTAssertEqual(w2?.tier, .confirmedElsewhere)
    }
}
