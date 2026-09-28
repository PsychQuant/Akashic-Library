import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #588：ISSN 的移除面與「同一個 ISSN 掛在 2+ venue」的警告。
final class ISSNRemovalTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-issn-remove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root) }
    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
    }
    private func issns(_ key: String) throws -> [String] {
        try XCTUnwrap(try store.load().venues.first { $0.key == key }).issn.map(\.normalized)
    }
    /// JRSS-B 的兩個真號與一個姊妹刊（JRSS-C）的號。
    private func seed() throws {
        _ = try service.addVenue(key: "jrss-b", names: ["Journal of the Royal Statistical Society Series B"],
                                 type: "periodical", note: nil, issn: ["1369-7412", "1467-9868", "0035-9254"])
        GitFixture.commitAll(root)
    }

    func testRemovingAWrongISSNReportsTheReasonAndKeepsTheRest() throws {
        try seed()
        let out = json(try service.updateVenue(key: "jrss-b", addNames: nil, note: nil, type: nil,
                                               removeISSN: ["0035-9254=這是 Series C 的號，不是 B"]))
        XCTAssertEqual(try issns("jrss-b"), ["1369-7412", "1467-9868"])
        let removed = try XCTUnwrap(out["issnRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.first?["issn"] as? String, "0035-9254")
        XCTAssertTrue((removed.first?["reason"] as? String)?.contains("Series C") == true, "\(removed)")
        let yaml = try String(contentsOf: try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("entities"), includingPropertiesForKeys: nil).first))
        XCTAssertFalse(yaml.contains("Series C 的號"), "理由不寫進 store（使用者 2026-09-27 裁決）")
    }

    /// 理由只在報告裡，所以 git 裡要有副本：沒 commit 的修改整批拒絕、零寫入。
    func testRemovalRequiresTheVenueFileToBeCommitted() throws {
        try seed()
        _ = try service.updateVenue(key: "jrss-b", addNames: nil, note: "未提交的修改", type: nil)
        XCTAssertThrowsError(try service.updateVenue(key: "jrss-b", addNames: nil, note: nil, type: nil,
                                                     removeISSN: ["0035-9254=姊妹刊的號"])) { error in
            XCTAssertTrue("\(error)".contains("#588"), "\(error)")
        }
        XCTAssertEqual(try issns("jrss-b").count, 3, "零寫入")
    }

    func testInputErrorsRefuseTheWholeCall() throws {
        try seed()
        for bad in [["0035-9254"], ["0035-9254=  "], ["1234-5678=x"], ["0000-0000=x"],
                    ["0035-9254=a", "0035-9254=b"]] {
            XCTAssertThrowsError(try service.updateVenue(key: "jrss-b", addNames: nil, note: nil, type: nil,
                                                         removeISSN: bad), "\(bad)")
        }
        XCTAssertThrowsError(try service.updateVenue(key: "jrss-b", addNames: nil, note: nil, type: nil,
                                                     addISSN: ["0035-9254"], removeISSN: ["0035-9254=x"]),
                             "同一個號同時加與移除是矛盾")
        XCTAssertEqual(try issns("jrss-b").count, 3)
    }

    /// R1 verify 兩席：帶 `field: issn` provenance 的號，移除後 reference 成了孤兒、寫入閘拒絕整個呼叫，而沒有任何面刪得掉
    /// venue 的 reference——又回到手改 YAML。現在一併移除並逐號回報筆數；另一個號的 provenance 不動。
    func testProvenanceOfTheRemovedISSNGoesWithIt() throws {
        try seed()
        var v = try XCTUnwrap(try store.load().venues.first { $0.key == "jrss-b" })
        func retrieval(_ issn: String) -> ProvenanceReference {
            ProvenanceReference(field: "issn", value: issn,
                                kind: .retrieval(url: "https://portal.issn.org/", retrieved: "2026-09-27", status: 200,
                                                 mediaType: "text/html", content: "sha256:" + String(repeating: "a", count: 64)))
        }
        v.references = [retrieval("0035-9254"), retrieval("1369-7412")]
        try store.writeVenue(v)
        GitFixture.commitAll(root)
        let out = json(try service.updateVenue(key: "jrss-b", addNames: nil, note: nil, type: nil,
                                               removeISSN: ["0035-9254=Series C 的號"]))
        let after = try XCTUnwrap(try store.load().venues.first { $0.key == "jrss-b" })
        XCTAssertEqual(after.references.compactMap(\.value), ["1369-7412"], "只移除指向被移除號的那一筆")
        let removed = try XCTUnwrap(out["issnRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.first?["referencesRemoved"] as? Int, 1, "\(removed)")
    }

    /// 理由不進 store，報告是唯一的一份：不得截在入口上限（4,096 位元組）之下（R1 verify：曾截 600）。
    func testTheReasonIsReportedInFull() throws {
        try seed()
        let reason = String(repeating: "理", count: 1_000) + "尾段"
        let out = json(try service.updateVenue(key: "jrss-b", addNames: nil, note: nil, type: nil,
                                               removeISSN: ["0035-9254=" + reason]))
        let removed = try XCTUnwrap(out["issnRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.first?["reason"] as? String, reason)
    }

    /// 同一個 ISSN 掛在兩本刊上：warning，兩個 key 都點名。
    func testSharedISSNAcrossVenuesIsAWarning() throws {
        try seed()
        _ = try service.addVenue(key: "jrss-c", names: ["Journal of the Royal Statistical Society Series C"],
                                 type: "periodical", note: nil, issn: ["0035-9254"])
        let issues = try store.load().crossRecordIssues().filter { $0.message.contains("ISSN「0035-9254」") }
        XCTAssertEqual(issues.count, 1, "\(issues)")
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertTrue(issues.first?.message.contains("jrss-b") == true && issues.first?.message.contains("jrss-c") == true)
        XCTAssertFalse(try store.load().crossRecordIssues().contains { $0.message.contains("ISSN「1369-7412」") }, "只有一本刊的號不報")
    }
}
