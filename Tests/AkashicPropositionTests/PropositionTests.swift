import XCTest
import AkashicCore
@testable import AkashicProposition

/// #198／#199／#200 的 vertical slice。
///
/// 這一層要守的不是「查得對」，是**「查不到不等於為假」**——所有測試都繞著
/// 那條線。
final class PropositionTests: XCTestCase {

    // MARK: - Fixture

    private let personKey = "cheng-che"
    private let workKey = "cheng2025identifiability"

    private func model(authorSlots: [AkashicCore.Author],
                       personNames: [String] = ["Che Cheng", "鄭澈"]) -> PropositionModel {
        var e = Entry(id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-0000000002A1")!,
                      citekey: workKey, type: "article", title: "T",
                      authors: authorSlots, date: "2025")
        e.fields = [:]
        return PropositionModel(entries: [e],
                                people: [Person(key: personKey, names: personNames)])
    }

    private var authored: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    // MARK: - #198 構造驗證

    func testMalformedKeyIsRejectedAtConstruction() {
        XCTAssertThrowsError(try Proposition.makeAuthored(
            person: .key("Not A Key"), work: .key(workKey))) { e in
            XCTAssertEqual(e as? PropositionError, .malformedKey("Not A Key"))
        }
    }

    /// **空 literal 不是「未知」，是構造錯誤。** 未知有它自己的表示（非空 literal
    /// 就是「還不知道指誰」），把空字串也算進去會讓兩個狀態混成一個。
    func testEmptyLiteralIsRejected() {
        XCTAssertThrowsError(try Proposition.makeAuthored(
            person: .literal("   "), work: .key(workKey))) { e in
            XCTAssertEqual(e as? PropositionError, .emptyLiteral)
        }
    }

    func testWellFormedPropositionIsAccepted() throws {
        let p = try Proposition.makeAuthored(person: .key(personKey), work: .literal("some title"))
        XCTAssertEqual(p.arguments.count, 2, "arity 由型別固定")
        XCTAssertEqual(p.predicateName, "authored")
    }

    /// 方向不可交換——兩者是**不同的命題**。
    func testDirectionIsPartOfIdentity() {
        let a = Proposition.authored(person: .key("a"), work: .key("b"))
        let b = Proposition.authored(person: .key("b"), work: .key("a"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - #199 投射

    func testUnresolvedSymbolIsNotProjectable() {
        let p = Proposition.authored(person: .literal("Che Cheng"), work: .key(workKey))
        XCTAssertEqual(p.project(in: model(authorSlots: [.key(personKey)])),
                       .unprojectable(.unresolvedSymbol(role: "person", literal: "Che Cheng")))
    }

    func testUnknownIdentityIsNotProjectable() {
        let p = Proposition.authored(person: .key("nobody"), work: .key(workKey))
        XCTAssertEqual(p.project(in: model(authorSlots: [])),
                       .unprojectable(.unknownIdentity(role: "person", key: "nobody")))
    }

    /// 把 work 放進 person 的位置——**這條證明方向是有意義的**，而且錯誤訊息要
    /// 指出真正的問題（型別不對），不是語意較弱的「找不到」。
    func testReversedArgumentsReportWrongEntityKind() {
        let reversed = Proposition.authored(person: .key(workKey), work: .key(personKey))
        XCTAssertEqual(reversed.project(in: model(authorSlots: [])),
                       .unprojectable(.wrongEntityKind(role: "person", key: workKey, expected: "person")))
    }

    func testFullyResolvedProjects() {
        guard case .projected = authored.project(in: model(authorSlots: [.key(personKey)])) else {
            return XCTFail("兩個符號都有 identity，應該投射得出來")
        }
    }

    // MARK: - 核心不變式：投射不足 → 不宣稱真值

    func testUnprojectableNeverClaimsTruth() {
        for p in [Proposition.authored(person: .literal("X"), work: .key(workKey)),
                  Proposition.authored(person: .key("nobody"), work: .key(workKey)),
                  Proposition.authored(person: .key(personKey), work: .key("no-such-work"))] {
            let t = p.evaluate(in: model(authorSlots: [.key(personKey)]))
            guard case .undetermined(.notProjectable) = t else {
                return XCTFail("投射不足卻宣稱了真值：\(t)")
            }
        }
    }

    func testSupportingEvidenceHolds() {
        XCTAssertEqual(authored.evaluate(in: model(authorSlots: [.key(personKey)])), .holds)
    }

    /// 作者槽是 literal 且字面對得上——**「像」不是「是」**。這要回未定，而且
    /// 原因要帶得出那個 literal，否則使用者無從判斷該不該去歸戶。
    func testLookalikeLiteralIsUndeterminedNotTrue() {
        let t = authored.evaluate(in: model(authorSlots: [.literal("Che Cheng")]))
        XCTAssertEqual(t, .undetermined(.supportingEvidenceUnresolved(literal: "Che Cheng")))
    }

    /// **本模組的中心主張。** 名單裡沒有他 → 未定，**不是為假**。
    ///
    /// store 不是封閉世界：作者槽可能還沒歸戶、可能匯入來源只給了前三位、可能
    /// 別名沒對上。「找不到」只支持未定。
    func testAbsenceIsUndeterminedNotFalse() {
        let t = authored.evaluate(in: model(authorSlots: [.key("someone-else")]))
        XCTAssertEqual(t, .undetermined(.noSupportingEvidence))
        XCTAssertNotEqual(t, .fails, "查不到不等於為假")
    }

    /// **誠實邊界，用測試釘住**：`authored` 目前**沒有任何輸入**會回 `.fails`。
    ///
    /// `.fails` 需要正面反證，而 store 沒有欄位能表達「這篇的作者名單已完備」。
    /// 型別留著 `.fails` 是因為答案空間需要它可被表達；規則產生不了它，是模型的
    /// 真實極限。哪天加了「名單完備」的證言型別，這條會紅——那時該連同 doc 一起改。
    func testAuthoredNeverReturnsFails() {
        let cases: [[AkashicCore.Author]] = [
            [], [.key(personKey)], [.key("other")], [.literal("Che Cheng")], [.literal("Someone")],
        ]
        for slots in cases {
            XCTAssertNotEqual(authored.evaluate(in: model(authorSlots: slots)), .fails,
                              "slots=\(slots) 產生了 .fails——若這是刻意的，doc 與本測試要一起改")
        }
    }

    // MARK: - #200 答案空間

    /// yes/no 問句有**三個**答案。少掉未定，問句就退化成「有沒有查到」。
    func testAnswerSpaceIncludesUndetermined() {
        let q = YesNoQuestion(authored)
        XCTAssertEqual(q.answerSpace, [.yes, .no, .undetermined])
        XCTAssertEqual(Set(q.answerSpace).count, 3, "互斥")
        XCTAssertEqual(Set(YesNoQuestion.Answer.allCases), Set(q.answerSpace), "窮盡")
    }

    func testAnswerMapsTruthWithoutFlattening() {
        XCTAssertEqual(YesNoQuestion(authored)
            .answer(in: model(authorSlots: [.key(personKey)])).answer, .yes)
        XCTAssertEqual(YesNoQuestion(authored)
            .answer(in: model(authorSlots: [])).answer, .undetermined)
    }

    // MARK: - 保存 ≠ 接受

    private func assertion(_ stance: Stance) -> Assertion {
        Assertion(proposition: authored, stance: stance,
                  source: "conversation", recorded: "2026-08-09")
    }

    func testAdjudicationRefusesUndetermined() {
        XCTAssertThrowsError(try adjudicate(assertion(.asserted),
                                            in: model(authorSlots: []),
                                            acceptedBy: "che", acceptedAt: "2026-08-09")) { e in
            guard case .notEstablished(.undetermined) = e as? AdjudicationRefusal else {
                return XCTFail("未定必須被拒絕，實際：\(e)")
            }
        }
    }

    /// **提問不得升格為主張。** 把一個問句記進系統，不能讓它的主題命題變成被接受。
    func testQuestionedStanceCannotBecomeFact() {
        for s in [Stance.questioned, .denied] {
            XCTAssertThrowsError(try adjudicate(assertion(s),
                                                in: model(authorSlots: [.key(personKey)]),
                                                acceptedBy: "che", acceptedAt: "2026-08-09")) { e in
                XCTAssertEqual(e as? AdjudicationRefusal, .stanceIsNotAssertion(s))
            }
        }
    }

    func testAdjudicationAcceptsEstablishedAssertion() throws {
        let f = try adjudicate(assertion(.asserted), in: model(authorSlots: [.key(personKey)]),
                               acceptedBy: "che", acceptedAt: "2026-08-09")
        XCTAssertEqual(f.proposition, authored)
        XCTAssertEqual(f.basis.stance, .asserted)
        XCTAssertEqual(f.acceptedBy, "che")
    }
}
