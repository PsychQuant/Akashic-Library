import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #68：person 的部分更新入口——外部 pipeline 不該手刻 YAML 合併。
///
/// 契約：**提及的欄位整個換、未提及一律不動**（欄位級覆寫；timeline 的增量語意
/// 刻意不做——那是 #100/#75 的未決區）。合併走 decoder→改→encoder：
/// tolerant-preserve 與 canary 白拿。
final class UpdatePersonTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-up-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-up-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var p = Person(key: "cheng-che",
                       names: PersonNames(authorized: ["Che Cheng", "鄭澈"]))
        p.orcid = "0000-0003-4038-9439"
        p.note = "既有備註"
        p.profile.ranks = Timeline([
            TemporalValue(value: "助研究員", range: DateRange(start: "2003"))])
        try store.writePerson(p)
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func load() throws -> Person {
        try XCTUnwrap(LibraryStore(root: root).load().people.first { $0.key == "cheng-che" })
    }

    // MARK: - 欄位級覆寫

    func testMentionedFieldsOverwrittenUnmentionedUntouched() throws {
        _ = try service.updatePerson(key: "cheng-che",
                                     fields: ["openalex": "A5017898742",
                                              "note": "新備註"],
                                     dryRun: false)
        let p = try load()
        XCTAssertEqual(p.openalex, "A5017898742")
        XCTAssertEqual(p.note, "新備註")
        // 未提及的一律不動
        XCTAssertEqual(p.orcid, "0000-0003-4038-9439")
        XCTAssertEqual(p.names, PersonNames(authorized: ["Che Cheng", "鄭澈"]))
        XCTAssertEqual(p.profile.ranks.entries.count, 1)
    }

    func testNullClearsField() throws {
        _ = try service.updatePerson(key: "cheng-che",
                                     fields: ["note": NSNull()], dryRun: false)
        XCTAssertNil(try load().note, "提及為 null ＝ 清除；與「未提及」不同")
    }

    func testListFieldIsFullReplacement() throws {
        // #227：names 收巢狀 object，全量替換整個 names 結構
        _ = try service.updatePerson(
            key: "cheng-che",
            fields: ["names": ["authorized": ["Che Cheng", "鄭澈"],
                               "variant": ["Cheng, C."]]], dryRun: false)
        XCTAssertEqual(try load().names,
                       PersonNames(authorized: ["Che Cheng", "鄭澈"], variant: ["Cheng, C."]))
    }

    func testProfileDimensionIsFullReplacementPerDimension() throws {
        _ = try service.updatePerson(
            key: "cheng-che",
            fields: ["profile": [
                "ranks": [["value": "副研究員", "start": "2010"],
                          ["value": "研究員", "start": "2018"]],
            ]], dryRun: false)
        let p = try load()
        XCTAssertEqual(p.profile.ranks.entries.map(\.value), ["副研究員", "研究員"],
                       "提及的維度全量替換")
        XCTAssertEqual(p.profile.affiliations.entries.count, 0, "未提及維度不動（原本就空）")
    }

    /// profile 只換提及的維度——未提及的維度保留（維度級、不是整個 profile 級）。
    func testProfileUnmentionedDimensionPreserved() throws {
        _ = try service.updatePerson(
            key: "cheng-che",
            fields: ["profile": [
                "fields": [["value": "統計學"]],
            ]], dryRun: false)
        let p = try load()
        XCTAssertEqual(p.profile.fields.entries.map(\.value), ["統計學"])
        XCTAssertEqual(p.profile.ranks.entries.map(\.value), ["助研究員"],
                       "未提及的 ranks 維度必須保留")
    }

    // MARK: - 白名單（由 decoder 的 known keys 推導，不手寫清單）

    func testUnknownFieldRejectedNamingIt() {
        XCTAssertThrowsError(try service.updatePerson(
            key: "cheng-che", fields: ["orcidd": "typo"], dryRun: false)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("orcidd"), "錯誤必須指名不認得的欄位：\(msg)")
            // #148 verify F5：必須走白名單分支（列出可更新集合），不是 default
            // 分支的「decoder 認得但未支援」——那對 typo 是一句假話。拔掉白名單
            // 檢查時這兩個斷言會紅。
            XCTAssertTrue(msg.contains("orcid") && msg.contains("profile"),
                          "訊息必須列出可更新集合：\(msg)")
            XCTAssertFalse(msg.contains("尚未支援"),
                           "typo 不得被說成「decoder 認得但未支援」：\(msg)")
        }
    }

    /// #227：#148 F4 的「authorized 懸空」在巢狀結構下**不可表達**，原測試由本
    /// 測試取代——平坦陣列拒收（與 decoder 同紀律）、舊頂層 authorized 鍵已不在
    /// 可更新集合，且拒絕不落盤。
    func testFlatNamesArrayAndOldAuthorizedKeyRefused() throws {
        XCTAssertThrowsError(try service.updatePerson(
            key: "cheng-che", fields: ["names": ["鄭澈", "Cheng, C."]],
            dryRun: false)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("authorized") && msg.contains("variant"),
                          "訊息要指出新形狀：\(msg)")
        }
        XCTAssertThrowsError(try service.updatePerson(
            key: "cheng-che", fields: ["authorized": ["Che Cheng"]],
            dryRun: false)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("不認得的欄位"), msg)
        }
        // 檔案未被改動
        XCTAssertEqual(try load().names, PersonNames(authorized: ["Che Cheng", "鄭澈"]))
    }

    /// #148 verify F7：contacts 是「值為子鍵 map」的維度——維度級覆寫＝整個
    /// contacts map 替換（未提及的子鍵會消失），釘住這個容易被誤讀的形狀。
    func testContactsDimensionReplacesWholeMap() throws {
        _ = try service.updatePerson(
            key: "cheng-che",
            fields: ["profile": ["contacts": [
                "email": [["value": "a@b.c"]],
                "phone": [["value": "123"]],
            ]]], dryRun: false)
        _ = try service.updatePerson(
            key: "cheng-che",
            fields: ["profile": ["contacts": ["phone": [["value": "456"]]]]],
            dryRun: false)
        let p = try load()
        XCTAssertNil(p.profile.contacts["email"],
                     "contacts 是一個維度：整 map 替換，email 消失是契約行為")
        XCTAssertEqual(p.profile.contacts["phone"]?.entries.first?.value, "456")
    }

    /// #148 verify F3：深度炸彈回真正的錯誤，不是進程死亡。
    ///
    /// **只覆蓋 service 層**（in-process）：R2 複驗定位到 depth 200-700 的撞毀
    /// 其實在 MCP transport（SDK 解訊息層、影響全部 tool、與本 PR 無關——任何
    /// 帶深巢狀的 JSON-RPC 訊息都殺 server，連 unknown tool 都到不了 handler）。
    /// 本測試綠**不代表** transport 層安全——那屬 transport 深度 issue 的範圍。
    /// 這裡的兩個深度上限是 defence in depth（65-100 層有效、訊息可讀）。
    func testNestingDepthBombReturnsErrorNotCrash() {
        var nested: Any = "leaf"
        for _ in 0..<300 { nested = [nested] }
        XCTAssertThrowsError(try service.updatePerson(
            key: "cheng-che",
            fields: ["profile": ["contacts": ["phone": nested]]], dryRun: true)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("深度"), "必須是深度上限的錯誤：\(msg)")
        }
    }

    func testStructuralKeysRefused() {
        for k in ["id", "key", "type"] {
            XCTAssertThrowsError(try service.updatePerson(
                key: "cheng-che", fields: [k: "x"], dryRun: false),
                "結構性鍵 \(k) 不可經部分更新改動")
        }
    }

    func testAbsentPersonRefused() {
        XCTAssertThrowsError(try service.updatePerson(
            key: "no-such-person", fields: ["note": "x"], dryRun: false))
    }

    // MARK: - tolerant-preserve round-trip

    func testUnknownFieldsOnDiskSurviveUpdate() throws {
        // 較新 binary 寫的未知欄位——手動注入檔案層
        let store = LibraryStore(root: root)
        let url = store.entityURL(id: try load().id)
        var text = try String(contentsOf: url, encoding: .utf8)
        text += "future-field: 未來的值\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        _ = try service.updatePerson(key: "cheng-che",
                                     fields: ["note": "更新後"], dryRun: false)
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("future-field: 未來的值"),
                      "tolerant-preserve：未知欄位必須在 read-modify-write 中存活：\(after)")
        XCTAssertTrue(after.contains("更新後"))
    }

    // MARK: - dry-run

    func testDryRunWritesNothingAndReportsDiff() throws {
        let url = LibraryStore(root: root).entityURL(id: try load().id)
        let before = try Data(contentsOf: url)
        let out = try service.updatePerson(key: "cheng-che",
                                           fields: ["note": "dry 的新值",
                                                    "openalex": "A5017898742"],
                                           dryRun: true)
        XCTAssertEqual(try Data(contentsOf: url), before, "dry-run 零寫入")
        XCTAssertTrue(out.contains("note") && out.contains("openalex"),
                      "diff 要列出會改的欄位：\(out)")
        XCTAssertTrue(out.contains("dryRun") || out.contains("dry"), out)
    }

    /// dry-run 的 gate 預演（#63/#131 的 v6 gate）：不預演的 dry-run 會說「會改」
    /// 而 real run 被 gate 擋——dry-run 就成了謊言。
    func testDryRunPredictsFormatGateRejection() throws {
        // 造一個 format 5 store（v6 gate 會擋 ended 段）
        let oldRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-up-old-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: oldRoot) }
        let old = LibraryStore(root: oldRoot)
        try FileManager.default.createDirectory(
            at: oldRoot.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: oldRoot, format: 5)
        let p = Person(key: "wang-x", names: ["Wang, X."])
        try old.writePerson(p)
        let oldService = AkashicService(root: oldRoot,
                                        environment: ["AKASHIC_HOME": fakeHome.path])

        let fields: [String: Any] = ["profile": [
            "affiliations": [["value": ["literal": "某機構"], "ended": true]],
        ]]
        let out = try oldService.updatePerson(key: "wang-x", fields: fields, dryRun: true)
        XCTAssertTrue(out.contains("format") && (out.contains("6") || out.contains("gate")),
                      "dry-run 必須預告 real run 會被 v6 gate 擋：\(out)")
        // real run 真的被擋（gate 行為與預演一致）
        XCTAssertThrowsError(try oldService.updatePerson(
            key: "wang-x", fields: fields, dryRun: false))
        // 檔案未被改動
        let reload = try old.load()
        XCTAssertEqual(reload.people.first?.profile.affiliations.entries.count, 0)
    }
}
