import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// `record-divergence` 撞上「同一個 id 已被另一組候選占著」時，**使用者實際讀到的輸出**要看得到出路（#611 R3 verify 第 1／2／5／8 列）。
///
/// R2 的拒絕訊息是約 550 字的單行、出路從第 390 字起，CLI 頂層的錯誤出口逐行截 400——stderr 印到「先處置…（已截斷）」為止，
/// `dismiss-divergence`、`resolve-divergence` 一個都看不到；而單元測試斷言的是未截的 `localizedDescription`，所以綠著。
/// 這裡走**真 binary**，斷言 sink 之後的文字。候選 key 用真實長度的 citekey（越長，R2 的截點越早）。
final class DivergenceIdRefusalCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-divid-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-divid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        try LibraryStore(root: root).ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    func testTheRefusalShowsThePathOutAfterTheSink() throws {
        let a = "vanderwaals2025identifiabilityofpolychoriccorrelationmodelsundermisspecification"
        let b = "kowalczykiewicz2025estimatingthresholdsinordinalfactoranalysiswithmissingdata"
        let store = LibraryStore(root: root)
        for key in [a, a + "-renamed", b] {
            try store.writeEntry(Entry(id: UUID(), citekey: key, type: .periodicalArticle, title: key))
        }
        // `rename` 之後的形狀：id 是 H({a, b})，候選已被就地改寫成 {a-renamed, b}（rename 不重算 id）
        let id = DeterministicUUID.forDivergence(candidateKeys: [a, b])
        _ = try store.writeDivergence(Divergence(id: id, question: "已改名的一組",
                                                 candidates: [a + "-renamed", b].map { DivergenceCandidate(key: $0, shape: .work) }))

        let r = try CLITestHarness.run(["record-divergence", "--question", "又一次",
                                        "--candidate", "\(a):work", "\(b):work", "--library", root.path], env: env)

        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("akashic dismiss-divergence \(id.uuidString) --reason"), "出路要在使用者看得到的輸出裡：\(r.output)")
        XCTAssertTrue(r.output.contains("akashic resolve-divergence") && r.output.contains("akashic divergences"), r.output)
        XCTAssertTrue(r.output.contains("\(a)-renamed"), "現有那一筆的候選：\(r.output)")
        XCTAssertTrue(r.output.contains("key 不同"), r.output)
        let refusal = r.output.split(separator: "\n").filter { !$0.isEmpty }
        let dismissLine = try XCTUnwrap(refusal.firstIndex { $0.contains("dismiss-divergence") }, r.output)
        XCTAssertLessThanOrEqual(dismissLine, 2, "出路在前兩行（匯入列接成一行之後 MCP 再截 512，出路要在前面）：\(r.output)")
        XCTAssertFalse(r.output.contains("（已截斷）"), "每一行都在 sink 的 400 之內，沒有一行被截：\(r.output)")
    }
}
