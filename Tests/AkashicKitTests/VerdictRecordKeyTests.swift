import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// change `resolution-verdict-states`：verdict 的三把鍵與判定層級（spec「Verdict identity SHALL be defined by three named keys」
/// 「Confirmed and rejected verdicts SHALL belong to one of two judgement classes」）。
final class VerdictRecordKeyTests: XCTestCase {

    private func value(_ literal: String, holder: String = "chen2020a") -> String {
        ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: holder, literal: literal).encoded
    }
    private func verdict(_ field: String, _ literal: String, rule: String?,
                         statement: String = "理由", restsOn: [String] = []) -> ProvenanceReference {
        let s = rule.map { "\(statement) [rule: \($0)]" } ?? statement
        return ProvenanceReference(field: field, value: value(literal), kind: .judgement(statement: s, restsOn: restsOn))
    }
    private let confirmed = "resolution-confirmed"
    private let rejected = "resolution-rejected"
    private let undecided = "resolution-undecided"
    private let digest = "sha256:" + String(repeating: "a", count: 64)

    // MARK: - 判定層級（封閉二值）

    func testClassIsJudgedOnlyForTheTwoNamedRules() {
        XCTAssertEqual(ProvenanceReference.verdictClass(rule: "author-judged-per-work"), .judged)
        XCTAssertEqual(ProvenanceReference.verdictClass(rule: "author-organization-judged"), .judged)
        for r in ["author-name-exact", "author-name-initials", "author-name-confirmed-elsewhere",
                  "venue-name-exact", "org-name-exact", "author-judged", "judged", "非標準"] {
            XCTAssertEqual(ProvenanceReference.verdictClass(rule: r), .nominated, r)
        }
        XCTAssertEqual(ProvenanceReference.judgedRules.count, 2, "封閉列舉：兩個，不得類推第三個")
    }

    func testLegacyVerdictWithoutRuleTailIsNominated() {
        XCTAssertEqual(verdict(confirmed, "C.-H. Chen", rule: nil).verdictClass, .nominated)
        XCTAssertEqual(ProvenanceReference.verdictClass(rule: nil), .nominated)
    }

    func testUndecidedHasNoClass() {
        XCTAssertNil(verdict(undecided, "C.-H. Chen", rule: "checked-undecided").verdictClass)
    }

    // MARK: - 記錄鍵（spec 的 Record-key equality 表）

    func testSameClassWhitespaceVariantIsTheSameRecord() {
        XCTAssertEqual(verdict(confirmed, "C.-H. Chen", rule: "author-name-exact").verdictRecordKey,
                       verdict(confirmed, "C.-H.  Chen", rule: "author-name-exact").verdictRecordKey)
    }

    func testNominatedAndJudgedAreDistinctRecords() {
        XCTAssertNotEqual(verdict(confirmed, "C.-H. Chen", rule: "author-name-exact").verdictRecordKey,
                          verdict(confirmed, "C.-H. Chen", rule: "author-judged-per-work").verdictRecordKey)
        XCTAssertNotEqual(verdict(rejected, "C.-H. Chen", rule: "author-name-exact").verdictRecordKey,
                          verdict(rejected, "C.-H. Chen", rule: "author-judged-per-work").verdictRecordKey)
    }

    func testTwoNominatedTiersAreTheSameRecord() {
        XCTAssertEqual(verdict(confirmed, "C.-H. Chen", rule: "author-name-exact").verdictRecordKey,
                       verdict(confirmed, "C.-H. Chen", rule: "author-name-initials").verdictRecordKey,
                       "層級是二值：不同 tier 的 apply 不得累積成多筆")
    }

    func testUndecidedChecksWithDifferentStatementsAreDistinct() {
        XCTAssertNotEqual(verdict(undecided, "C.-H. Chen", rule: "checked-undecided", statement: "查了機構欄").verdictRecordKey,
                          verdict(undecided, "C.-H. Chen", rule: "checked-undecided", statement: "查了共同作者").verdictRecordKey)
        XCTAssertNotEqual(verdict(undecided, "C.-H. Chen", rule: "checked-undecided").verdictRecordKey,
                          verdict(undecided, "C.-H. Chen", rule: "checked-undecided", restsOn: [digest]).verdictRecordKey,
                          "只差 rests-on 也是兩次查證")
    }

    func testIdenticalUndecidedIsTheSameRecord() {
        XCTAssertEqual(verdict(undecided, "C.-H. Chen", rule: "checked-undecided", restsOn: [digest]).verdictRecordKey,
                       verdict(undecided, "C.-H. Chen", rule: "checked-undecided", restsOn: [digest]).verdictRecordKey)
    }

    func testUndecidedNeverCollidesWithADecision() {
        let u = verdict(undecided, "C.-H. Chen", rule: "checked-undecided").verdictRecordKey
        XCTAssertNotEqual(u, verdict(confirmed, "C.-H. Chen", rule: "checked-undecided").verdictRecordKey)
        XCTAssertNotEqual(u, verdict(rejected, "C.-H. Chen", rule: "checked-undecided").verdictRecordKey)
    }

    // MARK: - 配對鍵

    func testPairingKeyIgnoresFieldAndClass() {
        let k = ProvenanceReference.verdictPairingKey(value: value("C.-H. Chen"))
        XCTAssertNotNil(k)
        XCTAssertEqual(k, ProvenanceReference.verdictPairingKey(value: value("C.-H.  Chen")))
        XCTAssertNotEqual(k, ProvenanceReference.verdictPairingKey(value: value("C.-H. Chen", holder: "chen2021b")))
        XCTAssertNil(ProvenanceReference.verdictPairingKey(value: "garbage"))
        XCTAssertNil(ProvenanceReference.verdictPairingKey(value: nil))
    }

    // MARK: - 寫入去重

    func testAppendIfAbsentKeepsBothClassesAndDedupsWithinOne() {
        var refs: [ProvenanceReference] = []
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(verdict(confirmed, "C.-H. Chen", rule: "author-name-exact"), to: &refs))
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(verdict(confirmed, "C.-H. Chen", rule: "author-judged-per-work"), to: &refs),
                      "#636：逐篇判定與 apply 並存")
        XCTAssertFalse(ResolutionLedger.appendIfAbsent(verdict(confirmed, "C.-H.  Chen", rule: "author-judged-per-work",
                                                               statement: "另一句"), to: &refs),
                       "同層級只差空白仍是同一筆（#470）")
        XCTAssertEqual(refs.count, 2)
    }
}
