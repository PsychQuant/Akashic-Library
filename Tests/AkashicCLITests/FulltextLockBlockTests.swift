import XCTest
import Foundation

/// #781 第 2 輪 verify 第 1、3、6、9、11 列，第 3 輪第 1–8、10、17、18 列：SKILL 第 3 步的三段 bash——〈`fetch` 之後的鎖分頁〉、〈一層層按〉按了之後的落點那一段、
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

    /// SKILL 裡第一段同時含 `markers` 的 bash，找不到就是 nil（不記失敗）。
    private func optionalBlock(_ markers: [String]) throws -> [String]? {
        let skill = try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        let blocks = skill.components(separatedBy: "```bash\n").dropFirst().map { $0.components(separatedBy: "```").first ?? "" }
        guard let found = blocks.first(where: { b in markers.allSatisfy { b.contains($0) } }) else { return nil }
        return found.replacingOccurrences(of: "alarm shift; exec @ARGV' 20 ", with: "alarm shift; exec @ARGV' 2 ")
            .split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    /// 變數那一行：`profile` 是 `fetch` 的 `window <N> profile:` 一行印的（空的就是沒有讀到）。`M` 也給：24cda776 的鎖分頁那一段從
    /// 第一行讀記號，現在的從 `.mark` 讀，多給的變數不影響。
    private func vars(profile: String = "own", mark: String = "", extra: String = "") -> String {
        "D='\(base.path)'; K='k1'; W=9005; P='\(profile)'; M='\(mark)'\(extra)"
    }

    /// 鎖分頁那一段；第一行（佔位的變數）換成測試的值。記號寫進 `.mark`（起點那一段寫的檔）。
    private func lockBlock(mark: String = "", profile: String = "own") throws -> String {
        var lines = try block(["--rawfile u \"$D/$K.url\"", "對不到分頁"])
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = vars(profile: profile, mark: mark)
        try Data((mark + "\n").utf8).write(to: base.appendingPathComponent("k1.mark"))
        return lines.joined(separator: "\n")
    }

    /// 起點那一段：`T` 是 `handover:` 一行的分頁位置。
    private func startBlock(position: Int, mark: String, profile: String = "own") throws -> String {
        var lines = try block(["read -r t by"])
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = vars(profile: profile, mark: mark, extra: "; T=\(position)")
        return lines.joined(separator: "\n")
    }

    /// 按了之後的落點那一段；`held: true` 是「交出去之後再接」（基準換成 `.held.json`）。
    private func afterBlock(held: Bool = false, profile: String = "own") throws -> String {
        var lines = try block(["--slurpfile b \"$B\""])
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = vars(profile: profile, extra: "; B=\"$D/$K.\(held ? "held" : "before").json\"")
        return lines.joined(separator: "\n")
    }

    /// 讀頁面文字那一段；前面補上鎖分頁那一段會設的變數。
    private func textBlock() throws -> String {
        let lines = try block(["get text", "bot-signals --kind"])
        return (["D='\(base.path)'; K='k1'; W=9005; t=2; PF=(--profile own)"] + lines.filter { !$0.hasPrefix("#") }).joined(separator: "\n")
    }

    private func row(_ window: Int, _ id: Int, _ tab: Int, _ url: String, dialog: String = "clear", messages: [String] = []) -> [String: Any] {
        ["window": window, "window_id": id, "tab_in_window": tab, "url": url, "profile": "own",
         "blocking_dialog": ["state": dialog, "window_id": id, "messages": messages]]
    }

    private func write(_ rows: [[String: Any]], to name: String) throws {
        try JSONSerialization.data(withJSONObject: rows).write(to: base.appendingPathComponent(name))
    }

    /// 假的 safari-browser：`documents` 印 docs.json（`hang` 時先睡）；`get title`／`get text` 照 `titleMode`／`textMode`；其他命令只記下。
    /// 假的 `akashic`：把 stdin 寫進 bot-input、回 1（沒有命中）。回（結束碼，stdout＋stderr 以外的 stdout，safari-browser 收到的命令）。
    private func run(_ script: String, docs: [[String: Any]], hang: Bool = false, textMode: String = "ok", titleMode: String = "ok",
                     shell: String = "/bin/bash") throws -> (Int32, String, [String]) {
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
          "get title") case '\(titleMode)' in
              fail) echo 'Error: The tab is not running scripts' >&2; exit 1 ;;
              *) echo 'Article Title' ;;
            esac ;;
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
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = shell.hasSuffix("zsh") ? ["-f", "-c", script] : ["-c", script]
        p.environment = ["PATH": "\(base.appendingPathComponent("bin").path):/usr/bin:/bin:/opt/homebrew/bin"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let calls = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        return (p.terminationStatus, o, calls)
    }

    private func kept(_ url: String) throws { try Data((url + "\n").utf8).write(to: base.appendingPathComponent("k1.url")) }
    private func file(_ name: String) -> String { (try? String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: base.appendingPathComponent(name).path) }

    private static let mark = "akashic-0123456789abcdef"
    private static let article = "https://www.sd.example/science/article/pii/S1"
    private static let documents = "documents --json --profile own"

    // MARK: 鎖分頁那一段

    func testTheMarkedTabInFetchsWindowIsUsedAndOnlyItsHostIsPrinted() throws {
        try kept("stale")
        let (rc, out, calls) = try run(try lockBlock(mark: Self.mark),
                                       docs: [row(1, 9005, 1, "https://user.example/"),
                                              row(1, 9005, 2, "https://pub.example/doi/10.1/x?token=SECRET#" + Self.mark),
                                              row(2, 9006, 1, "https://pub.example/doi/10.1/x#" + Self.mark)])
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls.first, Self.documents, "fetch 印了 profile：documents 帶 --profile")
        XCTAssertEqual(calls.last, "snapshot -i --profile own --window-id 9005 --tab-in-window 2")
        XCTAssertTrue(out.contains("pub.example"), out)
        XCTAssertFalse(out.contains("SECRET"), "只印主機：\(out)")
        XCTAssertFalse(exists("k1.raw.json"), "完整的清單篩完就刪")
        XCTAssertFalse(file("k1.docs.json").contains("9006"), "只留這個視窗的列：\(file("k1.docs.json"))")
    }

    func testWithoutTheMarkTheTabIsFoundByItsFullURLEvenAfterItMoved() throws {
        try kept(Self.article)
        let (rc, _, calls) = try run(try lockBlock(), docs: [row(1, 9005, 1, "https://new.example/"), row(1, 9005, 2, "https://user.example/"),
                                                             row(1, 9005, 3, Self.article)])
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls.last, "snapshot -i --profile own --window-id 9005 --tab-in-window 3")
    }

    /// `fetch` 讀不出視窗的 profile（`(none read)`）時沒有 `--profile` 可帶：清單不以 profile 篩，仍只留這個視窗的列。
    func testWithoutAProfileTheListIsFilteredByTheWindowOnly() throws {
        try kept(Self.article)
        let (rc, _, calls) = try run(try lockBlock(profile: ""), docs: [row(1, 9005, 1, Self.article), row(2, 9006, 1, "https://other.example/")])
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls, ["documents --json", "snapshot -i --window-id 9005 --tab-in-window 1"])
        XCTAssertFalse(file("k1.docs.json").contains("9006"))
    }

    func testAnUnmatchedOrDuplicatedTabSendsNothing() throws {
        for (keptURL, rows) in [(Self.article, [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, Self.article + "?other")]),
                                (Self.article, [row(1, 9005, 1, Self.article), row(1, 9005, 2, Self.article)]),
                                (Self.article, [row(2, 9006, 1, Self.article)]),
                                ("", [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "")])] {   // 空的網址不認空白分頁
            try kept(keptURL)
            let (rc, _, calls) = try run(try lockBlock(), docs: rows)
            XCTAssertEqual(rc, 4)
            XCTAssertEqual(calls, [Self.documents], "沒有送任何命令：\(calls)")
        }
    }

    // spec-example: fulltext-division-of-labour / A lock miss after a click is not the end of the article
    func testALockMissAfterAClickIsNotTheEndOfTheArticle() throws {
        try kept(Self.article)
        let rows = [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/redirected")]
        var (rc, _, calls) = try run(try lockBlock(), docs: rows)
        XCTAssertEqual(rc, 4, "這一篇還沒按過：取不到")
        XCTAssertEqual(calls, [Self.documents])
        try Data().write(to: base.appendingPathComponent("k1.clicked"))   // 第 4 步按的時候留下的
        (rc, _, calls) = try run(try lockBlock(), docs: rows)
        XCTAssertEqual(rc, 2, "按過之後對不到：等一次、重取、再判，不是取不到")
        XCTAssertEqual(calls, [Self.documents])
    }

    func testAPageChosenURLIsNeverExecuted() throws {
        let canary = base.appendingPathComponent("PWNED").path
        let hostile = "https://pub.example/a$(touch \(canary))`touch \(canary)`'\"x"
        try kept(hostile)
        let (rc, _, _) = try run(try lockBlock(), docs: [row(1, 9005, 1, hostile)])
        XCTAssertEqual(rc, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canary), "頁面的網址被 shell 執行了")
    }

    func testSafariNotAnsweringIsExit5() throws {
        try kept(Self.article)
        let (rc, _, calls) = try run(try lockBlock(), docs: [row(1, 9005, 1, Self.article)], hang: true)
        XCTAssertEqual(rc, 5)
        XCTAssertEqual(calls, [Self.documents])
    }

    // spec-example: fulltext-division-of-labour / Only the host is printed
    func testOnlyTheHostIsPrinted() throws {
        for (url, host) in [("https://alice:s3cret@pub.example/x?token=SECRET", "pub.example"), ("blob:https://pub.example/2f1c-SECRET", "(blob)"),
                            ("data:text/html,<h1>SECRET</h1>", "(data)")] {
            try kept(url)
            let (rc, out, _) = try run(try lockBlock(), docs: [row(1, 9005, 1, url)])
            XCTAssertEqual(rc, 0, url)
            XCTAssertTrue(out.contains(host), "\(url) → \(out)")
            for leak in ["alice", "s3cret", "SECRET"] { XCTAssertFalse(out.contains(leak), "\(url) → \(out)") }
        }
        try clicked(before: beforeRows)
        let (_, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://alice:s3cret@cdn.example/x.pdf"),
                                                           row(1, 9005, 3, "https://mail.example/")])
        XCTAssertTrue(out.contains("host=cdn.example "), out)
        XCTAssertFalse(out.contains("alice") || out.contains("s3cret"), out)
    }

    /// 鎖分頁那一段在 zsh（Claude Code 的 Bash 工具在這台機器跑 zsh）也一樣：`"${PF[@]}"` 的陣列與 `read`。
    func testTheBlocksRunTheSameUnderZsh() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/bin/zsh"), "需要 zsh")
        try kept(Self.article)
        var (rc, _, calls) = try run(try lockBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, Self.article)], shell: "/bin/zsh")
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls, [Self.documents, "snapshot -i --profile own --window-id 9005 --tab-in-window 2"])
        (rc, _, calls) = try run(try lockBlock(profile: ""), docs: [row(1, 9005, 1, Self.article)], shell: "/bin/zsh")
        XCTAssertEqual(calls, ["documents --json", "snapshot -i --window-id 9005 --tab-in-window 1"])
        (rc, _, _) = try run(try startBlock(position: 2, mark: ""), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, Self.article)],
                             shell: "/bin/zsh")
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(file("k1.pos"), "2\n")
    }

    // MARK: 起點那一段

    // spec-example: fulltext-division-of-labour / The start finds the tab by the mark and then by position
    func testTheStartFindsTheTabByTheMarkAndThenByPosition() throws {
        let rows = [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, Self.article + "#" + Self.mark), row(1, 9005, 3, "https://mail.example/")]
        var (rc, out, calls) = try run(try startBlock(position: 3, mark: Self.mark), docs: rows)
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("by=mark") && out.contains("host=www.sd.example"), out)
        XCTAssertEqual(calls, [Self.documents], "起點只讀清單，不送別的命令")
        XCTAssertEqual(file("k1.pos"), "2\n")
        XCTAssertEqual(file("k1.mark"), Self.mark + "\n")
        XCTAssertTrue(exists("k1.before.json"), "按之前的基準（tab-unchanged 也要它）")
        // Elsevier：記號已經不在，照 handover: 的位置
        let lost = [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pdf.cdn.example/x.pdf?sig=SECRET")]
        (rc, out, calls) = try run(try startBlock(position: 2, mark: Self.mark), docs: lost)
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("by=position") && out.contains("host=pdf.cdn.example"), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        XCTAssertEqual(file("k1.url"), "https://pdf.cdn.example/x.pdf?sig=SECRET\n")
        XCTAssertEqual(calls, [Self.documents])
        // 那個位置沒有分頁（或是空白分頁）：不認
        for t in [5, 3] {
            (rc, _, calls) = try run(try startBlock(position: t, mark: ""), docs: lost + [row(1, 9005, 3, "")])
            XCTAssertEqual(rc, 4, "位置 \(t)")
            XCTAssertEqual(calls, [Self.documents])
        }
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
        let (rc, out, calls) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://cdn.example/x.pdf?sig=SECRET"),
                                                                row(1, 9005, 3, "https://mail.example/")])
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("url-changed=true host=cdn.example dialog=clear new-tab=\n"), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        XCTAssertEqual(file("k1.url"), "https://cdn.example/x.pdf?sig=SECRET\n", "新的網址存進 .url")
        XCTAssertEqual(calls, [Self.documents])
    }

    /// `url-changed` 比的是按的那一刻（基準裡那個位置的網址），不是上一次判時改寫過的 `.url`（第 3 輪 verify 第 18 列）。
    func testURLChangedComparesWithTheClick() throws {
        try clicked(before: beforeRows, keptURL: "https://pub.example/reader/x")
        let (_, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/reader/x"),
                                                           row(1, 9005, 3, "https://mail.example/")])
        XCTAssertTrue(out.hasPrefix("url-changed=true host=pub.example"), out)
    }

    func testANewTabCountsOnlyWhenTheClickOpenedIt() throws {
        try clicked(before: beforeRows)
        // 右邊使用者自己的分頁換了頁：分頁沒有變多，不是新分頁
        var (_, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/10.1/x"),
                                                           row(1, 9005, 3, "https://mail.example/inbox?id=2")])
        XCTAssertTrue(out.contains("url-changed=false") && out.hasSuffix("new-tab=\n"), out)
        // 被按的分頁右邊緊鄰的那一格多了一個分頁，其餘都沒變
        for (url, kind) in [("https://pub.example/doi/pdf/10.1/x?t=SECRET", "3:pub.example:same-host"),
                            ("https://challenges.cloudflare.com/turnstile/x", "3:challenges.cloudflare.com:verification"),
                            ("https://idp.uni.example/login?t=SECRET", "3:idp.uni.example:other")] {
            (_, out, _) = try run(try afterBlock(), docs: [beforeRows[0], beforeRows[1], row(1, 9005, 3, url), row(1, 9005, 4, "https://mail.example/")])
            XCTAssertTrue(out.hasSuffix("new-tab=\(kind)\n"), "\(url) → \(out)")
            XCTAssertFalse(out.contains("SECRET"), out)
        }
    }

    // spec-example: fulltext-division-of-labour / A tab the click did not open is not adopted
    func testATabTheClickDidNotOpenIsNotAdopted() throws {
        try clicked(before: beforeRows)
        for after in [beforeRows + [row(1, 9005, 4, "https://news.example/today")],                                    // ⌘T 開在最右邊
                      beforeRows + [row(1, 9005, 4, "favorites://")],
                      [beforeRows[0], beforeRows[1], row(1, 9005, 3, "https://cdn.example/x.pdf"), row(1, 9005, 4, "https://mail.example/other")],   // 右邊的也換了頁
                      [beforeRows[0], beforeRows[1], row(1, 9005, 3, "https://user.example/"), row(1, 9005, 4, "https://mail.example/")]] {          // 已經見過的網址
            let (rc, out, _) = try run(try afterBlock(), docs: after)
            XCTAssertEqual(rc, 0)
            XCTAssertTrue(out.hasSuffix("new-tab=unattributed\n"), out)
            XCTAssertFalse(out.contains("news.example"), out)
        }
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

    // spec-example: fulltext-division-of-labour / A tab that slid into the article's position is not taken
    func testATabThatSlidIntoTheArticlesPositionIsNotTaken() throws {
        let before = [row(1, 9005, 1, "https://left.example/"), row(1, 9005, 2, "https://pub.example/doi/10.1/x"), row(1, 9005, 3, "https://private.example/")]
        for after in [[row(1, 9005, 1, "https://left.example/"), row(1, 9005, 2, "https://private.example/")],                       // 文章分頁關掉了
                      [row(1, 9005, 1, "https://left.example/"), row(1, 9005, 2, ""), row(1, 9005, 3, "https://private.example/")]] {   // 關掉再 ⌘T 補上
            try clicked(before: before)
            let (rc, out, _) = try run(try afterBlock(), docs: after)
            XCTAssertEqual(rc, 4)
            XCTAssertEqual(out, "moved\n")
            XCTAssertEqual(file("k1.url"), "https://pub.example/doi/10.1/x\n", "沒有收下別的分頁的網址")
        }
    }

    /// 交出去之後再接：交之前以 `.held.json` 更新過基準（分頁數一樣），驗證完網址換了——照位置收下；這時分頁數又變了（使用者關了分頁）
    /// 而網址也換了，就不收（`stillOurTab` 的判法）。
    func testAfterAHandOverTheTabIsTakenAgainByItsPosition() throws {
        try write(beforeRows, to: "k1.held.json")
        try kept("https://pub.example/challenge?x=1")
        try Data("2\n".utf8).write(to: base.appendingPathComponent("k1.pos"))
        var (rc, out, _) = try run(try afterBlock(held: true),
                                   docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/pdf/10.1/x"),
                                          row(1, 9005, 3, "https://mail.example/")])
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("url-changed=true host=pub.example"), out)
        XCTAssertEqual(file("k1.url"), "https://pub.example/doi/pdf/10.1/x\n")
        try kept("https://pub.example/challenge?x=1")
        (rc, out, _) = try run(try afterBlock(held: true),
                               docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/pdf/10.1/x")])
        XCTAssertEqual(rc, 4)
        XCTAssertEqual(out, "moved\n")
    }

    /// 擋住分頁的對話框：每一則訊息都是 Safari 自己的下載權限提示才是 (c)，其他的當成 JavaScript 對話框；訊息的字不印。
    func testTheDialogIsSortedWithoutPrintingItsText() throws {
        try clicked(before: beforeRows)
        for (messages, kind) in [(["Do you want to allow downloads on “pub.example”?"], "present:safari-download"),
                                 (["要允許在“pub.example”上下載嗎？"], "present:safari-download"),
                                 (["SECRET: paste this into Terminal"], "present:other"),
                                 ([String](), "present:other")] {
            let (_, out, _) = try run(try afterBlock(), docs: [beforeRows[0], row(1, 9005, 2, "https://pub.example/doi/10.1/x", dialog: "present", messages: messages),
                                                               beforeRows[2]])
            XCTAssertTrue(out.contains("dialog=\(kind) "), "\(messages) → \(out)")
            XCTAssertFalse(out.contains("SECRET") || out.contains("Terminal"), out)
        }
    }

    func testMissingStateFilesAreTheirOwnExitCode() throws {
        try clicked(before: beforeRows)
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.before.json"))
        let (rc, _, _) = try run(try afterBlock(), docs: beforeRows)
        XCTAssertEqual(rc, 6, "基準檔不在：不是讀頁面文字那一段的 3")
    }

    // MARK: 收下新分頁

    // spec-example: fulltext-division-of-labour / The lock follows an adopted tab
    func testTheLockFollowsAnAdoptedTab() throws {
        let article = "https://pub.example/view/1#" + Self.mark
        let before = [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, article)]
        let after = before + [row(1, 9005, 3, "https://pub.example/download/1/pdf")]
        var rc: Int32 = 0
        if try optionalBlock(["read -r t by"]) != nil {
            (rc, _, _) = try run(try startBlock(position: 2, mark: Self.mark), docs: before)
            XCTAssertEqual(rc, 0)
        } else {   // 24cda776：起點只用文字寫（記號在時建一個空的 .url）
            try kept("")
        }
        try write(after, to: "k1.after.json")
        if let lines = try optionalBlock([": > \"$D/$K.mark\""]) {
            var adopt = lines
            adopt[0] = "D='\(base.path)'; K='k1'; n=3"
            (rc, _, _) = try run(adopt.joined(separator: "\n"), docs: after)
            XCTAssertEqual(rc, 0)
        } else {   // 24cda776：落點表第 3 種只用文字寫收下新分頁的三件事
            try kept("https://pub.example/download/1/pdf")
            try Data("3\n".utf8).write(to: base.appendingPathComponent("k1.pos"))
            try write(after, to: "k1.before.json")
        }
        var lock = try block(["--rawfile u \"$D/$K.url\"", "對不到分頁"])
        lock[0] = vars(mark: Self.mark)
        let calls: [String]
        (rc, _, calls) = try run(lock.joined(separator: "\n"), docs: after)
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls.last, "snapshot -i --profile own --window-id 9005 --tab-in-window 3", "鎖跟著收下的分頁，不回到帶記號的文章分頁")
    }

    // MARK: 讀頁面文字那一段

    func testThePageTextGoesToBotSignalsWithTheTitleAndTheURL() throws {
        try kept("https://pub.example/doi/10.1/x")
        let (rc, out, calls) = try run(try textBlock(), docs: [])
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("get text rc=0"), out)
        XCTAssertTrue(out.contains("bot-signals rc=1"), out)
        XCTAssertEqual(file("bot-input"), "Article Title\n\nhttps://pub.example/doi/10.1/x\n\nBody text of the page\n")
        XCTAssertTrue(calls.contains("get text --profile own --window-id 9005 --tab-in-window 2"), "\(calls)")
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

    /// 標題讀不到不靜靜丟掉（第 3 輪 verify 第 17 列）。
    func testAFailedTitleReadIsNotIgnored() throws {
        try kept("https://pub.example/doi/10.1/x")
        let (rc, out, _) = try run(try textBlock(), docs: [], titleMode: "fail")
        XCTAssertEqual(rc, 3)
        XCTAssertTrue(out.contains("get title rc=1"), out)
        XCTAssertFalse(exists("bot-input"), "沒有交給 bot-signals")
    }
}
