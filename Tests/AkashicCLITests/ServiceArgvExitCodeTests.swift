import XCTest
import Foundation

/// #654（#549 的餘項 2）：服務層（與 store 層）做的 argv 檢查，在 CLI 是用法錯誤。
///
/// 先前 CLI 呼叫 `AkashicService` 時，服務丟的 `ServiceError` 一律變成 exit 1——其中有些只看參數（key 的格式、id 的形狀、理由空白、
/// 同一批重複、一次的上限、digest 的形狀）。現在服務把它們暴露成不碰 store 的 static 函式，CLI 的 `validate()` 呼叫同一個函式：
/// exit 64、印子命令 usage、而且早於開 store——所以這裡全部指向一個**沒有佈局**的目錄，缺佈局不得搶先報執行期失敗。
///
/// 走真 binary（exit code 與 usage 是頂層出口的行為）。每一格斷言服務的原句（同一份描述，不是 CLI 另寫一句）。
final class ServiceArgvExitCodeTests: XCTestCase {
    private var tmp: URL!
    private var bare: URL!
    private let emptyDigest = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-svc-argv-\(UUID().uuidString)")
        bare = tmp.appendingPathComponent("not-a-store")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func run(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", bare.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
    }

    /// (argv, 服務的原句片段)。usage 行取 argv 的子命令路徑。
    private func assertUsageError(_ args: [String], _ needle: String, usage: String? = nil,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let r = try run(args)
        XCTAssertEqual(r.status, 64, "\(args)：\(r.output)", file: file, line: line)
        XCTAssertTrue(r.output.contains(needle), "\(args) 要說出服務的原句「\(needle)」：\(r.output)", file: file, line: line)
        XCTAssertFalse(r.output.contains("不是 Akashic library"), "argv 錯誤不得被缺佈局搶先——\(args)：\(r.output)", file: file, line: line)
        XCTAssertTrue(r.output.contains("Usage: akashic \(usage ?? args[0])"), "\(args)：\(r.output)", file: file, line: line)
    }

    func testEntryEditArgvChecks() throws {
        try assertUsageError(["set-status", "a2020b"], "要嘛給 status，要嘛給 clear")
        try assertUsageError(["set-status", "a2020b", "read", "--clear"], "status 與 clear 互斥")
        try assertUsageError(["tag", "a2020b"], "add 與 remove 至少要給一個")
        try assertUsageError(["link", "a2020b", "--kind", "nope", "--add", "b2020c"], "kind 必須是 cites / related")
        try assertUsageError(["link", "a2020b", "--kind", "cites"], "--add 與 --remove 至少要給一個")
    }

    func testLookupArgvChecks() throws {
        try assertUsageError(["person"], "person 需要 key 或 name 至少其一")
        try assertUsageError(["person", "  "], "key 不可為空白")
        try assertUsageError(["person", "--name", " "], "name 不可為空白")
        try assertUsageError(["person", "p-one", "--name", "P"], "key 與 name 互斥")
        try assertUsageError(["person", "--name", "P", "--in-library", "lib"], "--in-library 只在 key 模式有效")
        try assertUsageError(["venue", " "], "key 不可為空白")
    }

    func testRecordCreationArgvChecks() throws {
        let file = tmp.appendingPathComponent("x.txt")
        try "bytes".write(to: file, atomically: true, encoding: .utf8)
        try assertUsageError(["store-source", file.path, "--media-type", " ", "--retrieved", "2026-09-28",
                              "--origin", "o", "--acquisition", "file"], "mediaType 不可為空")
        try assertUsageError(["add-person", "Bad Key", "--name", "X"], "不符合")
        try assertUsageError(["add-person", "p-one", "--name", "X", "--orcid", "0000-0000"], "不是合法的 ORCID")
        try assertUsageError(["add-venue", "Bad Key", "--names", "X", "--type", "periodical"], "不符合")
        try assertUsageError(["add-venue", "v-one", "--names", "X", "--type", "nope"], "不在封閉列舉")
        try assertUsageError(["add-venue", "v-one", "--names", "  ", "--type", "periodical"], "names 全是空白")
        try assertUsageError(["add-venue", "v-one", "--names", "X", "--type", "periodical", "--issn", "1234"], "不是合法的 ISSN")
        try assertUsageError(["update-person", "--key", "p-one", "--fields", #"{"bogus": 1}"#], "不認得的欄位")
        try assertUsageError(["update-person", "--key", "p-one", "--fields", #"{"orcid": "nope"}"#], "不是合法的 ORCID")
    }

    /// #544：`update-entry` 只看參數的檢查（服務的同一個函式）。
    func testUpdateEntryArgvChecks() throws {
        try assertUsageError(["update-entry", "a2020b"], "沒有要做的事")
        try assertUsageError(["update-entry", "a2020b", "--remove-field", "abstract"], "缺少 `=`")
        try assertUsageError(["update-entry", "a2020b", "--remove-field", "abstract= "], "的理由是空白")
        try assertUsageError(["update-entry", "a2020b", "--remove-field", "abstract=a", "abstract=b"], "出現兩次")
    }

    func testUpdateVenueArgvChecks() throws {
        try assertUsageError(["update-venue", "v-one", "--remove-issn", "0378-5955"], "缺少 `=`")
        try assertUsageError(["update-venue", "v-one", "--remove-issn", "0378-5955= "], "的理由是空白")
        try assertUsageError(["update-venue", "v-one", "--type", "nope"], "不在封閉列舉")
        try assertUsageError(["update-venue", "v-one", "--add-issn", "1234"], "不是合法的 ISSN")
        try assertUsageError(["update-venue", "v-one", "--paginated", "true"], "設 paginated 必附 judgement")
        try assertUsageError(["update-venue", "v-one", "--judgement", "j"], "只伴隨 paginated 或 clear_paginated")
        try assertUsageError(["update-venue", "v-one", "--authorize", "Alpha", "--add-variant", "Alpha"], "兩句矛盾的話")
        // 兩個餘項的交會：空內容的 digest 在 rests-on 被拒，而那也是只看參數的檢查
        try assertUsageError(["update-venue", "v-one", "--paginated", "true", "--judgement", "j", "--rests-on", emptyDigest], "0 byte")
    }

    func testRecordDivergenceArgvChecks() throws {
        let base = ["record-divergence", "--question", "q"]
        try assertUsageError(base + ["--candidate", "p-a:person"], "需要兩個以上的候選")
        try assertUsageError(base + ["--candidate", "p-a:bogus", "p-b:person"], "候選格式為 `key:shape`")
        try assertUsageError(base + ["--candidate", "p-a:person", "p-b:person", "--judgement", "j"], "判斷與依據必須成對")
        try assertUsageError(base + ["--candidate", "p-a:person", "p-b:person", "--judgement", "j", "--rests-on", digest,
                                     "--prefers", "p-c"], "不是本次的候選之一")
        try assertUsageError(base + ["--candidate", "p-a:person", "p-b:person", "--judgement", "j", "--rests-on", emptyDigest], "0 byte")
    }

    func testResolveLegArgvChecks() throws {
        try assertUsageError(["resolve-people", "--judge", "a2020b:0:p-one"], "缺少 `=`")
        try assertUsageError(["resolve-people", "--refute", "a2020b:p-one=r"], "不是三段形")
        try assertUsageError(["resolve-people", "--undecided", "a2020b:0:p-one= "], "的說明是空白")
        try assertUsageError(["resolve-people", "--undecided", "a2020b:0:p-one=查過", "--rests-on", emptyDigest], "0 byte")
        try assertUsageError(["resolve-people", "--split-author", "a2020b:0:與"], "缺少 `=`")
        try assertUsageError(["resolve-people", "--un-split", "nocolon"], "缺少 `:`")
        try assertUsageError(["resolve-people", "--drop-author", "a2020b:X"], "缺少 `=`")
        try assertUsageError(["resolve-people", "--attribute-org", "a2020b:x:org=r"], "不是三段形")
        try assertUsageError(["resolve-venues", "--repoint", "a2020b:0"], "不是 citekey:venueIndex:newKey 形")
        try assertUsageError(["resolve-venues", "--demote", "a2020b"], "不是 citekey:venueIndex 形")
        try assertUsageError(["resolve-venues", "--drop-venue", "a2020b:0"], "理由必填")
        try assertUsageError(["resolve-venues", "--undecided", "a2020b:0:v-one=x", "--rests-on", "md5:x"], "rests_on 不合法")
        let many = (0...200).map { "row\($0)@org=x" }
        try assertUsageError(["resolve-organizations", "--undecided"] + many, "一次最多記 200 筆未決")
        try assertUsageError(["resolve-organizations", "--judge"] + many, "一次最多判定 200 筆")
        // 每一筆 id 要在這次列表上切（要讀 store），但連一個 `@<orgKey>=` 位置都沒有的，與列表無關
        try assertUsageError(["resolve-organizations", "--judge", "no-cut-position=理由"], "的格式（orgKey 是小寫英數與連字號）")
        try assertUsageError(["resolve-organizations", "--undecided", "row@Org=x"], "的格式（orgKey 是小寫英數與連字號）")
        try assertUsageError(["resolve-organizations", "--undecided", "row@org=x", "--rests-on", emptyDigest], "0 byte")
    }

    /// 目標確認閘要解析 registry（讀 config），解析失敗是執行期（1）。只看 argv 的用法錯誤不得排在它之後：
    /// 這裡把 config 弄壞讓閘必然失敗，看用法錯誤是不是先出來（#654——inventory 指出這三處先前排在閘之後）。
    func testUsageErrorsPrecedeTheTargetGate() throws {
        try "files:\n  Not A Key: /nowhere\n".write(to: tmp.appendingPathComponent("config.yaml"),
                                                   atomically: true, encoding: .utf8)
        // 對照：同一份壞 config 下，argv 合法時閘確實失敗——否則下面三格證不到先後
        let control = try run(["resolve-people", "--apply"])
        XCTAssertEqual(control.status, 1, control.output)
        XCTAssertTrue(control.output.contains("files key"), "閘要因為壞 config 失敗：\(control.output)")
        try assertUsageError(["resolve-people", "--apply", "--reject", "a2020b:0"], "--apply 與 --reject 不可同用")
        try assertUsageError(["bootstrap-people", "--json", "--apply"], "--json 是唯讀輸出，不與 --apply 併用")
        try assertUsageError(["enrich-from-zotero", "--citekeys", " , ", "--apply"], "--citekeys 不得為空")
    }

    /// 對照組：同樣的命令，argv 合法時仍走到開 store，缺佈局是執行期失敗（1、不印 usage）——`validate()` 沒有多擋。
    func testValidArgvStillReachesTheStore() throws {
        let cases: [[String]] = [
            ["set-status", "a2020b", "read"],
            ["tag", "a2020b", "--add", "t"],
            ["link", "a2020b", "--kind", "cites", "--add", "b2020c"],
            ["person", "p-one"],
            ["venue", "v-one"],
            ["add-person", "p-one", "--name", "X"],
            ["add-venue", "v-one", "--names", "X", "--type", "periodical"],
            ["update-venue", "v-one", "--add-name", "X"],
            ["update-person", "--key", "p-one", "--fields", #"{"note": "n"}"#],
            ["record-divergence", "--question", "q", "--candidate", "p-a:person", "p-b:person"],
            ["resolve-people", "--judge", "a2020b:0:p-one=理由"],
            ["resolve-venues", "--repoint", "a2020b:0:v-one"],
            ["resolve-organizations", "--judge", "row@org=理由"],
        ]
        for args in cases {
            let r = try run(args)
            XCTAssertEqual(r.status, 1, "\(args)：\(r.output)")
            XCTAssertTrue(r.output.contains("不是 Akashic library"), "\(args)：\(r.output)")
            XCTAssertFalse(r.output.contains("Usage:"), "執行期失敗不印 usage——\(args)：\(r.output)")
        }
    }
}
