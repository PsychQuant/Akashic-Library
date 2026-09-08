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
        // #227：空 names——本 fixture 釘的是 verdict 閘的閾值（8）；具名 person
        // 另受 v10 names 閘管，帶 names 會讓 format 8/9 的放行斷言誤紅
        var p = Person(key: "cheng-che")
        p.references = [ResolutionLedger.record(
            .rejected, holderKind: .work, holder: "a2020x", literal: "Che Cheng",
            rule: ResolutionLedger.personRule, statement: "s")]
        return p
    }

    // 精確 format 值的 pin 隨最新 format 的測試搬家（#131 verify 慣例）——
    // 現住 KnownLayerEvolutionTests（format 9，#223）。verdict gate 自身只要求 ≥ 8。
    func testVerdictGateFormatFloorHolds() {
        XCTAssertGreaterThanOrEqual(StoreVersion.supported, 8,
                                    "verdict 欄位對需要 format ≥ 8（#232）")
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
        XCTAssertNoThrow(try store.writePerson(Person(key: "k")))   // 空 names（#227 v10 閘另計）
    }

    // MARK: - rename 遷移（verify NEW-1）

    func testRenameMigratesVerdictValues() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writePerson(verdictPerson())
        let report = try store.renameEntry(from: "a2020x", to: "b2021y")
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.person, "cheng-che")],
                       "verdict 遷移要報出來——rename 改寫別的記錄是最不被預期的副作用")
        let load = try LibraryStore(root: root, key: nil, environment: [:]).load()
        let p = load.people.first { $0.key == "cheng-che" }!
        XCTAssertEqual(p.references.map(\.value), ["work:b2021y :: Che Cheng"],
                       "判定史跟著 citekey 走")
        // 否決仍然抑制（rename 前後同一個真實配對）——這正是 NEW-1 的傷害面
        let rejected = ResolutionLedger.rejectedPairings(people: load.people)
        let resolveReport = PersonResolver.resolve(entries: load.entries, people: load.people,
                                                   rejected: rejected, confirmed: [:])
        XCTAssertTrue(resolveReport.candidates.isEmpty,
                      "rename 之後否決不得安靜變回待判：\(resolveReport.candidates)")
        // 沉底列也跟著新 citekey
        let sunk = ResolutionLedger.observedRejections(people: load.people,
                                                       entries: load.entries)
        XCTAssertEqual(sunk.map(\.citekey), ["b2021y"])
    }

    /// 不相干的 verdict（別的 citekey／org 族）不被 rename 動到。
    func testRenameLeavesUnrelatedVerdictsAlone() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
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

    /// **format 閘不得用 `invalidKey` 承載**（#496）。
    ///
    /// `invalidKey` 的渲染框架是「「<key>」不符合 \A[a-z0-9][a-z0-9-]*\z，拒絕寫入」。
    /// 對一個**合法**的 key 那是假斷言——實測（#463 verify DA-6，format 7 的 store 上
    /// `akashic rename`）訊息尾巴接了「「some-org」不符合 …」，而 `some-org` 符合那個 regex。
    ///
    /// 後果不只是難看：MCP 消費端讀到「不符合 regex」會去**清洗 key**，而 key 沒有問題
    /// ——問題是 store 的 format 太舊。`invalidInput(what:why:)` 就是為了這個而立的（#133）。
    ///
    /// 判準：任何提到 `store format ≥` 的 throw，其上三行內不得出現 `invalidKey`。
    /// 實測轉換前 7 處（entry v9、organization v6／v7／v8、person v6／v7／v8），轉換後 0。
    func testFormatGatesDoNotBorrowInvalidKeyRendering() throws {
        var dir = URL(fileURLWithPath: #filePath)
        var srcRoot: URL?
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            let c = dir.appendingPathComponent("Sources/AkashicStoreIO")
            if FileManager.default.fileExists(atPath: c.path) { srcRoot = c; break }
        }
        guard let srcRoot else { throw XCTSkip("找不到 Sources/AkashicStoreIO") }
        let files = try FileManager.default.contentsOfDirectory(atPath: srcRoot.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "掃不到原始碼——斷言會空跑")

        var offenders: [String] = []
        var gatesSeen = 0
        for f in files {
            let lines = try String(contentsOf: srcRoot.appendingPathComponent(f), encoding: .utf8)
                .components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains("store format ≥") {
                gatesSeen += 1
                let lo = max(0, i - 3)
                if lines[lo..<i].contains(where: { $0.contains("invalidKey") }) {
                    offenders.append("\(f):\(i + 1) \(line.trimmingCharacters(in: .whitespaces).prefix(60))")
                }
            }
        }
        // 空集合會讓上面的迴圈零次迭代而靜默通過——#521 記過的形狀。
        XCTAssertGreaterThan(gatesSeen, 0, "一個 format 閘都沒掃到——斷言等於沒跑")
        XCTAssertTrue(offenders.isEmpty,
            "format 閘用 invalidKey 承載——它的渲染框架會說「key 不合文法」，"
            + "而 key 是合法的；MCP 消費端會照著去清洗 key。改用 invalidInput(what:why:)：\n"
            + offenders.joined(separator: "\n"))
    }
}
