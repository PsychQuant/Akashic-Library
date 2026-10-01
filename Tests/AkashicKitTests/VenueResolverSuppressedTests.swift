import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// #712：`VenueResolver.resolve` 的 `suppressed`——被**正規化配對**的否決壓掉的候選。
///
/// 抑制本身（#554 R12：以 `matchingKey` 為鍵）不是本檔要測的，那一半由既有的測試守；這裡釘的是：
/// 1. 報出來的集合恰好是「抑制若比逐字（R12 之前）本來會列在 `candidates`」的那一批——不多不少；
/// 2. 報出來**不改變**抑制：`candidates`／`ambiguities` 與不看 `suppressed` 時完全一樣。
final class VenueResolverSuppressedTests: XCTestCase {
    private let venue = Venue(key: "psychometrika", type: .periodical,
                              names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: [])

    private func entry(_ citekey: String, _ literals: [String]) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T", date: "2020")
        e.venues = literals.map { .literal($0) }
        return e
    }

    private func rejection(_ citekey: String, _ literal: String, venue: String = "psychometrika") -> ResolutionPairing {
        ResolutionPairing(holderKind: .work, holder: citekey, literal: literal, judgedKey: venue)
    }

    func testAnotherSpellingOfARejectedPairingIsReportedWithTheSpellingThatSuppressedIt() {
        let report = VenueResolver.resolve(
            entries: [entry("x2025", ["Psychometrika", "PSYCHOMETRIKA", "psychometrika"])],
            venues: [venue], rejected: [rejection("x2025", "Psychometrika")])
        XCTAssertEqual(report.candidates, [], "三個拼法都被壓住——抑制不變")
        XCTAssertEqual(report.suppressed, [
            VenueSuppressedCandidate(citekey: "x2025", venueIndex: 1, literal: "PSYCHOMETRIKA",
                                     venueKey: "psychometrika", rejectedLiterals: ["Psychometrika"]),
            VenueSuppressedCandidate(citekey: "x2025", venueIndex: 2, literal: "psychometrika",
                                     venueKey: "psychometrika", rejectedLiterals: ["Psychometrika"]),
        ], "逐字相等的 index 0 是普通的已否決、不在這裡；另兩個是被正規化配對壓掉的")
    }

    func testAnEqualSpellingAmongTheRejectedOnesIsTheOrdinaryCase() {
        // 同一配對有兩個拼法被否決：候選逐字等於其中之一 → 普通的已否決，即使另一個拼法也壓得住它
        let report = VenueResolver.resolve(
            entries: [entry("x2025", ["PSYCHOMETRIKA", "psychometrika"])],
            venues: [venue],
            rejected: [rejection("x2025", "Psychometrika"), rejection("x2025", "PSYCHOMETRIKA")])
        XCTAssertEqual(report.candidates, [])
        XCTAssertEqual(report.suppressed.map(\.literal), ["psychometrika"], "PSYCHOMETRIKA 自己被否決過，不報")
        XCTAssertEqual(report.suppressed.first?.rejectedLiterals, ["PSYCHOMETRIKA", "Psychometrika"],
                       "壓住它的是兩個拼法，依字串排序")
    }

    func testByteExactRejectionIsNotReported() {
        let report = VenueResolver.resolve(entries: [entry("x2025", ["Psychometrika"])], venues: [venue],
                                           rejected: [rejection("x2025", "Psychometrika")])
        XCTAssertEqual(report.candidates, [])
        XCTAssertEqual(report.suppressed, [], "列表一向不列普通的已否決，維持原樣")
    }

    func testCanonicallyEqualSpellingIsNotANarrowing() {
        // NFC 與 NFD 是同一個 Swift 字串（canonical equivalence）——R12 之前就壓得住，不是 R12 收窄出來的
        let nfc = "Caf\u{E9} Journal", nfd = "Cafe\u{301} Journal"
        XCTAssertEqual(nfc, nfd, "前提：Swift 視為相等")
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8), "前提：位元組不同")
        let cafe = Venue(key: "cafe-journal", type: .periodical,
                         names: Timeline([TemporalValue(value: "Café Journal")]), authorized: [])
        let report = VenueResolver.resolve(entries: [entry("x2025", [nfd])], venues: [cafe],
                                           rejected: [rejection("x2025", nfc, venue: "cafe-journal")])
        XCTAssertEqual(report.candidates, [])
        XCTAssertEqual(report.suppressed, [])
    }

    func testRejectionIsPerWorkPerVenue() {
        // 否決只作用於同一 work 的同一 venue：別的 work、別的 venue 的同名拼法照常是候選，也不進 suppressed
        let report = VenueResolver.resolve(
            entries: [entry("x2025", ["PSYCHOMETRIKA"]), entry("y2026", ["PSYCHOMETRIKA"])],
            venues: [venue], rejected: [rejection("x2025", "Psychometrika"),
                                        rejection("y2026", "Psychometrika", venue: "some-other-venue")])
        XCTAssertEqual(report.candidates.map(\.citekey), ["y2026"], "y2026 否決的是另一個 venue，這個配對沒被否決")
        XCTAssertEqual(report.suppressed.map(\.citekey), ["x2025"])
    }

    func testAmbiguitiesAreNeverSuppressedSoNeverReported() {
        // 抑制只作用於不歧義的提名（keys.count == 1）。對到 2+ venue 的 literal 照列在 ambiguities，不進 suppressed
        let twin = Venue(key: "psychometrika-2", type: .periodical,
                         names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: [])
        let report = VenueResolver.resolve(entries: [entry("x2025", ["PSYCHOMETRIKA"])], venues: [venue, twin],
                                           rejected: [rejection("x2025", "Psychometrika")])
        XCTAssertEqual(report.candidates, [])
        XCTAssertEqual(report.ambiguities.map(\.citekey), ["x2025"])
        XCTAssertEqual(report.suppressed, [])
    }

    func testReportingDoesNotChangeWhatIsSuppressed() {
        // 抑制不變：同一份輸入，`candidates` 恰是「沒有任何拼法被否決」的那幾條邊
        let entries = [entry("a2020", ["Psychometrika"]), entry("b2020", ["PSYCHOMETRIKA", "Psychometrika"]),
                       entry("c2020", ["psychometrika"])]
        let report = VenueResolver.resolve(entries: entries, venues: [venue], rejected: [rejection("b2020", "Psychometrika")])
        XCTAssertEqual(report.candidates.map(\.rowID), ["a2020:0", "c2020:0"])
        XCTAssertEqual(report.suppressed.map { "\($0.citekey):\($0.venueIndex)" }, ["b2020:0"],
                       "b2020 的 index 1 逐字等於被否決的拼法，普通的已否決")
        // 沒有被否決的拼法時 suppressed 是空的
        XCTAssertEqual(VenueResolver.resolve(entries: entries, venues: [venue], rejected: []).suppressed, [])
    }
}
