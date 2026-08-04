import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// 6-AI verify（#71 R1）指出的 blocking findings 的回歸測試。
///
/// 每個測試對應一則 finding，測試名與 finding 的失敗情境一致。R1 的 verdict 是
/// FAIL（11 HIGH），這些是把它推回 PASS 的機械證據。
final class DivergenceHardeningTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-hard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - R1 #3：候選遷移只比 key、不比 shape

    /// 另一筆歧異記錄的候選同名但**不同形狀**時，不得被改寫，更不得被刪除。
    ///
    /// `shape:` 存進記錄的唯一理由就是「鍵在不同形狀之間可以同名」（organization spec
    /// 明載 key 與 person 同名是刻意的）。遷移不比 shape 等於把那個理由作廢。
    func testCandidateMigrationRespectsShape() throws {
        var p1 = Person(key: "academia-sinica-a"); p1.names = ["A"]
        var p2 = Person(key: "academia-sinica-b"); p2.names = ["B"]
        try store.writePerson(p1)
        try store.writePerson(p2)
        let personDiv = Divergence(
            id: UUID(), question: "同一人？",
            candidates: [DivergenceCandidate(key: "academia-sinica-a", shape: .person),
                         DivergenceCandidate(key: "academia-sinica-b", shape: .person)])
        // 完全不相干的機構歧異，候選鍵剛好同名。
        let orgDiv = Divergence(
            id: UUID(), question: "同一機構？",
            candidates: [DivergenceCandidate(key: "academia-sinica-b", shape: .organization),
                         DivergenceCandidate(key: "academia-sinica-c", shape: .organization)])
        try store.writeDivergence(personDiv)
        try store.writeDivergence(orgDiv)

        _ = try store.resolveDivergence(id: personDiv.id, survivor: "academia-sinica-a")

        let load = try store.load()
        let survivingOrg = try XCTUnwrap(load.divergences.first { $0.id == orgDiv.id },
                                         "不相干的機構歧異記錄被刪掉了")
        XCTAssertEqual(survivingOrg.candidates.map(\.key).sorted(),
                       ["academia-sinica-b", "academia-sinica-c"],
                       "不同形狀的同名候選不得被改寫：\(survivingOrg.candidates)")
    }

    // MARK: - R1 #4／#22：rests-on 靜默丟棄非 scalar

    /// `rests-on` 的元素不是 scalar 時擲錯，不得靜默丟棄。
    ///
    /// 失敗情境：`- sha256: 9a23…`（冒號後多一個空格）在 YAML 是 mapping。舊行為把它
    /// compactMap 掉——若還有其他合法項，那筆證據永久消失，而 canary 兩側都缺同一項
    /// 所以比對相等、照樣寫出。這正是 canary 要擋卻擋不到的靜默資料遺失。
    func testRestsOnNonScalarRefused() throws {
        let yaml = """
        divergence:
        id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
        question: 是否為同一人
        candidates:
        - key: fann-cathy-s-j
          shape: person
        - key: fann-cathy-s-j-2
          shape: person
        judgement: 兩者一致
        rests-on:
        - sha256: 9a23d701e4fe4888
        - sha256:ffff0000

        """
        XCTAssertThrowsError(try DivergenceYAML.decode(yaml)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("rests-on") || msg.contains("scalar"),
                          "錯誤須指向 rests-on 的形狀而非「成對」：\(msg)")
        }
    }

    // MARK: - R1 #5／#7／#9：刪除階段的失敗不中止後續刪除

    /// 被併實體刪不掉時，歧異記錄**不得**被刪——否則使用者連重跑的依據都沒了。
    func testDeleteFailureKeepsDivergenceRecord() throws {
        var keeper = Person(key: "fann-cathy-s-j"); keeper.names = ["Fann, Cathy S-J"]
        var doomed = Person(key: "fann-cathy-s-j-2"); doomed.names = ["Fann, Cathy S. J."]
        try store.writePerson(keeper)
        try store.writePerson(doomed)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)

        // 讓被併者的檔案刪不掉（immutable 擋 unlink）。
        let doomedURL = store.entityURL(id: doomed.id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: doomedURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false],
                                                       ofItemAtPath: doomedURL.path) }

        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertTrue(report.hasFailures, "刪除失敗必須進 failures")
        XCTAssertEqual(try store.load().divergences.count, 1,
                       "被併實體還在時，歧異記錄不得被刪——那是唯一能重跑的依據")
        XCTAssertTrue(report.merged.isEmpty, "沒真的併掉就不該回報 merged：\(report.merged)")
    }

    // MARK: - R1 #10／#17／#41：佈局硬綁 entities/

    /// legacy 佈局（format < 4）的 store 上，歧異記錄的寫入與消歧一律拒絕。
    ///
    /// DA 的更正指出真正的機制：`writeDivergence` 無條件寫進 `entities/`，而 person
    /// 在 legacy 佈局落在 `people/<key>.yaml`——刪除只用 `entityURL(id:)` 必然失敗，
    /// 停在「參照全改了、被併檔還在」的半完成狀態。拒絕比部分支援誠實。
    func testRefusesOnLegacyLayout() throws {
        let legacy = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: legacy) }
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent("entries"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try StoreVersion.write(root: legacy, format: 1)
        let s = LibraryStore(root: legacy)

        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "a-b", shape: .person),
                                        DivergenceCandidate(key: "a-b-2", shape: .person)])
        XCTAssertThrowsError(try s.writeDivergence(d)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("佈局") || msg.contains("format"),
                          "錯誤須說明佈局前提：\(msg)")
        }
    }

    // MARK: - R1 #11／#14／#19：合併只搬 names，其餘欄位靜默消失

    /// 被併 person 帶有倖存者沒有的識別碼時，拒絕合併並指名將失去什麼。
    ///
    /// 歧異的典型來源正是「兩個聚合器對同一位作者的比對結果不一致」——那種情況下
    /// 兩筆各帶一半識別碼的機率很高。靜默丟掉 ORCID 不可接受。
    func testMergeRefusesWhenMergedCarriesFieldsSurvivorLacks() throws {
        var keeper = Person(key: "fann-cathy-s-j"); keeper.names = ["Fann, Cathy S-J"]
        var doomed = Person(key: "fann-cathy-s-j-2")
        doomed.names = ["Fann, Cathy S. J."]
        doomed.orcid = "0000-0002-1825-0097"
        try store.writePerson(keeper)
        try store.writePerson(doomed)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)

        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("orcid"), "錯誤須指名將失去的欄位：\(msg)")
            XCTAssertTrue(msg.contains("0000-0002-1825-0097"), "錯誤須列出實際值：\(msg)")
        }
        XCTAssertEqual(try store.load().people.count, 2, "拒絕後不得有任何刪除")
    }

    /// 倖存者已持有同值時不算衝突，正常合併。
    func testMergeProceedsWhenFieldsAgree() throws {
        var keeper = Person(key: "fann-cathy-s-j")
        keeper.names = ["Fann, Cathy S-J"]; keeper.orcid = "0000-0002-1825-0097"
        var doomed = Person(key: "fann-cathy-s-j-2")
        doomed.names = ["Fann, Cathy S. J."]; doomed.orcid = "0000-0002-1825-0097"
        try store.writePerson(keeper)
        try store.writePerson(doomed)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertFalse(report.hasFailures, "\(report.failures)")
        XCTAssertEqual(try store.load().people.count, 1)
    }

    // MARK: - R1 #21／#25：work 合併造出自我引用

    /// 倖存者原本引用被併作品時，合併後不得變成引用自己。
    func testWorkMergeDoesNotCreateSelfReference() throws {
        var keeper = Entry(id: UUID(), citekey: "shen2015model", type: "article", title: "M")
        keeper.akashic.relations.cites = ["shen2015model-dup"]
        var dup = Entry(id: UUID(), citekey: "shen2015model-dup", type: "article", title: "M dup")
        try store.writeEntry(keeper)
        try store.writeEntry(dup)
        let d = Divergence(id: UUID(), question: "同一篇？",
                           candidates: [DivergenceCandidate(key: "shen2015model", shape: .work),
                                        DivergenceCandidate(key: "shen2015model-dup", shape: .work)])
        try store.writeDivergence(d)

        _ = try store.resolveDivergence(id: d.id, survivor: "shen2015model")
        let e = try XCTUnwrap(try store.load().entries.first { $0.citekey == "shen2015model" })
        XCTAssertFalse(e.akashic.relations.cites.contains("shen2015model"),
                       "合併不得造出自我引用：\(e.akashic.relations.cites)")
        _ = dup
    }

    // MARK: - R1 #20／#30：重複候選通過「至少兩個」

    /// 兩個一模一樣的候選不是歧異——它沒有東西可以與之相同。
    ///
    /// 舊行為讓它成為一條可執行、exit 0、無痕跡的「只刪記錄」路徑，而 spec 明文
    /// 拒絕提供那個操作。
    func testDuplicateCandidatesRefused() throws {
        let yaml = """
        divergence:
        id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
        question: 是否為同一人
        candidates:
        - key: fann-cathy-s-j
          shape: person
        - key: fann-cathy-s-j
          shape: person

        """
        XCTAssertThrowsError(try DivergenceYAML.decode(yaml)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("重複") || msg.contains("兩個"),
                          "錯誤須說明重複候選不構成歧異：\(msg)")
        }
    }

    // MARK: - R1 #16／#18／#23：canary 對未知欄位內容全盲

    /// 未知欄位的**內容**改變必須讓相等性判為不等，否則 canary 看不見它。
    func testEqualitySeesUnknownFieldContent() throws {
        let base = Divergence(
            id: UUID(uuidString: "6577DE3B-DAFE-5CC0-A9DE-2E04030737B3")!,
            question: "Q",
            candidates: [DivergenceCandidate(key: "a-b", shape: .person),
                         DivergenceCandidate(key: "a-c", shape: .person)],
            unknownFields: [UnknownField(key: "note", raw: "note: 原值\n")])
        var mutated = base
        mutated.unknownFields = [UnknownField(key: "note", raw: "note: 被改掉了\n")]
        XCTAssertNotEqual(base, mutated,
                          "只比 key 的相等性會讓 encode canary 對未知區塊內容全盲")
    }

    // MARK: - R1 #38：必填欄位接受空字串

    /// 空的 question 與空的候選鍵都不成立。
    func testEmptyRequiredFieldsRefused() throws {
        for (label, yaml) in [
            ("空 question", """
            divergence:
            id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
            question:
            candidates:
            - key: a-b
              shape: person
            - key: a-c
              shape: person

            """),
            ("空候選鍵", """
            divergence:
            id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
            question: Q
            candidates:
            - key:
              shape: person
            - key: a-c
              shape: person

            """),
        ] {
            XCTAssertThrowsError(try DivergenceYAML.decode(yaml), label)
        }
    }

    // MARK: - R1 #31／#34／#48：懸空候選沒有任何輸出說它壞了

    /// 候選指名的鍵不存在時，跨記錄檢查以 warning 指名該鍵。
    ///
    /// DA 的更正：這不是安全漏洞（候選鍵從未進過任何路徑），真正的後果是那筆記錄
    /// **永遠無法被消歧**且沒有任何輸出說它壞了。所以補的是可見性，不是 write gate。
    func testDanglingCandidateReportedAsWarning() throws {
        var p = Person(key: "fann-cathy-s-j"); p.names = ["F"]
        try store.writePerson(p)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "who-is-this", shape: .person)])
        try store.writeDivergence(d)

        let issues = try store.load().crossRecordIssues()
        let hit = issues.first { $0.message.contains("who-is-this") }
        XCTAssertNotNil(hit, "懸空候選必須被指名：\(issues.map(\.message))")
        XCTAssertEqual(hit?.severity, .warning,
                       "懸空參照在本 store 是 warning 而非 error——error 會鎖住整個寫入面")
    }
}
