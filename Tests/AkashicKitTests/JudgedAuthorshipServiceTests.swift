import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// 判定的**入口**契約（change `per-work-judged-authorship`；spec person-resolution）。
///
/// 型別層的行為由 `JudgedPairingTests` 釘住；本檔釘的是「使用者／agent 送一個三段形 id
/// 加一句 judgement 進來之後，store 變成什麼樣」——含解析、守衛、回報形狀。
///
/// **service 而非 CLI**：`resolve-people` 的 `--reject` 既有作法就是委派給
/// `AkashicService`（該處註解：「與 MCP 同一條實作路徑，兩條各自寫會分岔」），
/// 判定沿用同一條。
final class JudgedAuthorshipServiceTests: XCTestCase {
    var root: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-judged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"),
                               atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        // verdict 需要 store format ≥ 8
        try StoreVersion.write(root: root, format: StoreVersion.supported)

        var p1 = Person(key: "chen-hsin-chen")
        p1.names = PersonNames(authorized: ["Chen, Chen-Hsin"], variant: [])
        var p2 = Person(key: "chun-houh-chen")
        p2.names = PersonNames(authorized: ["Chen, Chun-houh"], variant: [])
        try store.writePerson(p1)
        try store.writePerson(p2)

        var e = Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T")
        e.authors = [.literal("Someone Else"), .literal("C-H Chen")]
        try store.writeEntry(e)

        service = AkashicService(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func judge(_ specs: [String]) throws -> [String: Any] {
        let json = try service.resolvePeople(apply: nil, judge: specs)
        return (try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    private func reloadEntry() throws -> Entry {
        try LibraryStore(root: root).load().entries.first { $0.citekey == "w1" }!
    }

    // MARK: - 正常路徑

    /// spec scenario「A judged pairing resolves the named author position」。
    func testJudgementResolvesTheNamedPositionAndRecordsTheVerdict() throws {
        let out = try judge(["w1:1:chun-houh-chen=該作者位登記機構為統計所"])
        XCTAssertEqual((out["judged"] as? [Any])?.count, 1, "回報應含 1 筆判定：\(out)")

        XCTAssertEqual(try reloadEntry().authors,
                       [.literal("Someone Else"), .key("chun-houh-chen")])

        let p = try LibraryStore(root: root).load().people
            .first { $0.key == "chun-houh-chen" }!
        let v = p.references.filter { $0.field == "resolution-confirmed" }
        XCTAssertEqual(v.count, 1, "應寫一筆 confirmed verdict")
        guard case let .judgement(statement, restsOn) = v[0].kind else {
            return XCTFail("verdict 應是 judgement，實得 \(v[0].kind)")
        }
        XCTAssertTrue(statement.contains("該作者位登記機構為統計所"), statement)
        XCTAssertTrue(statement.contains(ResolutionLedger.judgedRule), statement)
        XCTAssertTrue(restsOn.isEmpty, "#280：verdict 不攜 rests-on")
    }

    /// 判定的 literal **由 store 讀**，不由使用者打——順帶天然強制「該位置仍是 literal」。
    func testLiteralIsReadFromTheStoreNotSuppliedByTheCaller() throws {
        _ = try judge(["w1:1:chun-houh-chen=理由"])
        let p = try LibraryStore(root: root).load().people
            .first { $0.key == "chun-houh-chen" }!
        let v = p.references.first { $0.field == "resolution-confirmed" }!
        XCTAssertTrue((v.value ?? "").contains("C-H Chen"),
                      "verdict 的 value 應含 store 裡的 literal：\(v.value ?? "")")
    }

    // MARK: - 失敗模式（皆須具名，不得靜默）

    func testBlankJudgementIsRefusedByName() throws {
        XCTAssertThrowsError(try judge(["w1:1:chun-houh-chen=   "])) { e in
            XCTAssertTrue("\(e)".contains("judgement"), "錯誤應指名 judgement：\(e)")
        }
        XCTAssertEqual(try reloadEntry().authors,
                       [.literal("Someone Else"), .literal("C-H Chen")],
                       "拒絕時不得有任何寫入")
    }

    func testMissingSeparatorIsRefusedByName() throws {
        XCTAssertThrowsError(try judge(["w1:1:chun-houh-chen"])) { e in
            XCTAssertTrue("\(e)".contains("="), "錯誤應說明缺少分隔符：\(e)")
        }
    }

    // MARK: - 狀態不符 → **略過並具名**，不中止其餘（spec 明訂）

    /// spec: `A judged pairing SHALL be applied only when the named position still holds
    /// the named literal` —— 「SHALL NOT abort the remaining pairings」那一句。
    ///
    /// 這三項（work 不存在／索引越界／位置已歸戶）是 store **狀態**不符，不是輸入語法錯，
    /// 語意同 `apply` 的既有三道守衛：一筆過期的判定不該讓其餘進不去。
    func testUnknownCitekeyIsSkippedByNameWithoutBlockingOthers() throws {
        let out = try judge(["nope:0:chun-houh-chen=理由",
                             "w1:1:chun-houh-chen=好的那筆"])
        let skipped = (out["skipped"] as? [[String: Any]]) ?? []
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped.first?["id"] as? String, "nope:0:chun-houh-chen")
        XCTAssertTrue((skipped.first?["why"] as? String ?? "").contains("nope"),
                      "略過原因應指名該 citekey：\(skipped)")
        XCTAssertEqual((out["judged"] as? [Any])?.count, 1, "好的那筆仍須落地")
        XCTAssertEqual(try reloadEntry().authors[1], .key("chun-houh-chen"))
    }

    func testOutOfRangeIndexIsSkippedByName() throws {
        let out = try judge(["w1:9:chun-houh-chen=理由"])
        let skipped = (out["skipped"] as? [[String: Any]]) ?? []
        XCTAssertEqual(skipped.count, 1)
        XCTAssertTrue((skipped.first?["why"] as? String ?? "").contains("9"),
                      "略過原因應指名該索引：\(skipped)")
        XCTAssertEqual((out["judged"] as? [Any])?.count, 0)
    }

    /// 該位置已歸戶 → 略過並具名，**不覆寫既有歸戶**。
    func testAlreadyKeyedPositionIsSkippedAndNotOverwritten() throws {
        _ = try judge(["w1:1:chun-houh-chen=第一次"])
        let out = try judge(["w1:1:chen-hsin-chen=想改判"])
        let skipped = (out["skipped"] as? [[String: Any]]) ?? []
        XCTAssertEqual(skipped.count, 1)
        XCTAssertTrue((skipped.first?["why"] as? String ?? "").contains("已經歸戶"),
                      "略過原因應說明已歸戶：\(skipped)")
        XCTAssertEqual(try reloadEntry().authors[1], .key("chun-houh-chen"),
                       "既有歸戶不得被覆寫")
    }

    func testUnknownPersonKeyIsRefusedByName() throws {
        XCTAssertThrowsError(try judge(["w1:1:no-such-person=理由"])) { e in
            XCTAssertTrue("\(e)".contains("no-such-person"), "錯誤應指名該 person：\(e)")
        }
    }

    /// judgement 含 `=` 時只切第一個——理由文字本來就可能有等號。
    func testJudgementMayContainEqualsSign() throws {
        _ = try judge(["w1:1:chun-houh-chen=機構 = 統計所"])
        let p = try LibraryStore(root: root).load().people
            .first { $0.key == "chun-houh-chen" }!
        let v = p.references.first { $0.field == "resolution-confirmed" }!
        guard case let .judgement(statement, _) = v.kind else { return XCTFail() }
        XCTAssertTrue(statement.contains("機構 = 統計所"), statement)
    }
}
