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

    /// **#159 verify §6**：不可逆操作不得在帶有本 binary 不理解欄位的記錄上執行。
    ///
    /// 觸發它的實驗：塞一個叫 `future-veto` 的未知欄位，新 binary 的 `validate`
    /// **會印出**「未知欄位（已保留）」——它知道自己讀不懂——然後照樣把記錄連同
    /// 那個欄位一起刪掉。明知有讀不懂的東西還做不可逆刪除，與上游那道
    /// 「quarantined 檔讀不到就改寫不到」的 gate 是同一條理由的另一面。
    ///
    /// 這是 verify 席駁回「為 prefers bump format」時給的替代方案：版本無關、一次
    /// 保護所有未來欄位、代價侷限在該筆記錄（bump 是整庫拒開）。
    func testRefusesToResolveRecordWithUnknownFields() throws {
        var p1 = Person(key: "fann-a"); p1.names = ["Fann, A"]
        var p2 = Person(key: "fann-b"); p2.names = ["Fann, B"]
        try store.writePerson(p1); try store.writePerson(p2)
        let d = Divergence(
            id: UUID(), question: "同一人？",
            candidates: [DivergenceCandidate(key: "fann-a", shape: .person),
                         DivergenceCandidate(key: "fann-b", shape: .person)],
            unknownFields: [UnknownField(key: "future-veto", raw: "future-veto: 別合併\n")])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed unknown")

        // 記錄真的帶著那個欄位（不是被 encode 丟掉——否則這條測試是空的）
        let reloaded = try store.load().divergences.first { $0.id == d.id }
        XCTAssertEqual(reloaded?.unknownFields.map(\.key), ["future-veto"],
                       "未知欄位要被保留，測試才有東西可擋")

        // **preview 與實跑都要擋**（gate 在共用驗證裡——否則 dry-run 會說「沒問題」）
        for (label, run) in [
            ("preview", { try self.store.previewResolveDivergence(
                id: d.id, survivor: "fann-a", overrideReason: nil) }),
            ("actual", { try self.store.resolveDivergence(id: d.id, survivor: "fann-a") }),
        ] {
            XCTAssertThrowsError(try run(), "\(label) 要擋") { error in
                guard case DivergenceResolveError.recordHasUnknownFields(_, let fields) = error else {
                    return XCTFail("\(label) 預期 recordHasUnknownFields，實得 \(error)")
                }
                XCTAssertEqual(fields, ["future-veto"], "要說出是哪個欄位擋住的")
            }
        }
        // 記錄與兩個候選都還在——擋下來就不該有任何副作用
        XCTAssertEqual(try store.load().divergences.count, 1)
        XCTAssertEqual(try store.load().people.count, 2)
    }

    /// **gate 涵蓋另外兩類記錄**（#159 verify 159-12）：第一版只守使用者指名的那筆，
    /// 但這個操作親手摧毀／改寫的 divergence 有三類。席位實測另外兩類都放行：
    ///
    /// - `collapsed`：候選遷移後與目標重複 → **一併刪除**，帶著它的未知欄位
    /// - `toWrite`：候選被 read-modify-write 改寫 → 產出**自相矛盾**的檔案（候選
    ///   改成 `fann-b`，未知欄位仍指著全庫已無的 `fann-a`）
    ///
    /// 沒有測試就沒有這個發現——mutation 只能證明「寫下來的那條被測到」，證不了
    /// 「沒寫的那條不存在」。
    func testGateCoversCollapsedAndRewrittenRecords() throws {
        func seed(extraCandidate: String?, unknown: String) throws -> UUID {
            var p1 = Person(key: "fann-a"); p1.names = ["Fann, A"]
            var p2 = Person(key: "fann-b"); p2.names = ["Fann, B"]
            var p3 = Person(key: "chen-a"); p3.names = ["Chen, A"]
            try store.writePerson(p1); try store.writePerson(p2); try store.writePerson(p3)
            let main = Divergence(
                id: UUID(), question: "同一人？",
                candidates: [DivergenceCandidate(key: "fann-a", shape: .person),
                             DivergenceCandidate(key: "fann-b", shape: .person)])
            try store.writeDivergence(main)
            var others = [DivergenceCandidate(key: "fann-a", shape: .person)]
            if let e = extraCandidate { others.append(DivergenceCandidate(key: e, shape: .person)) }
            else { others.append(DivergenceCandidate(key: "fann-b", shape: .person)) }
            let other = Divergence(
                id: UUID(), question: "另一筆", candidates: others,
                unknownFields: [UnknownField(key: unknown, raw: "\(unknown): x\n")])
            try store.writeDivergence(other)
            GitFixture.commitAll(root, message: "seed")
            return main.id
        }

        // (a) collapsed：候選 {fann-a, fann-b} → 遷移後與目標重複 → 連帶刪除
        let idA = try seed(extraCandidate: nil, unknown: "future-veto")
        XCTAssertThrowsError(try store.resolveDivergence(id: idA, survivor: "fann-b")) { e in
            guard case DivergenceResolveError.recordHasUnknownFields(_, let f) = e else {
                return XCTFail("collapsed 那筆要擋，實得 \(e)")
            }
            XCTAssertEqual(f, ["future-veto"])
        }
        try? FileManager.default.removeItem(at: root)
        try setUpWithError()

        // (b) toWrite：候選 {fann-a, chen-a} → fann-a 改寫成 fann-b，記錄被改寫
        let idB = try seed(extraCandidate: "chen-a", unknown: "future-candidate-meta")
        XCTAssertThrowsError(try store.resolveDivergence(id: idB, survivor: "fann-b")) { e in
            guard case DivergenceResolveError.recordHasUnknownFields(_, let f) = e else {
                return XCTFail("toWrite 那筆要擋，實得 \(e)")
            }
            XCTAssertEqual(f, ["future-candidate-meta"])
        }
        // 兩筆記錄都還在——擋下來零副作用
        XCTAssertEqual(try store.load().divergences.count, 2)
    }
}
