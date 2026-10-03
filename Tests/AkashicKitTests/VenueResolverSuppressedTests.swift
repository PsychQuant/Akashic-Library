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
                                     venueKey: "psychometrika", rejectedLiterals: ["Psychometrika"], rejectedLiteralsTotal: 1),
            VenueSuppressedCandidate(citekey: "x2025", venueIndex: 2, literal: "psychometrika",
                                     venueKey: "psychometrika", rejectedLiterals: ["Psychometrika"], rejectedLiteralsTotal: 1),
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

    // MARK: - #712 R1 verify 第 0／1 列：成本要線性

    /// `psychometrika` 的大小寫變體：13 個字母，2^13 個彼此不同、`matchingKey` 全同的拼法。
    private func variant(_ i: Int) -> String {
        String("psychometrika".enumerated().map { j, c in (i >> j) & 1 == 1 ? Character(c.uppercased()) : c })
    }

    /// N 條邊共用同一組 K 個被否決拼法時，每列至多帶 `suppressedLiteralsPerRow` 個、另記總數。第一版每列存全部 K 個
    /// （記憶體 N×K）並各排序一次（N×K log K）——真 binary 在 N=K=4000 量到 16.9 秒、306 MB。截到 5 是在 **resolver** 裡，
    /// 不是在 payload：這裡直接讀 report，所以第一版在這裡會看到 K 個。
    func testEachRowCarriesAtMostTheCapEvenWhenManySpellingsWereRejected() {
        let k = 200, n = 50
        let rejected = Set((0..<k).map { rejection("x2025", variant($0)) })
        XCTAssertEqual(rejected.count, k, "前提：K 個拼法彼此不同")
        let report = VenueResolver.resolve(entries: [entry("x2025", (k..<(k + n)).map(variant))], venues: [venue],
                                           rejected: rejected)
        XCTAssertEqual(report.candidates, [], "抑制不變")
        XCTAssertEqual(report.suppressed.count, n)
        let expected = Array((0..<k).map(variant).sorted().prefix(VenueResolver.suppressedLiteralsPerRow))
        for row in report.suppressed {
            XCTAssertEqual(row.rejectedLiterals.count, VenueResolver.suppressedLiteralsPerRow, "每列的陣列長度有上界，與 K 無關")
            XCTAssertEqual(row.rejectedLiterals, expected, "依字串排序的前幾個")
            XCTAssertEqual(row.rejectedLiteralsTotal, k, "總數照實說")
        }
    }

    /// 被否決的拼法少於上限時不補、總數等於陣列長度（payload 據此不帶 `rejectedLiteralsTotal`）。
    func testFewRejectedSpellingsAreAllShownAndTheTotalMatches() {
        let report = VenueResolver.resolve(entries: [entry("x2025", [variant(5)])], venues: [venue],
                                           rejected: [rejection("x2025", variant(1)), rejection("x2025", variant(2))])
        XCTAssertEqual(report.suppressed.map(\.rejectedLiterals), [[variant(1), variant(2)].sorted()])
        XCTAssertEqual(report.suppressed.map(\.rejectedLiteralsTotal), [2])
    }

    /// apply／reject 腿不讀 `suppressed`，所以不組它（R1 verify 第 0 列）；candidates 與 ambiguities 不受影響。
    /// R2（#712 R2 verify 第 15 列）：上一版的分身叫 `Psychometrika 2`，`matchingKey` 與 `Psychometrika` 不同，兩個 report 的
    /// `ambiguities` 都是空的——那個斷言比的是 `[]` 與 `[]`。現在分身與 `psychometrika` 同名（真的歧義），被壓住的那條邊在
    /// 第三個 venue 上（歧義一向不被抑制，所以被壓住的列不能與歧義共用同一個名字）。
    func testNotReportingSuppressedLeavesCandidatesAndAmbiguitiesUnchanged() {
        let twin = Venue(key: "psychometrika-2", type: .periodical,
                         names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: [])
        let methods = Venue(key: "psychological-methods", type: .periodical,
                            names: Timeline([TemporalValue(value: "Psychological Methods")]), authorized: [])
        let entries = [entry("x2025", ["Psychological Methods", "PSYCHOLOGICAL METHODS"]),
                       entry("y2026", ["Psychometrika"]),
                       entry("z2027", ["psychological methods"])]
        let rejected: Set = [rejection("x2025", "Psychological Methods", venue: "psychological-methods")]
        let venues = [venue, twin, methods]
        let listing = VenueResolver.resolve(entries: entries, venues: venues, rejected: rejected)
        let writeLeg = VenueResolver.resolve(entries: entries, venues: venues, rejected: rejected,
                                             reportingSuppressed: false)
        XCTAssertEqual(listing.suppressed.map { "\($0.citekey):\($0.venueIndex)" }, ["x2025:1"], "前提：列表腿有一列")
        XCTAssertEqual(listing.ambiguities.map(\.citekey), ["y2026"], "前提：真的有一個歧義")
        XCTAssertEqual(listing.candidates.map(\.rowID), ["z2027:0"], "前提：真的有一個候選")
        XCTAssertEqual(writeLeg.suppressed, [])
        XCTAssertEqual(writeLeg.candidates, listing.candidates)
        XCTAssertEqual(writeLeg.ambiguities, listing.ambiguities)
    }

    // MARK: - #712 R2 verify 第 3 列：`shown` 是每個否決鍵一份的快取

    /// 三個 (work, venue) 否決鍵各有不同的被否決拼法、各至少一條被壓住的邊：兩個鍵同 venue 不同 work（a2020、b2021），
    /// 兩個鍵同 work 不同 venue（c2022）。每一列帶的必須是壓住**它自己那個鍵**的拼法與總數。
    /// R1 的快取在第一次有列需要時才排序、之後各列共用——它若被寫成整個函式共用一份（或只以 work、只以 venue 為鍵），
    /// 第二列起帶的就是別的鍵的拼法，而 R1 的十個測試全綠（每個情境只有一個否決鍵有被壓住的列）。
    func testEachRejectedKeyReportsItsOwnSpellingsAndTotal() {
        let methods = Venue(key: "psychological-methods", type: .periodical,
                            names: Timeline([TemporalValue(value: "Psychological Methods")]), authorized: [])
        let bSpellings = ["PSYCHOMETRIKA", "PsychometrikA"]
        let cMethodsSpellings = ["Psychological Methods", "PSYCHOLOGICAL METHODS", "Psychological methods"]
        var rejected: Set<ResolutionPairing> = [rejection("a2020", "Psychometrika"), rejection("c2022", "PSYCHOMETRIKA")]
        for s in bSpellings { rejected.insert(rejection("b2021", s)) }
        for s in cMethodsSpellings { rejected.insert(rejection("c2022", s, venue: "psychological-methods")) }
        let report = VenueResolver.resolve(
            entries: [entry("a2020", ["PSYCHOMETRIKA"]), entry("b2021", ["psychometrika"]),
                      entry("c2022", ["Psychometrika", "psychological methods"])],
            venues: [venue, methods], rejected: rejected)
        XCTAssertEqual(report.candidates, [], "四條邊都被壓住——抑制不變")
        XCTAssertEqual(report.suppressed, [
            VenueSuppressedCandidate(citekey: "a2020", venueIndex: 0, literal: "PSYCHOMETRIKA", venueKey: "psychometrika",
                                     rejectedLiterals: ["Psychometrika"], rejectedLiteralsTotal: 1),
            VenueSuppressedCandidate(citekey: "b2021", venueIndex: 0, literal: "psychometrika", venueKey: "psychometrika",
                                     rejectedLiterals: bSpellings.sorted(), rejectedLiteralsTotal: 2),
            VenueSuppressedCandidate(citekey: "c2022", venueIndex: 0, literal: "Psychometrika", venueKey: "psychometrika",
                                     rejectedLiterals: ["PSYCHOMETRIKA"], rejectedLiteralsTotal: 1),
            VenueSuppressedCandidate(citekey: "c2022", venueIndex: 1, literal: "psychological methods",
                                     venueKey: "psychological-methods",
                                     rejectedLiterals: cMethodsSpellings.sorted(), rejectedLiteralsTotal: 3),
        ], "每一列帶的是它自己那個 (work, venue) 鍵的拼法")
    }

    // MARK: - #712 R2 verify 第 10 列：apply／reject 腿不組 `suppressed`

    /// 效能修正的一半住在呼叫端的一個引數上：apply／reject 腿傳 `reportingSuppressed: false`。翻回 `true` 不會讓任何輸出改變
    /// （那兩條腿不讀 `suppressed`），只有 CPU 與記憶體退步，所以行為測試抓不到。源碼掃描釘住 `Sources/` 裡每個
    /// `VenueResolver.resolve(` 都**顯式**傳這個引數，而且值恰是這兩個：apply＋reject 組合腿的前置列表傳 `false`；
    /// 主路徑傳「apply 與 reject 都空」（只有列表腿是真）。新增呼叫點時這裡會紅——那時決定它是不是列表腿，再改這張清單。
    func testWriteLegsPassReportingSuppressedFalse() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = repo.appendingPathComponent("Sources")
        var values: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != "VenueResolver.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            var rest = Substring(text)
            while let r = rest.range(of: "VenueResolver.resolve(") {
                var depth = 1, i = r.upperBound
                while i < rest.endIndex, depth > 0 {
                    if rest[i] == "(" { depth += 1 } else if rest[i] == ")" { depth -= 1 }
                    i = rest.index(after: i)
                }
                let args = rest[r.upperBound..<rest.index(before: i)]
                if let label = args.range(of: "reportingSuppressed:") {
                    values.append(args[label.upperBound...].split(whereSeparator: \.isWhitespace).joined(separator: " "))
                } else {
                    values.append("（沒有顯式傳 reportingSuppressed：\(url.lastPathComponent)）")
                }
                rest = rest[i...]
            }
        }
        XCTAssertEqual(values.sorted(), ["(apply ?? []).isEmpty && (reject ?? []).isEmpty", "false"].sorted(),
                       "apply＋reject 組合腿傳 false、主路徑只在列表腿為真")
    }
}
