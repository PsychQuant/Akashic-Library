import XCTest
@testable import AkashicCore
@testable import AkashicEntity

final class EntityTests: XCTestCase {
    private let people = [
        Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"]),
        Person(key: "chen-chun-houh", names: ["Chun-Houh Chen", "陳君厚"]),
    ]

    private func entry(_ citekey: String, authors: [Author]) -> Entry {
        Entry(id: UUID(), citekey: citekey, type: "article", title: "T", authors: authors)
    }

    func testExactAliasMatchYieldsCandidate() {
        let entries = [entry("a2020b", authors: [.literal("Che Cheng")])]
        let candidates = PersonResolver.candidates(entries: entries, people: people, rejected: [], confirmed: [:])
        XCTAssertEqual(candidates, [ResolutionCandidate(
            citekey: "a2020b", authorIndex: 0, literal: "Che Cheng",
            personKey: "cheng-che", reason: "alias 完全命中", tier: .exact)])
    }

    func testMatchIsCaseAndWhitespaceInsensitive() {
        let entries = [entry("a2020b", authors: [.literal("  che   cheng ")])]
        let candidates = PersonResolver.candidates(entries: entries, people: people, rejected: [], confirmed: [:])
        XCTAssertEqual(candidates.first?.personKey, "cheng-che")
    }

    func testCJKAliasMatches() {
        let entries = [entry("a2020b", authors: [.literal("陳君厚")])]
        let candidates = PersonResolver.candidates(entries: entries, people: people, rejected: [], confirmed: [:])
        XCTAssertEqual(candidates.first?.personKey, "chen-chun-houh")
    }

    func testNoMatchYieldsNothing() {
        let entries = [entry("a2020b", authors: [.literal("Somebody Else")])]
        XCTAssertTrue(PersonResolver.candidates(entries: entries, people: people, rejected: [], confirmed: [:]).isEmpty)
    }

    func testAmbiguousAliasIsExcluded() {
        // 兩個人共用同名 alias → 同名不同人地雷，不出候選
        let ambiguousPeople = people + [Person(key: "cheng-che-2", names: ["Che Cheng"])]
        let entries = [entry("a2020b", authors: [.literal("Che Cheng")])]
        XCTAssertTrue(PersonResolver.candidates(entries: entries, people: ambiguousPeople, rejected: [], confirmed: [:]).isEmpty)
    }

    // MARK: - #231：歧義不再被靜默丟棄

    /// 三種結果**必須分得開**。#231 之前「沒人匹配」與「2+ 人匹配」走同一條
    /// `continue`，而後者才是有情報價值的那個——系統知道自己遇到了決定點，卻什麼
    ///都沒說。
    func testResolveDistinguishesNoMatchUniqueAndAmbiguous() {
        let ambiguousPeople = people + [Person(key: "cheng-che-2", names: ["Che Cheng"])]
        let entries = [
            entry("no2020", authors: [.literal("Nobody Here")]),      // 沒人匹配
            entry("uniq2020", authors: [.literal("陳君厚")]),          // 唯一匹配
            entry("amb2020", authors: [.literal("Che Cheng")]),       // 2+ 匹配
        ]
        let r = PersonResolver.resolve(entries: entries, people: ambiguousPeople, rejected: [], confirmed: [:])

        // 唯一命中照舊進 candidates
        XCTAssertEqual(r.candidates.map(\.citekey), ["uniq2020"])

        // **2+ 命中現在被回報**，且帶齊定位資訊與所有候選
        XCTAssertEqual(r.ambiguities.count, 1, "歧義必須被回報，不能靜默丟棄")
        XCTAssertEqual(r.ambiguities.first?.citekey, "amb2020")
        XCTAssertEqual(r.ambiguities.first?.authorIndex, 0)
        XCTAssertEqual(r.ambiguities.first?.literal, "Che Cheng")
        XCTAssertEqual(r.ambiguities.first?.personKeys, ["cheng-che", "cheng-che-2"],
                       "personKeys 必須排序——同一份 store 兩次執行要給同一份報告")

        // 「沒人匹配」**刻意不回報**：那是 `.literal` 的合法長期狀態。全部報出來會讓
        // 報告被噪音淹沒，而被淹沒的報告等於沒有報告。
        XCTAssertFalse(r.ambiguities.contains { $0.citekey == "no2020" })
    }

    /// `candidates` 是 `resolve` 的薄包裝——**不是第二支遍歷**。
    ///
    /// #140 的教訓：bootstrap 與 resolver 各留一份正規化，分裂後主流程對連字號變體
    /// 從 2 候選掉到 0、完全靜默。兩支遍歷會分岔，而分岔的方式是安靜的。
    func testCandidatesIsExactlyResolveCandidates() {
        let ambiguousPeople = people + [Person(key: "cheng-che-2", names: ["Che Cheng"])]
        let entries = [
            entry("a2020b", authors: [.literal("Che Cheng"), .literal("陳君厚")]),
            entry("c2021d", authors: [.literal("鄭澈")]),
        ]
        XCTAssertEqual(PersonResolver.candidates(entries: entries, people: ambiguousPeople, rejected: [], confirmed: [:]),
                       PersonResolver.resolve(entries: entries, people: ambiguousPeople, rejected: [], confirmed: [:]).candidates)
    }

    /// 「歧義只有一個候選」在型別層不可表達。
    func testAmbiguousMatchRefusesFewerThanTwoKeys() {
        XCTAssertNil(AmbiguousMatch(entryID: UUID(), citekey: "a", authorIndex: 0, literal: "X", personKeys: [], tier: .exact))
        XCTAssertNil(AmbiguousMatch(entryID: UUID(), citekey: "a", authorIndex: 0, literal: "X", personKeys: ["one"], tier: .exact))
        XCTAssertNotNil(AmbiguousMatch(entryID: UUID(), citekey: "a", authorIndex: 0, literal: "X",
                                       personKeys: ["one", "two"], tier: .exact))
    }

    func testResolvedKeyAuthorsAreNotCandidates() {
        let entries = [entry("a2020b", authors: [.key("cheng-che")])]
        XCTAssertTrue(PersonResolver.candidates(entries: entries, people: people, rejected: [], confirmed: [:]).isEmpty)
    }

    func testApplyConvertsOnlyListedCandidates() {
        let e = entry("a2020b", authors: [.literal("Che Cheng"), .literal("Somebody Else")])
        let candidates = PersonResolver.candidates(entries: [e], people: people, rejected: [], confirmed: [:])
        let applied = PersonResolver.apply(candidates, to: [e])
        XCTAssertEqual(applied.first?.authors,
                       [.key("cheng-che"), .literal("Somebody Else")])
    }
}
