import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #575：`AkashicService.repairVenueNames`——計畫之外的 store 層契約：乾跑不寫、`--apply` 只寫確定性的那幾筆、
/// 寫入前要求那些 venue 檔已 commit、任一筆過不了寫入閘就整批零寫入、要人判斷的一筆都不動。
final class VenueNameRepairServiceTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-vnrepair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 繞過寫入閘直接寫檔——舊 binary 或手改 YAML 的形狀（`VenueYAML.encode` 不驗名字內容）。
    @discardableResult
    private func dirtyVenue(_ key: String, names: [String], authorized: [String] = [], paginated: Bool? = nil) throws -> Venue {
        var v = Venue(key: key, type: .periodical, names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.paginated = paginated
        try VenueYAML.encode(v).write(to: file(v), atomically: true, encoding: .utf8)
        return v
    }
    private func file(_ v: Venue) -> URL { root.appendingPathComponent("entities/\(v.id.uuidString).yaml") }
    private func bytes(_ v: Venue) throws -> Data { try Data(contentsOf: file(v)) }
    private func loaded(_ key: String) throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == key })
    }

    func testDryRunListsButDoesNotWrite() throws {
        let v = try dirtyVenue("alpha", names: ["Alpha Journal "], authorized: ["Alpha Journal "])
        StoreGitCommit.commitAll(root)
        let before = try bytes(v)
        let report = try service.repairVenueNames(apply: false)
        XCTAssertFalse(report.applied)
        XCTAssertEqual(report.applicable.map(\.key), ["alpha"])
        XCTAssertEqual(report.applicable.first?.rewrites.count, 2)
        XCTAssertNil(report.applyRefusal, "已 commit：--apply 不會被拒")
        XCTAssertEqual(try bytes(v), before, "乾跑零寫入")
    }

    func testApplyRewritesOnlyTheDeterministicVenues() throws {
        let fixable = try dirtyVenue("alpha", names: ["Alpha Journal "], authorized: ["Alpha Journal "])
        let judged = try dirtyVenue("beta", names: ["Beta ", "Tag\u{E0041}Name"])
        StoreGitCommit.commitAll(root)
        let judgedBefore = try bytes(judged)
        let report = try service.repairVenueNames(apply: true)
        XCTAssertTrue(report.applied)
        XCTAssertEqual(report.needsJudgment.map(\.key), ["beta"])
        let a = try loaded("alpha")
        XCTAssertEqual(a.names.entries.map(\.value), ["Alpha Journal"])
        XCTAssertEqual(a.authorized, ["Alpha Journal"])
        XCTAssertEqual(a.id, fixable.id, "身分不動")
        XCTAssertTrue(a.validate().filter { $0.severity == .error }.isEmpty)
        XCTAssertEqual(try bytes(judged), judgedBefore, "要人判斷的那筆一個位元組都不動——連它可改的那一筆也延後")
        let again = try service.repairVenueNames(apply: false)
        XCTAssertEqual(again.applicable.map(\.key), [], "冪等")
        XCTAssertEqual(again.needsJudgment.map(\.key), ["beta"])
    }

    func testApplyRefusesUncommittedFilesAndDryRunForetellsIt() throws {
        let v = try dirtyVenue("alpha", names: ["Alpha Journal "])
        StoreGitCommit.commitAll(root)
        try dirtyVenue("gamma", names: ["Gamma  Journal"])   // 新檔，未 commit
        let before = try bytes(v)
        let dry = try service.repairVenueNames(apply: false)
        XCTAssertTrue(dry.applyRefusal?.contains("#575") == true, "\(String(describing: dry.applyRefusal))")
        XCTAssertThrowsError(try service.repairVenueNames(apply: true)) { err in
            XCTAssertTrue(String(describing: err).contains("未被 git 追蹤"), "\(err)")
        }
        XCTAssertEqual(try bytes(v), before, "整批拒絕：已 commit 的那一筆也不寫")
    }

    func testApplyRefusesOutsideGit() throws {
        let v = try dirtyVenue("alpha", names: ["Alpha Journal "])
        let before = try bytes(v)
        XCTAssertThrowsError(try service.repairVenueNames(apply: true)) { err in
            XCTAssertTrue(String(describing: err).contains("git 工作樹"), "\(err)")
        }
        XCTAssertEqual(try bytes(v), before)
    }

    /// 任一筆過不了寫入閘就整批零寫入：format 13 的 store 裡一筆帶 `paginated` 的 venue（format 14 的欄位，寫入閘拒）。
    func testOneRecordFailingTheWriteGateRefusesTheWholeBatch() throws {
        let ok = try dirtyVenue("alpha", names: ["Alpha Journal "])
        let gated = try dirtyVenue("delta", names: ["Delta Journal "], paginated: true)
        try StoreVersion.write(root: root, format: 13)
        StoreGitCommit.commitAll(root)
        let okBefore = try bytes(ok), gatedBefore = try bytes(gated)
        let dry = try service.repairVenueNames(apply: false)
        XCTAssertEqual(Set(dry.applicable.map(\.key)), ["alpha", "delta"], "計畫本身兩筆都可改")
        XCTAssertTrue(dry.applyRefusal?.contains("寫入閘") == true, "\(String(describing: dry.applyRefusal))")
        XCTAssertThrowsError(try service.repairVenueNames(apply: true))
        XCTAssertEqual(try bytes(ok), okBefore, "整批：另一筆也不寫")
        XCTAssertEqual(try bytes(gated), gatedBefore)
    }

    func testNothingToDo() throws {
        _ = try service.addVenue(key: "clean", names: ["Clean Journal"], type: "periodical", note: nil, issn: nil)
        let report = try service.repairVenueNames(apply: false)
        XCTAssertTrue(report.plans.isEmpty)
        XCTAssertEqual(report.scanned, 1)
        XCTAssertEqual(report.quarantined, 0)
    }

    /// 讀不進來的檔不在走訪範圍——報告要數出來，否則「沒有違反」會冒充整個 store 乾淨（`zero-instance-guards` 第 3 列）。
    func testQuarantinedFilesAreCounted() throws {
        _ = try service.addVenue(key: "clean", names: ["Clean Journal"], type: "periodical", note: nil, issn: nil)
        try "venue: {}\nnot: [valid\n".write(to: root.appendingPathComponent("entities/\(UUID().uuidString).yaml"),
                                              atomically: true, encoding: .utf8)
        let report = try service.repairVenueNames(apply: false)
        XCTAssertTrue(report.plans.isEmpty)
        XCTAssertEqual(report.scanned, 1)
        XCTAssertEqual(report.quarantined, 1)
    }
}
