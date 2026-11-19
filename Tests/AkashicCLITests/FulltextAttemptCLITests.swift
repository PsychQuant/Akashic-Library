import XCTest
import Foundation

/// #781／#780：`akashic fulltext attempt`——skill 在出版商頁面上每按一下之前記一次，與 `fetch` 共用同一本每日嘗試帳本。
/// 真 binary；**每一個呼叫都帶 `--ledger` 指到暫存路徑**（不帶就會寫進使用者真的帳本、用掉今天的額度）。
final class FulltextAttemptCLITests: XCTestCase {
    private var base: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-attempt-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private var env: [String: String] { ["AKASHIC_HOME": home.appendingPathComponent(".akashic-home").path, "HOME": home.path] }
    private var ledger: String { base.appendingPathComponent("ledger.jsonl").path }

    private func run(_ args: [String]) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
        p.arguments = args
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        for (k, v) in env { childEnv[k] = v }
        p.environment = childEnv
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    private func attempt(site: String, landing: String = "https://doi.org/10.1/x") throws -> (status: Int32, out: String, err: String) {
        try run(["fulltext", "attempt", "--site", site, "--landing", landing, "--ledger", ledger])
    }

    private func ledgerLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: ledger) else { return [] }
        return try String(contentsOfFile: ledger, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    /// 今天（Asia/Taipei）的 `n` 筆，直接寫進帳本。
    private func seed(_ n: Int, site: String) throws {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Taipei")!; f.formatOptions = [.withInternetDateTime]
        let line = "{\"at\":\"\(f.string(from: Date()))\",\"landing\":\"https://doi.org/10.1/y\",\"site\":\"\(site)\"}\n"
        try Data(String(repeating: line, count: n).utf8).write(to: URL(fileURLWithPath: ledger))
    }

    // spec-example: fulltext-attempt-accounting / First attempt of the day is recorded
    func testTheFirstAttemptOfTheDayIsRecorded() throws {
        let r = try attempt(site: "journals.example")
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.hasPrefix("attempt: journals.example 1/10 "), r.out)
        let lines = try ledgerLines()
        XCTAssertEqual(lines.count, 1, "\(lines)")
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(lines.first).utf8)) as? [String: Any])
        XCTAssertEqual(record["site"] as? String, "journals.example")
        XCTAssertEqual(record["landing"] as? String, "https://doi.org/10.1/x")
        XCTAssertTrue(r.err.contains("--ledger is for tests"), "換了帳本要警告：\(r.err)")
    }

    // spec-example: fulltext-attempt-accounting / Host case does not split the count
    func testHostCaseDoesNotSplitTheCount() throws {
        try seed(1, site: "journals.example")
        let r = try attempt(site: "Journals.EXAMPLE")
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.hasPrefix("attempt: journals.example 2/10 "), r.out)
    }

    // spec-example: fulltext-attempt-accounting / Eleventh attempt is refused
    func testTheEleventhAttemptIsRefused() throws {
        try seed(10, site: "journals.example")
        let r = try attempt(site: "journals.example")
        XCTAssertEqual(r.status, 9, r.out + r.err)
        XCTAssertTrue(r.out.hasPrefix("cap: journals.example 10/10 "), r.out)
        XCTAssertEqual(try ledgerLines().count, 10, "到上限不記")
        // 別的站不受影響
        let other = try attempt(site: "other.example")
        XCTAssertEqual(other.status, 0, other.err)
        XCTAssertTrue(other.out.hasPrefix("attempt: other.example 1/10 "), other.out)
    }

    /// 一個只夠走到記錄嘗試那一步的假 safari-browser（與 `SkillToolsCLITests.writeRaceStub` 同一個形狀）：文章頁在 `pub.example`、頁面有自己的 PDF 連結。
    private func writeStubBrowser() throws -> URL {
        let state = base.appendingPathComponent("stub-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let stub = base.appendingPathComponent("stub-safari")
        let script = """
        #!/bin/sh
        S='\(state.path)'
        case "$1" in
          documents)
            d='"window_id":9005,"blocking_dialog":{"state":"unknown","window_id":9005}'
            mine='{"window":5,"index":1,"tab_in_window":1,"url":"https://user.example/","title":"mine","profile":"own",'"$d"'}'
            if [ ! -f "$S/opened" ]; then printf '[%s]\\n' "$mine"; exit 0; fi
            m=$(cat "$S/opened")
            if [ -f "$S/navigated" ]; then u="https://pub.example/doi/pdf/10.1/x#$m"; else u="https://pub.example/doi/10.1/x#$m"; fi
            printf '[%s,{"window":5,"index":2,"tab_in_window":2,"url":"%s","title":"Article","profile":"own",%s}]\\n' "$mine" "$u" "$d" ;;
          open) for a; do last=$a; done
            case " $* " in *" --new-tab "*) printf '%s' "${last#*#}" > "$S/opened" ;;
              *" --profile "*|*" --tab-in-window "*|*" --window "*|*" --window-id "*|*" --url "*) : > "$S/navigated" ;; esac ;;
          js)
            for a; do last=$a; done
            case "$last" in
              *innerText.slice*) printf '\\nArticle\\nBody text\\n' ;;
              *document.contentType*) printf 'text/html\\ncomplete\\n' ;;
              *citation_pdf_url*) echo 'GET https://pub.example/doi/pdf/10.1/x' ;;
              *document.readyState*) echo complete ;;
            esac ;;
          wait) : ;;
          close) : ;;
        esac
        exit 0
        """
        try script.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        return stub
    }

    // spec-example: fulltext-attempt-accounting / Attempts and fetch share one count
    func testAttemptsAndFetchShareOneCount() throws {
        for n in 1...10 {
            let r = try attempt(site: "pub.example")
            XCTAssertEqual(r.status, 0, "第 \(n) 次：\(r.err)")
            XCTAssertTrue(r.out.hasPrefix("attempt: pub.example \(n)/10 "), r.out)
        }
        let stub = try writeStubBrowser()
        let f = try run(["fulltext", "fetch", "--window", "5", "--expect-profile", "own", "--landing", "https://doi.org/10.1/x",
                         "--ledger", ledger, "--bin", stub.path])
        XCTAssertEqual(f.status, 9, f.err + f.out)
        XCTAssertTrue(f.err.contains("DAILY CAP"), f.err)
        XCTAssertEqual(try ledgerLines().count, 10, "fetch 到上限不記")
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("stub-state/navigated").path), "沒有導航到 PDF")
    }

    // spec-example: fulltext-attempt-accounting / Malformed sites are refused before the ledger is touched
    func testMalformedSitesAreRefusedBeforeTheLedgerIsTouched() throws {
        for site in ["https://journals.example", "journals.example:8443", "user@journals.example", "journals.example/doi/x",
                     "journals%2Eexample", "journals example", ""] {
            let r = try attempt(site: site)
            XCTAssertEqual(r.status, 64, "\(site)：\(r.out)\(r.err)")
            XCTAssertTrue(r.err.contains("--site 必須是"), "要是 --site 的形狀錯誤，不是別的用法錯誤：\(r.err)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: ledger), "\(site)：帳本不該被建立")
        }
        for landing in ["http://doi.org/10.1/x", "doi.org/10.1/x", ""] {
            let r = try attempt(site: "journals.example", landing: landing)
            XCTAssertEqual(r.status, 64, "\(landing)：\(r.out)\(r.err)")
            XCTAssertTrue(r.err.contains("--landing 必須是"), "要是 --landing 的形狀錯誤：\(r.err)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: ledger), "\(landing)：帳本不該被建立")
        }
    }

    // spec-example: fulltext-attempt-accounting / A garbage line stops the command
    func testAGarbageLineStopsTheCommand() throws {
        try Data("not json\n".utf8).write(to: URL(fileURLWithPath: ledger))
        let r = try attempt(site: "journals.example")
        XCTAssertEqual(r.status, 1, r.out + r.err)
        XCTAssertEqual(r.out, "", "沒有記到就不印 attempt:")
        XCTAssertTrue(r.err.contains("attempt ledger"), "原因印在 stderr：\(r.err)")
        XCTAssertTrue(r.err.contains("nothing was recorded"), r.err)
        XCTAssertEqual(try String(contentsOfFile: ledger, encoding: .utf8), "not json\n")
    }
}
