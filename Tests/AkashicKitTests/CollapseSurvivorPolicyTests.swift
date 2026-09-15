import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 收攏時「留哪一筆」是裁決出來的，不是陣列順序決定的（#468）。
///
/// 收攏只在兩筆對**同一個配對**得出**同一個結論**時發生，差別只在理由。而 `rule` 尾註在
/// 下游的職責是**警告**（`PersonResolver` 的「confirmed-elsewhere 弱血統可見」）。留強丟弱
/// ＝一個確實存在的警告被靜默拿掉（假陰性，而身分誤判不可逆）；留弱丟強＝多一句提醒給
/// 一個正在做判斷的人（假陽性，一行字）。
final class CollapseSurvivorPolicyTests: XCTestCase {

    private func ref(holder: String, literal: String, rule: String,
                     statement: String = "s") -> ProvenanceReference {
        ProvenanceReference(
            field: "resolution-confirmed",
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "\(statement) [rule: \(rule)]", restsOn: []))
    }
    private func ruleOf(_ r: ProvenanceReference) -> String? {
        guard case .judgement(let s, _) = r.kind else { return nil }
        return ProvenanceReference.ruleTail(ofStatement: s)
    }
    private func collapse(_ refs: [ProvenanceReference])
        -> (refs: [ProvenanceReference], changed: Bool, collapsed: [String]) {
        LibraryStore.migrateHolderVerdicts(refs, merged: ["doomed2020a"],
                                           survivor: "keeper2020a", holderKind: .work)
    }

    private let weak = "author-name-initials"
    private let exact = ProvenanceReference.RuleName.personExact

    /// **第 1 層**：弱血統勝，**兩種排列都是**——政策不得由順序決定。
    func testWeakLineageWinsRegardlessOfOrder() {
        for (desc, refs) in [
            ("強在前", [ref(holder: "keeper2020a", literal: "A B", rule: exact),
                        ref(holder: "doomed2020a", literal: "A B", rule: weak)]),
            ("弱在前", [ref(holder: "doomed2020a", literal: "A B", rule: weak),
                        ref(holder: "keeper2020a", literal: "A B", rule: exact)]),
        ] {
            let got = collapse(refs)
            XCTAssertEqual(got.refs.count, 1, desc)
            XCTAssertEqual(ruleOf(got.refs[0]), weak,
                           "\(desc)：弱血統要留下——留強等於靜默拿掉一個確實存在的警告")
            XCTAssertEqual(got.collapsed.count, 1, desc)
        }
    }

    /// **第 2 層**：兩邊血統相同時，原本就指向 survivor 的那一筆勝（與 #271 keeper 恆勝一致）。
    func testTieOnLineageGoesToTheUnrewrittenRow() {
        for (desc, refs) in [
            ("keeper 在前", [ref(holder: "keeper2020a", literal: "A B", rule: exact, statement: "zz"),
                             ref(holder: "doomed2020a", literal: "A B", rule: exact, statement: "aa")]),
            ("keeper 在後", [ref(holder: "doomed2020a", literal: "A B", rule: exact, statement: "aa"),
                             ref(holder: "keeper2020a", literal: "A B", rule: exact, statement: "zz")]),
        ] {
            let got = collapse(refs)
            XCTAssertEqual(got.refs.count, 1, desc)
            guard case .judgement(let s, _) = got.refs[0].kind else { return XCTFail(desc) }
            XCTAssertTrue(s.hasPrefix("zz"),
                          "\(desc)：keeper 側（未被改寫）要留下，即使它的 statement 字典序較大")
        }
    }

    /// **第 3 層**：血統與改寫狀態都相同時，字典序最小——任意但**穩定且不依賴順序**。
    func testFinalTieBreakIsDeterministicAndOrderIndependent() {
        let a = ref(holder: "doomed2020a", literal: "A B", rule: weak, statement: "aaa")
        let b = ref(holder: "doomed2020a", literal: "A B", rule: weak, statement: "bbb")
        for (desc, refs) in [("aaa 在前", [a, b]), ("bbb 在前", [b, a])] {
            let got = collapse(refs)
            XCTAssertEqual(got.refs.count, 1, desc)
            guard case .judgement(let s, _) = got.refs[0].kind else { return XCTFail(desc) }
            XCTAssertTrue(s.hasPrefix("aaa"), "\(desc)：兩種排列必須得到同一個留存者")
        }
    }

    /// 沒有碰撞時什麼都不變——政策不得順手動到不相干的列。
    func testNoCollisionMeansNoPolicy() {
        let refs = [ref(holder: "doomed2020a", literal: "A B", rule: weak),
                    ref(holder: "doomed2020a", literal: "C D", rule: exact)]
        let got = collapse(refs)
        XCTAssertEqual(got.refs.count, 2)
        XCTAssertEqual(got.collapsed, [])
    }

    /// 丟棄仍然可見——政策改的是「留哪一筆」，不是「要不要報」。
    func testTheDroppedRowIsStillReported() {
        let got = collapse([ref(holder: "keeper2020a", literal: "A B", rule: exact, statement: "強的理由"),
                            ref(holder: "doomed2020a", literal: "A B", rule: weak, statement: "弱的理由")])
        XCTAssertEqual(got.collapsed.count, 1)
        XCTAssertTrue(got.collapsed[0].contains("強的理由"),
                      "被丟的是強的那筆，報告要說出它：\(got.collapsed)")
    }

    // MARK: - R17（#554 D47）：位元組不同時，倖存配對自己的那筆勝

    /// R16 verify DA 第 1 列（真 binary 重現）：第 1 層「弱血統優先」排在「未改寫者勝」之前，被併記錄那筆弱血統的 `VEE JOURNAL`
    /// 贏過倖存者自己使用者確認過的 `Vee Journal`——連**位元組**一起取代，之後 `--demote` 把邊寫成不是這筆記錄原本寫的字
    /// （`confirmedLiteral` 承諾不做的事）。#468 的弱血統優先只在**拼法位元組相同**時適用（那時留弱只多一句警告、不動任何字串）；
    /// 拼法不同時倖存配對自己的（未改寫）那筆勝，收攏列印出兩個拼法。
    func testDifferentSpellingNeverReplacesTheSurvivingPairingsOwnBytes() {
        for (desc, refs) in [
            ("強在前", [ref(holder: "keeper2020a", literal: "Vee Journal", rule: exact),
                        ref(holder: "doomed2020a", literal: "VEE JOURNAL", rule: weak)]),
            ("弱在前", [ref(holder: "doomed2020a", literal: "VEE JOURNAL", rule: weak),
                        ref(holder: "keeper2020a", literal: "Vee Journal", rule: exact)]),
        ] {
            let got = collapse(refs)
            XCTAssertEqual(got.refs.count, 1, desc)
            let kept = ProvenanceReference.VerdictPairingValue.parse(got.refs.first?.value ?? "")?.literal ?? ""
            XCTAssertEqual(Array(kept.utf8), Array("Vee Journal".utf8), "\(desc)：倖存配對自己的位元組不得被換掉（拿到 \(kept)）")
            XCTAssertEqual(ruleOf(got.refs[0]), exact, desc)
            XCTAssertEqual(got.collapsed.count, 1, desc)
            let row = got.collapsed.first ?? ""
            XCTAssertTrue(row.contains("VEE JOURNAL") && row.contains("Vee Journal") && row.contains("位元組"), "兩個拼法都要印：\(row)")
        }
        // 對照：拼法相同時 #468 的第 1 層照舊——弱血統留下
        let same = collapse([ref(holder: "keeper2020a", literal: "A B", rule: exact), ref(holder: "doomed2020a", literal: "A B", rule: weak)])
        XCTAssertEqual(ruleOf(same.refs[0]), weak)
        XCTAssertFalse((same.collapsed.first ?? "").contains("位元組"), "同拼法不印「位元組不同」：\(same.collapsed)")
    }
}
