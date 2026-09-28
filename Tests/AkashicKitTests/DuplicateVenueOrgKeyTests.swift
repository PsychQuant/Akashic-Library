import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicExport

/// #669：兩筆 venue（或兩筆 organization）持有同一個 key 時，store 沒有任何面報它，而讀取端以
/// `Dictionary(uniqueKeysWithValues:)` 建查找表的地方會 trap（`export-bib`、CSL、Projection）。
///
/// 處置比照 citekey／person key：`crossRecordIssues` 報 error（三個面都看得到，改名與合併也先停下）；
/// 讀取端的查找表留第一筆、不 trap；以 key 定位的寫入面拒絕。
final class DuplicateVenueOrgKeyTests: XCTestCase {

    private func twins<T>(_ make: () -> T) -> [T] { [make(), make()] }

    func testDuplicateVenueAndOrganizationKeysAreCrossRecordErrors() {
        let load = LibraryLoad(entries: [], people: [],
                               organizations: twins { Organization(key: "iss", id: UUID()) },
                               venues: twins { Venue(key: "psychometrika", type: .periodical) })
        let errors = load.crossRecordIssues().filter { $0.severity == .error }.map(\.message)
        XCTAssertTrue(errors.contains { $0.hasPrefix("venue key「psychometrika」重複") }, "\(errors)")
        XCTAssertTrue(errors.contains { $0.hasPrefix("organization key「iss」重複") }, "\(errors)")
    }

    /// 不同 kind 共用一個 key 不是重複：venue 與 organization 各有自己的 key 空間（live store 有 2 個這樣的 key）。
    func testSameKeyAcrossKindsIsNotADuplicate() {
        let load = LibraryLoad(entries: [], people: [],
                               organizations: [Organization(key: "apa")],
                               venues: [Venue(key: "apa", type: .periodical)])
        XCTAssertTrue(load.crossRecordIssues().isEmpty, "\(load.crossRecordIssues().map(\.message))")
    }

    /// 匯出不 trap：重複的 person／organization／venue key 都在同一次匯出裡。trap 會讓整個 test process 崩潰——
    /// 所以這支測試的「通過」就是「跑完」。
    func testExportsDoNotTrapOnDuplicateKeys() throws {
        var e = Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle, title: "T", date: "2020")
        e.authors = [.key("wang-p"), .organization("iss")]
        e.venues = [.key("psychometrika")]
        let people = twins { Person(key: "wang-p", names: PersonNames(variant: ["Wang, P."])) }
        let orgs = twins { Organization(key: "iss", id: UUID()) }
        let venues = twins { Venue(key: "psychometrika", type: .periodical) }
        let bib = BibExport.bibFile(entries: [e], people: people, organizations: orgs, venues: venues)
        XCTAssertTrue(bib.contains("a2020x"))
        _ = BibExport.apa7Report(entries: [e], people: people, organizations: orgs, venues: venues)
        let csl = try CSLExport.cslJSON(entries: [e], people: people, organizations: orgs, venues: venues)
        XCTAssertTrue(csl.contains("a2020x"))
    }

    // MARK: - 守衛：以 store key 建的查找表不得用 `uniqueKeysWithValues`

    /// 掃 `Sources/`：`Dictionary(uniqueKeysWithValues:)` 的來源若以 store key（`$0.key`／`$0.citekey`）或
    /// 消毒後的字串（`displaySafe…`，截斷不是單射）當鍵，一次重複就 trap。唯一的例外是由生成器發、生成即唯一的
    /// ref（AkashicService 的 `people`，那裡的註解寫著理由）——它的鍵不是這兩種，所以不在掃描的前件裡。
    func testNoStoreKeyLookupTableTrapsOnDuplicates() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var offenders: [String] = []
        var scannedSites = 0
        let walker = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        while let rel = walker.nextObject() as? String {
            guard rel.hasSuffix(".swift") else { continue }
            let lines = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            func code(_ l: String) -> String { l.range(of: "//").map { String(l[..<$0.lowerBound]) } ?? l }
            for (i, line) in lines.enumerated() where code(line).contains("uniqueKeysWithValues:") {
                scannedSites += 1
                // 這一行加上後兩行（多行的 `Dictionary(uniqueKeysWithValues:\n  xs.map { … })`）
                let statement = lines[i..<min(i + 3, lines.count)].map(code).joined(separator: " ")
                if statement.contains("$0.key") || statement.contains("$0.citekey") || statement.contains("displaySafe") {
                    offenders.append("\(rel):\(i + 1)：\(code(line).trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertGreaterThan(scannedSites, 0, "一個 uniqueKeysWithValues 都沒掃到——掃描壞了，不是沒有違規")
        XCTAssertTrue(offenders.isEmpty,
                      "以 store key 或消毒後字串為鍵的 uniqueKeysWithValues 會在重複時 trap（#669）；改成"
                      + " `uniquingKeysWith: { first, _ in first }`（消毒的鍵先依原始鍵排序）：\n"
                      + offenders.joined(separator: "\n"))
    }
}
