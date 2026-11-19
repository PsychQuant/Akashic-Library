import XCTest
import Foundation

/// #781 第 2 輪 verify 第 1、3、6、9、11 列：SKILL 第 3 步的三段 bash——〈`fetch` 之後的鎖分頁〉、〈一層層按〉按了之後的落點那一段、
/// 讀頁面文字那一段——原文照跑，對一個假的 safari-browser（與假的 `akashic`）。
///
/// 斷言：鎖分頁那一段只在 `fetch` 的視窗裡、以記號或完整網址認出恰好一個分頁時才送命令，認不出來（含上一步存的網址是空的）就不送
/// （結束碼 4），Safari 不回答是結束碼 5，完整的分頁清單篩完就刪；網址只經 `jq` 與檔案，路徑裡的 `$(…)`、反引號不會被執行，印出來的只有
/// 主機。落點那一段只在左邊的分頁沒變時收下被按的位置，新分頁只在視窗的分頁變多時才算。讀頁面文字那一段印出狀態、交給 `bot-signals`
/// 的是標題、網址與頁面文字。
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

    /// SKILL 裡第一段同時含 `markers` 的 bash；行首空白去掉，20 秒換成 2 秒。
    private func block(_ markers: [String]) throws -> [String] {
        let skill = try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        let blocks = skill.components(separatedBy: "```bash\n").dropFirst().map { $0.components(separatedBy: "```").first ?? "" }
        let found = try XCTUnwrap(blocks.first { b in markers.allSatisfy { b.contains($0) } }, "SKILL 找不到含 \(markers) 的那一段")
        return found.replacingOccurrences(of: "alarm shift; exec @ARGV' 20 ", with: "alarm shift; exec @ARGV' 2 ")
            .split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    /// 鎖分頁那一段；第一行（佔位的變數）換成測試的值。
    private func lockBlock(mark: String) throws -> String {
        var lines = try block(["endswith($m)", "--rawfile u \"$D/$K.url\""])
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = "D='\(base.path)'; K='k1'; W=9005; M='\(mark)'"
        return lines.joined(separator: "\n")
    }

    /// 按了之後的落點那一段；`held: true` 是「交出去之後再接」（基準換成 `.held.json`）。
    private func afterBlock(held: Bool = false) throws -> String {
        var lines = try block(["--slurpfile b \"$B\""])
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = "D='\(base.path)'; K='k1'; W=9005; B=\"$D/$K.\(held ? "held" : "before").json\""
        return lines.joined(separator: "\n")
    }

    /// 讀頁面文字那一段；前面補上鎖分頁那一段會設的變數。
    private func textBlock() throws -> String {
        let lines = try block(["safari-browser get text --window-id \"$W\"", "bot-signals --kind"])
        return (["D='\(base.path)'; K='k1'; W=9005; t=2"] + lines.filter { !$0.hasPrefix("#") }).joined(separator: "\n")
    }

    private func row(_ window: Int, _ id: Int, _ tab: Int, _ url: String) -> [String: Any] {
        ["window": window, "window_id": id, "tab_in_window": tab, "url": url, "profile": "own",
         "blocking_dialog": ["state": "clear", "window_id": id]]
    }

    private func write(_ rows: [[String: Any]], to name: String) throws {
        try JSONSerialization.data(withJSONObject: rows).write(to: base.appendingPathComponent(name))
    }

    /// 假的 safari-browser：`documents` 印 docs.json（`hang` 時先睡）；`get title`／`get text` 照 `text-mode` 檔；其他命令只記下。
    /// 假的 `akashic`：把 stdin 寫進 bot-input、回 1（沒有命中）。回（結束碼，stdout，safari-browser 收到的命令）。
    private func run(_ script: String, docs: [[String: Any]], hang: Bool = false, textMode: String = "ok") throws -> (Int32, String, [String]) {
        try write(docs, to: "docs-answer.json")
        let log = base.appendingPathComponent("calls.log")
        try? FileManager.default.removeItem(at: log)
        let answer = base.appendingPathComponent("docs-answer.json").path
        let stub = base.appendingPathComponent("bin/safari-browser")
        try """
        #!/bin/sh
        echo "$*" >> '\(log.path)'
        case "$1 $2" in
          documents*) \(hang ? "sleep 10;" : "") cat '\(answer)' ;;
          "get title") echo 'Article Title' ;;
          "get text") case '\(textMode)' in
              hang) sleep 10 ;;
              nomatch) echo 'Error: No Safari document matches "x".' >&2; echo 'Available documents:' >&2; echo '  [1] https://secret.example/' >&2; exit 1 ;;
              empty) : ;;
              *) echo 'Body text of the page' ;;
            esac ;;
        esac
        """.write(to: stub, atomically: true, encoding: .utf8)
        let akashic = base.appendingPathComponent("bin/akashic")
        try "#!/bin/sh\ncat > '\(base.appendingPathComponent("bot-input").path)'\nexit 1\n".write(to: akashic, atomically: true, encoding: .utf8)
        for f in [stub, akashic] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script]
        p.environment = ["PATH": "\(base.appendingPathComponent("bin").path):/usr/bin:/bin:/opt/homebrew/bin"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        return (p.terminationStatus, o, calls)
    }

    private func kept(_ url: String) throws { try Data((url + "\n").utf8).write(to: base.appendingPathComponent("k1.url")) }
    private func file(_ name: String) -> String { (try? String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)) ?? "" }

    private static let mark = "akashic-0123456789abcdef"
    private static let article = "https://www.sd.example/science/article/pii/S1"

    // MARK: 鎖分頁那一段

    func testTheMarkedTabInFetchsWindowIsUsedAndOnlyItsHostIsPrinted() throws {
        try kept("stale")
        let (rc, out, calls) = try run(try lockBlock(mark: Self.mark),
                                       docs: [row(1, 9005, 1, "https://user.example/"),
                                              row(1, 9005, 2, "https://pub.example/doi/10.1/x?token=SECRET#" + Self.mark),
                                              row(2, 9006, 1, "https://pub.example/doi/10.1/x#" + Self.mark)])
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls.last, "snapshot -i --window-id 9005 --tab-in-window 2")
        XCTAssertTrue(out.contains("pub.example"), out)
        XCTAssertFalse(out.contains("SECRET"), "只印主機：\(out)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("k1.raw.json").path), "完整的清單篩完就刪")
        XCTAssertFalse(file("k1.docs.json").contains("9006"), "只留這個視窗的列：\(file("k1.docs.json"))")
    }

    func testWithoutTheMarkTheTabIsFoundByItsFullURLEvenAfterItMoved() throws {
        try kept(Self.article)
        let (rc, _, calls) = try run(try lockBlock(mark: ""), docs: [row(1, 9005, 1, "https://new.example/"), row(1, 9005, 2, "https://user.example/"),
                                                                     row(1, 9005, 3, Self.article)])
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls.last, "snapshot -i --window-id 9005 --tab-in-window 3")
    }

    func testAnUnmatchedOrDuplicatedTabSendsNothing() throws {
        for (keptURL, rows) in [(Self.article, [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, Self.article + "?other")]),
                                (Self.article, [row(1, 9005, 1, Self.article), row(1, 9005, 2, Self.article)]),
                                (Self.article, [row(2, 9006, 1, Self.article)]),
                                ("", [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "")])] {   // 空的網址不認空白分頁
            try kept(keptURL)
            let (rc, _, calls) = try run(try lockBlock(mark: ""), docs: rows)
            XCTAssertEqual(rc, 4)
            XCTAssertEqual(calls, ["documents --json"], "沒有送任何命令：\(calls)")
        }
    }

    func testAPageChosenURLIsNeverExecuted() throws {
        let canary = base.appendingPathComponent("PWNED").path
        let hostile = "https://pub.example/a$(touch \(canary))`touch \(canary)`'\"x"
        try kept(hostile)
        let (rc, _, _) = try run(try lockBlock(mark: ""), docs: [row(1, 9005, 1, hostile)])
        XCTAssertEqual(rc, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canary), "頁面的網址被 shell 執行了")
    }

    func testSafariNotAnsweringIsExit5() throws {
        try kept(Self.article)
        let (rc, _, calls) = try run(try lockBlock(mark: ""), docs: [row(1, 9005, 1, Self.article)], hang: true)
        XCTAssertEqual(rc, 5)
        XCTAssertEqual(calls, ["documents --json"])
    }

    // MARK: 按了之後的落點那一段

    private func clicked(before: [[String: Any]], position: Int = 2, keptURL: String = "https://pub.example/doi/10.1/x") throws {
        try write(before, to: "k1.before.json")
        try kept(keptURL)
        try Data("\(position)\n".utf8).write(to: base.appendingPathComponent("k1.pos"))
    }

    private var beforeRows: [[String: Any]] {
        [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/10.1/x"), row(1, 9005, 3, "https://mail.example/")]
    }

    func testAChangedURLIsTakenAndOnlyItsHostIsPrinted() throws {
        try clicked(before: beforeRows)
        let (rc, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://cdn.example/x.pdf?sig=SECRET"),
                                                            row(1, 9005, 3, "https://mail.example/")])
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("url-changed=true host=cdn.example dialog=clear new-tabs="), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        XCTAssertEqual(file("k1.url"), "https://cdn.example/x.pdf?sig=SECRET\n", "新的網址存進 .url")
    }

    func testANewTabCountsOnlyWhenTheWindowGainedOne() throws {
        try clicked(before: beforeRows)
        // 右邊使用者自己的分頁換了頁：分頁沒有變多，不是新分頁
        var (_, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/10.1/x"),
                                                           row(1, 9005, 3, "https://mail.example/inbox?id=2")])
        XCTAssertTrue(out.contains("url-changed=false") && out.hasSuffix("new-tabs=\n"), out)
        // 真的多了一個分頁
        (_, out, _) = try run(try afterBlock(), docs: beforeRows + [row(1, 9005, 4, "https://idp.uni.example/login?t=SECRET")])
        XCTAssertTrue(out.contains("new-tabs=4:idp.uni.example"), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        // 多了一個，同時右邊的分頁也換了頁：對不上就不猜
        (_, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/10.1/x"),
                                                       row(1, 9005, 3, "https://mail.example/other"), row(1, 9005, 4, "https://cdn.example/x.pdf")])
        XCTAssertTrue(out.contains("new-tabs=ambiguous"), out)
    }

    func testTabsShiftedOnTheLeftAreNotTakenForOurs() throws {
        try clicked(before: beforeRows)
        let (rc, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://new.example/")] + beforeRows.enumerated().map { i, r in
            row(1, 9005, i + 2, r["url"] as! String)
        })
        XCTAssertEqual(rc, 4)
        XCTAssertEqual(out, "moved\n")
        XCTAssertEqual(file("k1.url"), "https://pub.example/doi/10.1/x\n", "沒有收下別的分頁的網址")
    }

    /// 交出去之後再接：基準是交出去那時存的 `.held.json`；批次後面各篇的分頁開在右邊，驗證完這一篇的分頁換了網址——照位置收下。
    func testAfterAHandOverTheTabIsTakenAgainByItsPosition() throws {
        try write(beforeRows, to: "k1.held.json")
        try kept("https://pub.example/challenge?x=1")
        try Data("2\n".utf8).write(to: base.appendingPathComponent("k1.pos"))
        let (rc, out, _) = try run(try afterBlock(held: true),
                                   docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/pdf/10.1/x"),
                                          row(1, 9005, 3, "https://mail.example/"), row(1, 9005, 4, "https://other.example/doi/10.2/y")])
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("url-changed=true host=pub.example"), out)
        XCTAssertEqual(file("k1.url"), "https://pub.example/doi/pdf/10.1/x\n")
    }

    // MARK: 讀頁面文字那一段

    func testThePageTextGoesToBotSignalsWithTheTitleAndTheURL() throws {
        try kept("https://pub.example/doi/10.1/x")
        let (rc, out, calls) = try run(try textBlock(), docs: [])
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("get text rc=0"), out)
        XCTAssertTrue(out.contains("bot-signals rc=1"), out)
        XCTAssertEqual(file("bot-input"), "Article Title\n\nhttps://pub.example/doi/10.1/x\n\nBody text of the page\n")
        XCTAssertTrue(calls.contains("get text --window-id 9005 --tab-in-window 2"), "\(calls)")
    }

    func testTheGetTextStatusIsPrintedAndBranchedOn() throws {
        try kept("https://pub.example/doi/10.1/x")
        var (rc, out, _) = try run(try textBlock(), docs: [], textMode: "hang")
        XCTAssertEqual(rc, 3)
        XCTAssertTrue(out.contains("get text rc=142"), out)
        (rc, out, _) = try run(try textBlock(), docs: [], textMode: "nomatch")
        XCTAssertEqual(rc, 3)
        XCTAssertTrue(out.contains("Error: No Safari document matches"), out)
        XCTAssertFalse(out.contains("secret.example"), "只印錯誤的第一行：\(out)")
        (rc, out, _) = try run(try textBlock(), docs: [], textMode: "empty")
        XCTAssertEqual(rc, 3)
        XCTAssertTrue(out.contains("get text rc=0"), out)
    }
}
