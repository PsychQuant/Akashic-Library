import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import akashic

/// #458：generic add-only 補值的 CLI 面（`akashic enrich --from <file.json> [--apply] [--include-absent-authors] [--json]`）。
///
/// **走真 binary、經 `CLITestHarness`**；fixture 用已註冊 store（`registerStore()`）——閘的測試需要
/// 「未指名目標時解析到哪」這件事真的發生在假 home 裡。
final class EnrichCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    let alpha = UUID()

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-enrich-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e1 = Entry(id: alpha, citekey: "cheng2025alpha", type: .periodicalArticle,
                       title: "Alpha", authors: [.key("che-cheng")], date: "2025", doi: [DOI("10.1037/x")!])
        e1.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e1)
        try store.writeEntry(Entry(id: UUID(), citekey: "noauthor2020x", type: .periodicalArticle, title: "Anon"))
        try store.writePerson(Person(key: "che-cheng", names: PersonNames(authorized: ["Cheng, Che"])))
        try "files:\n  probe: \(root.path)\ncurrent: probe\n"
            .write(to: fakeHome.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func proposals(_ json: String) throws -> String {
        let f = fakeHome.appendingPathComponent("proposals-\(UUID().uuidString).json")
        try json.write(to: f, atomically: true, encoding: .utf8)
        return f.path
    }
    private func entry(_ citekey: String) throws -> Entry {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == citekey })
    }
    private func bytes(_ id: UUID) throws -> Data { try Data(contentsOf: LibraryStore(root: root).entityURL(id: id)) }

    // MARK: - 乾跑預設

    /// spec「CLI dry run writes nothing」：報告印出來、磁碟逐位元組不變。
    func testDryRunPrintsReportAndWritesNothing() throws {
        let before = try bytes(alpha)
        let f = try proposals(#"[{"citekey":"cheng2025alpha","fields":{"abstract":"An abstract","journaltitle":"X"}}]"#)
        let r = try cli(["enrich", "--from", f])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("cheng2025alpha"), r.output)
        XCTAssertTrue(r.output.contains("+ abstract"), "要印會補什麼：\(r.output)")
        XCTAssertTrue(r.output.contains("journaltitle"), "已有的鍵要說出來：\(r.output)")
        XCTAssertTrue(r.output.contains("dry-run"), r.output)
        XCTAssertEqual(try bytes(alpha), before)
    }

    // MARK: - --apply 走 #298 閘

    /// 未指名目標 store（無 `--library`、無 `--yes`）→ 拒絕，磁碟不動；`--yes` 是知情同意的出路。
    func testApplyWithoutTargetHitsGate() throws {
        let before = try bytes(alpha)
        let f = try proposals(#"[{"citekey":"cheng2025alpha","fields":{"abstract":"A"}}]"#)
        let bare = try CLITestHarness.run(["enrich", "--from", f, "--apply"], env: env)
        XCTAssertNotEqual(bare.status, 0, bare.output)
        XCTAssertTrue(bare.output.contains("未指名目標 store"), bare.output)
        XCTAssertEqual(try bytes(alpha), before, "被閘擋下＝零寫入")
        let yes = try CLITestHarness.run(["enrich", "--from", f, "--apply", "--yes"], env: env)
        XCTAssertEqual(yes.status, 0, yes.output)
        XCTAssertEqual(try entry("cheng2025alpha").fields["abstract"], "A")
    }

    func testApplyWithLibraryWrites() throws {
        let f = try proposals(#"[{"doi":"10.1037/X","fields":{"abstract":"Via DOI"}}]"#)
        let r = try cli(["enrich", "--from", f, "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("已寫入 1 筆"), r.output)
        XCTAssertEqual(try entry("cheng2025alpha").fields["abstract"], "Via DOI")
    }

    // MARK: - --json 同源

    /// `--json` 原樣轉印 service payload——與直接呼叫 service 逐字相同（`entity-backlink-completeness` 執行細節 2）。
    func testJSONIsServiceResponseVerbatim() throws {
        let body = #"[{"citekey":"cheng2025alpha","fields":{"abstract":"A"},"sourceDigest":"sha256:\#(String(repeating: "cd", count: 32))"},{"doi":"10.9999/none","fields":{"abstract":"B"}}]"#
        let f = try proposals(body)
        let r = try cli(["enrich", "--from", f, "--json"])
        XCTAssertEqual(r.status, 0, r.output)
        let expected = try AkashicService(root: root, environment: env).enrich(
            proposals: try AddOnlyEnrichment.decodeProposals(from: Data(body.utf8)),
            dryRun: true, includeAbsentAuthors: false)
        XCTAssertEqual(r.output.trimmingCharacters(in: .whitespacesAndNewlines),
                       expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - 輸入錯要大聲

    /// #542 Expected 3：CLI 的來源行由 payload 現算，不得與 `provenanceWritten` 矛盾。
    /// 那一行曾逐字寫著「只記在報告，不進 store」——#517 之後為假，而沒有任何測試斷言它。三種狀態各驗一次。
    func testSourceLineAgreesWithPayload() throws {
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        let full = try proposals(#"[{"citekey":"cheng2025alpha","fields":{"abstract":"A"},"sourceDigest":"\#(digest)","sourceURL":"https://api.crossref.org/works/10.1037%2Fx","sourceRetrieved":"2026-09-09","sourceMediaType":"application/json","sourceStatus":200}]"#)
        // dry-run：什麼都沒寫，不得說「已寫入」（這支測試第一次跑就抓到它這樣說）
        let dry = try cli(["enrich", "--from", full])
        XCTAssertTrue(dry.output.contains("--apply 時會寫 1 筆 reference"), dry.output)
        XCTAssertFalse(dry.output.contains("已寫入"), dry.output)
        XCTAssertFalse(dry.output.contains("不進 store"), dry.output)
        let dryJSON = try cli(["enrich", "--from", full, "--json"])
        let dryItem = try XCTUnwrap(((try JSONSerialization.jsonObject(with: Data(dryJSON.output.utf8)) as? [String: Any])?["items"] as? [[String: Any]])?.first)
        XCTAssertNil(dryItem["provenanceWritten"], "dry-run 的 payload 不得帶 provenanceWritten：\(dryJSON.output)")
        XCTAssertEqual(dryItem["provenancePlanned"] as? [String], ["fields.abstract"], dryJSON.output)
        // 寫了：payload 與 CLI 行說同一件事
        let json = try cli(["enrich", "--from", full, "--apply", "--json"])
        XCTAssertEqual(json.status, 0, json.output)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.output.utf8)) as? [String: Any], json.output)
        let item = try XCTUnwrap((obj["items"] as? [[String: Any]])?.first, json.output)
        let written = try XCTUnwrap(item["provenanceWritten"] as? [String], "payload 要帶 provenanceWritten：\(json.output)")
        XCTAssertEqual(written.count, 1, json.output)
        XCTAssertEqual(try entry("cheng2025alpha").references.filter { $0.field == "fields.abstract" }.count, 1, "store 裡真的有那筆 reference")
        // 只有 digest：不寫，理由具名；CLI 行不得說寫了
        let digestOnly = try proposals(#"[{"citekey":"cheng2025alpha","fields":{"note":"N"},"sourceDigest":"\#(digest)"}]"#)
        let skipped = try cli(["enrich", "--from", digestOnly, "--apply"])
        XCTAssertEqual(skipped.status, 0, skipped.output)
        XCTAssertTrue(skipped.output.contains("只記在報告，不進 store——"), "要帶具名理由：\(skipped.output)")
        XCTAssertFalse(skipped.output.contains("已寫入 1 筆 reference"), skipped.output)
    }

    /// 頂層打錯位置的欄位（`abstract` 不在 `fields` 裡）→ 非零、訊息指名鍵與正確位置、磁碟不動。
    func testMalformedProposalsFileFailsLoudly() throws {
        let before = try bytes(alpha)
        let f = try proposals(#"[{"citekey":"cheng2025alpha","abstract":"misplaced"}]"#)
        let r = try cli(["enrich", "--from", f, "--apply"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("abstract") && r.output.contains("fields"), r.output)
        XCTAssertEqual(try bytes(alpha), before)
    }

    func testMissingFileFailsLoudly() throws {
        let r = try cli(["enrich", "--from", fakeHome.appendingPathComponent("nope.json").path])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("nope.json"), r.output)
    }

    // MARK: - --include-absent-authors 直通

    func testIncludeAbsentAuthorsIsPassedThrough() throws {
        let f = try proposals(#"[{"citekey":"noauthor2020x","authors":["Some One"],"fields":{"note":"n"}}]"#)
        let without = try cli(["enrich", "--from", f, "--apply"])
        XCTAssertEqual(without.status, 0, without.output)
        XCTAssertTrue(try entry("noauthor2020x").authors.isEmpty, "沒開旗標不補作者")
        XCTAssertTrue(without.output.contains("includeAbsentAuthors"), "沒補要說為什麼：\(without.output)")
        let with = try cli(["enrich", "--from", f, "--apply", "--include-absent-authors"])
        XCTAssertEqual(with.status, 0, with.output)
        XCTAssertEqual(try entry("noauthor2020x").authors, [.literal("Some One")])
    }
}
