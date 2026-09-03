import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// `migrate-venue-variants`（#422）的遷移本體——#422 verify R1 之前零測試，而它是
/// 「時間軸只承載沿革」唯一的機械執行者。釘住的是分類的**五個桶**（其中 `noAuthorized`
/// 是 R1 B3 新增：補集規則對空的 `authorized` 會把每個名字都標成自己的異寫，實測三筆）、
/// 乾跑不動 store、`--apply` 之後第二次是 no-op、未追蹤檔進 `failed` 而不是讓例外穿出。
final class VenueVariantMigrationTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vvm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue(_ key: String, names: [TemporalValue<String>],
                       authorized: [String] = [], variant: [String] = []) throws {
        var v = Venue(key: key, type: .periodical, names: TimelineOf(names))
        v.authorized = authorized
        v.variant = variant
        _ = try store.writeVenue(v)
    }

    private func loaded(_ key: String) throws -> Venue? {
        try store.load().venues.first { $0.key == key }
    }

    /// 乾跑把每一筆放進正確的桶，且**不動 store**。
    func testDryRunClassifiesEveryBucketAndDoesNotWrite() throws {
        try venue("single", names: [TemporalValue(value: "Solo Journal")])
        // authorized 每個書寫系統至多一個（既有不變式）——兩個 authorized 用不同書寫系統
        try venue("all-auth", names: [TemporalValue(value: "Journal A"), TemporalValue(value: "期刊甲")],
                  authorized: ["Journal A", "期刊甲"])
        try venue("no-auth", names: [TemporalValue(value: "Wikipedia"), TemporalValue(value: "維基百科")])
        try venue("dated", names: [TemporalValue(value: "Old Series Bulletin"),
                                   TemporalValue(value: "New Series Bulletin", range: DateRange(start: "2007"))],
                  authorized: ["New Series Bulletin"])
        try venue("planned", names: [TemporalValue(value: "PLOS ONE"), TemporalValue(value: "PLoS One")],
                  authorized: ["PLOS ONE"])
        try venue("done", names: [TemporalValue(value: "Done Journal"), TemporalValue(value: "DONE J")],
                  authorized: ["Done Journal"], variant: ["DONE J"])
        GitFixture.commitAll(store.root)

        let r = try VenueVariantMigration.run(store: store, apply: false)
        XCTAssertEqual(r.singleName, ["single"])
        XCTAssertEqual(r.allAuthorized, ["all-auth"], "多名字但全在 authorized 不是「單一名字」")
        XCTAssertEqual(r.noAuthorized, ["no-auth"], "authorized 為空 → 不分類、交人（R1 B3）")
        XCTAssertEqual(r.hasTemporal, ["dated"])
        XCTAssertEqual(r.alreadyPartitioned, ["done"])
        XCTAssertEqual(r.planned, [VenueVariantMigration.Planned(key: "planned", variants: ["PLoS One"])])
        XCTAssertTrue(r.failed.isEmpty, "\(r.failed)")
        XCTAssertEqual(r.applied, 0)

        XCTAssertEqual(try loaded("planned")?.variant, [], "乾跑不得寫入")
        XCTAssertEqual(try loaded("no-auth")?.variant, [],
                       "authorized 為空的記錄不得被標成「每個名字都是自己的異寫」")
    }

    /// `--apply` 只寫 `planned` 那一桶；第二次跑同一個 store 是 no-op（`alreadyPartitioned`）。
    func testApplyWritesPlannedOnlyAndSecondRunIsNoOp() throws {
        try venue("no-auth", names: [TemporalValue(value: "Wikipedia"), TemporalValue(value: "維基百科")])
        try venue("planned", names: [TemporalValue(value: "PLOS ONE"), TemporalValue(value: "PLoS One")],
                  authorized: ["PLOS ONE"])
        GitFixture.commitAll(store.root)

        let first = try VenueVariantMigration.run(store: store, apply: true)
        XCTAssertEqual(first.applied, 1, "\(first)")
        XCTAssertTrue(first.failed.isEmpty, "\(first.failed)")
        XCTAssertEqual(try loaded("planned")?.variant, ["PLoS One"])
        XCTAssertEqual(try loaded("no-auth")?.variant, [], "authorized 為空的記錄 apply 也不動")

        let second = try VenueVariantMigration.run(store: store, apply: true)
        XCTAssertEqual(second.applied, 0)
        XCTAssertTrue(second.planned.isEmpty)
        XCTAssertEqual(second.alreadyPartitioned, ["planned"])
        XCTAssertEqual(second.noAuthorized, ["no-auth"], "第二次仍點名交人，不會因為跑過就消失")
    }

    /// 未被 git 追蹤的檔**拒寫、進 `failed`**，其餘照常——改寫無回復路徑的檔不能碰。
    func testUntrackedFileIsRefusedIntoFailedNotThrown() throws {
        try venue("tracked", names: [TemporalValue(value: "Tracked J"), TemporalValue(value: "TRACKED J")],
                  authorized: ["Tracked J"])
        GitFixture.commitAll(store.root)
        try venue("untracked", names: [TemporalValue(value: "Untracked J"), TemporalValue(value: "UNTRACKED J")],
                  authorized: ["Untracked J"])   // 寫在 commit 之後 → git 零歷史

        // 乾跑要看到**同一組**拒絕（R2 L1）：未追蹤的檔不得被印成「將分類」
        let dry = try VenueVariantMigration.run(store: store, apply: false)
        XCTAssertEqual(dry.planned.map(\.key), ["tracked"])
        XCTAssertEqual(dry.failed.map(\.key), ["untracked"], "乾跑也要點名未追蹤的檔：\(dry)")
        XCTAssertEqual(dry.applied, 0)

        let r = try VenueVariantMigration.run(store: store, apply: true)
        XCTAssertEqual(r.applied, 1)
        XCTAssertEqual(r.planned.map(\.key), ["tracked"])
        XCTAssertEqual(r.failed.map(\.key), ["untracked"])
        XCTAssertTrue(r.failed.first?.reason.contains("未被 git 追蹤") ?? false, "\(r.failed)")
        XCTAssertEqual(try loaded("untracked")?.variant, [], "拒寫的檔不得被改")
    }
}
