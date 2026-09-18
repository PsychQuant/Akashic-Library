import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 歧異記錄的候選 shape 沒有合併管線（#555 R2，D90）：記得起來（`byShape` 收）、解不掉
/// （`resolveDivergence` 擲 `unsupportedShape`）。`zero-instance-guards` 第 24 列裁「暫不做」的
/// 觸發條件之一自此由工具出聲——第 16 列的紀律：散文觸發條件沒有機制會叫醒任何人（#555 R1 verify
/// 第 13 列：第一筆 org divergence 在 doctor／App 上與一筆正常待判的 person 歧異長得完全一樣）。
final class UnmergeableDivergenceScanTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func seedPeople() throws {
        var a = Person(key: "a-b", names: ["A B"]); try store.writePerson(a)
        var c = Person(key: "c-d", names: ["C D"]); try store.writePerson(c)
        a.names = ["A B"]; c.names = ["C D"]
    }
    private func seedOrgs() throws {
        var a = Organization(key: "org-a", names: Timeline([TemporalValue(value: "Org A")]))
        var b = Organization(key: "org-b", names: Timeline([TemporalValue(value: "Org B")]))
        _ = try store.writeOrganization(a); _ = try store.writeOrganization(b)
        a.key = "org-a"; b.key = "org-b"
    }

    /// 乾淨的 store（person 攣生——解得掉）是零：恆非空的掃描分不出「有實例」與「掃描壞了」。
    func testMergeableShapesReportNothing() throws {
        try seedPeople()
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "a-b", shape: .person),
                                        DivergenceCandidate(key: "c-d", shape: .person)])
        try store.writeDivergence(d)
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.unmergeableDivergences.count, 0, "\(health.unmergeableDivergences.map(\.issue.message))")
    }

    /// 含 org 候選的記錄 → 一則 warning，說得出是哪筆、哪個候選、支援的是哪些 shape、處置指向第 24 列與 #586。
    func testOrganizationCandidateIsReported() throws {
        try seedOrgs()
        let d = Divergence(id: UUID(), question: "同一個機構嗎",
                           candidates: [DivergenceCandidate(key: "org-a", shape: .organization),
                                        DivergenceCandidate(key: "org-b", shape: .organization)])
        try store.writeDivergence(d)
        let health = store.health(from: try store.load())
        let got = health.unmergeableDivergences
        XCTAssertEqual(got.count, 1, "一筆記錄一則，不是每個候選一則：\(got.map(\.issue.message))")
        guard let first = got.first else { return }   // 斷言已紅；不要再 got[0] 越界把整個 test process 帶走（NC harness 才分得出 RED 與 crash）
        XCTAssertEqual(first.owner, d.id.uuidString)
        XCTAssertEqual(first.kind, "divergence")
        XCTAssertEqual(first.issue.severity, .warning, "記錄合法可載入，失效的是處置面——error 會擋住 export 類流程")
        let m = first.issue.message
        XCTAssertTrue(m.hasPrefix(StoreHealth.unmergeableDivergencePrefix), m)
        XCTAssertTrue(m.contains("org-a") && m.contains("organization") && m.contains("#586") && m.contains("第 24 列"), m)
        for s in DivergenceResolveError.mergeableShapes { XCTAssertTrue(m.contains(s), "訊息要說出支援的 \(s)：\(m)") }
        XCTAssertTrue(health.perRecordIssues.contains { $0.issue.message == m }, "住在 perRecordIssues——三個面同一條路徑")
    }
}
