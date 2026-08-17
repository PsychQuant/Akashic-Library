import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// `migrate-venues`：從書目字串欄位回填 `venues` literal ref（#304 task 3.1）。
/// 契約：dry-run 預設零寫入、只加不改、idempotent、per-file tracked 前置。
final class VenueMigrationTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vmig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        // migration 的 --apply 前提：檔案被 git 追蹤
        _ = LibraryStore.git(["init", "-q"], in: root)
        _ = LibraryStore.git(["config", "user.email", "t@t"], in: root)
        _ = LibraryStore.git(["config", "user.name", "t"], in: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func commitAll() {
        _ = LibraryStore.git(["add", "-A"], in: root)
        _ = LibraryStore.git(["commit", "-q", "-m", "seed"], in: root)
    }

    private func writeArticle(_ ck: String, journal: String?) throws -> Entry {
        var e = Entry(id: UUID(), citekey: ck, type: "article", title: "T-\(ck)")
        if let journal { e.fields["journaltitle"] = journal }
        _ = try store.writeEntry(e)
        return e
    }

    func testDryRunPlansButWritesNothing() throws {
        _ = try writeArticle("a2020", journal: "Journal A")
        commitAll()
        let before = try String(contentsOf: store.entityURL(id: try store.load().entries[0].id),
                                encoding: .utf8)
        let report = try VenueMigration.run(store: store, apply: false)
        XCTAssertEqual(report.planned, ["a2020"])
        XCTAssertEqual(report.applied, 0)
        let after = try String(contentsOf: store.entityURL(id: try store.load().entries[0].id),
                               encoding: .utf8)
        XCTAssertEqual(before, after, "dry-run 零寫入")
    }

    func testApplyAddsLiteralAndKeepsFields() throws {
        _ = try writeArticle("a2020", journal: "JOURNAL OF X")
        commitAll()
        let report = try VenueMigration.run(store: store, apply: true)
        XCTAssertEqual(report.applied, 1)
        let e = try store.load().entries[0]
        XCTAssertEqual(e.venues, [.literal("JOURNAL OF X")], "只產生 literal，不猜 key")
        XCTAssertEqual(e.fields["journaltitle"], "JOURNAL OF X", "欄位字串照舊保留")
    }

    func testIdempotentSecondRunZeroChanges() throws {
        _ = try writeArticle("a2020", journal: "Journal A")
        commitAll()
        _ = try VenueMigration.run(store: store, apply: true)
        commitAll()
        let second = try VenueMigration.run(store: store, apply: true)
        XCTAssertEqual(second.applied, 0)
        XCTAssertEqual(second.skippedExisting, ["a2020"], "已有 venues 者不動")
    }

    func testExistingVenuesUntouched() throws {
        var e = Entry(id: UUID(), citekey: "keep2020", type: "article", title: "K")
        e.fields["journaltitle"] = "Ignored Because Present"
        e.venues = [.key("some-venue")]
        _ = try store.writeEntry(e)
        commitAll()
        let report = try VenueMigration.run(store: store, apply: true)
        XCTAssertEqual(report.skippedExisting, ["keep2020"])
        XCTAssertEqual(try store.load().entries[0].venues, [.key("some-venue")])
    }

    func testProceedingsBooktitleAndPublisher() throws {
        var e = Entry(id: UUID(), citekey: "p2019", type: "inproceedings", title: "P")
        e.fields["booktitle"] = "Proc. of Great Conf"
        e.fields["publisher"] = "Some Press"
        _ = try store.writeEntry(e)
        commitAll()
        _ = try VenueMigration.run(store: store, apply: true)
        let got = try store.load().entries[0].venues
        XCTAssertEqual(got, [.literal("Proc. of Great Conf"), .literal("Some Press")],
                       "booktitle（proceedings 型）在前、publisher 在後")
    }

    func testNoSourceFieldsLeavesEntryAlone() throws {
        _ = try writeArticle("bare2020", journal: nil)
        commitAll()
        let report = try VenueMigration.run(store: store, apply: true)
        XCTAssertEqual(report.applied, 0)
        XCTAssertTrue(report.planned.isEmpty)
        XCTAssertEqual(report.noVenueSource, ["bare2020"])
    }

    func testUntrackedFileRefusedFromApply() throws {
        _ = try writeArticle("tracked2020", journal: "Journal A")
        commitAll()
        _ = try writeArticle("untracked2020", journal: "Journal B")   // 未 commit
        let report = try VenueMigration.run(store: store, apply: true)
        XCTAssertEqual(report.applied, 1, "tracked 者照常")
        XCTAssertEqual(report.failed.map(\.citekey), ["untracked2020"])
        // 未追蹤者未被改寫
        let untouched = try store.load().entries.first { $0.citekey == "untracked2020" }!
        XCTAssertTrue(untouched.venues.isEmpty)
    }
}
