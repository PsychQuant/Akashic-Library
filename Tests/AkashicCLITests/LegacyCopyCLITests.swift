import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #705：寫進 `entities/`、搬移後的 legacy 拷貝沒刪掉的那一筆，CLI 面記在成功那一側（`writtenWithLegacyCopy`）。
///
/// 兩條出口，各走真 binary：
/// - 直接印 service JSON 的寫入命令（`update-person`、`tag`……）：鍵進那份 JSON，stdout 仍是合法 JSON。
/// - 其餘命令：CLI 進入點（`AkashicCLI.main`）的收集範圍在命令結束後把它印在輸出末尾——命令後來失敗也照印，
///   寫進去的那一筆不跟著錯誤一起消失。
///
/// 刪不掉的造法同 #702：legacy 檔受 git 追蹤、乾淨，所在目錄唯讀。#709 起 index 重建以 `entities/` 那份為準、略過 legacy 拷貝，
/// 所以寫入之後重建 index 的命令照常成功、結束碼 0；#709 之前 work 的兩份讓重建撞 UNIQUE、以非零結束。
final class LegacyCopyCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!

    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }   // #239：hook 環境帶 GIT_DIR
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private var store: LibraryStore { LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path]) }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-705-cli-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for dir in [store.entriesDir, store.peopleDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        for dir in [store.entriesDir, store.peopleDir] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        }
        try? FileManager.default.removeItem(at: base)
    }

    private func commitAndLock(_ dir: URL) throws {
        git(["init", "-q"])
        git(["add", "-A"])
        git(["commit", "-q", "-m", "fixture"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    private func legacyWork() throws -> Entry {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                      title: "Identifiability of polychoric models", authors: [.literal("Che Cheng")], date: "2025")
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        try commitAndLock(store.entriesDir)
        return e
    }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args, env: ["AKASHIC_HOME": home.path])
    }

    /// 直接印 service JSON 的命令：鍵進 JSON、stdout 仍能整份解析、結束碼 0（person 的兩份不擋 index 重建，#670）。
    func testUpdatePersonPutsItInTheJSONItPrints() throws {
        let p = Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        try commitAndLock(store.peopleDir)

        let r = try cli(["update-person", "--library", root.path, "--key", p.key, "--fields", #"{"note":"改過"}"#])
        XCTAssertEqual(r.status, 0, r.output)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any],
                                "stdout 必須仍是一份 JSON：\(r.output)")
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], r.output)
        XCTAssertEqual(rows.first?["key"], p.key)
        XCTAssertEqual(rows.first?["legacyFile"], "people/\(p.key).yaml")
        XCTAssertEqual(rows.first?["kind"], "person")
    }

    /// #709：直接印 JSON 的命令在留下 legacy 拷貝之後照常成功——index 以 entities/ 那份為準、略過 legacy 拷貝，鍵在那份 JSON 裡、結束碼 0。
    /// #709 之前 tag 之後的 index rebuild 撞重複的 citekey，這一筆只能印在錯誤之前。
    func testTagOnALegacyWorkSucceedsWithTheKeyInItsJSON() throws {
        let e = try legacyWork()
        let r = try cli(["tag", "--library", root.path, e.citekey, "--add", "x"])
        XCTAssertEqual(r.status, 0, r.output)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any],
                                "stdout 必須仍是一份 JSON：\(r.output)")
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], r.output)
        XCTAssertEqual(rows.map { $0["key"] }, [e.citekey])
        XCTAssertEqual(rows.first?["legacyFile"], "entries/\(e.citekey).yaml")
        XCTAssertTrue(try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8).contains("- x"), "寫了")
    }

    /// 寫了之後別的步驟失敗（store 裡另有兩筆**不同**的記錄共用 citekey——#709 不替真的重複選一筆，index rebuild 照舊撞 UNIQUE）：
    /// 命令沒印出它的 JSON，收到的交給 CLI 進入點，在錯誤之前印出來——#705 R2 verify 第 19 列起印成一份只有
    /// `writtenWithLegacyCopy` 三個鍵的 JSON（stdout 仍是一份 JSON）。
    func testTagThatFailsAfterWritingStillReportsIt() throws {
        for title in ["A", "B"] {   // 兩筆不同的記錄（id 不同）共用一個 citekey
            try store.writeEntry(Entry(id: UUID(), citekey: "dup2020x", type: .periodicalArticle, title: title, date: "2020"))
        }
        let e = try legacyWork()
        let r = try runSplit(["tag", "--library", root.path, e.citekey, "--add", "x"])
        XCTAssertNotEqual(r.status, 0, "前提：index rebuild 撞兩筆不同記錄共用的 citekey：\(r.out)\(r.err)")
        XCTAssertTrue(r.err.contains("UNIQUE"), "非零的原因是 index rebuild：\(r.err)")
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any], "stdout 是一份 JSON：\(r.out)")
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], r.out)
        XCTAssertEqual(rows.map { $0["key"] }, [e.citekey])
        XCTAssertEqual(rows.first?["legacyFile"], "entries/\(e.citekey).yaml")
        let onDisk = try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("- x"), "寫了：\(onDisk)")
    }

    /// 印人可讀文字的命令：CLI 進入點的收集範圍收下它、印在輸出末尾；逐筆失敗清單（「寫入失敗」）不含這一筆。
    func testATextCommandPrintsItAtTheEnd() throws {
        let e = try legacyWork()
        let proposals = base.appendingPathComponent("p.json")
        try #"[{"citekey":"cheng2025identifiability","fields":{"abstract":"摘要"}}]"#
            .write(to: proposals, atomically: true, encoding: .utf8)
        let r = try cli(["enrich", "--library", root.path, "--from", proposals.path, "--apply"])
        XCTAssertTrue(r.output.contains("writtenWithLegacyCopy"), r.output)
        XCTAssertTrue(r.output.contains("work「\(e.citekey)」"), r.output)
        XCTAssertFalse(r.output.contains("writeFailed"), "不是寫入失敗：\(r.output)")
    }

    /// #705 R1 verify 第 4／11 列（DA 席的真 binary 重現）：`rename` 在刪舊 citekey 的 legacy 檔時以 Foundation 的原始錯誤中止，
    /// 引用它的 work 還沒改寫（同 id 兩份、引用指著舊鍵），也沒有 writtenWithLegacyCopy。現在改名做完、引用改寫、legacy 那份在報告裡。
    /// work 的兩份共用同一個 id；#709 起 index 以 entities/ 那份（新 citekey）為準、略過舊 citekey 的 legacy 拷貝，結束碼 0
    /// （#709 之前撞 `entries.uuid` PRIMARY KEY、以非零結束）。
    func testRenameFinishesAndReportsTheLegacyCopy() throws {
        var citing = Entry(id: UUID(), citekey: "yang2026citing", type: .periodicalArticle, title: "Citing", date: "2026")
        citing.akashic.relations.cites = ["cheng2025identifiability"]
        try store.writeEntry(citing)
        let e = try legacyWork()
        let r = try cli(["rename", "--library", root.path, e.citekey, "cheng2025renamed"])
        XCTAssertEqual(r.status, 0, "index 以 entities/ 那份為準，重建不再撞重複（#709）：\(r.output)")
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.hasPrefix("writtenWithLegacyCopy") }, r.output)
        XCTAssertTrue(line.hasSuffix(": 1"), String(line))
        XCTAssertTrue(r.output.contains("work「cheng2025renamed」"), r.output)
        XCTAssertTrue(r.output.contains("entries/\(e.citekey).yaml"), r.output)
        XCTAssertTrue(r.output.contains("改名前的 citekey"), r.output)
        XCTAssertTrue(r.output.contains("刪掉之前 index、匯出與 App 以 entities/ 那份為準、略過 legacy 拷貝"), "附記說的是 #709 之後的事：\(r.output)")
        XCTAssertFalse(r.output.contains("撞重複"), "index 不再撞重複（#709）：\(r.output)")
        let rewritten = try EntryYAML.decode(try String(contentsOf: store.entityURL(id: citing.id), encoding: .utf8))
        XCTAssertEqual(rewritten.akashic.relations.cites, ["cheng2025renamed"], "改名做完：引用它的 work 改寫了")
    }

    /// #709（使用者 2026-10-01）：同一筆記錄兩份並存（entities/ 一份、legacy 拷貝一份，同一個 id）時——
    /// 匯出（`export-bib`、`export-tables`）只有 entities/ 那一份；doctor 照常重建 index、結束碼 0（這一對是 warning 不是 error）；
    /// 另一筆記錄的改名照常進行。
    func testExportDoctorAndAnUnrelatedRenameUseTheEntitiesCopy() throws {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                      title: "Entities title", date: "2025")
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
        var stale = e; stale.title = "Legacy title"
        try EntryYAML.encode(stale).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                          atomically: true, encoding: .utf8)
        try store.writeEntry(Entry(id: UUID(), citekey: "yang2026other", type: .periodicalArticle, title: "Other", date: "2026"))

        let bib = try cli(["export-bib", "--library", root.path])
        XCTAssertEqual(bib.status, 0, bib.output)
        XCTAssertEqual(bib.output.components(separatedBy: "cheng2025identifiability,").count - 1, 1, "只匯出一筆：\(bib.output)")
        XCTAssertTrue(bib.output.contains("Entities title") && !bib.output.contains("Legacy title"), bib.output)

        let tablesDir = base.appendingPathComponent("tables")
        let tables = try cli(["export-tables", "--library", root.path, "--output", tablesDir.path])
        XCTAssertEqual(tables.status, 0, tables.output)
        let publications = try String(contentsOf: tablesDir.appendingPathComponent("publication.csv"), encoding: .utf8)
        XCTAssertEqual(publications.split(separator: "\n").filter { $0.contains("cheng2025identifiability") }.count, 1, publications)
        XCTAssertTrue(publications.contains("Entities title") && !publications.contains("Legacy title"), publications)

        let doctor = try cli(["doctor", "--library", root.path])
        XCTAssertEqual(doctor.status, 0, "這一對不再是 error，doctor 照常重建：\(doctor.output)")
        XCTAssertTrue(doctor.output.contains("entries: 2"), "index 裡兩筆（legacy 拷貝不算）：\(doctor.output)")
        XCTAssertTrue(doctor.output.contains("同一筆記錄的 legacy 拷貝還在"), "validate 照舊報兩份並存：\(doctor.output)")

        let rename = try cli(["rename", "--library", root.path, "yang2026other", "yang2026renamed"])
        XCTAssertEqual(rename.status, 0, "不相干的改名不再被這一對擋下：\(rename.output)")
    }

    /// `rename-person` 同形。person 的兩份不擋 index 重建（#670），所以結束碼 0、改名的報告照印，legacy 那份在輸出末尾。
    func testRenamePersonFinishesAndReportsTheLegacyCopy() throws {
        let work = Entry(id: UUID(), citekey: "yang2026work", type: .periodicalArticle, title: "W",
                         authors: [.key("yang-hau-hung")], date: "2026")
        try store.writeEntry(work)
        let p = Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        try commitAndLock(store.peopleDir)

        let r = try cli(["rename-person", "--library", root.path, p.key, "yang-h-h"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("作品的作者邊已遷移"), r.output)
        XCTAssertTrue(r.output.contains("writtenWithLegacyCopy") && r.output.contains("person「yang-h-h」"), r.output)
        XCTAssertTrue(r.output.contains("people/\(p.key).yaml"), r.output)
        let rewritten = try EntryYAML.decode(try String(contentsOf: store.entityURL(id: work.id), encoding: .utf8))
        XCTAssertEqual(rewritten.authors, [.key("yang-h-h")], "改名做完：作者邊改寫了")
    }
}

/// #705 R2 verify 第 16／19 列：失敗時 stdout 與 stderr 各自說得通。
/// - stderr 的第一行也說 stdout 上報告過的那幾筆寫了——只擷取 stderr 與結束碼的呼叫端（cron、CI）讀得到那幾筆寫了、要不要重跑；
/// - `--json` 的命令寫入後失敗時，stdout 仍是**一份** JSON（只有 `writtenWithLegacyCopy` 三個鍵），不是 JSON 之外的文字。
extension LegacyCopyCLITests {
    /// stdout 與 stderr 分開收（`CLITestHarness.run` 把兩者合在一起）。
    private func runSplit(_ args: [String]) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
        p.arguments = args
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        childEnv["AKASHIC_HOME"] = home.path
        p.environment = childEnv
        let outFile = base.appendingPathComponent("stdout-\(UUID().uuidString)")
        let errFile = base.appendingPathComponent("stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outFile.path, contents: nil)
        FileManager.default.createFile(atPath: errFile.path, contents: nil)
        let o = try FileHandle(forWritingTo: outFile), e = try FileHandle(forWritingTo: errFile)
        p.standardOutput = o; p.standardError = e
        try p.run()
        p.waitUntilExit()
        try o.close(); try e.close()
        return (p.terminationStatus, try String(contentsOf: outFile, encoding: .utf8), try String(contentsOf: errFile, encoding: .utf8))
    }

    /// 文字命令（enrich 不帶 --json）寫入後失敗：stdout 有人可讀報告，stderr 的第一行說那一筆寫了、不必為了它重跑，接著才是原本的錯誤。
    func testStderrLeadsWithTheWrittenCountWhenATextCommandFails() throws {
        for title in ["A", "B"] {   // 兩筆不同的記錄（id 不同）共用一個 citekey——#709 起寫入後的 index rebuild 只在這種真的重複上失敗
            try store.writeEntry(Entry(id: UUID(), citekey: "dup2020x", type: .periodicalArticle, title: title, date: "2020"))
        }
        let e = try legacyWork()
        let proposals = base.appendingPathComponent("p.json")
        try #"[{"citekey":"cheng2025identifiability","fields":{"abstract":"摘要"}}]"#
            .write(to: proposals, atomically: true, encoding: .utf8)
        let r = try runSplit(["enrich", "--library", root.path, "--from", proposals.path, "--apply"])
        XCTAssertNotEqual(r.status, 0, "前提：index rebuild 撞兩筆不同記錄共用的 citekey：\(r.out)\(r.err)")
        XCTAssertTrue(r.out.contains("work「\(e.citekey)」"), "報告在 stdout：\(r.out)")
        let first = String(r.err.split(separator: "\n").first ?? "")
        XCTAssertTrue(first.hasPrefix("已寫入 1 筆、搬移後的 legacy 拷貝沒刪掉"), "stderr 第一行：\(r.err)")
        XCTAssertTrue(first.contains("不必為了自己重跑"), "這一筆沒有後續被拒：\(first)")
        XCTAssertFalse(first.contains("不要重跑"), "#705 R2 verify：失敗本身可能要重跑，不說「不要重跑」：\(first)")
        XCTAssertTrue(r.err.contains("Error: "), "原本的錯誤接在後面：\(r.err)")
    }

    /// `enrich --json` 寫入後失敗：stdout 仍能整份解析成一個 JSON 物件，帶那一筆與總數；stderr 第一行同上。
    func testAFailingJSONCommandStillPrintsOneJSONDocument() throws {
        for title in ["A", "B"] {   // 兩筆不同的記錄（id 不同）共用一個 citekey——#709 起寫入後的 index rebuild 只在這種真的重複上失敗
            try store.writeEntry(Entry(id: UUID(), citekey: "dup2020x", type: .periodicalArticle, title: title, date: "2020"))
        }
        let e = try legacyWork()
        let proposals = base.appendingPathComponent("p.json")
        try #"[{"citekey":"cheng2025identifiability","fields":{"abstract":"摘要"}}]"#
            .write(to: proposals, atomically: true, encoding: .utf8)
        let r = try runSplit(["enrich", "--library", root.path, "--from", proposals.path, "--apply", "--json"])
        XCTAssertNotEqual(r.status, 0, "前提：index rebuild 撞兩筆不同記錄共用的 citekey：\(r.out)\(r.err)")
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any],
                                "stdout 必須是一份 JSON：\(r.out)")
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], r.out)
        XCTAssertEqual(rows.map { $0["key"] }, [e.citekey])
        XCTAssertEqual(obj["writtenWithLegacyCopyTotal"] as? Int, 1)
        XCTAssertEqual(obj["writtenWithLegacyCopyTruncated"] as? Bool, false, "CLI 全列")
        XCTAssertTrue(r.err.hasPrefix("已寫入 1 筆、搬移後的 legacy 拷貝沒刪掉"), "stderr 第一行：\(r.err)")
    }
}
