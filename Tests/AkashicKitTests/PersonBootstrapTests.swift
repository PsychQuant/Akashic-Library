import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicEntity

/// #34：從 literal 作者 bootstrap person 記錄。
final class PersonBootstrapTests: XCTestCase {

    private func entry(_ ck: String, _ authors: [String]) -> Entry {
        Entry(id: UUID(), citekey: ck, type: "article", title: "T",
              authors: authors.map { .literal($0) }, date: "2020")
    }

    // MARK: - 安全方向：寧可分割，絕不合併

    /// **機械可判的重排才合併。** `Last, First` ↔ `First Last` 是字串操作，不是猜測。
    func testReorderedFormsMergeIntoOneCandidate() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"]), entry("b", ["Cheng, Che"])], existing: [])
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(cs[0].names.sorted(), ["Che Cheng", "Cheng, Che"])
        XCTAssertEqual(cs[0].occurrences, 2)
    }

    /// **縮寫不與全名合併。** `Cheng, C` 看起來像 `Cheng, Che`，但也可能是 `Cheng, Chao`。
    /// 過度合併不可回復——兩個人被併成一個，區別就此消失且沒有任何訊號。
    func testAbbreviationDoesNotMergeWithFullName() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Cheng, Che"]), entry("b", ["Cheng, C"])], existing: [])
        XCTAssertEqual(cs.count, 2, "縮寫與全名必須分開，讓人決定：\(cs)")
    }

    /// 連字號差異不合併——`Jeng-Min` 與 `Jeng Min` 可能是同一人也可能不是，
    /// 去掉連字號就等於替人決定了。
    func testHyphenVariantsDoNotMerge() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Jeng-Min Chiou"]), entry("b", ["Jeng Min Chiou"])],
            existing: [])
        XCTAssertEqual(cs.count, 2)
    }

    /// 大小寫與空白差異**是**機械可判的，合併。
    func testCaseAndWhitespaceVariantsMerge() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Chun-Houh Chen"]), entry("b", ["chun-houh  chen"])],
            existing: [])
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(cs[0].occurrences, 2)
    }

    // MARK: - 不重複建立

    /// 已存在的 person 不再產出候選——它們的 alias 已在 `PersonResolver` 的比對範圍內，
    /// 再造一個就是在製造重複。
    func testExistingPersonIsNotProposedAgain() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"])],
            existing: [Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"])])
        XCTAssertTrue(cs.isEmpty, "\(cs)")
    }

    /// 既有 person 的**任一** alias 命中就算數（不只第一個）。
    func testAnyExistingAliasSuppresses() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Cheng, Che"])],
            existing: [Person(key: "cheng-che", names: ["鄭澈", "Che Cheng"])])
        XCTAssertTrue(cs.isEmpty, "重排形式也要被既有 alias 吸收：\(cs)")
    }

    /// 機構名（#6 的 `{...}` 標記）不是人——不建 person。
    func testCorporateNamesAreNotPeople() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", [CorporateName.mark("World Health Organization")])],
            existing: [])
        XCTAssertTrue(cs.isEmpty, "\(cs)")
    }

    // MARK: - key 生成

    func testSuggestedKeyIsSurnameFirst() {
        let cs = PersonBootstrap.candidates(entries: [entry("a", ["Yi-Hau Chen"])], existing: [])
        XCTAssertEqual(cs[0].key, "chen-yi-hau")
    }

    /// key 撞號時加序號——**不合併**。撞號代表兩個不同的名字產生同一個 slug
    /// （`Chen, Y-H` 與 `Chen, YH`），那正是需要人看的情形。
    func testKeyCollisionGetsSuffixNotMerge() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Yi-Hau Chen"]), entry("b", ["Yi Hau Chen"])], existing: [])
        XCTAssertEqual(cs.count, 2)
        XCTAssertEqual(Set(cs.map(\.key)).count, 2, "key 必須唯一：\(cs.map(\.key))")
    }

    func testKeyAvoidsExistingPersonKeys() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"])],
            existing: [Person(key: "cheng-che", names: ["別人"])])
        XCTAssertEqual(cs.count, 1)
        XCTAssertNotEqual(cs[0].key, "cheng-che", "不得與既有 key 相同")
    }

    // MARK: - 排序

    /// 出現次數多的先——處理它們的投報率最高。
    func testCandidatesSortedByOccurrence() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Rare Person"]),
                      entry("b", ["Common Person"]), entry("c", ["Common Person"])],
            existing: [])
        XCTAssertEqual(cs.map(\.occurrences), [2, 1])
    }

    /// 產出的 Person 直接可寫——names 就是這一組的所有寫法。
    func testPersonsForProducesUsableRecords() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"]), entry("b", ["Cheng, Che"])], existing: [])
        let ps = PersonBootstrap.personsFor(cs)
        XCTAssertEqual(ps.count, 1)
        XCTAssertEqual(ps[0].names.count, 2, "兩種寫法都要成為 alias")
    }
}
