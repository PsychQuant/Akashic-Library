import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564 b40 Z1 的合併三則（b41 Q1）——都不改合併的行為，釘住它實際做什麼：
///
/// - 第 3／12 列：攣生豁免放行之後，合併照搬記錄的規則（`carryCollecting`）仍會**重搬**被併者較早的記錄。名字仍在 authorized、兩筆攣生都持有
///   「指定 R → 撤回 W」時，倖存者的尾端本身矛盾，「倖存者已有、而且此刻尾端一致才略過」不成立，「指定 R」被接在撤回之後——倖存者的最後一筆
///   從撤回變成指定。「什麼都不搬、倖存者記錄不變」只對單筆指定、名字不在分割的那一種攣生成立。被豁免的攣生該不該停止重搬，待使用者裁決；
///   裁決之前這裡斷言的是現況。
/// - 第 10 列：「同一個矛盾」要同一個方向（`heldKey`）——方向不同的形狀，載入時就被隔離（名字分類記錄錨定 names），在載得進來的 store 上到不了。
///   方向那一項保留（程式不改），測試說清楚它釘的是記憶體裡的定義。
final class NameClassificationMergeB41Tests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncm41-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }

    /// INFO 第 12 列的真 binary 重現，改走 store：兩筆 person 逐位元組持有「指定 R → 撤回 W」、名字仍在 authorized（倖存者原本就有「仍在卻以撤回結尾」
    /// 的矛盾）。合併放行（條件 2 豁免），預覽與實跑都搬一筆「指定 R」，合併後倖存者的記錄是 [指定 R, 撤回 W, 指定 R]、最後一筆是指定。
    func testTwinsEndingInAWithdrawalOnAStillAuthorizedNameRecarryTheEarlierDesignation() throws {
        let history = [record("authorized", "Mei Lin", .designate, "R"), record("authorized", "Mei Lin", .withdraw, "W")]
        for key in ["pk", "pd"] {
            var p = Person(key: key, names: PersonNames(authorized: ["Mei Lin"], variant: []))
            p.references = history
            _ = try store.writePerson(p)
        }
        let d = Divergence(id: UUID(), question: "同一個人嗎", candidates: ["pk", "pd"].map { DivergenceCandidate(key: $0, shape: .person) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        let carried = LibraryStore.describeCarriedReference("pd", history[0], kind: "person")
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "pk", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried, [carried], "較早的指定被重搬（不是什麼都不搬）")
        let report = try store.resolveDivergence(id: d.id, survivor: "pk")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, [carried], "預覽與實跑同一份")
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "pk" })
        XCTAssertEqual(kept.references.map(\.byteExactKey), (history + [history[0]]).map(\.byteExactKey))
        XCTAssertEqual(NameClassificationRecord.latestAction(in: kept.references, name: "Mei Lin"), .designate,
                       "倖存者的最後一筆從撤回變成指定——合併改了倖存者原本的最後一筆（現況；待使用者裁決）")
    }

    /// 第 10 列：方向那一項（`heldKey` 的「仍在／不在」）唯一會改變結論的形狀——倖存者持有一筆錨不到它 names 的名字分類記錄——寫到磁碟上就載不進來。
    /// `NameClassificationMergeB39Tests.testASurvivorContradictionInTheOtherDirectionDoesNotExempt` 在記憶體裡建那個倖存者，釘的是定義本身。
    func testTheOtherDirectionShapeDoesNotLoad() throws {
        // 手寫 YAML：encode 自己的 canary decode 就會擋下這筆（寫入面寫不出它）——磁碟上只能是手改
        let id = UUID()
        let yaml = "venue:\nid: \(id.uuidString)\nkey: kx\ntype: periodical\nnames:\n- value: Main J\nauthorized:\n- Main J\n"
            + "references:\n- field: variant\n  value: X J\n  judgement: 指定：手改\n  rests-on: []\n"
        let file = root.appendingPathComponent("entities").appendingPathComponent("\(id.uuidString).yaml")
        try yaml.write(to: file, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertFalse(load.venues.contains { $0.key == "kx" }, "錨不到 names 的名字分類記錄讓整筆隔離")
        XCTAssertTrue(load.quarantined.contains { $0.reason.contains("名字分類的判定記錄錨定在 names") }, "\(load.quarantined)")
    }
}
