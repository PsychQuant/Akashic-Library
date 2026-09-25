import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// change `resolution-verdict-states`（#619）：未決腿的寫入面與提名揭露
/// （spec「Undecided verdicts SHALL be written only through an explicit per-id leg」
/// 「Nomination SHALL disclose undecided checks and filtered apply SHALL exclude them」）。
final class UndecidedServiceTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService!
    private let digest = "sha256:" + String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-undecided-svc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        var p = Person(key: "chen-ch")
        p.names = PersonNames(authorized: ["Chen, C-H"], variant: [])
        try store.writePerson(p)
        var q = Person(key: "chen-ch-2")
        q.names = PersonNames(authorized: ["Chen, Chun-Hua"], variant: [])
        try store.writePerson(q)
        var e = Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T")
        e.authors = [.literal("Someone Else"), .literal("C-H Chen")]
        try store.writeEntry(e)
        try store.writeVenue(Venue(key: "alpha", type: .periodical,
                                   names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: []))
        var w = Entry(id: UUID(), citekey: "w2", type: .periodicalArticle, title: "U")
        w.venues = [.literal("Alpha Journal")]
        try store.writeEntry(w)
        service = AkashicService(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
    }
    private func undecided(_ specs: [String], restsOn: [String]? = nil) throws -> [String: Any] {
        json(try service.resolvePeople(apply: nil, undecided: specs, restsOn: restsOn))
    }
    private func refs(_ key: String) throws -> [ProvenanceReference] {
        try XCTUnwrap(try store.load().people.first { $0.key == key }).references
    }

    // MARK: - 寫入

    func testRecordsUndecidedWithRestsOnAndLeavesTheSlot() throws {
        let out = try undecided(["w1:1:chen-ch=查了機構欄只寫 Taipei"], restsOn: [digest])
        let row = try XCTUnwrap((out["undecided"] as? [[String: Any]])?.first, "\(out)")
        XCTAssertEqual(row["restsOn"] as? [String], [digest])
        let r = try XCTUnwrap(try refs("chen-ch").first)
        XCTAssertEqual(r.field, "resolution-undecided")
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "w1" }?.authors[1], .literal("C-H Chen"), "作者位不動")
    }

    func testChecksAccumulateAndIdenticalResendIsAlreadyRecorded() throws {
        _ = try undecided(["w1:1:chen-ch=查了機構"])
        _ = try undecided(["w1:1:chen-ch=查了共同作者"])
        let again = try undecided(["w1:1:chen-ch=查了共同作者"])
        XCTAssertEqual(again["alreadyRecorded"] as? [String], ["w1:1:chen-ch"], "\(again)")
        XCTAssertEqual(try refs("chen-ch").count, 2)
    }

    /// 六種整批拒絕，零寫入。
    func testInputErrorsRefuseTheWholeBatch() throws {
        let cases: [([String], [String]?)] = [
            (["w1:1:chen-ch"], nil),                          // 缺 =
            (["w1:chen-ch=x"], nil),                          // 非三段
            (["w1:1:chen-ch=x", "w1:01:chen-ch=y"], nil),     // 重複 id（解析後）
            (["w1:1:chen-ch=   "], nil),                      // 說明空白
            (["w1:1:nobody=x"], nil),                         // person 不存在
            (["w1:1:chen-ch=x"], ["sha256:short"]),           // digest 形狀不合
        ]
        for (specs, ro) in cases {
            XCTAssertThrowsError(try undecided(specs, restsOn: ro), "\(specs)")
        }
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, restsOn: [digest]), "rests_on 沒有伴隨 undecided")
        try StoreVersion.write(root: root, format: 18)
        XCTAssertThrowsError(try undecided(["w1:1:chen-ch=x"]), "format < 19")
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertTrue(try refs("chen-ch").isEmpty, "零寫入")
    }

    /// 四種逐筆略過，其餘照寫。
    func testStoreStateMismatchesAreSkippedByName() throws {
        var p = try XCTUnwrap(try store.load().people.first { $0.key == "chen-ch-2" })
        p.references = [ResolutionLedger.record(.rejected, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                                rule: ResolutionLedger.personRule, statement: "s")]
        try store.writePerson(p)
        let out = try undecided(["nope:0:chen-ch=x", "w1:9:chen-ch=x", "w1:1:chen-ch-2=x", "w1:1:chen-ch=寫得進去"])
        let skipped = (out["skipped"] as? [[String: Any]]) ?? []
        XCTAssertEqual(skipped.count, 3, "\(out)")
        XCTAssertTrue(skipped.contains { ($0["why"] as? String ?? "").contains("已判定") }, "已 decided 的配對要具名略過")
        XCTAssertEqual((out["undecided"] as? [[String: Any]])?.count, 1)
    }

    func testKeyedSlotIsSkipped() throws {
        var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == "w1" })
        e.authors[1] = .key("chen-ch")
        try store.writeEntry(e)
        let out = try undecided(["w1:1:chen-ch=x"])
        XCTAssertEqual((out["skipped"] as? [[String: Any]])?.count, 1, "\(out)")
    }

    func testUndecidedLegRefusesCombination() throws {
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, judge: ["w1:1:chen-ch=a"], undecided: ["w1:1:chen-ch=b"]))
        XCTAssertThrowsError(try service.resolvePeople(apply: ["w1:1:chen-ch"], undecided: ["w1:1:chen-ch=b"]))
    }

    // MARK: - 提名揭露

    func testListDisclosesUndecidedChecksAndFourStateCounts() throws {
        _ = try undecided(["w1:1:chen-ch=查了機構", "w1:1:chen-ch-2=查了機構"])
        let list = json(try service.resolvePeople(apply: nil))
        let rows = (list["candidates"] as? [[String: Any]] ?? []) + []
        let amb = list["ambiguities"] as? [[String: Any]] ?? []
        let checks = (rows.compactMap { $0["undecidedChecks"] as? Int } + amb.compactMap { $0["undecidedChecks"] as? Int })
        XCTAssertFalse(checks.isEmpty, "查過未決的配對要在列表揭露：\(list)")
        XCTAssertNotNil(list["undecidedTotal"], "\(list.keys)")
    }

    // MARK: - venue

    func testVenueUndecidedIsRecordedAndListed() throws {
        let out = json(try service.resolveVenues(apply: nil, undecided: ["w2:0:alpha=查了刊名沿革"]))
        XCTAssertEqual((out["undecided"] as? [[String: Any]])?.count, 1, "\(out)")
        let list = json(try service.resolveVenues(apply: nil))
        let row = (list["candidates"] as? [[String: Any]])?.first { $0["citekey"] as? String == "w2" }
        XCTAssertEqual(row?["undecidedChecks"] as? Int, 1, "\(list)")
        XCTAssertThrowsError(try service.resolveVenues(apply: ["w2:0"], undecided: ["w2:0:alpha=x"]))
    }
}
