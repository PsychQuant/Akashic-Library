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
        // #73：真 repo。版控前提升級成「要刪的檔案 tracked 且 clean」之後，
        // 假 `.git` 目錄不再夠用。
        GitFixture.initRepo(root)
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

        // #73：resolve 之前先 commit——被測的是消歧本身，不是「未 commit 會被擋」。
        // 後者由 DivergenceResolveTests 的三個專門測試覆蓋。
        GitFixture.commitAll(store.root)
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

        GitFixture.commitAll(store.root)
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
        GitFixture.initRepo(legacy)
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

        GitFixture.commitAll(store.root)
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
        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertFalse(report.hasFailures, "\(report.failures)")
        XCTAssertEqual(try store.load().people.count, 1)
    }

    // MARK: - R1 #21／#25：work 合併造出自我引用

    /// 倖存者原本引用被併作品時，合併後不得變成引用自己。
    func testWorkMergeDoesNotCreateSelfReference() throws {
        var keeper = Entry(id: UUID(), citekey: "shen2015model", type: "article", title: "M")
        keeper.akashic.relations.cites = ["shen2015model-dup"]
        let dup = Entry(id: UUID(), citekey: "shen2015model-dup", type: "article", title: "M dup")
        try store.writeEntry(keeper)
        try store.writeEntry(dup)
        let d = Divergence(id: UUID(), question: "同一篇？",
                           candidates: [DivergenceCandidate(key: "shen2015model", shape: .work),
                                        DivergenceCandidate(key: "shen2015model-dup", shape: .work)])
        try store.writeDivergence(d)

        GitFixture.commitAll(store.root)
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

    // MARK: - R2：讀不到的檔可能正指著要被刪掉的東西

    /// store 有任何 quarantined 檔時，消歧拒絕執行。
    ///
    /// quarantined 檔沒進 `snapshot.entries`，它的參照永遠不會被改寫，卻擋不住刪除
    /// ——留下一筆藏在工具讀不到的檔案裡、`crossRecordIssues()` 也掃不到的永久懸空
    /// 參照。與本檔對 legacy 佈局的立場（拒絕比部分支援誠實）是同一條理由。
    func testQuarantinedFileBlocksResolve() throws {
        var keeper = Person(key: "fann-cathy-s-j"); keeper.names = ["F"]
        var doomed = Person(key: "fann-cathy-s-j-2"); doomed.names = ["F2"]
        try store.writePerson(keeper)
        try store.writePerson(doomed)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)
        // 一個檔名 UUID 與內容 id 不符的檔 → load() 會 quarantine 它。
        let stray = root.appendingPathComponent("entities/\(UUID().uuidString).yaml")
        try "work:\nid: \(UUID().uuidString)\ncitekey: ghost\ntype: article\ntitle: G\n"
            .write(to: stray, atomically: true, encoding: .utf8)

        XCTAssertFalse(try store.load().quarantined.isEmpty, "前提：該檔應被 quarantine")
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("讀不進來"), "錯誤須說明理由：\(msg)")
        }
        XCTAssertEqual(try store.load().people.count, 2, "拒絕後不得有任何刪除")
    }

    // MARK: - R2：消歧不是清理工具

    /// 沒指名被併鍵的記錄不得被改動——即使它自己有既存的重複作者。
    func testUnrelatedRecordWithDuplicateAuthorsLeftAlone() throws {
        var keeper = Person(key: "fann-cathy-s-j"); keeper.names = ["F"]
        var doomed = Person(key: "fann-cathy-s-j-2"); doomed.names = ["F2"]
        var other = Person(key: "someone-else"); other.names = ["S"]
        try store.writePerson(keeper); try store.writePerson(doomed); try store.writePerson(other)
        // 這筆與本次消歧無關，但它自己有重複作者。
        var unrelated = Entry(id: UUID(), citekey: "unrelated2020", type: "article", title: "U")
        unrelated.authors = [.key("someone-else"), .key("someone-else")]
        try store.writeEntry(unrelated)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)

        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertFalse(report.rewritten.contains("unrelated2020"),
                       "無關記錄不該被算進 rewritten：\(report.rewritten)")
        let e = try XCTUnwrap(try store.load().entries.first { $0.citekey == "unrelated2020" })
        XCTAssertEqual(e.authors, [.key("someone-else"), .key("someone-else")],
                       "既存的重複不該被順手折疊——消歧不是清理工具：\(e.authors)")
    }

    // MARK: - R2：rename 之後歧異候選要跟著走

    /// `rename` 遷移歧異記錄的 work 候選，否則那筆歧異永遠無法被消歧。
    func testRenameMigratesDivergenceCandidates() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "jou2025generalized",
                                   type: "article", title: "G"))
        try store.writeEntry(Entry(id: UUID(), citekey: "jou2026generalized",
                                   type: "article", title: "G2"))
        let d = Divergence(id: UUID(), question: "同一篇？",
                           candidates: [DivergenceCandidate(key: "jou2025generalized", shape: .work),
                                        DivergenceCandidate(key: "jou2026generalized", shape: .work)])
        try store.writeDivergence(d)

        _ = try store.renameEntry(from: "jou2025generalized", to: "jou2025generalized-v2")
        let after = try XCTUnwrap(try store.load().divergences.first)
        XCTAssertEqual(after.candidates.map(\.key).sorted(),
                       ["jou2025generalized-v2", "jou2026generalized"],
                       "候選沒跟著改名，這筆歧異就再也消不掉：\(after.candidates)")
    }

    /// 改名會讓兩個候選塌縮成一個時，`rename` 拒絕——它沒有合併語意。
    func testRenameRefusesWhenItWouldCollapseADivergence() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "chu2024pseudo", type: "article", title: "P"))
        let d = Divergence(id: UUID(), question: "同一篇？",
                           candidates: [DivergenceCandidate(key: "chu2024pseudo", shape: .work),
                                        DivergenceCandidate(key: "chu2025pseudo", shape: .work)])
        try store.writeDivergence(d)
        XCTAssertThrowsError(try store.renameEntry(from: "chu2024pseudo", to: "chu2025pseudo")) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            // 指示必須**可執行**。原本寫「先跑 resolve-divergence」，但能走到這裡
            // 代表新 citekey 是懸空候選，消歧對它只會擲 candidateMissing——那是一條
            // 做不到的指示，而測試把它固定成了契約（#71 R2 DA 未修好 6）。
            XCTAssertTrue(msg.contains("entities/"), "錯誤須給出可執行的操作：\(msg)")
            XCTAssertFalse(msg.contains("先跑 resolve-divergence"),
                           "不得指向一條做不到的操作：\(msg)")
        }
    }

    // MARK: - R2：寫入面的鍵驗證與 validate 的可見性

    /// 畸形候選鍵不得被寫出——否則會產生一筆自己的 validate 永遠不通過、
    /// 而又沒有編輯入口可修的記錄。
    func testWriteRefusesInvalidCandidateKey() throws {
        let d = Divergence(id: UUID(), question: "Q",
                           candidates: [DivergenceCandidate(key: "../../etc/passwd", shape: .person),
                                        DivergenceCandidate(key: "ok-key", shape: .person)])
        XCTAssertThrowsError(try store.writeDivergence(d))
    }

    /// 未知欄位在 `validate()` 現身——`akashic validate` 的提示只來自這條路徑。
    func testValidateSurfacesUnknownFields() throws {
        let d = Divergence(
            id: UUID(), question: "Q",
            candidates: [DivergenceCandidate(key: "a-b", shape: .person),
                         DivergenceCandidate(key: "a-c", shape: .person)],
            unknownFields: [UnknownField(key: "confidence_note", raw: "confidence_note: x\n")])
        let issues = d.validate()
        XCTAssertTrue(issues.contains { $0.message.contains("confidence_note") },
                      "未知欄位必須被指名，否則 validate 會印「全部通過」：\(issues.map(\.message))")
        XCTAssertEqual(issues.first?.severity, .warning)
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

    // MARK: - R3：DA 抓到的、R2 修復自己引入的缺陷

    /// **倖存者比被併者豐富**時照樣合併——這是消歧的常態，不是例外。
    ///
    /// R2 的修復用整體相等（「要嘛與倖存者相同、要嘛全預設」）當判定，於是使用者
    /// 把資料較完整的那筆選為倖存者就被擋死，儘管沒有任何東西會消失。子集關係
    /// 無法用相等表達（#71 R2 DA 未修好 1，附實測）。
    func testMergeProceedsWhenSurvivorIsRicher() throws {
        var keeper = Person(key: "fann-cathy-s-j")
        keeper.names = ["Fann, Cathy S-J"]
        keeper.orcid = "0000-0002-1825-0097"
        keeper.note = "中研院統計所"
        var doomed = Person(key: "fann-cathy-s-j-2")
        doomed.names = ["Fann, Cathy S. J."]
        doomed.orcid = "0000-0002-1825-0097"   // 同值，不會失去
        try store.writePerson(keeper); try store.writePerson(doomed)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)

        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertFalse(report.hasFailures, "\(report.failures)")
        let p = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(p.note, "中研院統計所", "倖存者自己的資料不得被合併影響")
    }

    /// `Person` 加欄位而合併檢查沒跟上時，這條會紅。
    ///
    /// 逐欄是必要的（子集關係無法用相等表達），所以防腐不能靠結構比較——靠反射
    /// 數屬性。這是「白名單會靜默失效」的機械解答。
    /// #157 verify 157-4：work 側的同型防腐——`Entry` 加欄位而 work 合併檢查沒跟上
    /// 時這條會紅。person 側有守衛、work 側先前沒有（同一個 feature 的兩半不對稱）。
    func testEntryFieldCoverageOfMergeCheck() throws {
        let n = Mirror(reflecting: Entry(id: UUID(), citekey: "x", type: "article",
                                         title: "T")).children.count
        XCTAssertEqual(n, LibraryStore.entryFieldsCoveredByMergeCheck,
                       "Entry 的儲存屬性數變了（\(n)）——請同步更新 "
                       + "LibraryStore.fieldsLostByMerging(_:into:) 的 Entry 版與這個常數"
                       + "（刻意排除的欄位見該函式下方的 doc）")
    }

    func testPersonFieldCoverageOfMergeCheck() throws {
        let n = Mirror(reflecting: Person(key: "x")).children.count
        XCTAssertEqual(n, LibraryStore.personFieldsCoveredByMergeCheck,
                       "Person 的儲存屬性數變了（\(n)），"
                       + "請同步更新 LibraryStore.fieldsLostByMerging 與這個常數"
                       + "——否則新欄位會在合併時靜默消失")
    }

    /// 畸形候選鍵的記錄在**載入時**就被 quarantine，不會留在 store 裡擋別人。
    ///
    /// 只有 write-time 守衛而沒有 load-time quarantine，會讓一筆手寫的壞記錄在改寫
    /// 階段才引爆——而那時倖存者的別名已經落地（#71 R2 DA PROBE 12）。
    func testMalformedCandidateKeyQuarantinedAtLoad() throws {
        let id = UUID()
        try """
        divergence:
        id: \(id.uuidString)
        question: Q
        candidates:
        - key: Bad_Key
          shape: person
        - key: ok-key
          shape: person

        """.write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertTrue(load.divergences.isEmpty, "畸形候選鍵的記錄不該進 divergences")
        XCTAssertTrue(load.quarantined.contains { $0.reason.contains("Bad_Key") },
                      "\(load.quarantined)")
    }

    // MARK: - R4：DA 指認自己 R2 處方造成的缺陷

    /// 被併實體不在 `entities/<uuid>.yaml` 時，**動磁碟前**就拒絕。
    ///
    /// 這是「冪等刪除」得以成立的前提。`load()` 同時讀 entities/ 與 legacy 目錄，
    /// 所以住在 `people/<key>.yaml` 的 person 照樣進得了 snapshot；而刪除只組
    /// `entityURL(id:)`。沒有這道檢查，「檔案不存在就跳過」會把**刪不掉**當成
    /// **已刪掉**——參照全改、被併檔原封不動、歧異記錄被刪、零警告、exit 0
    /// （#71 R3 DA 的 P3）。
    func testRefusesWhenCandidateLivesInLegacyDirectory() throws {
        var keeper = Person(key: "fann-cathy-s-j"); keeper.names = ["F"]
        try store.writePerson(keeper)
        // 被併者手動放進 legacy 目錄——半途遷移／還原的舊備份，是預期存在的狀態。
        var doomed = Person(key: "fann-cathy-s-j-2"); doomed.names = ["F2"]
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("people"), withIntermediateDirectories: true)
        try PersonYAML.encode(doomed).write(
            to: root.appendingPathComponent("people/fann-cathy-s-j-2.yaml"),
            atomically: true, encoding: .utf8)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)

        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("佈局") || msg.contains("migrate"),
                          "錯誤須指出佈局不一致：\(msg)")
        }
        XCTAssertEqual(try store.load().people.count, 2, "拒絕後不得有任何刪除")
        XCTAssertEqual(try store.load().divergences.count, 1, "歧異記錄不得被刪")
    }

    /// 被併者的 profile 是倖存者的**子集**時照樣合併——那不會失去任何東西。
    func testMergeProceedsWhenDoomedProfileIsSubset() throws {
        var keeper = Person(key: "p-keeper"); keeper.names = ["K"]
        keeper.profile.ranks = TimelineOf([
            TemporalValue(value: "助研究員", range: DateRange(start: "2010", end: "2015")),
            TemporalValue(value: "副研究員", range: DateRange(start: "2015", end: nil)),
        ])
        var doomed = Person(key: "p-doomed"); doomed.names = ["D"]
        doomed.profile.ranks = TimelineOf([
            TemporalValue(value: "副研究員", range: DateRange(start: "2015", end: nil)),
        ])
        try store.writePerson(keeper); try store.writePerson(doomed)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "p-keeper", shape: .person),
                                        DivergenceCandidate(key: "p-doomed", shape: .person)])
        try store.writeDivergence(d)

        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "p-keeper")
        XCTAssertFalse(report.hasFailures, "\(report.failures)")
    }

    /// 未知欄位是三分：key 不在 → 失去；raw 相同 → 放行；raw 不同 → **衝突**。
    func testUnknownFieldSameKeyDifferentRawIsReportedAsConflict() throws {
        var keeper = Person(key: "p-keeper"); keeper.names = ["K"]
        keeper.unknownFields = [UnknownField(key: "scopus", raw: "scopus: 123\n")]
        var doomed = Person(key: "p-doomed"); doomed.names = ["D"]
        doomed.unknownFields = [UnknownField(key: "scopus", raw: "scopus: 456\n")]
        let losses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertEqual(losses.count, 1)
        XCTAssertTrue(losses[0].contains("內容不同"), "同 key 不同值是衝突不是缺少：\(losses)")

        // 同值不同排版不該被報成任何東西——那是排版差異，不是資料遺失。
        var sameValue = doomed
        sameValue.unknownFields = [UnknownField(key: "scopus", raw: "scopus: 123\n")]
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(sameValue, into: keeper).isEmpty)
    }

    /// keeper 自己既存的重複／自我參照不得被順手折掉。
    func testKeeperOwnRelationsUntouchedWhenNoHit() throws {
        var keeper = Entry(id: UUID(), citekey: "shen2015model", type: "article", title: "M")
        keeper.akashic.relations.cites = ["z2019q", "z2019q", "a2020x"]
        let dup = Entry(id: UUID(), citekey: "shen2015model-dup", type: "article", title: "D")
        try store.writeEntry(keeper); try store.writeEntry(dup)
        let d = Divergence(id: UUID(), question: "同一篇？",
                           candidates: [DivergenceCandidate(key: "shen2015model", shape: .work),
                                        DivergenceCandidate(key: "shen2015model-dup", shape: .work)])
        try store.writeDivergence(d)

        GitFixture.commitAll(store.root)
        _ = try store.resolveDivergence(id: d.id, survivor: "shen2015model")
        let e = try XCTUnwrap(try store.load().entries.first { $0.citekey == "shen2015model" })
        XCTAssertEqual(e.akashic.relations.cites, ["z2019q", "z2019q", "a2020x"],
                       "沒命中被併鍵就不該改動 keeper 自己的參照：\(e.akashic.relations.cites)")
    }
}
