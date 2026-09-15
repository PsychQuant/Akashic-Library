import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 配對唯一性兩半的 per-record warning（#554 D28／D36）要有具名的 `StoreHealth` 家族（R14 verify regression 第 22 列）：
/// 既有六族各有 `*Prefix` 常量＋計算屬性、doctor 的 `recordIssues` 與 App 的 `RecordIssuesSummary` 各一個計數，這兩族三處都沒有——
/// MCP 面截 20 則、App 預覽 5 則時它們可以完全看不到，而第 26／27 列宣稱的「掃得到」只對 CLI validate 成立。
final class PairingUniquenessHealthTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-puh-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func confirmed(_ work: String, _ literal: String) -> ProvenanceReference {
        ProvenanceReference(field: "resolution-confirmed",
                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: work, literal: literal).encoded,
                            kind: .judgement(statement: "測試", restsOn: []))
    }

    func testBothHalvesHaveANamedFamily() throws {
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [confirmed("w1", "Alpha Journal"), confirmed("w1", "Beta Review"),
                        confirmed("w2", "Alpha Journal"), confirmed("w2", "ALPHA JOURNAL")]
        try store.writeVenue(v)
        var e = Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T", authors: [.literal("A B")], date: "2020")
        e.venues = [.key("alpha"), .key("alpha")]
        try store.writeEntry(e)
        try store.writeEntry(Entry(id: UUID(), citekey: "w2", type: .periodicalArticle, title: "T2", authors: [.literal("A B")], date: "2020"))
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.confirmedLiteralAmbiguities.count, 2, "正規化後不同（w1）＋只差位元組（w2）：\(health.confirmedLiteralAmbiguities.map(\.issue.message))")
        XCTAssertEqual(health.duplicateVenueEdges.count, 1)
        XCTAssertTrue(health.confirmedLiteralAmbiguities.allSatisfy { $0.kind == "venue" && $0.owner == "alpha" && $0.issue.severity == .warning })
        XCTAssertTrue(health.duplicateVenueEdges.allSatisfy { $0.kind == "entry" && $0.owner == "w1" && $0.issue.severity == .warning })
        XCTAssertEqual(health.deadVerdicts.count, 0)
        XCTAssertEqual(StoreHealth.confirmedLiteralAmbiguityPrefix, Venue.confirmedLiteralAmbiguityPrefix, "單一定義")
        XCTAssertEqual(StoreHealth.duplicateVenueEdgePrefix, Entry.duplicateVenueEdgePrefix, "單一定義")
    }
}
