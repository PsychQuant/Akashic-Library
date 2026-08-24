import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import AkashicSQLite
@testable import AkashicQuery
@testable import AkashicGraph
@testable import AkashicEntity

final class ServiceTests: XCTestCase {
    var root: URL!
    var service: AkashicService!

    /// #37：index 現在住在 `$AKASHIC_HOME/index/<key>.sqlite`。測試必須注入假 home——
    /// 否則會寫進**使用者真實的** `~/.akashic/index/`（實測發生過，留下 `other.sqlite`）。
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-svc-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        // fixture 手寫原始檔進 entries/、people/，需自己宣告 legacy 目錄（#101）
        for sub in ["entries", "people"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                       title: "Identifiability of polychoric models",
                       authors: [.key("cheng-che"), .literal("Hau-Hung Yang")], date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        e1.akashic.tags = ["identifiability"]
        e1.akashic.relations.cites = ["olsson1979maximum"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "olsson1979maximum", type: .periodicalArticle,
                       title: "Maximum likelihood estimation", authors: [.literal("Ulf Olsson")], date: "1979")
        e2.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e2)
        // #81：對外顯示名由 `authorized` 指定，`names` 的順序不再帶語意。
        try store.writePerson(Person(key: "cheng-che",
                                     names: PersonNames(authorized: ["Che Cheng", "鄭澈"])))
        service = AkashicService(root: root, environment: env)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func json(_ s: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(s.utf8))
    }

    /// #138 verify F1：fatal cross-record（重複 citekey）時 doctor 必須**說話**而
    /// 不是把 SQLite 的 UNIQUE constraint 內部錯誤丟給 consumer。CLI 的 #35 順序
    /// （跨記錄檢查先於 rebuild）在 MCP 面必須同樣成立。
    func testDoctorSurvivesFatalCrossRecordIssues() throws {
        // 構造重複 citekey：複製一筆 entry 檔、換 UUID（檔名與 id 同步換，
        // 否則先被 filename≠id 的 quarantine 擋住，到不了 rebuild）
        let entities = root.appendingPathComponent("entities")
        let src = try XCTUnwrap(FileManager.default
            .contentsOfDirectory(at: entities, includingPropertiesForKeys: nil)
            .first { (try? String(contentsOf: $0, encoding: .utf8))?
                .contains("cheng2025identifiability") == true })
        let newID = UUID().uuidString
        let dup = try String(contentsOf: src, encoding: .utf8)
            .replacingOccurrences(of: src.deletingPathExtension().lastPathComponent,
                                  with: newID)
        try dup.write(to: entities.appendingPathComponent("\(newID).yaml"),
                      atomically: true, encoding: .utf8)

        let out = try service.doctor()   // 不得 throw
        XCTAssertFalse(out.contains("UNIQUE constraint"),
                       "SQLite 內部錯誤不得露給 consumer：\(out)")
        let obj = try json(out) as! [String: Any]
        XCTAssertEqual(obj["indexRebuilt"] as? Bool, false, "fatal 時不重建 index：\(out)")
        let cross = try XCTUnwrap(obj["crossRecordIssues"] as? [String: Any])
        let first = try XCTUnwrap(cross["first"] as? [[String: String]])
        XCTAssertTrue(first.contains { $0["severity"] == "error" },
                      "severity 要逐條攜帶（✗/⚠ 之別不得只在 CLI 面）：\(out)")
    }

    /// #138 verify F3：CLI doctor 的普查面（#81/#82）MCP 也要有。
    func testDoctorReportsCensusFacetsMirroringCLI() throws {
        let obj = try json(try service.doctor()) as! [String: Any]
        XCTAssertEqual(obj["indexRebuilt"] as? Bool, true)
        XCTAssertNotNil(obj["noAuthorizedName"], "#81 面向不得只在 CLI 可見")
        XCTAssertNotNil(obj["authorizedOnlyByCitationForm"], "#82 面向不得只在 CLI 可見")
    }

    func testSearchByJournal() throws {
        let out = try service.search(journal: "Psychometrika")
        let arr = try json(out) as! [[String: Any]]
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr.first?["citekey"] as? String, "cheng2025identifiability")
    }

    func testGetEntryIncludesAkashicNamespace() throws {
        let out = try service.getEntry(citekey: "cheng2025identifiability")
        let obj = try json(out) as! [String: Any]
        let akashic = obj["akashic"] as! [String: Any]
        XCTAssertEqual(akashic["tags"] as? [String], ["identifiability"])
        XCTAssertThrowsError(try service.getEntry(citekey: "nope"))
    }

    func testRelationsKinds() throws {
        let cites = try json(try service.relations(citekey: "cheng2025identifiability", kind: "cites")) as! [[String: Any]]
        XCTAssertEqual(cites.first?["citekey"] as? String, "olsson1979maximum")
        let sameJournal = try json(try service.relations(citekey: "cheng2025identifiability", kind: "same-journal")) as! [[String: Any]]
        XCTAssertEqual(sameJournal.count, 1)
        XCTAssertThrowsError(try service.relations(citekey: "cheng2025identifiability", kind: "bogus"))
    }

    func testGraphMermaid() throws {
        let out = try service.graph(focus: "cheng2025identifiability", depth: 1, format: "mermaid")
        XCTAssertTrue(out.hasPrefix("graph LR"))
    }

    func testExportBibAndCSL() throws {
        let bib = try service.export(citekeys: ["cheng2025identifiability"], format: "bib")
        XCTAssertTrue(bib.contains("@ARTICLE{cheng2025identifiability,"))
        let csl = try service.export(citekeys: nil, format: "csl-json")
        XCTAssertEqual((try json(csl) as! [[String: Any]]).count, 2)
        XCTAssertThrowsError(try service.export(citekeys: ["nope"], format: "bib"))
    }

    func testPeopleQuery() throws {
        let all = try json(try service.people(query: nil)) as! [[String: Any]]
        XCTAssertEqual(all.count, 1)
        let hit = try json(try service.people(query: "鄭")) as! [[String: Any]]
        XCTAssertEqual(hit.first?["key"] as? String, "cheng-che")
    }

    func testDoctorStats() throws {
        let obj = try json(try service.doctor()) as! [String: Any]
        XCTAssertEqual(obj["entries"] as? Int, 2)
        XCTAssertEqual(obj["people"] as? Int, 1)
        XCTAssertEqual(obj["unresolvedAuthorLiterals"] as? Int, 2)
        XCTAssertNil(obj["unknownFieldFiles"], "無未知欄位時不 emit（與 quarantined 同慣例）")
    }

    // #23 tolerant-preserve：doctor 對含未知欄位（較新 schema）的檔案給計數提示
    /// #227 verify R2 C6：store 有 quarantined 檔時，person 查無的語意是**無法判定**
    /// ——錯誤類型是 undeterminable、訊息前綴「無法判定」，不是 notFound／「找不到」。
    /// 依錯誤種類或字面分支的呼叫端（含 LLM）不得把未知讀成否。
    func testPersonLookupWithQuarantineIsUndeterminableNotNotFound() throws {
        let qid = UUID()
        try "person:\nid: \(qid.uuidString)\nkey: old-shape\nnames:\n- Old Shape\n".write(
            to: root.appendingPathComponent("entities/\(qid.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.person(key: "nobody-here", name: nil,
                                                library: nil)) { error in
            guard case ServiceError.undeterminable = error else {
                return XCTFail("錯誤類型必須是 undeterminable，實得 \(error)")
            }
            let msg = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.hasPrefix("無法判定"), "前綴不得是「找不到」：\(msg)")
            XCTAssertTrue(msg.contains("quarantined"), "要說明原因：\(msg)")
        }
    }

    // MARK: - #294：四個列表面不得把「讀不進來」折成「空」

    /// 種一個舊形狀 person 檔 → `load()` 會 quarantine 它。
    ///
    /// 與 `testPersonLookupWithQuarantineIsUndeterminableNotNotFound` 同一種 fixture
    /// ——那條驗**單筆查詢**，以下四條驗**列表面**（#294 修的就是後者停在錯的行為）。
    private func seedQuarantinedFile() throws {
        let qid = UUID()
        try "person:\nid: \(qid.uuidString)\nkey: old-shape\nnames:\n- Old Shape\n".write(
            to: root.appendingPathComponent("entities/\(qid.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertFalse(try LibraryStore(root: root).load().quarantined.isEmpty,
                       "前提：該檔應被 quarantine")
    }

    private func assertUndeterminable(_ label: String,
                                      _ body: () throws -> String) {
        XCTAssertThrowsError(try body(), label) { error in
            guard case ServiceError.undeterminable = error else {
                return XCTFail("\(label)：錯誤類型必須是 undeterminable，實得 \(error)")
            }
            let msg = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.hasPrefix("無法判定"), "\(label)：前綴不得是「找不到」：\(msg)")
            XCTAssertTrue(msg.contains("quarantined"), "\(label)：要說明原因：\(msg)")
        }
    }

    /// `people()` 零結果 + 有 quarantine → 無法判定。
    ///
    /// 先前回 `[]` + `isError:false`，**LLM 消費端會據此斷言 library 是空的**
    /// ——這正是 #294 具名的失敗。
    func testPeopleEmptyWithQuarantineIsUndeterminable() throws {
        try seedQuarantinedFile()
        assertUndeterminable("people") { try self.service.people(query: "no-such-person-xyz") }
    }

    /// `search()` 零結果 + 有 quarantine → 無法判定。
    func testSearchEmptyWithQuarantineIsUndeterminable() throws {
        try seedQuarantinedFile()
        assertUndeterminable("search") {
            try self.service.search(author: "no-such-author-xyz")
        }
    }

    /// `export()` **指名的 citekey 查無** + 有 quarantine → 無法判定，不是 notFound。
    ///
    /// 與 `person()` 完全同型：該 citekey 或許就在讀不進來的那個檔裡。
    func testExportMissingCitekeyWithQuarantineIsUndeterminable() throws {
        try seedQuarantinedFile()
        assertUndeterminable("export") {
            try self.service.export(citekeys: ["no-such-citekey-xyz"], format: "biblatex")
        }
    }

    /// 沒有 quarantine 時，行為**不變**——查無仍是 `notFound`。
    ///
    /// 這條防的是過度觸發：把所有查無都改成「無法判定」會讓錯誤類型失去分辨力。
    func testExportMissingCitekeyWithoutQuarantineStaysNotFound() throws {
        XCTAssertThrowsError(try service.export(citekeys: ["no-such-citekey-xyz"],
                                                format: "biblatex")) { error in
            guard case ServiceError.notFound = error else {
                return XCTFail("無 quarantine 時必須維持 notFound，實得 \(error)")
            }
        }
    }

    func testDoctorReportsUnknownFieldFiles() throws {
        let f = root.appendingPathComponent("people/future-person.yaml")
        try """
        id: 11111111-1111-4111-8111-111111111111
        key: future-person
        names:
          variant:
          - Future Person
        affiliations:
          - organization: ISS
        """.write(to: f, atomically: true, encoding: .utf8)
        let obj = try json(try service.doctor()) as! [String: Any]
        XCTAssertEqual(obj["people"] as? Int, 2, "新 schema 檔必須可用，不進 quarantine")
        XCTAssertNil(obj["quarantined"])
        XCTAssertEqual(obj["unknownFieldFiles"] as? [String], ["people/future-person.yaml"])
    }

    func testSetStatusPersistsAndReindexes() throws {
        _ = try service.setStatus(citekey: "olsson1979maximum", status: "reading")
        let store = LibraryStore(root: root)
        let entry = try store.load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(entry.akashic.status, "reading")
    }

    func testTagAddRemove() throws {
        _ = try service.tag(citekey: "olsson1979maximum", add: ["classic", "polychoric"], remove: [])
        _ = try service.tag(citekey: "olsson1979maximum", add: [], remove: ["classic"])
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(entry.akashic.tags, ["polychoric"])
    }

    // #258：三態契約下沉 service——兩面（CLI/MCP）共用同一份判準。
    // 先前 MCP schema 明文「省略＝清除」、DA 實測靜默清空成功；從此省略被拒。

    func testSetStatusOmissionIsRefusedNotClear() throws {
        _ = try service.setStatus(citekey: "olsson1979maximum", status: "reading")
        XCTAssertThrowsError(try service.setStatus(citekey: "olsson1979maximum",
                                                   status: nil, clear: false),
                             "省略 status 不是清除——打錯字的呼叫不得安靜清掉既有狀態")
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(entry.akashic.status, "reading", "被拒的呼叫不得產生任何寫入")
    }

    func testSetStatusValueAndClearAreMutuallyExclusive() throws {
        XCTAssertThrowsError(try service.setStatus(citekey: "olsson1979maximum",
                                                   status: "read", clear: true))
    }

    func testSetStatusExplicitClearClears() throws {
        _ = try service.setStatus(citekey: "olsson1979maximum", status: "reading")
        _ = try service.setStatus(citekey: "olsson1979maximum", status: nil, clear: true)
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertNil(entry.akashic.status)
    }

    func testTagWithNoArgsIsRefused() throws {
        // 原 MCP 面零參數是 no-op「成功」——與 CLI 的拒絕分岔；收斂到拒絕
        XCTAssertThrowsError(try service.tag(citekey: "olsson1979maximum", add: [], remove: []))
    }

    func testLinkAddRemove() throws {
        _ = try service.link(citekey: "olsson1979maximum", kind: "related",
                             add: ["cheng2025identifiability"], remove: [])
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(entry.akashic.relations.related, ["cheng2025identifiability"])
        XCTAssertThrowsError(try service.link(citekey: "olsson1979maximum", kind: "bogus", add: ["x"], remove: []))
    }

    /// #231：**歧義要走到 MCP 面**，不能只活在 kit 裡。
    ///
    /// 教訓來自先前的漏接：kit 全綠仍漏掉兩個入口——只有用真的 service 呼叫才看得見。
    /// 這條同時驗兩件事：歧義有被回報、且每個 key 帶了區辨欄位（`names` / `orcid`）
    /// ——否則讀的人分不出「兩個同名的人」（各自歸屬）與「同一人兩筆」（該合併）。
    func testResolvePeopleSurfacesAmbiguitiesWithDiscriminators() throws {
        let store = LibraryStore(root: root)
        var a = Person(key: "amb-one", names: ["Ambi Guous"])
        a.orcid = ORCID("0000-0001-2345-6789")
        try store.writePerson(a)
        try store.writePerson(Person(key: "amb-two", names: ["Ambi Guous"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Ambi Guous")], date: "2020"))

        let out = try json(try service.resolvePeople(apply: nil)) as! [String: Any]
        let ambs = out["ambiguities"] as! [[String: Any]]
        let hit = ambs.first { $0["citekey"] as? String == "amb2020x" }
        XCTAssertNotNil(hit, "歧義必須出現在 MCP 回應裡，不能只在 kit 內：\(ambs)")
        XCTAssertEqual(hit?["literal"] as? String, "Ambi Guous")
        XCTAssertEqual(hit?["authorIndex"] as? Int, 0)
        XCTAssertNotNil(hit?["entryID"] as? String,
                        "要帶 entry 身分——重複 citekey 下 (citekey, authorIndex) 不足以定位")

        // **區辨欄位只送一次、依不透明 ref 索引**（#236 R1 是體積、R2 是崩潰——
        // 見 testResolvePeopleSurvivesDisplaySafeKeyCollision）
        let refs = hit?["personRefs"] as! [String]
        let people = out["people"] as! [String: [String: Any]]
        let byDisplayKey = Dictionary(uniqueKeysWithValues:
            people.map { ($0.value["key"] as! String, $0.value) })
        XCTAssertEqual(refs.compactMap { people[$0]?["key"] as? String },
                       ["amb-one", "amb-two"], "須依 raw key 排序，且 ref 查得到")
        XCTAssertEqual(byDisplayKey["amb-one"]?["orcid"] as? String, "0000-0001-2345-6789")
        XCTAssertEqual(byDisplayKey["amb-one"]?["names"] as? [String], ["Ambi Guous"])
        // **缺席就不輸出**，不送空字串——否則「沒有 ORCID」與「ORCID 是空字串」
        // 在 JSON 上不再有分別（同本檔既有慣例）
        XCTAssertNil(byDisplayKey["amb-two"]?["orcid"],
                     "沒有 ORCID 時不該出現該鍵：\(byDisplayKey["amb-two"] ?? [:])")
    }

    /// #236 R2：**上限要量對軸——限列數不等於限 payload。**
    ///
    /// 席位實測：**一筆**歧義即可產出 **758 KB**，而回應同時聲稱 `truncated: false`
    /// / `ambiguityTotal: 1`。比完全沒有上限更糟——那個 `false` 是會被 LLM 消費端
    /// 信任的斷言。
    ///
    /// payload 有三個成長軸，列數只是其一：
    /// 1. 列數 O(歧義位置數)
    /// 2. **列寬** `personKeys` 長度 O(同名人數)，無上界
    /// 3. **每筆 people 的大小**：`names` × `displaySafe`（repo 自陳的 **8 倍膨脹器**）
    ///
    /// 這條直接量**序列化後的位元組**——不論日後哪一軸被改動，超標就紅。
    func testResolvePeoplePayloadStaysBoundedOnAdversarialStore() throws {
        let store = LibraryStore(root: root)
        // 60 人共用同一個名字、每人多個長 name（席位重現 758 KB 的形狀）
        // **必須用會膨脹的字元**（#236 R3）。前一版用 `String(repeating: "x", …)`
        // ——純 ASCII **不會膨脹**，`displaySafe` 只逃脫 C0/C1/LS/PS/bidi/BOM/反斜線。
        // 於是測試量到 4,662 B 對上 65,536 B 的斷言：14 倍餘裕，什麼都沒約束到。
        // 測試的 doc 自己寫著「displaySafe 是 8 倍膨脹器」，卻建了個觸發不了它的 store。
        let long = String(repeating: "\u{202E}", count: 200)
        for i in 0..<60 {
            try store.writePerson(Person(key: "flood-\(i)",
                                         names: PersonNames(variant: ["Flood Same"] + (0..<8).map { "\(long)-\(i)-\($0)" })))
        }
        try store.writeEntry(Entry(id: UUID(), citekey: "flood2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Flood Same")], date: "2020"))

        let raw = try service.resolvePeople(apply: nil)
        XCTAssertLessThan(raw.utf8.count, 64 * 1024,
                          "單筆歧義的 payload 必須有界——席位實測未設限時是 758 KB。"
                          + "實際 \(raw.utf8.count) bytes")

        let out = try json(raw) as! [String: Any]
        // **這條測試涵蓋不到 candidates 那一半**，而且是**結構上**涵蓋不到：60 人同名
        // → 全是歧義 → 一個候選都沒有。R4 指出它因此在 candidates 上恆真——同一個
        // 「守衛在它要防的失敗上恆真」的教訓，在這個檔案裡這是第三次。
        // 把前提寫成斷言，讓「形狀變了、覆蓋沒了」會紅，而不是安靜地繼續綠。
        XCTAssertTrue((out["candidates"] as! [[String: Any]]).isEmpty,
                      "前提：本 store 形狀產不出候選。candidates 那半由 "
                      + "testResolvePeopleCandidatesHalfIsAlsoByteBounded 涵蓋")
        // **截斷發生時就要說**，不論是哪一軸被截
        XCTAssertEqual(out["truncated"] as? Bool, true,
                       "ambiguityTotal 是 1 但 refs／people 被截了——truncated 必須為 true，"
                       + "否則回應在對消費端說謊")
        XCTAssertLessThanOrEqual((out["people"] as! [String: Any]).count, 60)
        let refs = (out["ambiguities"] as! [[String: Any]]).first?["personRefs"] as! [String]
        XCTAssertLessThanOrEqual(refs.count, 20, "單列的 ref 數也要有界")
        // **先斷言非空**——`[].allSatisfy` 是 `true`，前一版的守衛在它被寫來防的
        // 那個失敗上恆真（#236 R3：實測 50 列中 47 列 refs 為空而測試全綠）。
        for row in out["ambiguities"] as! [[String: Any]] {
            let rowRefs = row["personRefs"] as! [String]
            XCTAssertGreaterThanOrEqual(rowRefs.count, 2,
                "**每一列都必須有 ≥2 個 ref**。`AmbiguousMatch.init?` 拒絕 count<2 正是"
                + "為了讓「歧義只有一個候選」在型別層不可表達——序列化邊界不得把它造回來。"
                + "列：\(row)")
            XCTAssertTrue(rowRefs.allSatisfy { (out["people"] as! [String: Any])[$0] != nil },
                          "每個 ref 都要查得到——不得留下懸空引用")
        }
    }

    /// #236 R2 CRITICAL：**`displaySafe` 後的 key 碰撞會讓整個 MCP process trap。**
    ///
    /// 第一版把 `displaySafe(personKey)` 當 `people` 的 dictionary key。三個條件湊在
    /// 一起就是 SIGTRAP：
    ///
    /// 1. `Dictionary(uniqueKeysWithValues:)` 對重複鍵是 **precondition failure**，
    ///    不是可捕捉的 error——`try` 接不住，整個 process 死
    /// 2. `displaySafe` 在 `max` 處截斷 → **非單射**
    /// 3. `StoreKey.pattern` = `\A[a-z0-9][a-z0-9-]*\z`，**沒有長度上限**
    ///
    /// 兩個共用 200 字元前綴的**合法** key 即可觸發，且只用出貨的 MCP 工具就做得到
    /// （兩次 `add_person` + 一筆 entry）。`akashic validate` 對這種 store 回報
    /// 「全部通過」——沒有任何地方警告。
    ///
    /// 根因是**把消毒函數當成識別函數**：`displaySafe` 的目的是安全顯示、不是保持
    /// 區別，而這兩個目標在多對一的映射上直接衝突。修法是不透明 ref。
    func testResolvePeopleSurvivesDisplaySafeKeyCollision() throws {
        let store = LibraryStore(root: root)
        let prefix = String(repeating: "a", count: 200)
        try store.writePerson(Person(key: prefix + "b", names: ["Collide Me"]))
        try store.writePerson(Person(key: prefix + "c", names: ["Collide Me"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "collide2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Collide Me")], date: "2020"))
        // 前提：兩人都合法載入（不是被 quarantine 擋掉才沒事）
        XCTAssertEqual(try store.load().people.filter { $0.key.hasPrefix(prefix) }.count, 2)

        // 第一版在這一行 SIGTRAP：`Fatal error: Duplicate values for key: 'aaaa…（已截斷）'`
        let out = try json(try service.resolvePeople(apply: nil)) as! [String: Any]

        let people = out["people"] as! [String: [String: Any]]
        XCTAssertEqual(people.count, 2, "兩個不同的 person 必須是兩個條目，不得塌成一個")
        let hit = (out["ambiguities"] as! [[String: Any]])
            .first { $0["citekey"] as? String == "collide2020" }
        let refs = hit?["personRefs"] as! [String]
        XCTAssertEqual(refs.count, 2, "兩個 ref")
        XCTAssertEqual(Set(refs).count, 2, "**兩個 ref 必須不同**——否則兩人的資料被靜默覆蓋")
        XCTAssertTrue(refs.allSatisfy { people[$0] != nil }, "每個 ref 都查得到")

        // 歧義**不可**出現在 candidates（那條路是可 apply 的）
        let cands = out["candidates"] as! [[String: Any]]
        XCTAssertFalse(cands.contains { $0["citekey"] as? String == "amb2020x" },
                       "歧義絕不能混進可套用的候選")
    }

    /// #236 R1：payload 必須有上限，且**截斷要說出來**。
    ///
    /// MCP 結果直灌 LLM context——本 repo 明文的威脅模型（`TerminalOutputSafetyTests`：
    /// 「MCP/LLM context 的無上限灌注同型」）。歧義筆數是 `O(出現次數)`，由 store 內容
    /// 決定、無自然上界；席位用真 binary 實測 201 筆產出 176 KB。
    ///
    /// **靜默截斷會讓「沒有更多」與「沒給你更多」無法區分**，所以要有 `truncated`
    /// 與 `ambiguityTotal`。
    func testResolvePeopleCapsAmbiguitiesAndSaysSo() throws {
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "many-one", names: ["Many Same"]))
        try store.writePerson(Person(key: "many-two", names: ["Many Same"]))
        for i in 0..<60 {
            try store.writeEntry(Entry(id: UUID(), citekey: "many\(i)", type: .periodicalArticle,
                                       title: "T", authors: [.literal("Many Same")], date: "2020"))
        }
        let out = try json(try service.resolvePeople(apply: nil)) as! [String: Any]
        let ambs = out["ambiguities"] as! [[String: Any]]
        XCTAssertEqual(ambs.count, 50, "要有上限（與 person() 的候選上限同值）")
        XCTAssertEqual(out["truncated"] as? Bool, true, "截斷必須說出來")
        XCTAssertEqual(out["ambiguityTotal"] as? Int, 60, "要給總數，否則使用端不知道漏了多少")
        // 去重的證據：`people` 只有 2 筆，不隨歧義筆數增長
        // `people` 只為**實際回傳**的那 50 筆建——否則上限只擋較瘦的一半
        // （`people` 條目帶 names/orcid/openalex/died/隸屬，比 ambiguities 條目肥）
        let shownRefs = Set(ambs.flatMap { $0["personRefs"] as! [String] })
        XCTAssertEqual(Set((out["people"] as! [String: Any]).keys), shownRefs,
                       "people 的鍵必須恰好等於回傳歧義引用到的 ref 聯集——"
                       + "多了是孤兒 payload，少了是查不到")
    }

    /// **tool description 必須跟得上 payload**（#236 R4）。
    ///
    /// `akashic_resolve_people` 的 description 是 MCP 消費端（LLM）唯一的 schema 說明
    /// ——payload 加了欄位而它沒跟上，消費端就不知道那些欄位存在，或更糟：**照著它
    /// 描述的舊形狀去解析**。本輪就漂了兩次（`namesTotal`、`candidateRowsDropped`）。
    ///
    /// 這是結構性守衛而不是「記得同步更新」：只要 payload 多一個頂層鍵而 description
    /// 沒提到它，這條就紅。
    func testToolDescriptionCoversEveryTopLevelPayloadKey() throws {
        // 讓兩半都非空，否則掃不到只在其中一半出現的鍵
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "desc-amb-1", names: ["Desc Same"]))
        try store.writePerson(Person(key: "desc-amb-2", names: ["Desc Same"]))
        try store.writePerson(Person(key: "desc-solo", names: ["Desc Solo"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "desc2020", type: .periodicalArticle, title: "T",
                                   authors: [.literal("Desc Same"), .literal("Desc Solo")],
                                   date: "2020"))
        let out = try json(try service.resolvePeople(apply: nil)) as! [String: Any]
        XCTAssertFalse((out["candidates"] as! [Any]).isEmpty, "前提：candidates 非空")
        XCTAssertFalse((out["ambiguities"] as! [Any]).isEmpty, "前提：ambiguities 非空")

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicMCPTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let src = try String(contentsOf: repoRoot
            .appendingPathComponent("Sources/akashic-mcp/Server.swift"), encoding: .utf8)
        guard let toolRange = src.range(of: "akashic_resolve_people") else {
            return XCTFail("找不到 akashic_resolve_people 的 Tool 宣告")
        }
        let decl = String(src[toolRange.lowerBound...].prefix(3000))

        let missing = out.keys.filter { !decl.contains($0) }.sorted()
        XCTAssertTrue(missing.isEmpty,
                      "payload 有這些頂層鍵，但 tool description 沒提到：\(missing)。"
                      + "消費端只看得到 description——它落後就等於這些欄位不存在")
    }

    /// **candidates 那一半也要位元組上限**（#236 R4 CRITICAL）。
    ///
    /// 先前它只有列數上限（50）。`id` 是 `"<citekey>:<index>"`，而 citekey 是原始
    /// store 內容、`StoreKey.pattern` **沒有長度上限**——席位用真 binary 實測單列
    /// 1,208,606 bytes，四軸上限全設好的情況下整個回應仍是 281,919 bytes。
    ///
    /// `id` 不能截斷（`--apply` 要拿它對回來），所以吃不下的整列不印並回報。
    func testResolvePeopleCandidatesHalfIsAlsoByteBounded() throws {
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "solo-author", names: ["Solo Author"]))
        // 三筆正常 + 五筆巨大 citekey（合法：`[a-z0-9][a-z0-9-]*`，無長度上限）
        for i in 0..<3 {
            try store.writeEntry(Entry(id: UUID(), citekey: "short\(i)", type: .periodicalArticle,
                                       title: "T", authors: [.literal("Solo Author")], date: "2020"))
        }
        let huge = String(repeating: "a", count: 40_000)
        for i in 0..<5 {
            try store.writeEntry(Entry(id: UUID(), citekey: "\(huge)-\(i)", type: .periodicalArticle,
                                       title: "T", authors: [.literal("Solo Author")], date: "2020"))
        }

        let raw = try service.resolvePeople(apply: nil)
        let out = try json(raw) as! [String: Any]
        // 前提：這個 store 形狀**真的**產得出候選——否則本測試與它要防的失敗無關
        XCTAssertGreaterThan((out["candidates"] as! [[String: Any]]).count, 0,
                             "前提：必須有候選，否則這條又是空洞守衛")
        XCTAssertEqual(out["candidateTotal"] as? Int, 8)

        XCTAssertLessThan(raw.utf8.count, 128 * 1024,
                          "兩半各 48 KB 預算 → 整個回應必須有界。實際 \(raw.utf8.count) bytes")
        XCTAssertGreaterThan(out["candidateRowsDropped"] as? Int ?? 0, 0,
                             "巨大 citekey 的列吃不下 → 要丟，而且要說")
        XCTAssertEqual(out["truncated"] as? Bool, true,
                       "candidates 被丟也算截斷——旗標自稱涵蓋整個回應")
        // 丟掉的必須是巨大的那些；短的照樣可用（否則等於整個功能被一筆壞資料癱瘓）
        let ids = (out["candidates"] as! [[String: Any]]).compactMap { $0["id"] as? String }
        XCTAssertTrue(ids.contains { $0.hasPrefix("short") }, "短 citekey 的候選要留著：\(ids.count) 筆")
    }

    /// `people[ref].names` 的 `prefix(2)` 是第四種丟棄（#236 R4）。它先前**不算進**
    /// `truncated`，於是「每人五個異名、只送兩個」的回應仍宣稱 `truncated: false`——
    /// 而該旗標自稱是「整個回應」的截斷旗標。
    ///
    /// 本測試的價值全在**前置條件**：其餘三軸都必須沒被截，否則 `truncated: true`
    /// 可能來自別處，這條就證明不了 names 那一軸。
    func testResolvePeopleReportsDroppedNamesAndCountsThemAsTruncation() throws {
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "names-one",
                                     names: ["Many Same", "Alias A", "Alias B", "Alias C", "Alias D"]))
        try store.writePerson(Person(key: "names-two", names: ["Many Same", "Alias E", "Alias F"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "n1", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Many Same")], date: "2020"))
        let out = try json(try service.resolvePeople(apply: nil)) as! [String: Any]
        let ambs = out["ambiguities"] as! [[String: Any]]

        // 前置：其餘三軸皆未截
        XCTAssertEqual(ambs.count, 1, "一筆歧義，遠低於上限 50——列數軸未截")
        XCTAssertEqual(out["ambiguityTotal"] as? Int, 1)
        XCTAssertEqual(out["ambiguityRowsDropped"] as? Int, 0, "位元組預算未觸發")
        XCTAssertEqual((ambs[0]["personRefs"] as! [String]).count, 2, "ref 軸未截（上限 20）")
        XCTAssertEqual(out["candidateTotal"] as? Int, 0, "候選軸未截")

        let people = out["people"] as! [String: [String: Any]]
        let one = people.values.first { $0["key"] as? String == "names-one" }!
        XCTAssertEqual((one["names"] as! [String]).count, 2, "只送兩個")
        XCTAssertEqual(one["namesTotal"] as? Int, 5, "要給總數——使用端要判斷的是有沒有看到全部，那需要分母")
        let two = people.values.first { $0["key"] as? String == "names-two" }!
        XCTAssertEqual(two["namesTotal"] as? Int, 3)

        XCTAssertEqual(out["truncated"] as? Bool, true,
                       "names 被丟也算截斷——否則旗標按自己的定義說謊")
    }

    /// 對偶：沒丟就不報、也不說截斷。缺了這條，「永遠 true」與「永遠輸出 namesTotal」
    /// 兩種退化實作都能讓上面那條變綠。
    func testResolvePeopleOmitsNamesTotalWhenNothingDropped() throws {
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "few-one", names: ["Few Same", "Alias A"]))
        try store.writePerson(Person(key: "few-two", names: ["Few Same"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "f1", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Few Same")], date: "2020"))
        let out = try json(try service.resolvePeople(apply: nil)) as! [String: Any]
        let people = out["people"] as! [String: [String: Any]]
        XCTAssertEqual(people.count, 2)
        for p in people.values {
            XCTAssertNil(p["namesTotal"], "沒丟就不送——不要讓「沒丟」與「丟了 0 個」變成兩件事")
        }
        XCTAssertEqual(out["truncated"] as? Bool, false, "四軸皆未截")
    }

    func testResolvePeopleListsAndAppliesSelectively() throws {
        let e3 = Entry(id: UUID(), citekey: "cheng2020analysis", type: .thesis,
                       title: "Analysis of growth curves", authors: [.literal("Che Cheng")], date: "2020")
        try LibraryStore(root: root).writeEntry(e3)
        // #231：no-apply 回應由陣列改為 {candidates, ambiguities}
        let list = (try json(try service.resolvePeople(apply: nil)) as! [String: Any])["candidates"] as! [[String: Any]]
        XCTAssertEqual(list.count, 1)
        let id = list.first?["id"] as? String ?? ""
        XCTAssertEqual(id, "cheng2020analysis:0:cheng-che")   // B8：id 釘 person
        _ = try service.resolvePeople(apply: [id])
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "cheng2020analysis" }!
        XCTAssertEqual(entry.authors, [.key("cheng-che")])
        // 逐候選：Hau-Hung Yang（無 person）不受影響
        let e1 = try LibraryStore(root: root).load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(e1.authors[1], .literal("Hau-Hung Yang"))
    }

    func testCreateEntryGeneratesCitekeyAndPersists() throws {
        let out = try json(try service.createEntry(
            type: "periodical-article", title: "Manual reference entry",
            authors: ["Some Author"], date: "2024",
            fields: ["journaltitle": "Manual Journal"])) as! [String: Any]
        let citekey = out["citekey"] as? String ?? ""
        XCTAssertEqual(citekey, "author2024manual")
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == citekey }!
        XCTAssertNil(entry.provenance)   // 庫外文獻：無 provenance
    }

    func testAddPersonRejectsDuplicate() throws {
        _ = try service.addPerson(key: "yang-hau-hung", names: ["Hau-Hung Yang"], orcid: nil, openalex: nil)
        XCTAssertThrowsError(try service.addPerson(key: "cheng-che", names: ["X"], orcid: nil, openalex: nil))
    }

    func testIndexFreshnessAfterExternalWrite() throws {
        _ = try service.search(journal: "Psychometrika")   // 建 index
        var e3 = Entry(id: UUID(), citekey: "new2026entry", type: .periodicalArticle,
                       title: "Externally added", authors: [], date: "2026")
        e3.fields["journaltitle"] = "Psychometrika"
        try LibraryStore(root: root).writeEntry(e3)        // service 之外寫入
        let arr = try json(try service.search(journal: "Psychometrika")) as! [[String: Any]]
        XCTAssertEqual(arr.count, 3)                        // mtime stale → 自動重建
    }

    func testImportZoteroMissingDBFailsLoud() {
        XCTAssertThrowsError(try service.importZotero(zoteroDb: "/nonexistent/z.sqlite", libraryID: nil))
    }

    // MARK: - importWoS（#290——#206 鏡像的 MCP 匯入面）

    private func wosTSV(_ rows: [[String: String]]) throws -> String {
        let cols = ["Authors", "Article Title", "Publication Year", "Source Title", "DOI", "☃♥"]
        var lines = [cols.joined(separator: "\t")]
        for r in rows { lines.append(cols.map { r[$0] ?? "" }.joined(separator: "\t")) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wos-\(UUID().uuidString).txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    func testImportWoSCreatesFromTSV() throws {
        let path = try wosTSV([["Authors": "Hsu, Y-F", "Article Title": "Weber Study",
                                "Publication Year": "2021", "Source Title": "JMP",
                                "DOI": "10.1/abc"]])
        let obj = try json(try service.importWoS(path: path, csv: false, dryRun: false)) as! [String: Any]
        XCTAssertEqual((obj["created"] as? [String])?.count, 1, "\(obj)")
        let e = try LibraryStore(root: root).load().entries.first {
            ($0.fields["doi"]) == "10.1/abc" }
        XCTAssertNotNil(e, "匯入的 entry 要在 store 裡且 DOI 對映到 fields")
    }

    func testImportWoSDryRunWritesNothing() throws {
        let before = try LibraryStore(root: root).load().entries.count
        let path = try wosTSV([["Authors": "Lay, K-L", "Article Title": "Attachment",
                                "Publication Year": "2020", "Source Title": "DevPsy",
                                "DOI": "10.2/dry"]])
        let obj = try json(try service.importWoS(path: path, csv: false, dryRun: true)) as! [String: Any]
        XCTAssertEqual(obj["dryRun"] as? Bool, true)
        XCTAssertEqual((obj["created"] as? [String])?.count, 1, "乾跑要預告會建什麼")
        XCTAssertEqual(try LibraryStore(root: root).load().entries.count, before,
                       "dry_run 不得寫入任何 entry")
    }

    func testImportWoSIsIdempotent() throws {
        let path = try wosTSV([["Authors": "Chen, C-H", "Article Title": "Twice",
                                "Publication Year": "2019", "Source Title": "Psychometrika",
                                "DOI": "10.3/twice"]])
        _ = try service.importWoS(path: path, csv: false, dryRun: false)
        let obj = try json(try service.importWoS(path: path, csv: false, dryRun: false)) as! [String: Any]
        XCTAssertEqual((obj["created"] as? [String])?.count ?? 0, 0)
        XCTAssertEqual((obj["unchanged"] as? [String])?.count, 1, "同檔重跑＝unchanged，不建重複")
    }

    func testImportWoSReportsDroppedColumnsVisibly() throws {
        // 「☃♥」正規化為空（純符號）→ droppedColumns（丟棄必須可見，#206 §3）。
        // 注意 CJK 欄名**不會**被丟——isLetter 對 CJK 為真，會照 #206 收進 fields
        let path = try wosTSV([["Authors": "Wen, C-C", "Article Title": "Dropped",
                                "Publication Year": "2018", "Source Title": "SIM",
                                "DOI": "10.4/drop", "☃♥": "值"]])
        let obj = try json(try service.importWoS(path: path, csv: false, dryRun: false)) as! [String: Any]
        let dropped = obj["droppedColumns"] as? [String: Int]
        XCTAssertEqual(dropped?.count, 1, "收不進 fields 的欄位名必須出現在報告：\(obj)")
    }

    func testImportWoSMissingFileFailsLoud() {
        XCTAssertThrowsError(try service.importWoS(path: "/nonexistent/wos.txt",
                                                   csv: false, dryRun: false))
    }

    // MARK: - person 檢視的 verdict 面（#270——第 13 條邊的列舉入口）

    func testPersonPayloadListsVerdictsWithObservedAndStaleStates() throws {
        let store = LibraryStore(root: root)
        let e = Entry(id: UUID(), citekey: "hsu2021weber", type: .periodicalArticle, title: "W",
                      authors: [.literal("Hsu, Y.-F.")], date: "2021")
        try store.writeEntry(e)
        var p = Person(key: "hsu-yung-fong", names: ["Hsu, Yung-Fong"])
        // observed：holder entry 存在且 literal 仍在作者列
        _ = ResolutionLedger.appendIfAbsent(
            ResolutionLedger.record(.confirmed, holderKind: .work, holder: "hsu2021weber",
                                    literal: "Hsu, Y.-F.", rule: ResolutionLedger.personRule,
                                    statement: "s"), to: &p.references)
        // stale：holder entry 不存在（rename 前／已刪）
        _ = ResolutionLedger.appendIfAbsent(
            ResolutionLedger.record(.rejected, holderKind: .work, holder: "gone2000x",
                                    literal: "Hsu, Y.", rule: ResolutionLedger.personRule,
                                    statement: "s"), to: &p.references)
        try store.writePerson(p)
        // 不需顯式 rebuild——service.person 的 ensureFreshIndex 依 mtime 自動重建

        let obj = try json(try service.person(key: "hsu-yung-fong", name: nil, library: nil)) as! [String: Any]
        let person = obj["person"] as! [String: Any]
        let vs = person["verdicts"] as? [[String: Any]]
        XCTAssertEqual(vs?.count, 2, "verdict 是掛在記錄上的邊——檢視要看得到：\(person)")
        let byHolder = Dictionary(uniqueKeysWithValues: (vs ?? []).map { ($0["holder"] as! String, $0) })
        XCTAssertEqual(byHolder["hsu2021weber"]?["state"] as? String, "observed")
        XCTAssertEqual(byHolder["gone2000x"]?["state"] as? String, "stale",
                       "holder 不存在的 verdict 要標 stale——resolver 沉底段列不出它，這裡是唯一列舉面")
        XCTAssertEqual(byHolder["gone2000x"]?["kind"] as? String, "resolution-rejected")
    }

    func testPersonPayloadVerdictsEmptyIsExplicit() throws {
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "no-verdicts", names: ["N"]))
        let obj = try json(try service.person(key: "no-verdicts", name: nil, library: nil)) as! [String: Any]
        let person = obj["person"] as! [String: Any]
        XCTAssertNotNil(person["verdicts"], "空集合也要出現——缺席分辨不出「無判定」與「欄位掉了」")
        XCTAssertEqual((person["verdicts"] as? [[String: Any]])?.count, 0)
    }
}

// ── Verify R1 修復（#9）──

extension ServiceTests {
    // DA CONFIRMED HIGH：createEntry 不得覆寫 quarantined 檔
    func testCreateEntryNeverOverwritesQuarantinedFile() throws {
        let store = LibraryStore(root: root)
        let broken = "broken: [yaml\n"
        // 會與 createEntry 生成的 citekey（author2024manual）同名
        try broken.write(to: store.entriesDir.appendingPathComponent("author2024manual.yaml"),
                         atomically: true, encoding: .utf8)
        let out = try service.createEntry(type: "periodical-article", title: "Manual reference entry",
                                          authors: ["Some Author"], date: "2024", fields: [:])
        let citekey = (try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any])["citekey"] as! String
        XCTAssertEqual(citekey, "author2024bmanual")   // 讓位取衝突後綴
        XCTAssertEqual(try String(contentsOf: store.entriesDir.appendingPathComponent("author2024manual.yaml"),
                                  encoding: .utf8), broken)
    }

    // DA CONFIRMED HIGH：addPerson 不得覆寫 quarantined people 檔
    func testAddPersonNeverOverwritesQuarantinedFile() throws {
        let store = LibraryStore(root: root)
        let broken = "not: [valid person\n"
        try broken.write(to: store.peopleDir.appendingPathComponent("yang-hau-hung.yaml"),
                         atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.addPerson(key: "yang-hau-hung", names: ["Hau-Hung Yang"],
                                                   orcid: nil, openalex: nil))
        XCTAssertEqual(try String(contentsOf: store.peopleDir.appendingPathComponent("yang-hau-hung.yaml"),
                                  encoding: .utf8), broken)
    }

    // Codex/Logic CONFIRMED：外部刪檔後 freshness 要偵測到（目錄 mtime）
    //
    // #56：**檔案位置由 store 自己解析**，不寫死 legacy 路徑。原本假設
    // `entriesDir/<citekey>.yaml`，但新建的 store 走 entities 佈局（`entities/<uuid>.yaml`），
    // 於是刪不到檔。本測試要驗的是「外部刪檔 → freshness 偵測得到」，與佈局無關——
    // 讓它跑在**實際出貨格式**上比釘死 legacy 更有價值。
    func testFreshnessDetectsExternalDeletion() throws {
        _ = try service.search(journal: "Psychometrika")   // 建 index（2 筆）
        Thread.sleep(forTimeInterval: 1.1)                  // 目錄 mtime 秒級粒度
        let store = LibraryStore(root: root)
        let target = try XCTUnwrap(
            store.load().entries.first { $0.citekey == "olsson1979maximum" },
            "測試前提：store 內須有 olsson1979maximum")
        let targetURL = store.usesEntitiesLayout
            ? store.entityURL(id: target.id)
            : store.entryURL(citekey: target.citekey)
        try FileManager.default.removeItem(at: targetURL)
        let out = try service.search(journal: "Psychometrika")
        let arr = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [[String: Any]]
        XCTAssertEqual(arr.count, 1)
    }

    // get_entry 完整性：provenance 時間欄位入 JSON
    func testGetEntryIncludesProvenanceTimestamps() throws {
        let store = LibraryStore(root: root)
        var e = try store.load().entries.first { $0.citekey == "olsson1979maximum" }!
        e.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1,
                                  importedAt: Date(timeIntervalSince1970: 1_753_000_000),
                                  orphanedAt: Date(timeIntervalSince1970: 1_753_100_000))
        try store.writeEntry(e)
        let obj = try JSONSerialization.jsonObject(
            with: Data(try service.getEntry(citekey: "olsson1979maximum").utf8)) as! [String: Any]
        let prov = obj["provenance"] as! [String: Any]
        XCTAssertNotNil(prov["imported_at"])
        XCTAssertNotNil(prov["orphaned_at"])
    }
}

/// #13 多 library：akashic_libraries service handler + search 的 library 篩選。
extension ServiceTests {
    func testLibrariesLifecycleViaService() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        let list = try json(service.libraries(action: "list", key: nil, name: nil,
                                              description: nil, citekey: nil)) as! [[String: Any]]
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0]["key"] as? String, "sinica")
        XCTAssertEqual(list[0]["members"] as? Int, 0)

        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let hits = try json(service.search(library: "sinica")) as! [[String: Any]]
        XCTAssertEqual(hits.map { $0["citekey"] as! String }, ["cheng2025identifiability"])
        XCTAssertTrue((try json(service.search(library: "ghost")) as! [Any]).isEmpty)

        _ = try service.libraries(action: "remove", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        XCTAssertTrue((try json(service.search(library: "sinica")) as! [Any]).isEmpty)
    }

    func testLibrariesActionValidation() throws {
        XCTAssertThrowsError(try service.libraries(action: "bogus", key: nil, name: nil,
                                                   description: nil, citekey: nil))
        XCTAssertThrowsError(try service.libraries(action: "create", key: nil, name: "X",
                                                   description: nil, citekey: nil),
                             "create 缺 key 要拒")
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        XCTAssertThrowsError(try service.libraries(action: "create", key: "sinica", name: "重複",
                                                   description: nil, citekey: nil),
                             "重複 create 要拒")
        XCTAssertThrowsError(try service.libraries(action: "add", key: "ghostlib", name: nil,
                                                   description: nil, citekey: "cheng2025identifiability"),
                             "未知 library 要拒")
    }
}

/// #13 verify fix round：getEntry 含 libraries、dangling remove、create 驗證順序。
extension ServiceTests {
    func testGetEntryIncludesLibraries() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let entry = try json(service.getEntry(citekey: "cheng2025identifiability")) as! [String: Any]
        let akashic = entry["akashic"] as! [String: Any]
        XCTAssertEqual(akashic["libraries"] as? [String], ["sinica"],
                       "getEntry 必須回傳 membership（MCP 完整 entry 契約）")
    }

    func testRemoveWorksOnDanglingMembership() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        // registry 檔被手動刪除 → dangling membership；remove 仍須可清理
        try FileManager.default.removeItem(
            at: LibraryStore(root: root).libraryURL(key: "sinica"))
        _ = try service.libraries(action: "remove", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let entry = try json(service.getEntry(citekey: "cheng2025identifiability")) as! [String: Any]
        let akashic = entry["akashic"] as! [String: Any]
        XCTAssertNil(akashic["libraries"], "dangling membership 清掉後不應殘留")
    }

    func testCreateValidatesKeyBeforePathProbe() throws {
        // librariesDir/../oracle.yaml = root/oracle.yaml——存在性 oracle 的目標
        try "x".write(to: root.appendingPathComponent("oracle.yaml"),
                      atomically: true, encoding: .utf8)
        do {
            _ = try service.libraries(action: "create", key: "../oracle", name: "X",
                                      description: nil, citekey: nil)
            XCTFail("畸形 key 必須擲錯")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("不符合"),
                          "錯誤必須是 key 格式拒絕，不是洩漏路徑存在性的「已存在」：\(msg)")
        }
    }
}

/// DA must-fix #1/#7：MCP 側 stale-schema 自我修復 + getEntry 零 libraries case。
extension ServiceTests {
    func testServiceRecoversFromStaleSchemaIndex() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        // 模擬舊 binary 建的 index：砍新表 + 版本歸零
        let store = LibraryStore(root: root)
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: false)
        try db.execute("DROP TABLE entry_libraries")
        try db.execute("PRAGMA user_version = 0")
        let hits = try json(service.search(library: "sinica")) as! [[String: Any]]
        XCTAssertEqual(hits.map { $0["citekey"] as! String }, ["cheng2025identifiability"],
                       "MCP freshness 必須偵測 schema 過舊並重建，不得 no such table")
    }

    func testGetEntryOmitsLibrariesWhenEmpty() throws {
        let entry = try json(service.getEntry(citekey: "olsson1979maximum")) as! [String: Any]
        let akashic = (entry["akashic"] as? [String: Any]) ?? [:]
        XCTAssertNil(akashic["libraries"], "零 membership 時 key 省略（與 tags 慣例一致）")
    }
}

/// #14 人物檢索：person 聚合 handler。
extension ServiceTests {
    func testPersonByKeyAggregates() throws {
        let out = try json(service.person(key: "cheng-che", name: nil, library: nil)) as! [String: Any]
        XCTAssertEqual((out["person"] as? [String: Any])?["key"] as? String, "cheng-che")
        XCTAssertEqual((out["publications"] as? [[String: Any]])?.map { $0["citekey"] as! String },
                       ["cheng2025identifiability"])
        let co = out["co_authors"] as! [[String: Any]]
        XCTAssertEqual(co.first?["name"] as? String, "Hau-Hung Yang")
        XCTAssertEqual(co.first?["count"] as? Int, 1)
    }

    func testPersonByFuzzyNameReturnsCandidatesNeverAutoSelects() throws {
        let out = try json(service.person(key: nil, name: "cheng", library: nil)) as! [String: Any]
        let candidates = out["candidates"] as! [[String: Any]]
        XCTAssertTrue(candidates.contains { ($0["person_key"] as? String) == "cheng-che" })
        XCTAssertNil(out["publications"], "模糊名只回候選，絕不自動選定聚合")
    }

    func testPersonScopedByLibrary() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        let none = try json(service.person(key: "cheng-che", name: nil, library: "sinica")) as! [String: Any]
        XCTAssertTrue((none["publications"] as! [Any]).isEmpty, "未加入 library 前 scoped 應為空")
        _ = try service.libraries(action: "add", key: "sinica", name: nil,
                                  description: nil, citekey: "cheng2025identifiability")
        let some = try json(service.person(key: "cheng-che", name: nil, library: "sinica")) as! [String: Any]
        XCTAssertEqual((some["publications"] as! [[String: Any]]).count, 1)
    }

    func testPersonValidation() throws {
        XCTAssertThrowsError(try service.person(key: nil, name: nil, library: nil), "key/name 至少其一")
        XCTAssertThrowsError(try service.person(key: "ghost-person", name: nil, library: nil), "未知 person 擲錯")
    }
}

/// #14 verify fix round：R1 findings 釘住。
extension ServiceTests {
    func testPersonRejectsEmptyAndBothInputs() throws {
        XCTAssertThrowsError(try service.person(key: nil, name: "", library: nil), "空白 name 拒絕")
        XCTAssertThrowsError(try service.person(key: "  ", name: nil, library: nil), "空白 key 拒絕")
        XCTAssertThrowsError(try service.person(key: "cheng-che", name: "cheng", library: nil),
                             "key 與 name 互斥")
    }

    func testPersonScopedCoAuthorsConsistentWithLibrary() throws {
        _ = try service.libraries(action: "create", key: "sinica", name: "中研院",
                                  description: nil, citekey: nil)
        // 未加入 library：scoped 聚合的 publications 與 co_authors 都必須為空（內部一致）
        let none = try json(service.person(key: "cheng-che", name: nil, library: "sinica")) as! [String: Any]
        XCTAssertTrue((none["publications"] as! [Any]).isEmpty)
        XCTAssertTrue((none["co_authors"] as! [Any]).isEmpty,
                      "co_authors 必須吃 library 過濾（聚合內部一致性）")
        // 存在性不受 scope 影響：record 存在 → 不 notFound（上面沒 throw 即證）
    }

    func testPersonExistenceUsesUnscopedPublications() throws {
        // 無 people record、只有 literal→無 key。改用有 record 的：刪 record 後靠全集 pubs 存在
        // 構造：person key 出現在 entry 但 people/ 無記錄
        var e = try LibraryStore(root: root).load().entries.first { $0.citekey == "olsson1979maximum" }!
        e.authors = [.key("olsson-ulf")]
        try LibraryStore(root: root).writeEntry(e)
        _ = try service.libraries(action: "create", key: "empty-lib", name: "空庫",
                                  description: nil, citekey: nil)
        // scoped 查詢：全集有著作 → 不得 notFound；scoped publications 空
        let out = try json(service.person(key: "olsson-ulf", name: nil, library: "empty-lib")) as! [String: Any]
        XCTAssertTrue((out["publications"] as! [Any]).isEmpty)
    }

    func testPersonResolvedCoAuthorNameIsHumanReadable() throws {
        // 讓 cheng-che 與另一個 resolved person 合著
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "yang-hau-hung",
                                     names: PersonNames(authorized: ["Hau-Hung Yang"])))
        var e = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        e.authors = [.key("cheng-che"), .key("yang-hau-hung")]
        try store.writeEntry(e)
        let out = try json(service.person(key: "cheng-che", name: nil, library: nil)) as! [String: Any]
        let co = out["co_authors"] as! [[String: Any]]
        XCTAssertEqual(co.first?["person_key"] as? String, "yang-hau-hung")
        XCTAssertEqual(co.first?["name"] as? String, "Hau-Hung Yang",
                       "resolved 合著者的 name 給人讀的名字，不是 key")
    }
}

/// #14 R2：篇數語意（per-entry 去重）+ truncated 標記。
extension ServiceTests {
    func testFuzzyCountsPublicationsNotOccurrences() throws {
        let store = LibraryStore(root: root)
        var e = try store.load().entries.first { $0.citekey == "olsson1979maximum" }!
        e.authors = [.literal("Dup Person"), .literal("Dup Person")]   // 同篇重複掛名
        try store.writeEntry(e)
        let out = try json(service.person(key: nil, name: "dup person", library: nil)) as! [String: Any]
        let c = (out["candidates"] as! [[String: Any]]).first!
        XCTAssertEqual(c["publications"] as? Int, 1, "同篇重複掛名只計一篇")
    }

    func testFuzzyTruncationFlag() throws {
        let store = LibraryStore(root: root)
        for i in 0..<55 {
            try store.writePerson(Person(key: String(format: "zz-person-%02d", i),
                                         names: ["Zz Common \(i)"]))
        }
        let out = try json(service.person(key: nil, name: "zz", library: nil)) as! [String: Any]
        XCTAssertEqual((out["candidates"] as! [Any]).count, 50)
        XCTAssertEqual(out["truncated"] as? Bool, true)
    }
}

/// #18 多檔案：akashic_files handler（list / use；session-scoped 切換）。
extension ServiceTests {
    private func makeSecondUniverse() throws -> (configURL: URL, otherRoot: URL) {
        let otherRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-svc-other-\(UUID().uuidString)")
        let store = LibraryStore(root: otherRoot)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "other2020paper", type: .periodicalArticle,
                                   title: "Another universe", authors: [.literal("Someone Else")],
                                   date: "2020"))
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-svc-cfg-\(UUID().uuidString).yaml")
        var config = AkashicConfig()
        config.files = ["origin": root.path, "other": otherRoot.path]
        config.current = "origin"
        try config.write(to: configURL)
        return (configURL, otherRoot)
    }

    func testFilesListShowsRegistryAndActiveRoot() throws {
        let (configURL, _) = try makeSecondUniverse()
        let svc = AkashicService(root: root, configURL: configURL, environment: env)
        let out = try json(svc.files(action: "list", key: nil)) as! [String: Any]
        let files = out["files"] as! [[String: Any]]
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(out["active_root"] as? String, root.path)
        XCTAssertTrue(files.contains { ($0["key"] as? String) == "other" })
    }

    func testFilesUseSwitchesUniverseCompletely() throws {
        let (configURL, otherRoot) = try makeSecondUniverse()
        let svc = AkashicService(root: root, configURL: configURL, environment: env)
        // 切換前：搜得到本 universe 的 entry
        XCTAssertTrue(try svc.search(journal: "Psychometrika").contains("cheng2025identifiability"))
        let out = try json(svc.files(action: "use", key: "other")) as! [String: Any]
        XCTAssertEqual(out["active_root"] as? String, otherRoot.path)
        // 切換後：互不相通——舊 universe 的內容看不到、新 universe 的看得到
        let all = try svc.search()
        XCTAssertTrue(all.contains("other2020paper"), all)
        XCTAssertFalse(all.contains("cheng2025identifiability"), "互不相通：舊 universe 內容不得洩入")
    }

    func testFilesUseValidation() throws {
        let (configURL, _) = try makeSecondUniverse()
        let svc = AkashicService(root: root, configURL: configURL, environment: env)
        XCTAssertThrowsError(try svc.files(action: "use", key: "ghost"), "未註冊 key 擲錯")
        XCTAssertThrowsError(try svc.files(action: "use", key: nil), "use 缺 key 擲錯")
        XCTAssertThrowsError(try svc.files(action: "teleport", key: nil), "未知 action 擲錯")
    }
}

// R9（R8-verify M15）：resolve-people 的 per-item 收容契約 regression
extension ServiceTests {
    func testResolvePeopleContainsWriteFailurePerItem() throws {
        // 凍結記錄（decode 容忍、encode 平移不變式拒寫）+ literal 作者可解析
        let frozen = """
        id: 7C1F6C2E-0000-0000-0000-00000000CC01
        citekey: frozen3
        type: periodical-article
        title: T
        authors:
          - literal: Che Cheng
        akashic:
            tags:
            - keep
            weird: [a,
          b]
        """
        try (frozen + "\n").write(
            to: root.appendingPathComponent("entries/frozen3.yaml"),
            atomically: true, encoding: .utf8)
        // #231：no-apply 回應由陣列改為 {candidates, ambiguities}
        let list = (try json(try service.resolvePeople(apply: nil)) as! [String: Any])["candidates"] as! [[String: Any]]
        let ids = list.compactMap { $0["id"] as? String }
        XCTAssertTrue(ids.contains("frozen3:0:cheng-che"), "\(ids)")   // B8
        let out = try json(try service.resolvePeople(apply: ["frozen3:0"])) as! [String: Any]
        // 收容：不 throw、writeFailed 記錄、applied 不誇報
        let failed = out["writeFailed"] as? [String: String]
        XCTAssertNotNil(failed?["frozen3"], "\(out)")
        XCTAssertEqual(out["applied"] as? [String], [])
        XCTAssertEqual(out["entriesRewritten"] as? Int, 0)
        // 磁碟原封不動（fail-closed 不毀檔）
        let onDisk = try String(
            contentsOf: root.appendingPathComponent("entries/frozen3.yaml"), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("- literal: Che Cheng"))
    }
}

/// #77 層次 2：MCP 面的歧異記錄入口——LLM 驅動的資料補完流程正是 #71 診斷裡
/// 「七次歧異全部在寫入前被判斷掉」的實際發生點，MCP 記不了歧異等於逼流程
/// 當場判斷。刻意**不**提供 MCP 版 resolve（消歧含合併＋刪檔，屬人工確認面）。
final class ServiceRecordDivergenceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-divsvc-\(UUID().uuidString)")
        let store = LibraryStore(root: root, key: nil,
                                 environment: ["AKASHIC_HOME": fakeHome.path])
        try store.ensureLayout()
        try store.writePerson(Person(key: "chen-h-y", names: ["Chen, H.-Y."]))
        try store.writePerson(Person(key: "chen-hui-yun", names: ["Chen, Hui-Yun"]))
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    func testRecordDivergenceWritesRecord() throws {
        let out = try service.recordDivergence(
            question: "縮寫 H.-Y. 是否即 Hui-Yun",
            candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: [])
        XCTAssertTrue(out.contains("id"), "回傳要含記錄 id：\(out)")
        let load = try LibraryStore(root: root, key: nil,
                                    environment: ["AKASHIC_HOME": fakeHome.path]).load()
        XCTAssertEqual(load.divergences.count, 1)
        XCTAssertEqual(load.divergences.first?.candidates.map(\.key).sorted(),
                       ["chen-h-y", "chen-hui-yun"])
    }

    func testRecordDivergenceRejectsSingleCandidate() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:person"], judgement: nil, restsOn: []))
    }

    func testRecordDivergenceRejectsJudgementWithoutBasis() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: "同一人", restsOn: []),
            "判斷與依據必須成對（#71 不變式）——MCP 面與 CLI 同紀律")
    }

    func testRecordDivergenceRejectsMalformedCandidateSpec() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y", "chen-hui-yun:person"],
            judgement: nil, restsOn: []),
            "候選格式 key:shape——與 CLI 同格式，錯格式要指明")
    }

    /// #133 verify F1：同組候選 re-record 的三態——補寫允許、更新允許、毀損拒絕。
    func testRecordDivergenceRefusesToSilentlyEraseJudgement() throws {
        _ = try service.recordDivergence(
            question: "q1", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: "同一人", restsOn: ["https://example.org/roster"])
        // 有→nil：拒絕（曾經靜默抹掉判斷與 question）
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q2", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: [])) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(m.contains("判斷") && !m.contains("不符合"),
                          "要指明既有判斷會被抹掉、且不得套 key-pattern 框架：\(m)")
        }
        // 有→有：更新允許
        XCTAssertNoThrow(try service.recordDivergence(
            question: "q3", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: "仍同一人，另據", restsOn: ["https://example.org/other"]))
    }

    /// #133 verify F2：shape 說是什麼就到那個形狀的集合驗——person 記成 work 拒絕；
    /// 真正的 work（citekey）從此可用（曾因 known 漏掉 entries 而結構上不可用）。
    func testRecordDivergenceValidatesShapeMembership() throws {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:work", "chen-hui-yun:work"],
            judgement: nil, restsOn: []),
            "person 的 key 記成 work＝寫出一筆永遠無法消歧的記錄，必須當場拒絕")
    }

    /// #133 verify F3：拒絕訊息不得套「不符合 key 正規式」的假框架。
    func testRecordDivergenceErrorsDoNotClaimKeyPatternViolation() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["chen-h-y:person"], judgement: nil, restsOn: [])) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertFalse(m.contains("不符合"),
                           "候選數不足與 key 語法無關——框架錯了 LLM 會去清洗 key：\(m)")
        }
    }

    func testRecordDivergenceRejectsUnknownCandidate() {
        XCTAssertThrowsError(try service.recordDivergence(
            question: "q", candidates: ["ghost-person:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: []),
            "對不存在的鍵記歧異沒有意義（store 層既有守衛，經 MCP 面透傳）")
    }
}

/// #76：「承載必須可觀察」的 MCP 面——#71 第 7 條只在 CLI 落實，#133 之後
/// MCP 能寫歧異卻仍看不見它（寫得進、看不見比純粹看不見更糟——#133 verify F2
/// 實測：MCP 寫出 validate 會警告的記錄，警告只在 CLI 面出現）。
final class ServiceObservabilityTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-obs-\(UUID().uuidString)")
        let store = LibraryStore(root: root, key: nil,
                                 environment: ["AKASHIC_HOME": fakeHome.path])
        try store.ensureLayout()
        try store.writePerson(Person(key: "chen-h-y", names: ["Chen, H.-Y."]))
        try store.writePerson(Person(key: "chen-hui-yun", names: ["Chen, Hui-Yun"]))
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
        _ = try service.recordDivergence(
            question: "縮寫是否同一人", candidates: ["chen-h-y:person", "chen-hui-yun:person"],
            judgement: nil, restsOn: [])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    func testDoctorReportsDivergenceCount() throws {
        let out = try service.doctor()
        XCTAssertTrue(out.contains("\"divergences\""),
                      "MCP doctor 要與 CLI 對齊——同一個 store 不得從兩個 consumer 看到不同的事實：\(out)")
    }

    func testDoctorReportsCrossRecordIssues() throws {
        // 構造一筆跨記錄問題：歧異候選指向的 person 刪掉 → 懸空
        try FileManager.default.removeItem(
            at: try XCTUnwrap(FileManager.default
                .contentsOfDirectory(at: root.appendingPathComponent("entities"),
                                     includingPropertiesForKeys: nil)
                .first { url in
                    (try? String(contentsOf: url, encoding: .utf8))?.contains("chen-h-y") == true
                        && (try? String(contentsOf: url, encoding: .utf8))?.contains("divergence") != true
                }))
        let out = try service.doctor()
        XCTAssertTrue(out.contains("crossRecordIssues"),
                      "跨記錄警告（含「歧異無法被消歧」）不得只在 CLI 面可見：\(out)")
    }

    func testDivergencesListTool() throws {
        let out = try service.listDivergences()
        XCTAssertTrue(out.contains("縮寫是否同一人"), "list 要含 question：\(out)")
        XCTAssertTrue(out.contains("chen-h-y"), "list 要含候選鍵：\(out)")
        XCTAssertTrue(out.contains("hasJudgement"), "\(out)")
    }
}

/// #142：thrown error 不得把 caller 輸入的原始控制位元組 echo 回去——
/// MCP 情境下 error 文本直灌 LLM context（bidi override / ESC sequence）。
extension ServiceTests {
    func testErrorMessagesEscapeCallerControlBytes() throws {
        let hostile = "esc\u{1B}[31m\u{202E}evil"
        func assertClean(_ error: Error, _ ctx: String) {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertFalse(msg.contains("\u{1B}") || msg.contains("\u{202E}"),
                           "\(ctx)：原始位元組不得進錯誤訊息：\(msg.debugDescription)")
        }
        // key guard 拒絕路徑（StoreIOError.invalidKey 經 addPerson）
        XCTAssertThrowsError(try service.addPerson(
            key: hostile, names: ["X"], orcid: nil, openalex: nil)) { e in
            assertClean(e, "invalidKey")
            let msg = (e as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("evil"), "消毒後仍可辨認：\(msg)")
            // #149 verify F3：不得雙重 escape（\u{005C}u{001B}）
            XCTAssertFalse(msg.contains("u{005C}u{"), "雙重 escape：\(msg)")
        }
        // lookup miss（ServiceError.notFound）
        XCTAssertThrowsError(try service.getEntry(citekey: hostile)) { assertClean($0, "notFound") }
        // #149 verify F1：graph 與 relations 的 lookup miss（GraphError/QueryError）
        XCTAssertThrowsError(try service.graph(focus: hostile, depth: 1, format: "mermaid")) {
            assertClean($0, "graph/GraphError")
        }
        XCTAssertThrowsError(try service.relations(citekey: hostile, kind: "cites")) {
            assertClean($0, "relations/QueryError")
        }
    }

    /// #149 verify F1/F2：姊妹 error 型別的 errorDescription 消毒 caller 值
    /// （QueryError/GraphError/ConfigError——與 ServiceError.notFound 同 bug class）。
    func testSiblingErrorTypesEscapeCallerValues() {
        let hostile = "ev\u{1B}[31m\u{202E}il"
        let cases: [(String, LocalizedError)] = [
            ("QueryError", QueryError.unknownCitekey(hostile)),
            ("GraphError", GraphError.unknownCitekey(hostile)),
            ("ConfigError.invalidFileKey", ConfigError.invalidFileKey(hostile)),
            ("ConfigError.invalidCurrent", ConfigError.invalidCurrent(hostile)),
        ]
        for (name, err) in cases {
            let msg = err.errorDescription ?? ""
            XCTAssertFalse(msg.contains("\u{1B}") || msg.contains("\u{202E}"),
                           "\(name)：原始位元組不得進 errorDescription：\(msg.debugDescription)")
            XCTAssertTrue(msg.contains("il"), "\(name)：消毒後仍可辨認：\(msg)")
        }
    }
}

/// #171 verify 171-5：**成功回傳**的 dict 值也是 tool result——四條漏網。
///
/// 前面兩個 extension 釘的是 **error** 路徑。這一組釘 **success** 路徑：同一個
/// dict literal 裡有些值包了 `displaySafe`、有些沒有。`zotero_key` 最刺眼——
/// **下一行**的 `zotero_hash` 包了，註解還寫著「Zotero 寫進來的自由字串」。
///
/// 這是本檔案第四次記錄同一個形狀（literal／journal／tags／本組）。守衛看不見
/// 它們：`DisplaySinkCoverageTests` 的 dict-literal 判準對這些行不成立，而 #164
/// 試過的兩種擴充一個 recall 0/3、一個誤中 94%（已撤回並記錄）。
///
/// **所以這裡是行為測試，不是再加一條掃描規則。** 值得記的是發現方式：四條全部
/// 由「同一份資料在同一個檔案裡有兩種待遇」的人工比對找到，沒有一條是機械抓到的。
extension ServiceTests {
    private var hostileEcho: String { "ev\u{1B}[31m\u{202E}il" }

    private func assertNoRawControls(_ s: String, _ ctx: String) {
        XCTAssertFalse(s.contains("\u{1B}"), "\(ctx)：raw ESC 抵達 tool result")
        XCTAssertFalse(s.contains("\u{202E}"), "\(ctx)：raw U+202E 抵達 tool result")
    }

    /// (a) `Provenance.zoteroKey` — 與同 dict 下一行的 `zotero_hash` 同源、同待遇缺口。
    func testProvenanceZoteroKeyIsSanitised() throws {
        var e = Entry(id: UUID(), citekey: "prov2020", type: .periodicalArticle, title: "T")
        e.date = "2020"
        e.provenance = Provenance(zoteroKey: "ABCD\(hostileEcho)EF", zoteroVersion: 3)
        try LibraryStore(root: root).writeEntry(e)
        assertNoRawControls(try service.getEntry(citekey: "prov2020"), "provenance.zotero_key")
    }

    /// (b) `relations.cites/related` — 讀寫兩端**都沒有** StoreKey 驗證，是自由字串。
    ///     `link()` 與 `entryDict()` 兩個吐出點都要蓋到。
    func testRelationKeysAreSanitisedOnBothSurfaces() throws {
        var e = Entry(id: UUID(), citekey: "rel2020", type: .periodicalArticle, title: "T")
        e.date = "2020"
        e.akashic.relations.cites = ["other\(hostileEcho)key"]
        e.akashic.relations.related = ["rel\(hostileEcho)ated"]
        try LibraryStore(root: root).writeEntry(e)
        assertNoRawControls(try service.getEntry(citekey: "rel2020"), "entryDict 的 cites/related")
        // **兩個 surface 都要真的走到**（#171 複驗 171-8）：這條原本只呼叫
        // `getEntry`，卻在名字與 doc 裡宣稱蓋到 `link()`——只還原 `link()` 的消毒，
        // 1023 條零紅。修法有效但可以被無聲刪除，而「測試名字宣稱了它沒驗的性質，
        // 那比沒有測試更糟」是本 repo 已經記過的（`OrgBootstrapCLITests.swift:144`）。
        assertNoRawControls(try service.link(citekey: "rel2020", kind: "cites",
                                             add: [], remove: []),
                            "link() 的 cites/related")
    }

    /// (e) `files` 的 `list` 分支 — **同一個函式的 `use` 分支已經包了**。
    ///     config.yaml 的 path **值**是自由字串（只有 key 過 StoreKey）。
    func testFilesListSanitisesRootPaths() throws {
        let hostileRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ev\u{1B}[31m\u{202E}il-\(UUID().uuidString)")
        try LibraryStore(root: hostileRoot).ensureLayout()
        let cfg = AkashicConfig(library: hostileRoot.path,
                                files: ["hostile": hostileRoot.path], current: "hostile")
        try cfg.write(to: service.configURL)
        let svc = AkashicService(root: hostileRoot, key: "hostile", configURL: service.configURL,
                                 environment: ["AKASHIC_HOME": fakeHome.path])
        assertNoRawControls(try svc.files(action: "list", key: nil),
                            "files list 的 active_root / legacy_library")
        try? FileManager.default.removeItem(at: hostileRoot)
    }

    /// (f)(g) `person()` 的 `co_authors[].person_key` 與 `personDict["key"]`。
    ///
    /// **作者 key 讀寫兩端都沒有 StoreKey 驗證**（`writeEntry` 只驗 `citekey` 與
    /// `libraries`），與 (b) 的 `relations.cites` 同源。兩處都是「同一份字串在同一個
    /// 回應裡兩種待遇」——`co_authors` 的 `name` fallback 就是 `person_key` 本身。
    func testPersonKeyEchoesAreSanitised() throws {
        let hostileKey = "ev\u{1B}[31m\u{202E}il-key"
        var e = Entry(id: UUID(), citekey: "coauth2020", type: .periodicalArticle, title: "T")
        e.date = "2020"
        e.authors = [.key(hostileKey), .key("cheng-che")]
        try LibraryStore(root: root).writeEntry(e)
        // record == nil（沒有 person 檔）→ personDict 走 key 原樣回吐那條路徑
        assertNoRawControls(try service.person(key: hostileKey, name: nil, library: nil),
                            "personDict 的 key")
        // 有 record 的一側則走 co_authors.person_key
        assertNoRawControls(try service.person(key: "cheng-che", name: nil, library: nil),
                            "co_authors 的 person_key")
    }

    /// (c) `addPerson` 回吐 `names` — 單一來回把呼叫端字串原樣送進 LLM context。
    ///     這正是 #156 verify R5 在 `setStatus` 上認定為真洩漏的同一形狀。
    func testAddPersonDoesNotEchoRawNames() throws {
        let out = try service.addPerson(key: "hostile-echo", names: ["Nice Name\(hostileEcho)"],
                                        orcid: nil, openalex: nil)
        assertNoRawControls(out, "addPerson 的 names echo")
    }
}


/// #146 verify G2/N1：**MCP 的 `digestSources` 可以整個刪掉而沒人發現**。
///
/// `AkashicService.doctor()` 自己的註解寫著「CLI doctor 的普查面 MCP 也要有——
/// 同一個 store 不得從兩個 consumer 看到不同的事實」（#138 verify F3）。#146 的
/// 第一版只加了 CLI 側；補上 MCP 之後**仍然零測試**，席位 mutation 刪掉那一行
/// 1038 條全綠。
extension ServiceTests {
    func testMCPDoctorMirrorsDigestResidue() throws {
        let digest = "sha256:" + String(repeating: "0a", count: 32)
        var p = Person(key: "digest-holder", names: ["N"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.key("iss"), source: digest, note: "由論文推得")])
        try LibraryStore(root: root).writePerson(p)

        let out = try service.doctor()
        let d = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8))
                                as? [String: Any])
        let residue = try XCTUnwrap(d["digestSources"] as? [String],
                                    "MCP doctor 少了 digestSources——同一個 store 從兩個"
                                    + " consumer 看到不同的事實（#138 verify F3 的紀律）")
        XCTAssertEqual(residue, ["digest-holder.profile.affiliations"])
    }

    /// #236 R3：**reviewer 量到的最壞形狀**——50 個不同 literal、每列 2 人、
    /// 全部欄位用會膨脹的字元。前一版測試用「60 人共用一個名字」，量到 4.6 KB，
    /// 而真正的最壞是 474 KB（`truncated: false`）。**測試的 store 形狀決定了它
    /// 能發現什麼**，而我選的形狀恰好避開了最壞。
    func testPayloadBoundedOnManyDistinctLiteralsWithExpandingChars() throws {
        let store = LibraryStore(root: root)
        let bidi = String(repeating: "\u{202E}", count: 80)
        for i in 0..<50 {
            for s in ["a", "b"] {
                var p = Person(key: "wide-\(s)-\(i)", names: ["Wide \(i)", bidi, bidi])
                // orcid 已型別化（#394 task 3.3）：`bidi` 不合 ORCID 形狀，指派不到
                // 這個欄位上——膨脹字元的注入面收斂到 names／openalex，這是型別
                // 化刻意關閉的其中一個向量，不是漏測。
                p.openalex = bidi
                try store.writePerson(p)
            }
            try store.writeEntry(Entry(id: UUID(), citekey: "wide\(i)", type: .periodicalArticle,
                                       title: "T", authors: [.literal("Wide \(i)")], date: "2020"))
        }
        let raw = try service.resolvePeople(apply: nil)
        XCTAssertLessThan(raw.utf8.count, 64 * 1024,
                          "50 個不同 literal × 膨脹字元是 reviewer 量到 474 KB 的形狀。"
                          + "實際 \(raw.utf8.count) bytes")
        let out = try json(raw) as! [String: Any]
        for row in out["ambiguities"] as! [[String: Any]] {
            XCTAssertGreaterThanOrEqual((row["personRefs"] as! [String]).count, 2,
                                        "每列仍須 ≥2 refs：\(row)")
        }
    }
}
