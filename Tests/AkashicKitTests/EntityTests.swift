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
        let candidates = PersonResolver.candidates(entries: entries, people: people)
        XCTAssertEqual(candidates, [ResolutionCandidate(
            citekey: "a2020b", authorIndex: 0, literal: "Che Cheng",
            personKey: "cheng-che", reason: "alias 完全命中")])
    }

    func testMatchIsCaseAndWhitespaceInsensitive() {
        let entries = [entry("a2020b", authors: [.literal("  che   cheng ")])]
        let candidates = PersonResolver.candidates(entries: entries, people: people)
        XCTAssertEqual(candidates.first?.personKey, "cheng-che")
    }

    func testCJKAliasMatches() {
        let entries = [entry("a2020b", authors: [.literal("陳君厚")])]
        let candidates = PersonResolver.candidates(entries: entries, people: people)
        XCTAssertEqual(candidates.first?.personKey, "chen-chun-houh")
    }

    func testNoMatchYieldsNothing() {
        let entries = [entry("a2020b", authors: [.literal("Somebody Else")])]
        XCTAssertTrue(PersonResolver.candidates(entries: entries, people: people).isEmpty)
    }

    func testAmbiguousAliasIsExcluded() {
        // 兩個人共用同名 alias → 同名不同人地雷，不出候選
        let ambiguousPeople = people + [Person(key: "cheng-che-2", names: ["Che Cheng"])]
        let entries = [entry("a2020b", authors: [.literal("Che Cheng")])]
        XCTAssertTrue(PersonResolver.candidates(entries: entries, people: ambiguousPeople).isEmpty)
    }

    func testResolvedKeyAuthorsAreNotCandidates() {
        let entries = [entry("a2020b", authors: [.key("cheng-che")])]
        XCTAssertTrue(PersonResolver.candidates(entries: entries, people: people).isEmpty)
    }

    func testApplyConvertsOnlyListedCandidates() {
        let e = entry("a2020b", authors: [.literal("Che Cheng"), .literal("Somebody Else")])
        let candidates = PersonResolver.candidates(entries: [e], people: people)
        let applied = PersonResolver.apply(candidates, to: [e])
        XCTAssertEqual(applied.first?.authors,
                       [.key("cheng-che"), .literal("Somebody Else")])
    }
}
