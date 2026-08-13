import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicEntity

/// #232 verify NEW-1/NEW-2/NEW-3：verdict 是一條**邊**不是一個值——它的生命週期
/// （舊 binary 讀到、citekey 改名、bootstrap 重建）每一站都要有防線。
///
/// - format 8 write gate：verdict 欄位對 field 白名單是 strict，舊 binary 讀到是
///   整檔 quarantine（非保留）——與 6（ended）/7（attested）同型的「看似 additive
///   其實不是」，同一套 gate 補救。
/// - rename 遷移：value 內嵌 citekey，不遷移＝否決安靜變回待判。
final class VerdictFormatGateTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vgate-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdictPerson() -> Person {
        var p = Person(key: "cheng-che", names: ["Che Cheng"])
        p.references = [ResolutionLedger.record(
            .rejected, holderKind: .work, holder: "a2020x", literal: "Che Cheng",
            rule: ResolutionLedger.personRule, statement: "s")]
        return p
    }

    /// 目前的精確 format 值（#131 verify 慣例：釘精確值防「意外多 bump 一次」，
    /// 每次刻意 bump 隨新 format 的測試搬家——本次從 AttestedRangeTests 搬來，#232）。
    func testCurrentSupportedFormatIsExactlyEight() {
        XCTAssertEqual(StoreVersion.supported, 8)
    }

    func testWritePersonWithVerdictRequiresFormatEight() throws {
        try StoreVersion.write(root: root, format: 7)
        XCTAssertThrowsError(try store.writePerson(verdictPerson()),
                             "format 7 store 寫 verdict＝替舊 binary 埋 quarantine 地雷") { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("8") && msg.contains("format"), msg)
        }
        try StoreVersion.write(root: root, format: 8)
        XCTAssertNoThrow(try store.writePerson(verdictPerson()), "format 8 放行")
    }

    func testWriteOrganizationWithVerdictRequiresFormatEight() throws {
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計所", range: DateRange(start: "1987"))])
        org.references = [ResolutionLedger.record(
            .rejected, holderKind: .person, holder: "che-cheng", literal: "統計所",
            rule: ResolutionLedger.orgRule, statement: "s")]
        try StoreVersion.write(root: root, format: 7)
        XCTAssertThrowsError(try store.writeOrganization(org)) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("8"), msg)
        }
        try StoreVersion.write(root: root, format: 8)
        XCTAssertNoThrow(try store.writeOrganization(org))
    }

    /// 無 verdict 的記錄不受 gate 影響——例外不外溢。
    func testPersonWithoutVerdictUnaffectedByGate() throws {
        try StoreVersion.write(root: root, format: 7)
        XCTAssertNoThrow(try store.writePerson(Person(key: "k", names: ["N"])))
    }

    // MARK: - rename 遷移（verify NEW-1）

    func testRenameMigratesVerdictValues() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: "article",
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writePerson(verdictPerson())
        let report = try store.renameEntry(from: "a2020x", to: "b2021y")
        XCTAssertEqual(report.verdictValuesRewritten, ["cheng-che"],
                       "verdict 遷移要報出來——rename 改寫別的記錄是最不被預期的副作用")
        let load = try LibraryStore(root: root, key: nil, environment: [:]).load()
        let p = load.people.first { $0.key == "cheng-che" }!
        XCTAssertEqual(p.references.map(\.value), ["work:b2021y :: Che Cheng"],
                       "判定史跟著 citekey 走")
        // 否決仍然抑制（rename 前後同一個真實配對）——這正是 NEW-1 的傷害面
        let rejected = ResolutionLedger.rejectedPairings(people: load.people)
        let resolveReport = PersonResolver.resolve(entries: load.entries, people: load.people,
                                                   rejected: rejected)
        XCTAssertTrue(resolveReport.candidates.isEmpty,
                      "rename 之後否決不得安靜變回待判：\(resolveReport.candidates)")
        // 沉底列也跟著新 citekey
        let sunk = ResolutionLedger.observedRejections(people: load.people,
                                                       entries: load.entries)
        XCTAssertEqual(sunk.map(\.citekey), ["b2021y"])
    }

    /// 不相干的 verdict（別的 citekey／org 族）不被 rename 動到。
    func testRenameLeavesUnrelatedVerdictsAlone() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: "article",
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        var p = Person(key: "cheng-che", names: ["Che Cheng"])
        p.references = [
            ResolutionLedger.record(.rejected, holderKind: .work, holder: "other2019z",
                                    literal: "Che Cheng",
                                    rule: ResolutionLedger.personRule, statement: "s"),
        ]
        try store.writePerson(p)
        let report = try store.renameEntry(from: "a2020x", to: "b2021y")
        XCTAssertTrue(report.verdictValuesRewritten.isEmpty)
        let load = try LibraryStore(root: root, key: nil, environment: [:]).load()
        XCTAssertEqual(load.people.first?.references.map(\.value),
                       ["work:other2019z :: Che Cheng"])
    }
}
