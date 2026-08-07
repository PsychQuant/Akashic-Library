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

    /// 判斷本身錯了是常態——覆寫通道保留，但**要求理由**（判斷的變更也是判斷，
    /// 不能無聲蓋過）。#159 verify 159-2：舊名字叫 `testForce…` 是殘留——`--force`
    /// **從未存在過**，錯誤訊息叫人用它會拿到 `Unknown option '--force'`。
    func testOverrideRequiresReason() throws {
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

    // MARK: - #159 verify 的四個回歸

    /// **159-1**：preview 與實跑對同一組參數必須同進同出。
    ///
    /// 席位實測分岔且方向是壞的那個：`--dry-run --override-reason …` 被拒、拿掉
    /// `--dry-run` 卻成功——先跑 dry-run 的謹慎使用者被告知這件事做不到，唯一能
    /// 知道它會做什麼的方法是真的做下去，在一個會刪檔的操作上。根因是
    /// `previewResolveDivergence` 沒收 `overrideReason`、靜默吃到預設 nil。
    func testPreviewAndActualAgreeOnOverrideReason() throws {
        // (a) 兩邊都不帶 reason → 兩邊都要擲
        let d1 = try seedWithJudgement(prefers: "fann-a")
        XCTAssertThrowsError(try store.previewResolveDivergence(
            id: d1.id, survivor: "fann-b", overrideReason: nil), "preview 要擲")
        XCTAssertThrowsError(try store.resolveDivergence(
            id: d1.id, survivor: "fann-b"), "實跑要擲")

        // (b) 兩邊都帶 reason → 兩邊都要放行
        _ = try store.previewResolveDivergence(
            id: d1.id, survivor: "fann-b", overrideReason: "名冊確認 B")
        let actual = try store.resolveDivergence(
            id: d1.id, survivor: "fann-b", overrideReason: "名冊確認 B")
        XCTAssertEqual(actual.merged, ["fann-a"])
    }

    /// **159-5**：warning 在 preview 也要有。「有判斷但無 prefers、無從機械核對」
    /// 是決定要不要按下破壞性合併時最該看到的一條——只有實跑才印，等於在唯一還能
    /// 反悔的時點沉默。
    func testPreviewCarriesJudgementWarnings() throws {
        let d = try seedWithJudgement(prefers: nil)
        let preview = try store.previewResolveDivergence(
            id: d.id, survivor: "fann-b", overrideReason: nil)
        XCTAssertTrue(preview.warnings.contains { $0.contains("判斷") },
                      "preview 要帶同一組提醒：\(preview.warnings)")
        let actual = try store.resolveDivergence(id: d.id, survivor: "fann-b")
        XCTAssertEqual(preview.warnings, actual.warnings, "preview 與實跑的提醒必須一致")
    }

    /// **159-4**：重錄判斷不得靜默抹掉 `prefers`。
    ///
    /// 這是本 change 唯一能機械執法的東西——抹掉它，消歧就退回「只警告不擋」，
    /// 整個 #75 對一被一個省略的選填參數關掉。隔壁 20 行就有一道 #133 F1 的守衛
    /// 專門擋「無判斷的重呼叫靜默抹掉判斷」，這是同一個 bug class 在新欄位重演。
    func testRerecordCannotSilentlyDropPrefers() throws {
        var p1 = Person(key: "fann-a"); p1.names = ["Fann, A"]
        var p2 = Person(key: "fann-b"); p2.names = ["Fann, B"]
        try store.writePerson(p1); try store.writePerson(p2)
        let cands: [(key: String, shape: EntityKind)] =
            [("fann-a", .person), ("fann-b", .person)]
        _ = try store.recordDivergence(question: "同一人？", candidates: cands,
                                       judgement: "初判", restsOn: [digest],
                                       prefers: "fann-a")
        // 帶新 judgement、省略 prefers → 必須拒絕（不是靜默抹掉）
        XCTAssertThrowsError(try store.recordDivergence(
            question: "同一人？", candidates: cands,
            judgement: "再確認一次", restsOn: [digest], prefers: nil)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("fann-a"), "要說出既有傾向是什麼：\(msg)")
        }
        // 明確再帶一次同值 → 放行；磁碟上仍在
        _ = try store.recordDivergence(question: "同一人？", candidates: cands,
                                       judgement: "再確認一次", restsOn: [digest],
                                       prefers: "fann-a")
        let reload = try store.load().divergences.first { $0.candidates.count == 2 }
        XCTAssertEqual(reload?.judgement?.prefers, "fann-a", "沿用時要留著")
        XCTAssertEqual(reload?.judgement?.statement, "再確認一次", "judgement 照常更新")
        // 改傾向 → 放行（那是刻意動作）
        _ = try store.recordDivergence(question: "同一人？", candidates: cands,
                                       judgement: "改判", restsOn: [digest],
                                       prefers: "fann-b")
        XCTAssertEqual(try store.load().divergences.first?.judgement?.prefers, "fann-b")
    }
}
