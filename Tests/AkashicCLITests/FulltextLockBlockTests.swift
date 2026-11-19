import XCTest
import Foundation

/// #781 第 2 輪 verify 第 3、6、11 列：SKILL 第 3 步〈`fetch` 之後的鎖分頁〉那一段 bash，原文照跑，對一個假的 safari-browser。
/// 斷言它只在 `fetch` 的視窗裡、以記號或完整網址認出恰好一個分頁時才送命令；認不出來就不送（結束碼 4）；Safari 不回答是結束碼 5；
/// 網址只經 `jq` 與檔案，路徑裡的 `$(…)`、反引號不會被執行；印出來的只有主機。
final class FulltextLockBlockTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/jq") || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/jq"),
                          "需要 jq")
        base = FileManager.default.temporaryDirectory.appendingPathComponent("lock-block-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("bin"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { if let base { try? FileManager.default.removeItem(at: base) } }

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    /// SKILL 裡帶 `--rawfile u "$D/$K.url"` 與 `endswith($m)` 的那一段 bash；第一行（佔位的變數）換成測試的值，20 秒換成 2 秒。
    private func lockBlock(mark: String) throws -> String {
        let skill = try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        let blocks = skill.components(separatedBy: "```bash\n").dropFirst().map { $0.components(separatedBy: "```").first ?? "" }
        let block = try XCTUnwrap(blocks.first { $0.contains("endswith($m)") && $0.contains("--rawfile u \"$D/$K.url\"") }, "SKILL 找不到鎖分頁那一段")
        var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = "D='\(base.path)'; K='k1'; W=9005; M='\(mark)'"
        return lines.joined(separator: "\n").replacingOccurrences(of: "alarm shift; exec @ARGV' 20 ", with: "alarm shift; exec @ARGV' 2 ")
    }

    private func row(_ window: Int, _ id: Int, _ tab: Int, _ url: String) -> [String: Any] {
        ["window": window, "window_id": id, "tab_in_window": tab, "url": url, "profile": "own",
         "blocking_dialog": ["state": "clear", "window_id": id]]
    }

    /// 回（結束碼，stdout，假 safari-browser 收到的命令）。
    private func run(rows: [[String: Any]], kept: String, mark: String = "", hang: Bool = false) throws -> (Int32, String, [String]) {
        let docs = base.appendingPathComponent("docs.json")
        try JSONSerialization.data(withJSONObject: rows).write(to: docs)
        let log = base.appendingPathComponent("calls.log")
        try? FileManager.default.removeItem(at: log)
        let stub = base.appendingPathComponent("bin/safari-browser")
        try """
        #!/bin/sh
        echo "$*" >> '\(log.path)'
        case "$1" in documents) \(hang ? "sleep 10;" : "") cat '\(docs.path)' ;; *) : ;; esac
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        try Data((kept + "\n").utf8).write(to: base.appendingPathComponent("k1.url"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", try lockBlock(mark: mark)]
        p.environment = ["PATH": "\(base.appendingPathComponent("bin").path):/usr/bin:/bin:/opt/homebrew/bin"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        return (p.terminationStatus, o, calls)
    }

    private static let mark = "akashic-0123456789abcdef"
    private static let article = "https://www.sd.example/science/article/pii/S1"

    func testTheMarkedTabInFetchsWindowIsUsedAndOnlyItsHostIsPrinted() throws {
        let (rc, out, calls) = try run(rows: [row(1, 9005, 1, "https://user.example/"),
                                              row(1, 9005, 2, "https://pub.example/doi/10.1/x?token=SECRET#" + Self.mark),
                                              row(2, 9006, 1, "https://pub.example/doi/10.1/x#" + Self.mark)],
                                       kept: "stale", mark: Self.mark)
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls.last, "snapshot -i --window-id 9005 --tab-in-window 2")
        XCTAssertTrue(out.contains("pub.example"), out)
        XCTAssertFalse(out.contains("SECRET"), "只印主機：\(out)")
    }

    func testWithoutTheMarkTheTabIsFoundByItsFullURLEvenAfterItMoved() throws {
        let (rc, _, calls) = try run(rows: [row(1, 9005, 1, "https://new.example/"), row(1, 9005, 2, "https://user.example/"),
                                            row(1, 9005, 3, Self.article)], kept: Self.article)
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls.last, "snapshot -i --window-id 9005 --tab-in-window 3")
    }

    func testAnUnmatchedOrDuplicatedTabSendsNothing() throws {
        for rows in [[row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, Self.article + "?other")],
                     [row(1, 9005, 1, Self.article), row(1, 9005, 2, Self.article)],
                     [row(2, 9006, 1, Self.article)]] {
            let (rc, _, calls) = try run(rows: rows, kept: Self.article)
            XCTAssertEqual(rc, 4)
            XCTAssertEqual(calls, ["documents --json"], "沒有送任何命令：\(calls)")
        }
    }

    func testAPageChosenURLIsNeverExecuted() throws {
        let canary = base.appendingPathComponent("PWNED").path
        let hostile = "https://pub.example/a$(touch \(canary))`touch \(canary)`'\"x"
        let (rc, _, _) = try run(rows: [row(1, 9005, 1, hostile)], kept: hostile)
        XCTAssertEqual(rc, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canary), "頁面的網址被 shell 執行了")
    }

    func testSafariNotAnsweringIsExit5() throws {
        let (rc, _, calls) = try run(rows: [row(1, 9005, 1, Self.article)], kept: Self.article, hang: true)
        XCTAssertEqual(rc, 5)
        XCTAssertEqual(calls, ["documents --json"])
    }
}
