import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #586（Spectra change `divergence-dismissal`）：歧異記錄的移除面。spec 的四個 scenario 各一支，另加 id 不存在與理由過長。
final class DivergenceDismissalTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!
    private var divergenceID: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-dismiss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addPerson(key: "fann-cathy", names: ["Fann, Cathy"], orcid: nil, openalex: nil)
        _ = try service.addPerson(key: "fann-cathy-2", names: ["Fann, C."], orcid: nil, openalex: nil)
        _ = try service.recordDivergence(question: "兩筆是同一人嗎", candidates: ["fann-cathy:person", "fann-cathy-2:person"],
                                         judgement: nil, restsOn: [])
        divergenceID = try XCTUnwrap(LibraryStore(root: root).load().divergences.first).id.uuidString
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func state() throws -> (divergences: Int, people: [String]) {
        let l = try LibraryStore(root: root).load()
        return (l.divergences.count, l.people.map(\.key).sorted())
    }

    func testDismissalDeletesTheRecordAndNothingElse() throws {
        let peopleBefore = try LibraryStore(root: root).load().people
        let reason = String(repeating: "候選寫錯了", count: 200)   // 3,000 位元組：只在報告裡，所以要全文
        let out = try service.committed(root).dismissDivergence(id: divergenceID, reason: reason, dryRun: false)
        let d = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(d["dismissed"] as? Bool, true)
        XCTAssertEqual(d["reason"] as? String, reason)
        XCTAssertEqual(try state().divergences, 0)
        XCTAssertEqual(try LibraryStore(root: root).load().people, peopleBefore, "候選實體逐欄不動")
    }

    func testDismissalRequiresAReason() throws {
        for r in ["", "   \n"] {
            XCTAssertThrowsError(try service.committed(root).dismissDivergence(id: divergenceID, reason: r, dryRun: false))
        }
        XCTAssertThrowsError(try service.committed(root).dismissDivergence(
            id: divergenceID, reason: String(repeating: "x", count: 4_097), dryRun: false))
        XCTAssertEqual(try state().divergences, 1, "零寫入")
    }

    func testDismissalRefusesUncommittedOrUnversionedRecords() throws {
        // 不在 git 工作樹
        XCTAssertThrowsError(try service.dismissDivergence(id: divergenceID, reason: "r", dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("git"), "\(err)")
        }
        XCTAssertEqual(try state().divergences, 1)
        // 在 git 裡、但記錄檔有未提交修改
        StoreGitCommit.commitAll(root)
        let store = LibraryStore(root: root)
        var d = try XCTUnwrap(store.load().divergences.first)
        d.question = "改過的問題"
        _ = try store.writeDivergence(d)
        XCTAssertThrowsError(try service.dismissDivergence(id: divergenceID, reason: "r", dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("#586"), "\(err)")
        }
        XCTAssertEqual(try state().divergences, 1, "零寫入")
    }

    func testDryRunWritesNothing() throws {
        let out = try service.committed(root).dismissDivergence(id: divergenceID, reason: "r", dryRun: true)
        XCTAssertTrue(out.contains(divergenceID) && out.contains("\"dryRun\""), out)
        XCTAssertEqual(try state().divergences, 1)
    }

    func testUnknownOrMalformedIDIsRefused() throws {
        XCTAssertThrowsError(try service.committed(root).dismissDivergence(id: UUID().uuidString, reason: "r", dryRun: false))
        XCTAssertThrowsError(try service.committed(root).dismissDivergence(id: "not-a-uuid", reason: "r", dryRun: false))
        XCTAssertEqual(try state().divergences, 1)
    }
}

extension DivergenceDismissalTests {
    /// #75 的同一條理由：讀不懂的記錄不刪。
    func testRecordWithUnknownFieldsIsNotDismissed() throws {
        let store = LibraryStore(root: root)
        let rel = try XCTUnwrap(AkashicService.entityRelativePaths(root: root).values.first { p in
            (try? String(contentsOf: root.appendingPathComponent(p), encoding: .utf8))?.hasPrefix("divergence:") ?? false
        })
        let url = root.appendingPathComponent(rel)
        try (String(contentsOf: url, encoding: .utf8) + "future-veto: true\n").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().divergences.first?.unknownFields.count, 1, "前提：未知欄位被保留")
        XCTAssertThrowsError(try service.committed(root).dismissDivergence(id: divergenceID, reason: "r", dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("不認得的欄位"), "\(err)")
        }
        XCTAssertEqual(try state().divergences, 1, "零寫入")
    }
}
