import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #75 對一：消歧要看已寫下的判斷。
///
/// 病：`judgement` 是「唯一會用到它的操作」（消歧）對它惰性——寫判斷就變成純檔案
/// 裝飾。但 `statement` 是自由文字，「它指向哪個候選」無法機械判定，所以判斷層加
/// 一個**選填的結構化欄位** `prefers: <key>`：有它才比對，沒有就退回警告。
///
/// **不自動採信**（diagnosis 的關鍵論證）：#133 起判斷可經 MCP 由 LLM 寫入——
/// 「消歧自動照 prefers 執行」＝把「當場判斷」換成「延遲自動判斷」，#71 的人工
/// 確認底線被繞過。survivor 仍必須是消歧當下的人工輸入；`prefers` 只用來**擋下
/// 不一致**（prefers ≠ survivor → 拒絕），不用來代選。
final class JudgementPrefersTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-prefers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    /// prefers 是選填——沒有它的判斷照舊（向後相容）。
    func testJudgementWithoutPrefersRoundTrips() throws {
        let d = Divergence(
            id: UUID(), question: "同一人？",
            candidates: [DivergenceCandidate(key: "a", shape: .person),
                         DivergenceCandidate(key: "b", shape: .person)],
            judgement: Judgement(statement: "看起來是", restsOn: [digest]))
        let text = try DivergenceYAML.encode(d)
        XCTAssertFalse(text.contains("prefers"), "沒指定就不寫出該鍵：\(text)")
        XCTAssertEqual(try DivergenceYAML.decode(text), d)
    }

    func testPrefersRoundTrips() throws {
        let d = Divergence(
            id: UUID(), question: "同一人？",
            candidates: [DivergenceCandidate(key: "a", shape: .person),
                         DivergenceCandidate(key: "b", shape: .person)],
            judgement: Judgement(statement: "a 是正式寫法", restsOn: [digest], prefers: "a"))
        let text = try DivergenceYAML.encode(d)
        XCTAssertTrue(text.contains("prefers: a"), text)
        XCTAssertEqual(try DivergenceYAML.decode(text), d)
        XCTAssertEqual(try DivergenceYAML.encode(try DivergenceYAML.decode(text)), text,
                       "位元組冪等")
    }

    /// prefers 必須是**本記錄的候選之一**——指向別的東西是無法執行的判斷。
    func testPrefersMustBeACandidate() throws {
        let text = """
        divergence:
        id: 11111111-2222-3333-4444-555555555555
        question: 同一人？
        candidates:
        - key: a
          shape: person
        - key: b
          shape: person
        judgement: c 才對
        prefers: c
        rests-on:
        - \(digest)
        """
        XCTAssertThrowsError(try DivergenceYAML.decode(text)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("prefers") && msg.contains("候選"), msg)
        }
    }

    /// prefers 沒有 judgement 時無意義——成對要求（同 judgement/rests-on）。
    func testPrefersWithoutJudgementRejected() throws {
        let text = """
        divergence:
        id: 11111111-2222-3333-4444-555555555555
        question: 同一人？
        candidates:
        - key: a
          shape: person
        - key: b
          shape: person
        prefers: a
        """
        XCTAssertThrowsError(try DivergenceYAML.decode(text))
    }

    // MARK: - 消歧的一致性檢查

    private func seedWithJudgement(prefers: String?) throws -> Divergence {
        var p1 = Person(key: "fann-a"); p1.names = ["Fann, A"]
        var p2 = Person(key: "fann-b"); p2.names = ["Fann, B"]
        try store.writePerson(p1); try store.writePerson(p2)
        let d = Divergence(
            id: UUID(), question: "同一人？",
            candidates: [DivergenceCandidate(key: "fann-a", shape: .person),
                         DivergenceCandidate(key: "fann-b", shape: .person)],
            judgement: Judgement(statement: "判斷", restsOn: [digest], prefers: prefers))
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }

    /// prefers 與 survivor 不一致 → **拒絕**（消歧不再對已寫下的判斷惰性）。
    func testResolveRefusedWhenSurvivorContradictsPrefers() throws {
        let d = try seedWithJudgement(prefers: "fann-a")
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-b")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("fann-a") && msg.contains("fann-b"),
                          "訊息要指出判斷偏好誰、你選了誰：\(msg)")
        }
    }

    func testResolveProceedsWhenSurvivorMatchesPrefers() throws {
        let d = try seedWithJudgement(prefers: "fann-a")
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-a")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.merged, ["fann-b"])
    }

    /// 判斷本身錯了是常態——`--force` 通道保留，但**要求覆寫理由**（判斷的變更
    /// 也是判斷，不能無聲蓋過）。
    func testForceOverridesWithReason() throws {
        let d = try seedWithJudgement(prefers: "fann-a")
        XCTAssertThrowsError(try store.resolveDivergence(
            id: d.id, survivor: "fann-b", overrideReason: ""),
            "force 但沒給理由——不接受")
        let report = try store.resolveDivergence(
            id: d.id, survivor: "fann-b", overrideReason: "名冊確認 B 才是正式寫法")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.merged, ["fann-a"])
    }

    /// 無 prefers 的判斷 → 不擋，但**警告**（判斷存在、請自行核對）。
    func testWarnsWhenJudgementHasNoPrefers() throws {
        let d = try seedWithJudgement(prefers: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-b")
        XCTAssertEqual(report.failures, [])
        XCTAssertTrue(report.warnings.contains { $0.contains("判斷") },
                      "有判斷但無 prefers → 提醒人自行核對：\(report.warnings)")
    }
}
