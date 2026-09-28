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

    // MARK: - 守衛：每個 `uniqueKeysWithValues` 都要寫明鍵為何唯一

    /// 掃 `Sources/`：`Dictionary(uniqueKeysWithValues:)` 遇到重複鍵是 precondition trap，以 store key 或消毒後的
    /// 字串（截斷不是單射）當鍵，一次重複就讓整個 process 崩潰（#669）。每個呼叫點都要在前四行內寫一句
    /// `unique-keys: <理由>`；寫不出理由的改用 `uniquingKeysWith`。守衛只驗那句話在不在，不驗理由對不對——
    /// 理由由寫的人負責（`zero-instance-guards` 第 7 列的形：通過是必要條件，不是證明）。
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
                // 每個呼叫點都要在前四行內寫一句 `unique-keys: <鍵為何唯一>`（#669 R1 verify）。先前只找
                // `$0.key`／`$0.citekey`／`displaySafe` 三種字面：具名 closure 參數（`{ v in (v.key, v) }`）、
                // KeyPath（`map(\.key)`）、超過三行的多行寫法都掃不到，而本 repo 三種寫法都在用。
                // 改成白名單之後，新呼叫點不論怎麼寫都得有人說明鍵為何唯一。
                let context = lines[max(0, i - 4)...i].joined(separator: " ")
                if !context.contains("unique-keys:") {
                    offenders.append("\(rel):\(i + 1)：\(code(line).trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertGreaterThan(scannedSites, 0, "一個 uniqueKeysWithValues 都沒掃到——掃描壞了，不是沒有違規")
        XCTAssertTrue(offenders.isEmpty,
                      "uniqueKeysWithValues 在重複鍵時 trap（#669）；鍵不保證唯一就改成"
                      + " `uniquingKeysWith: { first, _ in first }`（消毒的鍵先依原始鍵排序），"
                      + "保證唯一就在前四行內寫一句 `// unique-keys: <理由>`：\n"
                      + offenders.joined(separator: "\n"))
    }
}
