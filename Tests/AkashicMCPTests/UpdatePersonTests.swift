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
        var p = Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"],
                       authorized: ["Che Cheng", "鄭澈"])
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
        XCTAssertEqual(p.names, ["Che Cheng", "鄭澈"])
        XCTAssertEqual(p.profile.ranks.entries.count, 1)
    }

    func testNullClearsField() throws {
        _ = try service.updatePerson(key: "cheng-che",
                                     fields: ["note": NSNull()], dryRun: false)
        XCTAssertNil(try load().note, "提及為 null ＝ 清除；與「未提及」不同")
    }

    func testListFieldIsFullReplacement() throws {
        _ = try service.updatePerson(
            key: "cheng-che",
            fields: ["names": ["Che Cheng", "鄭澈", "Cheng, C."]], dryRun: false)
        XCTAssertEqual(try load().names, ["Che Cheng", "鄭澈", "Cheng, C."])
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
        var p = Person(key: "wang-x", names: ["Wang, X."])
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
