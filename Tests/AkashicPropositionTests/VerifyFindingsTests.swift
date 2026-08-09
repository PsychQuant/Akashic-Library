import XCTest
import AkashicCore
@testable import AkashicProposition

/// #202–#205 對抗性複審找到的九項，逐項釘住。
///
/// **最有價值的一項是 F5**：四個新運算子裡有三個（`.and`／`.or`／`.implies`／
/// `.nor` 經 `Formula.evaluate`）**完全沒有測試**——席位把 implies 改成
/// `a ∨ ¬b`、把 and/or 對調、把 nor 的否定拿掉，53 條全綠。實作當時是對的，
/// 但沒有任何東西把它held在那裡。
final class VerifyFindingsTests: XCTestCase {

    private let pk = "cheng-che", wk = "w1"

    private func plainModel(_ slots: [AkashicCore.Author],
                            names: [String] = ["Che Cheng"]) throws -> PropositionModel {
        var e = Entry(id: UUID(), citekey: wk, type: "article", title: "T",
                      authors: slots, date: "2025")
        e.fields = [:]
        return try PropositionModel(entries: [e],
                                    people: [Person(key: pk, names: names),
                                             Person(key: "other", names: ["Other One"])])
    }
    private var p: Proposition { .authored(person: .key(pk), work: .key(wk)) }
    private var other: Proposition { .authored(person: .key("other"), work: .key(wk)) }

    private func attestation(_ work: String = "w1") throws -> AuthorListAttestation {
        try AuthorListAttestation(workCitekey: work, attestedBy: "che",
                                  attestedAt: "2026-08-09", basis: "出版社頁面")
    }

    // MARK: - F1：revision 的編碼必須單射

    /// **本 repo 的資料 routinely 觸發這個碰撞。** person 的 names 幾乎都是
    /// `Family, Given` 形式（實測 `~/.akashic` 有 893 個 person 檔含逗號），
    /// 而第一版用 `joined(separator: ",")` 不逃脫分隔符。
    ///
    /// 席位用的正是本 repo 自己 fixture 的名字。兩個世界求值不同、revision 相同，
    /// 於是 `revisionMismatch` 守衛放行——「可重播」在最常見的資料形狀上是假的。
    func testRevisionDoesNotCollideOnCommasInNames() throws {
        // **逗號後不能有空格**，否則 join 後兩者本來就不同、測不到碰撞。
        // 第一版寫 "Chen, Hui-Yun" vs ["Chen","Hui-Yun"] → "Chen, Hui-Yun" vs
        // "Chen,Hui-Yun"，本來就相異，於是 mutation 不紅（自己的 fixture 沒對準）。
        let a = try plainModel([.literal("X")], names: ["Chen,Hui-Yun"])
        let b = try plainModel([.literal("X")], names: ["Chen", "Hui-Yun"])
        XCTAssertNotEqual(try a.contentRevision, try b.contentRevision,
                          "含逗號的單一 name 不得與拆開的兩個 name 撞 revision")
    }

    /// 更一般的性質：**求值不同 → revision 必不同**。
    func testDifferentEvaluationImpliesDifferentRevision() throws {
        let a = try plainModel([.literal("Chen,Hui-Yun")], names: ["Chen,Hui-Yun"])
        let b = try plainModel([.literal("Chen,Hui-Yun")], names: ["Chen", "Hui-Yun"])
        let t1 = try p.evaluate(in: a), t2 = try p.evaluate(in: b)
        if t1 != t2 {
            XCTAssertNotEqual(try a.contentRevision, try b.contentRevision,
                              "兩個世界求值不同（\(t1) vs \(t2)）卻共用 revision")
        }
    }

    /// 拿 A 的 revision 求 B 必須被擋。
    func testCannotReplayIntoTheWrongWorld() throws {
        let a = try plainModel([.literal("Chen,Hui-Yun")], names: ["Chen,Hui-Yun"])
        let b = try plainModel([.literal("Chen,Hui-Yun")], names: ["Chen", "Hui-Yun"])
        let ctxA = ValuationContext(storeKey: "m", storeRevision: try a.contentRevision)
        XCTAssertThrowsError(try p.evaluate(in: b, context: ctxA),
                             "拿 A 的 revision 標 B 的求值必須被拒絕")
    }

    // MARK: - F2：證言必須進 revision

    /// 證言**會改變真值**，所以它必須進 revision——否則 `.fails` 整條路徑落在
    /// #202 的保證之外，同一個 revision 對應兩個不同答案的世界。
    func testAttestationChangesTheRevision() throws {
        let base = try plainModel([.key("other")])
        let without = try base.attesting([])
        let with = try base.attesting([try attestation()])
        XCTAssertEqual(try Formula.atom(p).evaluate(in: without),
                       .undetermined(.noSupportingEvidence))
        XCTAssertEqual(try Formula.atom(p).evaluate(in: with), .fails)
        XCTAssertNotEqual(try with.contentRevision, try without.contentRevision,
                          "證言改變真值就必須改變 revision")
    }

    /// 證言的**內容**（誰核對的、依據什麼）也要進 revision——換一份依據是換一個
    /// 世界，即使結論相同。
    func testAttestationContentIsInTheRevision() throws {
        let base = try plainModel([.key("other")])
        let a = try base.attesting([try attestation()])
        let b = try base.attesting([try AuthorListAttestation(
            workCitekey: wk, attestedBy: "someone-else", attestedAt: "2026-08-09",
            basis: "另一份依據")])
        XCTAssertNotEqual(try a.contentRevision, try b.contentRevision)
    }

    /// `AttestedModel` 也要能產生帶 context 的 `Valuation`。
    func testAttestedModelCanProduceAValuation() throws {
        let m = try (try plainModel([.key("other")])).attesting([try attestation()])
        let v = try p.evaluate(in: m,
            context: ValuationContext(storeKey: "m", storeRevision: try m.contentRevision))
        XCTAssertEqual(v.truth, .fails)
        XCTAssertEqual(v.context.storeRevision, try m.contentRevision)
    }

    // MARK: - F4：空名單不得製造反證

    /// **`allSatisfy` 對空陣列是空真。** 一份被清空（或從未匯入）作者的 work
    /// 配上證言，會對**每一個人**回 `.fails`——那是從缺席製造反證，正是本模組
    /// 存在要擋的推論。
    func testEmptyAuthorListNeverYieldsFails() throws {
        let m = try (try plainModel([])).attesting([try attestation()])
        guard case .undetermined = try Formula.atom(p).evaluate(in: m) else {
            return XCTFail("空名單不得成為反證")
        }
    }

    // MARK: - F5：三值組合的接線（席位三個 mutation 全綠的那一塊）

    private func triple() throws -> (t: Formula, f: Formula, u: Formula, m: AttestedModel) {
        // t：有正面支持 → holds；f：有證言且名單完備 → fails；u：查不到 → undetermined
        var e1 = Entry(id: UUID(), citekey: "wt", type: "article", title: "T",
                       authors: [.key(pk)], date: "2025"); e1.fields = [:]
        var e2 = Entry(id: UUID(), citekey: "wf", type: "article", title: "T",
                       authors: [.key("other")], date: "2025"); e2.fields = [:]
        var e3 = Entry(id: UUID(), citekey: "wu", type: "article", title: "T",
                       authors: [.literal("Nobody")], date: "2025"); e3.fields = [:]
        let base = try PropositionModel(entries: [e1, e2, e3],
                                        people: [Person(key: pk, names: ["Che Cheng"]),
                                                 Person(key: "other", names: ["O"])])
        let m = try base.attesting([try attestation("wf")])
        return (.atom(.authored(person: .key(pk), work: .key("wt"))),
                .atom(.authored(person: .key(pk), work: .key("wf"))),
                .atom(.authored(person: .key(pk), work: .key("wu"))),
                m)
    }

    /// 先確認三個 building block 真的是三個不同的真值——否則下面的表都是空跑。
    func testTripleFixtureCoversAllThreeValues() throws {
        let x = try triple()
        XCTAssertEqual(try x.t.evaluate(in: x.m), .holds)
        XCTAssertEqual(try x.f.evaluate(in: x.m), .fails)
        guard case .undetermined = try x.u.evaluate(in: x.m) else {
            return XCTFail("u 應為未定")
        }
    }

    /// **`.and` 經 `Formula.evaluate` 的完整 9 格**（兩個 evaluator 都測）。
    func testEpistemicAndTable() throws {
        let x = try triple()
        let cases: [(Formula, Formula, TruthValue)] = [
            (x.t, x.t, .holds), (x.t, x.f, .fails),
            (x.f, x.t, .fails), (x.f, x.f, .fails),
            (x.f, x.u, .fails), (x.u, x.f, .fails),
        ]
        for (a, b, want) in cases {
            XCTAssertEqual(try Formula.and(a, b).evaluate(in: x.m), want)
            XCTAssertEqual(try Formula.and(a, b).evaluate(in: x.m.base),
                           try Formula.and(a, b).evaluate(in: x.m.base), "plain 亦須決定性")
        }
        // 真 ∧ 未知 = 未知
        guard case .undetermined = try Formula.and(x.t, x.u).evaluate(in: x.m) else {
            return XCTFail("真 ∧ 未知 應為未知")
        }
    }

    /// **`.or` 的完整表。**
    func testEpistemicOrTable() throws {
        let x = try triple()
        XCTAssertEqual(try Formula.or(x.t, x.f).evaluate(in: x.m), .holds)
        XCTAssertEqual(try Formula.or(x.f, x.t).evaluate(in: x.m), .holds)
        XCTAssertEqual(try Formula.or(x.t, x.u).evaluate(in: x.m), .holds, "真 ∨ 未知 = 真")
        XCTAssertEqual(try Formula.or(x.f, x.f).evaluate(in: x.m), .fails)
        guard case .undetermined = try Formula.or(x.f, x.u).evaluate(in: x.m) else {
            return XCTFail("假 ∨ 未知 應為未知")
        }
    }

    /// **`.implies` ≡ `¬a ∨ b`。** 席位把它改成 `a ∨ ¬b`，53 條全綠。
    func testEpistemicImpliesTable() throws {
        let x = try triple()
        XCTAssertEqual(try Formula.implies(x.t, x.f).evaluate(in: x.m), .fails, "真→假 = 假")
        XCTAssertEqual(try Formula.implies(x.f, x.t).evaluate(in: x.m), .holds, "假→真 = 真")
        XCTAssertEqual(try Formula.implies(x.f, x.f).evaluate(in: x.m), .holds, "假→假 = 真")
        XCTAssertEqual(try Formula.implies(x.t, x.t).evaluate(in: x.m), .holds)
        XCTAssertEqual(try Formula.implies(x.f, x.u).evaluate(in: x.m), .holds,
                       "前件為假 → 真（不論後件）")
    }

    /// **`.nor` ≡ `¬(a ∨ b)`。** 席位把否定拿掉，53 條全綠。
    ///
    /// **兩個 evaluator 都要測。** 第一版只測 `AttestedModel`，於是把 plain
    /// `PropositionModel` 那條的 nor 改壞仍然全綠——有兩份實作就要有兩份測試。
    func testEpistemicNorTable() throws {
        let x = try triple()
        XCTAssertEqual(try Formula.nor(x.f, x.f).evaluate(in: x.m), .holds, "雙假 → 真")
        XCTAssertEqual(try Formula.nor(x.t, x.f).evaluate(in: x.m), .fails)
        XCTAssertEqual(try Formula.nor(x.f, x.t).evaluate(in: x.m), .fails)
        XCTAssertEqual(try Formula.nor(x.t, x.t).evaluate(in: x.m), .fails)
    }

    /// 同樣四格，走 **plain `PropositionModel`** 的 evaluator。
    /// plain 沒有 `.fails`（那要證言），所以用 holds／undetermined 的組合。
    func testEpistemicOperatorsOnPlainModelToo() throws {
        let x = try triple()
        let base = x.m.base
        // t ∨ u = 真；t ∧ u = 未知；nor(t,t) = 假；implies(t,t) = 真
        XCTAssertEqual(try Formula.or(x.t, x.u).evaluate(in: base), .holds)
        guard case .undetermined = try Formula.and(x.t, x.u).evaluate(in: base) else {
            return XCTFail("真 ∧ 未知 應為未知")
        }
        XCTAssertEqual(try Formula.nor(x.t, x.t).evaluate(in: base), .fails,
                       "nor 少了否定的話這裡會是 .holds")
        XCTAssertEqual(try Formula.implies(x.t, x.t).evaluate(in: base), .holds)
        XCTAssertEqual(try Formula.not(x.t).evaluate(in: base), .fails)
    }

    /// 巢狀組合也要對——單層對不保證接線對。
    func testNestedEpistemicComposition() throws {
        let x = try triple()
        // ¬(t ∧ f) = ¬false = true
        XCTAssertEqual(try Formula.not(.and(x.t, x.f)).evaluate(in: x.m), .holds)
        // (t ∨ u) ∧ ¬f = true ∧ true = true
        XCTAssertEqual(try Formula.and(.or(x.t, x.u), .not(x.f)).evaluate(in: x.m), .holds)
    }

    /// 真值分量可交換（reason 的左偏是已記錄行為，見 `kleeneAnd` 的 doc）。
    func testTruthComponentIsCommutative() throws {
        let x = try triple()
        func bare(_ t: TruthValue) -> Int {
            switch t { case .holds: return 1; case .fails: return 0; case .undetermined: return 2 }
        }
        for (a, b) in [(x.t, x.u), (x.f, x.u), (x.t, x.f)] {
            XCTAssertEqual(bare(try Formula.and(a, b).evaluate(in: x.m)),
                           bare(try Formula.and(b, a).evaluate(in: x.m)))
            XCTAssertEqual(bare(try Formula.or(a, b).evaluate(in: x.m)),
                           bare(try Formula.or(b, a).evaluate(in: x.m)))
        }
    }

    // MARK: - F6：只有 noSupportingEvidence 可被證言翻成 fails

    /// 席位把守衛從 `.undetermined(.noSupportingEvidence)` 放寬成 `.undetermined`，
    /// 53 條全綠——而那讓**根本不在 model 裡的人**得到一個「有依據的 no」。
    func testOnlyNoSupportingEvidenceCanBeUpgradedToFails() throws {
        let m = try (try plainModel([.key("other")])).attesting([try attestation()])
        let ghost = Proposition.authored(person: .key("nobody-here"), work: .key(wk))
        let t = try Formula.atom(ghost).evaluate(in: m)
        guard case .undetermined(.notProjectable) = t else {
            return XCTFail("投射不足不得被證言翻成 .fails，實際 \(t)")
        }
        let a = try YesNoQuestion(ghost).answer(in: m)
        XCTAssertEqual(a.answer, .undetermined, "不在 model 裡的人不得得到 no")
    }

    /// literal 槽的「像但不是」同樣不得被翻成 `.fails`。
    func testUnresolvedLookalikeIsNotUpgraded() throws {
        let m = try (try plainModel([.literal("Che Cheng")])).attesting([try attestation()])
        let t = try Formula.atom(p).evaluate(in: m)
        guard case .undetermined(.supportingEvidenceUnresolved) = t else {
            return XCTFail("像但沒歸戶不得被翻成 .fails，實際 \(t)")
        }
    }

    // MARK: - F7：atomKey 必須單射

    /// `authored(l:"a", l:"b,l:c")` 與 `authored(l:"a,l:b", l:"c")` 曾經編出
    /// **同一個鍵**——兩個相異命題塌成一個原子，`x ∧ ¬y` 被判成矛盾。
    func testAtomKeyIsInjective() throws {
        let x = Proposition.authored(person: .literal("a"), work: .literal("b,l:c"))
        let y = Proposition.authored(person: .literal("a,l:b"), work: .literal("c"))
        XCTAssertNotEqual(x, y)
        XCTAssertNotEqual(Formula.atomKey(x), Formula.atomKey(y), "相異命題不得同鍵")
        let f = Formula.and(.atom(x), .not(.atom(y)))
        XCTAssertEqual(f.canonicalAtoms.count, 2, "應為兩個相異原子")
        XCTAssertFalse(try f.isContradiction(), "x ∧ ¬y 不是矛盾——它們是不同的命題")
    }

    // MARK: - F8：古典層也要拒絕非法原子

    func testClassicalLayerRefusesMalformedAtoms() {
        let bad = Formula.atom(.authored(person: .key("Not A Key"), work: .key("w")))
        XCTAssertThrowsError(try bad.truthTable())
        XCTAssertThrowsError(try Formula.or(bad, .not(bad)).isTautology())
    }
}
