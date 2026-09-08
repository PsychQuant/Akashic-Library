import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 同一筆記錄對同一個配對同時說「是」與「不是」（#486）。
///
/// 這不是資料壞掉（兩條 verdict 各自合法、檔案載入得了），是**判定**壞掉——提名層會同時把
/// 它算成「已判給這個人」與「已被否決」，兩條路徑對同一個配對給出相反的答案。
///
/// **這個掃描在 #470 之前寫不出來**：那時「同一配對」在寫入面（位元組）與讀取面（正規化）
/// 有兩個答案，先寫任一個就是偷偷定案第三份相等定義。
final class ContradictoryVerdictScanTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-cv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdict(_ field: String, holder: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(
            field: field,
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))
    }
    private func person(_ key: String, _ refs: [ProvenanceReference]) throws {
        var p = Person(key: key, names: ["\(key) Name"])
        p.references = refs
        try store.writePerson(p)
    }
    private func issues() throws -> [StoreHealth.OwnedIssue] {
        store.contradictoryVerdictIssues(in: try store.load())
    }

    /// 乾淨的 store 是零——恆非空的掃描分不出「有矛盾」與「掃描壞了」。
    func testCleanStoreReportsNothing() throws {
        try person("a", [verdict("resolution-confirmed", holder: "k2020a", literal: "A B")])
        XCTAssertEqual(try issues().count, 0)
    }

    /// 同一配對兩個 field 並存 → 一條 warning，說得出是哪兩個 field、哪個配對。
    func testBothVerdictsOnOnePairingIsReported() throws {
        try person("a", [verdict("resolution-confirmed", holder: "k2020a", literal: "A B"),
                         verdict("resolution-rejected", holder: "k2020a", literal: "A B")])
        let got = try issues()
        XCTAssertEqual(got.count, 1, "\(got.map(\.issue.message))")
        XCTAssertEqual(got[0].owner, "a")
        XCTAssertEqual(got[0].issue.severity, .warning,
                       "判定壞掉不是資料壞掉——error 會擋住 export 類流程")
        let m = got[0].issue.message
        XCTAssertTrue(m.hasPrefix(StoreHealth.contradictoryVerdictPrefix), m)
        XCTAssertTrue(m.contains("resolution-confirmed 與 resolution-rejected"), m)
        XCTAssertTrue(m.contains("work:k2020a"), m)
        XCTAssertTrue(m.contains("A B"), m)
    }

    /// **#470 的相等在這裡起作用**：只差空白的 literal 是同一個配對。
    /// 若這個掃描退回位元組比對，這一條會靜靜變成 0——而矛盾仍然在。
    func testNormalisedEqualityCatchesWhitespaceVariants() throws {
        try person("a", [verdict("resolution-confirmed", holder: "k2020a", literal: "Fann, C."),
                         verdict("resolution-rejected", holder: "k2020a", literal: "Fann,  C.")])
        XCTAssertEqual(try issues().count, 1, "只差空白仍是同一個配對（#470）")
    }

    /// 真的不同的配對不得誤報——holder 與 literal 各驗一次。
    func testDifferentPairingsAreNotContradictions() throws {
        try person("a", [verdict("resolution-confirmed", holder: "k2020a", literal: "A B"),
                         verdict("resolution-rejected", holder: "k2020b", literal: "A B"),
                         verdict("resolution-rejected", holder: "k2020a", literal: "C D")])
        XCTAssertEqual(try issues().count, 0)
    }

    /// 三族 owner 都掃得到——只掃 person 會讓另外兩族的矛盾靜默（#460／#463 記過的形狀）。
    func testAllThreeOwnerKindsAreScanned() throws {
        try person("a", [verdict("resolution-confirmed", holder: "k2020a", literal: "A B"),
                         verdict("resolution-rejected", holder: "k2020a", literal: "A B")])
        var o = Organization(key: "some-org", names: TimelineOf([TemporalValue(value: "Org")]))
        o.references = [verdict("resolution-confirmed", holder: "k2020a", literal: "O"),
                        verdict("resolution-rejected", holder: "k2020a", literal: "O")]
        _ = try store.writeOrganization(o)
        var v = Venue(key: "some-venue", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "V")]))
        v.references = [verdict("resolution-confirmed", holder: "k2020a", literal: "V"),
                        verdict("resolution-rejected", holder: "k2020a", literal: "V")]
        _ = try store.writeVenue(v)
        XCTAssertEqual(Set(try issues().map(\.kind)), ["person", "organization", "venue"])
    }

    /// 進得了 `StoreHealth.perRecordIssues`，且計算屬性篩得出來——只有掃描函式而沒有接上
    /// 消費面，等於沒有掃描（#251 記過三次的形狀）。
    func testItReachesStoreHealthAndTheComputedProperty() throws {
        try person("a", [verdict("resolution-confirmed", holder: "k2020a", literal: "A B"),
                         verdict("resolution-rejected", holder: "k2020a", literal: "A B")])
        let h = store.health(from: try store.load())
        XCTAssertEqual(h.contradictoryVerdicts.count, 1)
        XCTAssertTrue(h.perRecordIssues.allSatisfy { $0.issue.severity != .error },
                      "warning 不得升成 error——那會擋住 export 類流程")
    }
}
