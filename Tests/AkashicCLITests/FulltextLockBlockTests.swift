import XCTest
import Foundation

/// #781 第 2 輪 verify 第 1、3、6、9、11 列，第 3 輪第 1–8、10、17、18 列，第 4 輪第 1–8、10、11、16、20 列：SKILL 第 3 步的各段 bash——
/// 起點、鎖分頁、〈按〉、落點、收下新分頁、交出去之後再接、讀頁面文字——原文照跑，對一個假的 safari-browser。
///
/// **fixture 是量到的版面**（2026-11-20 在真的 Safari 上，PsychQuant/Akashic-Library#820；plugin 裡的
/// `references/safari-measurements.md`）：`fetch` 的分頁是視窗的最後一個（M1）；連結開的新分頁在最後面、第一次讀取就顯示連結的目標（M2、M2b）；
/// 轉址過的連結顯示的不是 href（M2e）；⌘T 的分頁在最後面、網址 `favorites://`（M3）；`window.open` 可能開新視窗（M4b）；
/// `href="#"` 的按鈕會改掉片段（M5）；儲存面板是 `unknown`／`incomplete`（M6）；自己關掉的分頁讓一次讀取失敗（M7）；
/// `alert` 是 `present`、按的命令不回來（M8）。每一支新的或改過的測試在註解裡寫它用的是哪一列。
///
/// 斷言：鎖分頁那一段只在 `fetch` 的視窗裡、以記號或完整網址認出恰好一個分頁時才送命令；網址只經 `jq` 與檔案，印出來的只有主機。
/// 按了之後，新分頁只在按的同一個呼叫裡、恰好多一個在最後面、而且網址等於按的那個連結時才算這一下開的；其餘讓 Safari 變多的情形以 10 結束、
/// 不對多出來的送任何命令。對話框只印狀態。交出去之前才取基準，做完之後主機不對的分頁不讀。
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

    /// 變數那一行。63a87a98 的各段從第一行讀 `W`、`P`、`M`；現在的各段從起點那一段寫的檔讀（`.w`、`.profile`），第一行多給的變數不影響。
    /// 兩種都給，同一支測試在兩個版本的 SKILL 上跑的是同一件事。`inline: false` 時第一行不帶 `P`（名字裡有引號時放不進單引號）。
    private func vars(key: String = "k1", profile: String = "own", mark: String = "", extra: String = "", inline: Bool = true) -> String {
        try? Data(profile.utf8).write(to: base.appendingPathComponent("\(key).profile"))
        try? Data("9005\n".utf8).write(to: base.appendingPathComponent("\(key).w"))
        return "D='\(base.path)'; K='\(key)'; W=9005; \(inline ? "P='\(profile)'; " : "")M='\(mark)'\(extra)"
    }

    private static let lockMarkers = ["--rawfile u \"$D/$K.url\"", "對不到分頁"]

    /// 鎖分頁那一段；第一行（佔位的變數）換成測試的值。記號寫進 `.mark`（起點那一段寫的檔）。
    private func lockBlock(key: String = "k1", mark: String = "", profile: String = "own", inline: Bool = true) throws -> String {
        var lines = try block(Self.lockMarkers)
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = vars(key: key, profile: profile, mark: mark, inline: inline)
        try Data((mark + "\n").utf8).write(to: base.appendingPathComponent("\(key).mark"))
        return lines.joined(separator: "\n")
    }

    /// 鎖分頁那一段去掉最後送命令的那一行（它後面要接別的）；`.mark` 不動。
    private func lockPrefix(key: String = "k1", profile: String = "own") throws -> [String] {
        var lines = try block(Self.lockMarkers)
        lines[0] = vars(key: key, profile: profile)
        let last = try XCTUnwrap(lines.lastIndex { $0.hasPrefix("safari-browser snapshot -i") }, "鎖分頁那一段最後不是送命令的那一行")
        return Array(lines[..<last])
    }

    /// 起點那一段：`T` 是 `handover:` 一行的分頁位置。
    private func startBlock(position: Int, mark: String, profile: String = "own", inline: Bool = true) throws -> String {
        var lines = try block(["read -r t by"])
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = vars(profile: profile, mark: mark, extra: "; T=\(position)", inline: inline)
        return lines.joined(separator: "\n")
    }

    /// 按了之後的落點那一段，單獨跑（等過之後再判、鎖對不到之後）。63a87a98 的那一段以 `B` 指基準。
    private func afterBlock(key: String = "k1", held: Bool = false, profile: String = "own") throws -> String {
        var lines = try optionalBlock(["--slurpfile wb"]) ?? block(["--slurpfile b \"$B\""])
        XCTAssertTrue(lines.first?.hasPrefix("D='<暫存目錄>'") ?? false, lines.first ?? "")
        lines[0] = vars(key: key, profile: profile, extra: "; B=\"$D/$K.\(held ? "held" : "before").json\"")
        return lines.joined(separator: "\n")
    }

    /// 第 4 步的那一個 Bash 呼叫：鎖分頁那一段（最後一行拿掉）、〈按〉、〈落點〉。63a87a98 沒有〈按〉那一段，照它第 4 步的文字做同樣的事
    /// （存下按之前的狀態、留下 `.clicked`、送 `click`），所以這些測試在那個版本上是因為行為不同而失敗，不是因為找不到那一段。
    private func clickCall(key: String = "k1", profile: String = "own") throws -> String {
        let click = try optionalBlock(["LOOK=click"])?.map { $0.replacingOccurrences(of: "@<ref>", with: "@e1") }
            ?? ["cp \"$D/$K.docs.json\" \"$D/$K.before.json\"; touch \"$D/$K.clicked\"",
                "safari-browser click @e1 \"${PF[@]}\" --window-id \"$W\" --tab-in-window \"$t\""]
        return (try lockPrefix(key: key, profile: profile) + click).joined(separator: "\n") + "\n" + (try afterBlock(key: key, profile: profile))
    }

    /// 交出去之前的那一步：鎖分頁那一段，最後一行換成存下交出去那一刻的狀態。63a87a98 是以落點那一段（基準 `.held.json`）重判一次、
    /// 認得到才更新 `.held.json`。
    private func handOverStep(key: String) throws -> String {
        if try optionalBlock(["SITE="]) != nil {
            return (try lockPrefix(key: key) + ["cp \"$D/$K.docs.json\" \"$D/$K.held.json\"; touch \"$D/$K.handover\"; echo \"held pos=$t\""]).joined(separator: "\n")
        }
        return try afterBlock(key: key, held: true) + "\ncp \"$D/$K.after.json\" \"$D/$K.held.json\"; touch \"$D/$K.handover\""
    }

    /// 使用者說做完之後的那一段。63a87a98 沒有自己的一段，用的是落點那一段（基準 `.held.json`）。
    private func retakeBlock(key: String = "k1", site: String) throws -> String {
        guard var lines = try optionalBlock(["SITE="]) else { return try afterBlock(key: key, held: true) }
        lines[0] = vars(key: key, extra: "; SITE='\(site)'")
        return lines.joined(separator: "\n")
    }

    /// 收下新分頁那一段。
    private func adoptBlock(position: Int) throws -> String {
        var lines = try block(["n=<new-tab 印的位置>"])
        lines[0] = "D='\(base.path)'; K='k1'; n=\(position)"
        return lines.joined(separator: "\n")
    }

    /// 讀頁面文字那一段；前面補上鎖分頁那一段會設的變數。
    private func textBlock() throws -> String {
        let lines = try block(["get text", "bot-signals --kind"])
        return (["D='\(base.path)'; K='k1'; W=9005; t=2; PF=(--profile own)"] + lines.filter { !$0.hasPrefix("#") }).joined(separator: "\n")
    }

    private func row(_ window: Int, _ id: Int, _ tab: Int, _ url: String, dialog: String = "clear", messages: [String] = [], reason: String? = nil) -> [String: Any] {
        var d: [String: Any] = ["state": dialog, "window_id": id, "messages": messages]
        if let reason { d["reason"] = reason }
        return ["window": window, "window_id": id, "tab_in_window": tab, "url": url, "profile": "own", "blocking_dialog": d]
    }

    /// `fetch` 的視窗（id 9005）的分頁，依序。
    private func tabs(_ urls: String...) -> [[String: Any]] { urls.enumerated().map { row(1, 9005, $0.offset + 1, $0.element) } }

    private func write(_ rows: [[String: Any]], to name: String) throws {
        try JSONSerialization.data(withJSONObject: rows).write(to: base.appendingPathComponent(name))
    }

    private func run(_ script: String, docs: [[String: Any]], hang: Bool = false, textMode: String = "ok", titleMode: String = "ok",
                     shell: String = "/bin/bash") throws -> (Int32, String, [String]) {
        try run(script, reads: [docs], hang: hang, textMode: textMode, titleMode: titleMode, shell: shell)
    }

    /// 假的 safari-browser：第 n 次 `documents` 印 `reads` 的第 n 份（用完之後重複最後一份；`failing` 裡的那幾次以 1 結束、什麼都不印；
    /// `hang` 時先睡）；`click` 照 `clickMode`（`hang` 是不回來）；`get title`／`get text` 照 `titleMode`／`textMode`；其他命令只記下。
    /// 假的 `akashic`：`fulltext same-target` 交給測試建置的真 binary，其餘把 stdin 寫進 bot-input、回 1（沒有命中）。
    /// 回（結束碼，stdout，safari-browser 收到的命令）。
    private func run(_ script: String, reads: [[[String: Any]]], failing: Set<Int> = [], hang: Bool = false, clickMode: String = "ok",
                     textMode: String = "ok", titleMode: String = "ok", shell: String = "/bin/bash") throws -> (Int32, String, [String]) {
        let seq = base.appendingPathComponent("seq")
        try? FileManager.default.removeItem(at: seq)
        try FileManager.default.createDirectory(at: seq, withIntermediateDirectories: true)
        for (i, rows) in reads.enumerated() { try JSONSerialization.data(withJSONObject: rows).write(to: seq.appendingPathComponent("\(i + 1).json")) }
        try JSONSerialization.data(withJSONObject: reads.last ?? []).write(to: seq.appendingPathComponent("last.json"))
        for n in failing { try Data().write(to: seq.appendingPathComponent("fail.\(n)")) }
        let log = base.appendingPathComponent("calls.log")
        try? FileManager.default.removeItem(at: log)
        let stub = base.appendingPathComponent("bin/safari-browser")
        try """
        #!/bin/sh
        echo "$*" >> '\(log.path)'
        case "$1 $2" in
          documents*) \(hang ? "sleep 10;" : "")
            n=$(( $(cat '\(seq.path)/count' 2>/dev/null || echo 0) + 1 )); echo "$n" > '\(seq.path)/count'
            [ -e '\(seq.path)/fail.'"$n" ] && { echo 'Error: AppleScript -1719' >&2; exit 1; }
            f='\(seq.path)/'"$n"'.json'; [ -e "$f" ] || f='\(seq.path)/last.json'; cat "$f" ;;
          click*) case '\(clickMode)' in
              hang) sleep 10 ;;
            esac ;;
          "get title") case '\(titleMode)' in
              fail) echo 'Error: The tab is not running scripts' >&2; exit 1 ;;
              empty) : ;;
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
        let real = CLITestHarness.productsDirectory.appendingPathComponent("akashic").path
        try """
        #!/bin/sh
        case "$1 $2" in "fulltext same-target") exec '\(real)' "$@" ;; esac
        cat > '\(base.appendingPathComponent("bot-input").path)'
        exit 1
        """.write(to: akashic, atomically: true, encoding: .utf8)
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

    private func kept(_ url: String, key: String = "k1") throws { try Data((url + "\n").utf8).write(to: base.appendingPathComponent("\(key).url")) }
    private func file(_ name: String) -> String { (try? String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: base.appendingPathComponent(name).path) }
    private func href(_ value: String) throws { try Data((value + "\n").utf8).write(to: base.appendingPathComponent("k1.href")) }

    private static let mark = "akashic-0123456789abcdef"
    private static let article = "https://www.sd.example/science/article/pii/S1"
    private static let documents = "documents --json --profile own"
    /// `fetch` 開的文章分頁：帶著這次執行的記號，是視窗的最後一個分頁（2026-11-20 實測的 M1）。
    private static let page = "https://pub.example/doi/full/10.1/x#" + mark
    private static let user = "https://user.example/"
    /// 第 1 步讀到的 href（屬性原文，M2e）與它在 `page` 上解析出來的網址。
    private static let link = "/doi/pdf/10.1/x"
    private static let target = "https://pub.example/doi/pdf/10.1/x"

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
        XCTAssertEqual(rc, 4, "這一篇還沒按過")
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
        // 按了之後同一個分頁換到 CDN 上的網址（分頁數沒變）。版面是 M1（文章分頁在最後）；同一個分頁換頁這件事 2026-11-20 沒有量
        try clicked(before: tabs(Self.user, Self.page))
        let (_, out, _) = try run(try afterBlock(), docs: tabs(Self.user, "https://alice:s3cret@cdn.example/x.pdf"))
        XCTAssertTrue(out.contains("host=cdn.example "), out)
        XCTAssertFalse(out.contains("alice") || out.contains("s3cret"), out)
    }

    // spec-example: fulltext-division-of-labour / The profile name is read from a file
    func testTheProfileNameIsReadFromAFile() throws {
        let name = "Che's \"work\""
        let rows = tabs(Self.user, Self.article)   // 版面是 M1；profile 的名字不是版面的一部分，帶引號的名字沒有在真的 Safari 上試過
        var (rc, _, calls) = try run(try startBlock(position: 2, mark: "", profile: name, inline: false), docs: rows)
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls, ["documents --json --profile \(name)"], "名字裡有引號也照樣帶 --profile")
        (rc, _, calls) = try run(try lockBlock(profile: name, inline: false), docs: rows)
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(calls, ["documents --json --profile \(name)", "snapshot -i --profile \(name) --window-id 9005 --tab-in-window 2"])
        (rc, _, calls) = try run(try lockBlock(profile: "", inline: false), docs: rows)
        XCTAssertEqual(calls, ["documents --json", "snapshot -i --window-id 9005 --tab-in-window 2"], "profile 檔是空的（fetch 讀不出來）才不帶")
    }

    // spec-example: fulltext-division-of-labour / Positions that are not 1 to n are refused
    func testPositionsThatAreNotOneToNAreRefused() throws {
        // 頁面標題偽造的一列（safari-browser#355）：fetch 的視窗裡同一個位置兩列。**沒有量過**：#355 還沒在真的 Safari 上確認，2026-11-20 也沒有量
        let forged = tabs(Self.user, Self.article) + [row(1, 9005, 2, "https://evil.example/")]
        var (rc, _, calls) = try run(try startBlock(position: 2, mark: ""), docs: forged)
        XCTAssertEqual(rc, 7, "起點")
        XCTAssertEqual(calls, [Self.documents])
        XCTAssertFalse(file("k1.url").contains("evil.example"), file("k1.url"))
        try kept(Self.article)
        (rc, _, calls) = try run(try lockBlock(), docs: forged)
        XCTAssertEqual(rc, 7, "鎖分頁")
        XCTAssertEqual(calls, [Self.documents])
        XCTAssertEqual(file("k1.url"), Self.article + "\n", "網址檔沒有多出第二行")
        try clicked(before: tabs(Self.user, Self.article), keptURL: Self.article)
        (rc, _, calls) = try run(try afterBlock(), docs: forged)
        XCTAssertEqual(rc, 7, "落點")
        XCTAssertEqual(calls, [Self.documents])
        // 位置不連續（少了第 1 個）也一樣
        (rc, _, _) = try run(try lockBlock(), docs: [row(1, 9005, 2, Self.article)])
        XCTAssertEqual(rc, 7)
    }

    /// 各段在 zsh（Claude Code 的 Bash 工具在這台機器跑 zsh）也一樣：`"${PF[@]}"` 的陣列、`read`、`for`、`case`。
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
        // 第 4 步的那一個呼叫（M1 的版面，M2 的新分頁），再加收下新分頁
        (rc, _, _) = try run(try startBlock(position: 2, mark: Self.mark), docs: tabs(Self.user, Self.page), shell: "/bin/zsh")
        XCTAssertEqual(rc, 0)
        try href(Self.link)
        let out: String
        (rc, out, calls) = try run(try clickCall(), reads: [tabs(Self.user, Self.page), tabs(Self.user, Self.page, Self.target)], shell: "/bin/zsh")
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasSuffix("new-tab=3:pub.example\n"), out)
        (rc, _, _) = try run(try adoptBlock(position: 3), docs: [], shell: "/bin/zsh")
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(file("k1.pos"), "3\n")
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
        XCTAssertEqual(file("k1.w"), "9005\n", "視窗 id 隨這一篇的狀態存")
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
        // profile 檔沒寫：在讀清單之前就停（不是靜靜不帶 --profile）
        let script = try startBlock(position: 2, mark: "")
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.profile"))
        (rc, _, calls) = try run(script, docs: lost)
        XCTAssertEqual(rc, 6)
        XCTAssertEqual(calls, [])
    }

    // MARK: 按了之後的落點那一段

    /// 按之前的狀態，直接寫成〈按〉那一段會留下的檔（單獨跑落點那一段的測試用）。
    private func clicked(before: [[String: Any]], position: Int = 2, keptURL: String = "https://pub.example/doi/10.1/x", mark: String = "") throws {
        _ = vars()
        try write(before, to: "k1.before.json")
        try Data("[9005]\n".utf8).write(to: base.appendingPathComponent("k1.wins.before"))
        try Data((mark + "\n").utf8).write(to: base.appendingPathComponent("k1.mark"))
        try kept(keptURL)
        try Data("\(position)\n".utf8).write(to: base.appendingPathComponent("k1.pos"))
        try Data().write(to: base.appendingPathComponent("k1.clicked"))
    }

    /// 被按的分頁在 3 個裡的第 2 個（2026-11-20 的 M2b 就是這個版面）。
    private var beforeRows: [[String: Any]] {
        [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/doi/10.1/x"), row(1, 9005, 3, "https://mail.example/")]
    }

    /// 起點，再跑第 4 步的那一個呼叫：`before` 是按之前的讀取，`after` 是按的命令回來之後的各次讀取。
    private func startAndClick(before: [[String: Any]], after: [[[String: Any]]], position: Int = 2, link: String? = FulltextLockBlockTests.link, failing: Set<Int> = [],
                               clickMode: String = "ok") throws -> (Int32, String, [String]) {
        let (rc, _, _) = try run(try startBlock(position: position, mark: Self.mark), docs: before)
        XCTAssertEqual(rc, 0, "起點")
        if let link { try href(link) }
        return try run(try clickCall(), reads: [before] + after, failing: failing, clickMode: clickMode)
    }

    private static let click = "click @e1 --profile own --window-id 9005 --tab-in-window 2"

    func testAChangedURLIsTakenAndOnlyItsHostIsPrinted() throws {
        try clicked(before: beforeRows)   // M2b 的版面
        let (rc, out, calls) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://cdn.example/x.pdf?sig=SECRET"),
                                                                row(1, 9005, 3, "https://mail.example/")])
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("url-changed=true host=cdn.example vsvc=false dialog=clear was=clear new-tab=\n"), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        XCTAssertEqual(file("k1.url"), "https://cdn.example/x.pdf?sig=SECRET\n", "新的網址存進 .url")
        XCTAssertEqual(calls, [Self.documents])
    }

    /// `url-changed` 比的是基準（按的那一刻那個位置的網址），不是上一次判時改寫過的 `.url`（第 3 輪 verify 第 18 列）；
    /// 沒變的時候 `.url` 也照樣存（第 4 輪 verify 第 6 列）。
    func testURLChangedComparesWithTheClick() throws {
        // 版面是 M2b（被按的分頁在 3 個裡的第 2 個）；同一個分頁換頁再換回來沒有量過
        try clicked(before: beforeRows, keptURL: "https://pub.example/reader/x")
        var (_, out, _) = try run(try afterBlock(), docs: [row(1, 9005, 1, "https://user.example/"), row(1, 9005, 2, "https://pub.example/reader/x"),
                                                           row(1, 9005, 3, "https://mail.example/")])
        XCTAssertTrue(out.hasPrefix("url-changed=true host=pub.example"), out)
        try kept("https://pub.example/reader/x?step=2")
        (_, out, _) = try run(try afterBlock(), docs: beforeRows)
        XCTAssertTrue(out.hasPrefix("url-changed=false host=pub.example"), out)
        XCTAssertEqual(file("k1.url"), "https://pub.example/doi/10.1/x\n", "網址換回基準的那一個時，.url 也跟著換回來")
    }

    /// 驗證服務上的頁面印 `vsvc=true`（落點表第 1 種看它決定要不要探測）。
    func testTheLandingLineSaysWhetherThePageIsOnAVerificationService() throws {
        try clicked(before: tabs(Self.user, "https://pub.example/doi/10.1/x"))   // 文章分頁在最後（M1）；驗證服務的頁面沒有量過（量測沒有連任何外部網站）
        let (_, out, _) = try run(try afterBlock(), docs: tabs(Self.user, "https://challenges.cloudflare.com/turnstile/x?t=SECRET"))
        XCTAssertTrue(out.hasPrefix("url-changed=true host=challenges.cloudflare.com vsvc=true "), out)
        XCTAssertFalse(out.contains("SECRET"), out)
    }

    // spec-example: fulltext-division-of-labour / A tab the click did not open is not adopted
    func testATabTheClickDidNotOpenIsNotAdopted() throws {
        let before = tabs(Self.user, Self.page)   // M1：fetch 的分頁是最後一個
        // M2：連結開的新分頁在最後面，第一次讀取就顯示連結的目標
        var (rc, out, calls) = try startAndClick(before: before, after: [tabs(Self.user, Self.page, Self.target + "#page=1")])
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasSuffix("dialog=clear was=clear new-tab=3:pub.example\n"), out)
        XCTAssertEqual(calls, [Self.documents, Self.click, Self.documents])
        for (other, host) in [("favorites://", "(favorites)"),                                    // M3：⌘T 的分頁也在最後面；沒有主機的網址印 scheme
                              ("https://pub.example/search?q=mine&t=SECRET", "pub.example"),        // 使用者自己在出版商網站上開的分頁
                              ("https://cdn.example/x.pdf?sig=SECRET", "cdn.example")] {          // M2e：轉址過的連結，新分頁顯示的不是 href
            (rc, out, calls) = try startAndClick(before: before, after: [tabs(Self.user, Self.page, other)])
            XCTAssertEqual(rc, 10, "\(other) → \(out)")
            XCTAssertTrue(out.contains("\ngrown why=link-differ windows-new=0 unseen=3:\(host)\n"), "\(other) → \(out)")
            XCTAssertFalse(out.contains("SECRET") || out.contains("new-tab="), out)
            XCTAssertEqual(calls, [Self.documents, Self.click, Self.documents], "多出來的分頁沒有收到任何命令：\(calls)")
            XCTAssertFalse(file("k1.url").contains(other), "沒有收下它的網址")
        }
    }

    // spec-example: fulltext-division-of-labour / Other growth stops the batch
    func testOtherGrowthStopsTheBatch() throws {
        let before = tabs(Self.user, Self.page)   // M1
        // 一下開了兩個分頁（PDF 與 IdP 的登入頁）。一下開兩個分頁沒有量過；量到的是新分頁都落在最後面（M2–M4a）
        var (rc, out, calls) = try startAndClick(before: before, after: [tabs(Self.user, Self.page, "https://idp.uni.example/login?t=SECRET", Self.target)])
        XCTAssertEqual(rc, 10, out)
        XCTAssertTrue(out.contains("grown why=several-tabs windows-new=0 unseen=3:idp.uni.example,4:pub.example\n"), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        XCTAssertEqual(calls, [Self.documents, Self.click, Self.documents])
        // M4b：開出新視窗，原本視窗的分頁清單沒變
        (rc, out, calls) = try startAndClick(before: before, after: [before + [row(2, 9006, 1, "https://idp.uni.example/login")]])
        XCTAssertEqual(rc, 10, out)
        XCTAssertTrue(out.contains("grown why=new-window windows-new=1 unseen=\n"), out)
        XCTAssertEqual(calls, [Self.documents, Self.click, Self.documents])
        // 最後面多一個分頁（M2b），同時前面使用者的分頁也換了頁（這個組合沒有量過）
        (rc, out, _) = try startAndClick(before: tabs(Self.user, Self.page, "https://mail.example/"), after: [tabs(Self.user, Self.page, "https://mail.example/inbox", Self.target)])
        XCTAssertEqual(rc, 10, out)
        XCTAssertTrue(out.contains("grown why=not-last-or-others-changed "), out)
        XCTAssertTrue(out.contains("unseen=3:mail.example,4:pub.example\n"), out)
        // M4a：沒有 href 的按鈕（window.open）開的分頁在最後面
        (rc, out, _) = try startAndClick(before: before, after: [tabs(Self.user, Self.page, Self.target)], link: nil)
        XCTAssertEqual(rc, 10, out)
        XCTAssertTrue(out.contains("grown why=link-unresolvable windows-new=0 unseen=3:pub.example\n"), out)
        // 最後面多一個對得上連結的分頁，同時基準裡的一個視窗不見了：視窗 id 的集合要和基準一樣才收（這個組合沒有量過）
        let other = row(2, 9006, 1, "https://elsewhere.example/")
        (rc, out, _) = try startAndClick(before: before + [other], after: [tabs(Self.user, Self.page, Self.target)])
        XCTAssertEqual(rc, 10, out)
        XCTAssertTrue(out.contains("grown why=windows-changed windows-new=0 unseen=3:pub.example\n"), out)
    }

    // spec-example: fulltext-division-of-labour / A new window seen in a later read also stops the batch
    func testANewWindowSeenInALaterReadAlsoStopsTheBatch() throws {
        let before = tabs(Self.user, Self.page)   // M1
        var (rc, out, _) = try startAndClick(before: before, after: [before])
        XCTAssertEqual(rc, 0, out)
        // 等過之後單獨再判：這時多了一個視窗（M4b 量到按一下可以開新視窗；晚一步才開出來的時機沒有量過）
        let calls: [String]
        (rc, out, calls) = try run(try afterBlock(), docs: before + [row(2, 9007, 1, "https://idp.uni.example/login?t=SECRET")])
        XCTAssertEqual(rc, 10, out)
        XCTAssertEqual(out, "grown why=new-window windows-new=1 unseen=\n")
        XCTAssertEqual(calls, [Self.documents], "新視窗裡的分頁不讀、不送命令")
    }

    // spec-example: fulltext-division-of-labour / A new tab is adopted wherever the clicked tab sits
    func testANewTabIsAdoptedWhereverTheClickedTabSits() throws {
        // M2b：被按的分頁在 3 個裡的第 2 個，新分頁在第 4 個
        let before = tabs(Self.user, Self.page, "https://mail.example/")
        let (rc, out, _) = try startAndClick(before: before, after: [before + [row(1, 9005, 4, Self.target)]])
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasSuffix("new-tab=4:pub.example\n"), out)
    }

    // spec-example: fulltext-division-of-labour / A tab first seen in a later read is not adopted
    func testATabFirstSeenInALaterReadIsNotAdopted() throws {
        let before = tabs(Self.user, Self.page)   // M1
        var (rc, out, _) = try startAndClick(before: before, after: [before])
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasSuffix("new-tab=\n"), out)
        // 等過之後單獨再判：這時才出現的分頁，即使網址就是連結的目標，也不是按的那一次讀取裡看到的。
        // 量到的新分頁都在第一次讀取就出現（M2）；晚一步才出現的時機沒有量過，位置照 M2、M3（最後面）
        let calls: [String]
        (rc, out, calls) = try run(try afterBlock(), docs: tabs(Self.user, Self.page, Self.target))
        XCTAssertEqual(rc, 10, out)
        XCTAssertEqual(out, "grown why=after-the-click-read windows-new=0 unseen=3:pub.example\n")
        XCTAssertEqual(calls, [Self.documents])
    }

    // spec-example: fulltext-division-of-labour / A fragment change with a new tab is not moved
    func testAFragmentChangeWithANewTabIsNotMoved() throws {
        // M5：<a href="#" onclick="window.open(…)">，被按的分頁的片段從記號變成空的，最後面多一個分頁
        let after = tabs(Self.user, "https://pub.example/doi/full/10.1/x#", Self.target)
        var (rc, out, _) = try startAndClick(before: tabs(Self.user, Self.page), after: [after], link: "#")
        XCTAssertEqual(rc, 10, out)
        XCTAssertFalse(out.contains("moved"), out)
        XCTAssertTrue(out.contains("grown why=link-unresolvable windows-new=0 unseen=3:pub.example\n"), "被按的分頁自己不列在 unseen 裡：\(out)")
        XCTAssertEqual(file("k1.url"), "https://pub.example/doi/full/10.1/x#\n", "被按的分頁的新網址存下來")
        XCTAssertEqual(file("k1.mark"), "", "記號已經不在那個分頁的網址上")
        // 同一下沒有開分頁：只是網址換了
        (rc, out, _) = try startAndClick(before: tabs(Self.user, Self.page), after: [tabs(Self.user, "https://pub.example/doi/full/10.1/x#")], link: "#")
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.contains("url-changed=true host=pub.example") && out.hasSuffix("new-tab=\n"), out)
        let calls: [String]
        (rc, _, calls) = try run(try lockBlock(mark: ""), docs: tabs(Self.user, "https://pub.example/doi/full/10.1/x#"))
        XCTAssertEqual(rc, 0, "記號不見之後鎖以存下的網址認")
        XCTAssertEqual(calls.last, "snapshot -i --profile own --window-id 9005 --tab-in-window 2")
    }

    // spec-example: fulltext-division-of-labour / A new tab without a URL gets one wait
    func testANewTabWithoutAURLGetsOneWait() throws {
        let before = tabs(Self.user, Self.page)   // M1；新分頁在最後面（M2），這裡假設它第一次讀取時還沒有網址（沒有量過會不會這樣）
        for (later, expected, code) in [(Self.target, "new-tab=3:pub.example\n", Int32(0)), ("", "grown why=no-url windows-new=0 unseen=3:()\n", Int32(10)),
                                        ("https://ads.example/x", "grown why=link-differ windows-new=0 unseen=3:ads.example\n", Int32(10))] {
            var (rc, out, _) = try startAndClick(before: before, after: [tabs(Self.user, Self.page, "")])
            XCTAssertEqual(rc, 0, out)
            XCTAssertTrue(out.hasSuffix("new-tab=pending:3\n"), out)
            (rc, out, _) = try run(try afterBlock(), docs: tabs(Self.user, Self.page, later))
            XCTAssertEqual(rc, code, out)
            XCTAssertTrue(out.hasSuffix(expected), "\(later) → \(out)")
        }
    }

    // spec-example: fulltext-division-of-labour / A failed read right after a click is read again once
    func testAFailedReadRightAfterAClickIsReadAgainOnce() throws {
        // M7：target=_blank 的下載連結，一閃就關的分頁讓按了之後的第一次讀取失敗；之後的讀取沒有新分頁，對話框的探測是 unknown（儲存面板，M6）
        let before = tabs(Self.user, Self.page)
        let panel = [row(1, 9005, 1, Self.user, dialog: "unknown", reason: "incomplete"), row(1, 9005, 2, Self.page, dialog: "unknown", reason: "incomplete")]
        var (rc, out, calls) = try startAndClick(before: before, after: [before, panel], failing: [2])
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasSuffix("url-changed=false host=pub.example vsvc=false dialog=unknown was=clear new-tab=\n"), out)
        XCTAssertEqual(calls, [Self.documents, Self.click, Self.documents, Self.documents], "失敗的那一次之後再讀一次")
        (rc, out, calls) = try startAndClick(before: before, after: [before, before], failing: [2, 3])
        XCTAssertEqual(rc, 5, "兩次都失敗：\(out)")
        XCTAssertEqual(calls.filter { $0 == Self.documents }.count, 3)
        // 單獨再判時不重讀：那不是按了之後的第一次讀取
        try clicked(before: before, keptURL: Self.page, mark: Self.mark)
        (rc, _, calls) = try run(try afterBlock(), reads: [before, before], failing: [1])
        XCTAssertEqual(rc, 5)
        XCTAssertEqual(calls, [Self.documents])
    }

    // spec-example: fulltext-division-of-labour / A click that does not return is followed by the landing read
    func testAClickThatDoesNotReturnIsFollowedByTheLandingRead() throws {
        // M8：alert() 讓按的命令不回來；視窗裡每一個分頁都是 present，訊息是 Safari 加了來源前綴的那一句
        let message = "來自「http://127.0.0.1:47231」： measurement alert: plain page message"
        let alert = [row(1, 9005, 1, Self.user, dialog: "present", messages: [message]), row(1, 9005, 2, Self.page, dialog: "present", messages: [message])]
        let (rc, out, calls) = try startAndClick(before: tabs(Self.user, Self.page), after: [alert], clickMode: "hang")
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.contains("click rc=142"), out)
        XCTAssertTrue(out.contains("dialog=present was=clear new-tab=\n"), out)
        XCTAssertFalse(out.contains("measurement") || out.contains("127.0.0.1") || out.contains("來自"), "對話框的字不印：\(out)")
        XCTAssertEqual(calls.filter { $0.hasPrefix("click") }.count, 1, "不按第二次：\(calls)")
        XCTAssertEqual(calls.last, Self.documents, "按的命令沒回來，仍然接著讀落點")
    }

    // spec-example: fulltext-division-of-labour / The click is not sent when the dialog state is not clear
    func testTheClickIsNotSentWhenTheDialogStateIsNotClear() throws {
        // M6：儲存面板開著時整個視窗的分頁都是 unknown／incomplete
        let panel = [row(1, 9005, 1, Self.user, dialog: "unknown", reason: "incomplete"), row(1, 9005, 2, Self.page, dialog: "unknown", reason: "incomplete")]
        var (rc, _, _) = try run(try startBlock(position: 2, mark: Self.mark), docs: tabs(Self.user, Self.page))
        XCTAssertEqual(rc, 0)
        try href(Self.link)
        let calls: [String]
        (rc, _, calls) = try run(try clickCall(), reads: [panel, panel])
        XCTAssertEqual(rc, 12)
        XCTAssertEqual(calls, [Self.documents], "沒有按：\(calls)")
        XCTAssertFalse(exists("k1.clicked"))
    }

    // spec-example: fulltext-division-of-labour / A dialog's state is printed and never its text
    func testADialogsStateIsPrintedAndNeverItsText() throws {
        let message = "來自「http://127.0.0.1:47231」： measurement alert: plain page message"   // M8
        let before = tabs(Self.user, Self.page)
        for (state, messages, reason) in [("present", [message], String?.none),
                                          ("present", ["Do you want to allow downloads on “pub.example”?"], nil),   // 沒有量過的字樣（Safari 的下載提示沒有出現）；頁面可以寫任何字，所以不以字分類
                                          ("unknown", [String](), "incomplete")] {                                  // M6
            let now = [row(1, 9005, 1, Self.user, dialog: state, messages: messages, reason: reason),
                       row(1, 9005, 2, Self.page, dialog: state, messages: messages, reason: reason)]
            try clicked(before: before, keptURL: Self.page, mark: Self.mark)
            var (rc, out, _) = try run(try afterBlock(), docs: now)
            XCTAssertEqual(rc, 0, out)
            XCTAssertTrue(out.contains("dialog=\(state) was=clear "), "\(messages) → \(out)")
            XCTAssertFalse(out.contains("measurement") || out.contains("allow downloads") || out.contains("來自") || out.contains("safari-download"), out)
            (rc, out, _) = try run(try lockBlock(mark: Self.mark), docs: now)
            XCTAssertEqual(rc, 0)
            XCTAssertTrue(out.contains("host=pub.example dialog=\(state)\n"), out)
            XCTAssertFalse(out.contains("measurement") || out.contains("allow downloads") || out.contains("來自"), out)
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

    // MARK: 鎖對不到之後

    // spec-example: fulltext-division-of-labour / After a lock miss the landing block finds the tab again
    func testAfterALockMissTheLandingBlockFindsTheTabAgain() throws {
        // SAGE（2026-11-19 在出版商網站上看到的路徑，不在 2026-11-20 的量測裡）：按了之後同一個分頁先到 /doi/reader/，落點那一段存下它；之後分頁又轉到 /doi/epub/
        let before = tabs(Self.user, Self.page)   // M1
        var (rc, out, _) = try startAndClick(before: before, after: [tabs(Self.user, "https://pub.example/doi/reader/10.1/x")])
        XCTAssertEqual(rc, 0, out)
        let epub = tabs(Self.user, "https://pub.example/doi/epub/10.1/x")
        var calls: [String]
        (rc, _, calls) = try run(try lockBlock(mark: ""), docs: epub)
        XCTAssertEqual(rc, 2, "存下的是 reader 的網址：鎖認不到")
        XCTAssertEqual(calls, [Self.documents])
        (rc, out, _) = try run(try afterBlock(), docs: epub)
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasPrefix("url-changed=true host=pub.example"), out)
        (rc, _, calls) = try run(try lockBlock(mark: ""), docs: epub)
        XCTAssertEqual(rc, 0, "落點那一段以位置認到、改寫了 .url")
        XCTAssertEqual(calls.last, "snapshot -i --profile own --window-id 9005 --tab-in-window 2")

        // 收下的新分頁（M2）自己轉址、又轉回基準的那個網址（轉址再轉回沒有量過）
        (rc, out, _) = try startAndClick(before: before, after: [tabs(Self.user, Self.page, Self.target)])
        XCTAssertTrue(out.hasSuffix("new-tab=3:pub.example\n"), out)
        (rc, _, _) = try run(try adoptBlock(position: 3), docs: [])
        XCTAssertEqual(rc, 0)
        (rc, out, _) = try run(try afterBlock(), docs: tabs(Self.user, Self.page, Self.target + "?step=2"))
        XCTAssertTrue(out.hasPrefix("url-changed=true"), out)
        let back = tabs(Self.user, Self.page, Self.target)
        (rc, _, _) = try run(try lockBlock(mark: ""), docs: back)
        XCTAssertEqual(rc, 2)
        (rc, out, _) = try run(try afterBlock(), docs: back)
        XCTAssertTrue(out.hasPrefix("url-changed=false"), out)
        (rc, _, calls) = try run(try lockBlock(mark: ""), docs: back)
        XCTAssertEqual(rc, 0, "網址沒變也照樣存回 .url")
        XCTAssertEqual(calls.last, "snapshot -i --profile own --window-id 9005 --tab-in-window 3")
    }

    // spec-example: fulltext-division-of-labour / A page that moved on before any click is judged
    func testAPageThatMovedOnBeforeAnyClickIsJudged() throws {
        // left-site：fetch 落定在中繼頁（記號已經不在），之後那一頁自己轉到 IdP 的登入頁；文章分頁是最後一個（M1）。頁面自己轉走沒有量過
        var (rc, out, _) = try run(try startBlock(position: 2, mark: ""), docs: tabs(Self.user, "https://relay.other.example/go?id=1"))
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(out.contains("by=position host=relay.other.example"), out)
        let moved = tabs(Self.user, "https://idp.uni.example/login?return=SECRET")
        var calls: [String]
        (rc, _, calls) = try run(try lockBlock(mark: ""), docs: moved)
        XCTAssertEqual(rc, 4, "還沒按過")
        XCTAssertEqual(calls, [Self.documents])
        (rc, out, calls) = try run(try afterBlock(), docs: moved)
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasPrefix("url-changed=true host=idp.uni.example vsvc=false "), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        XCTAssertEqual(calls, [Self.documents], "只讀清單：那一頁照落點表判（別的主機上的登入頁是 (e)）")
    }

    // MARK: 交出去與再接

    /// 批次當中記下來的一篇（落點或鎖分頁那一段留下的 `.url`、`.pos`），`held` 是 63a87a98 在交出去那一刻就存的狀態。
    /// **交出去與再接的各個版面都沒有量過**（2026-11-20 的量測沒有做交接）：這裡用的是 M1 推出來的排列（`fetch` 每一篇的分頁都開在最後面，
    /// 所以先延後的在左邊）與第 4 輪 verify 的重現。
    private func deferred(_ key: String, url: String, position: Int, held: [[String: Any]]) throws {
        _ = vars(key: key)
        try kept(url, key: key)
        try Data("\(position)\n".utf8).write(to: base.appendingPathComponent("\(key).pos"))
        try Data("\n".utf8).write(to: base.appendingPathComponent("\(key).mark"))
        try Data().write(to: base.appendingPathComponent("\(key).clicked"))
        try write(held, to: "\(key).held.json")
    }

    // spec-example: fulltext-division-of-labour / Two deferred articles are both handed over
    func testTwoDeferredArticlesAreBothHandedOver() throws {
        // 第 4 輪 verify 的重現：k1（位置 2）與 k2（位置 3）延到最後，之後的一篇又在最後面開了 c/x（fetch 的分頁開在最後面，M1）
        let atDeferral = tabs("https://news.example/", "https://a.example/captcha", "https://b.example/signin")
        try deferred("k1", url: "https://a.example/captcha", position: 2, held: atDeferral)
        try deferred("k2", url: "https://b.example/signin", position: 3, held: atDeferral)
        let end = tabs("https://news.example/", "https://a.example/captcha", "https://b.example/signin", "https://c.example/x")
        var (rc, out, _) = try run(try handOverStep(key: "k1"), docs: end)
        XCTAssertEqual(rc, 0, "第一篇交得出去：\(out)")
        let afterA = tabs("https://news.example/", "https://a.example/article?t=SECRET", "https://b.example/signin", "https://c.example/x")
        (rc, out, _) = try run(try retakeBlock(key: "k1", site: "a.example"), docs: afterA)
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasPrefix("retake=ok url-changed=true host=a.example"), out)
        XCTAssertFalse(out.contains("SECRET"), out)
        // 第二篇：前一篇的網址已經變了、後面多了分頁——仍然交得出去
        (rc, out, _) = try run(try handOverStep(key: "k2"), docs: afterA)
        XCTAssertEqual(rc, 0, "第二篇也交得出去：\(out)")
        XCTAssertTrue(exists("k2.handover"))
        // 使用者登入完，網址換了，登入還在最後面多開了一個分頁
        let afterB = tabs("https://news.example/", "https://a.example/article?t=SECRET", "https://b.example/article", "https://c.example/x", "https://b.example/welcome")
        (rc, out, _) = try run(try retakeBlock(key: "k2", site: "b.example"), docs: afterB)
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasPrefix("retake=ok url-changed=true host=b.example"), out)
        XCTAssertEqual(file("k2.url"), "https://b.example/article\n")
    }

    // spec-example: fulltext-division-of-labour / A re-take on another host is not read
    func testAReTakeOnAnotherHostIsNotRead() throws {
        // 版面沒有量過（見 deferred 的說明）；使用者把交給他的分頁拿去看別的網站、關掉分頁，都是設想的情形
        let held = tabs("https://news.example/", "https://pub.example/captcha", "https://pub.example/other-paper")
        try deferred("k1", url: "https://pub.example/captcha", position: 2, held: held)
        var (rc, out, calls) = try run(try handOverStep(key: "k1"), docs: held)
        XCTAssertEqual(rc, 0, out)
        // 使用者把那個分頁拿去看別的網站
        (rc, out, calls) = try run(try retakeBlock(site: "pub.example"),
                                   docs: tabs("https://news.example/", "https://bank.example/statement.pdf?acct=SECRET", "https://pub.example/other-paper"))
        XCTAssertEqual(rc, 11, out)
        XCTAssertEqual(out, "retake=other-host\n")
        XCTAssertEqual(calls, [Self.documents], "那個分頁沒有收到任何命令")
        XCTAssertEqual(file("k1.url"), "https://pub.example/captcha\n", "沒有收下它的網址")
        // 那個分頁關掉了，右邊同一個站的另一篇滑進這個位置
        (rc, out, calls) = try run(try retakeBlock(site: "pub.example"), docs: tabs("https://news.example/", "https://pub.example/other-paper", "https://x.example/"))
        XCTAssertEqual(rc, 4, out)
        XCTAssertEqual(out, "moved\n")
        XCTAssertEqual(calls, [Self.documents])
        // 驗證服務上的頁面、同一個主機上換了網址：收
        for (now, line) in [("https://challenges.cloudflare.com/turnstile/x", "retake=ok url-changed=true host=challenges.cloudflare.com vsvc=true\n"),
                            ("https://pub.example/doi/pdf/10.1/x", "retake=ok url-changed=true host=pub.example vsvc=false\n"),
                            ("https://pub.example/captcha", "retake=ok url-changed=false host=pub.example vsvc=false\n")] {
            try kept("https://pub.example/captcha")
            (rc, out, _) = try run(try retakeBlock(site: "pub.example"), docs: tabs("https://news.example/", now, "https://pub.example/other-paper"))
            XCTAssertEqual(rc, 0, out)
            XCTAssertEqual(out, line)
            XCTAssertEqual(file("k1.url"), now + "\n")
        }
    }

    // spec-example: fulltext-division-of-labour / A re-take on another host is not read
    func testASameSiteNeighbourThatSlidInAfterAHandOverIsNotTaken() throws {
        // 同一個出版商的幾篇接連延到最後，是批次裡常見的排列：交出去的那個分頁右邊緊鄰的就是同一個站的另一篇
        // （版面沒有量過；`fetch` 的分頁依序開在最後面，M1）。協調者重放 a0e2696c 時找到：右邊緊鄰的那一篇滑進來會被收下。
        let held = tabs("https://news.example/", "https://a.example/article", "https://b.example/signin?paper=1", "https://b.example/doi/10.1/paper2")
        try deferred("k1", url: "https://b.example/signin?paper=1", position: 3, held: held)
        var (rc, out, calls) = try run(try handOverStep(key: "k1"), docs: held)
        XCTAssertEqual(rc, 0, out)
        // 交出去的分頁關掉了，右邊同一個站的那一篇滑進這個位置（清單變短，它原本的位置已經不存在）
        (rc, out, calls) = try run(try retakeBlock(site: "b.example"),
                                   docs: tabs("https://news.example/", "https://a.example/article", "https://b.example/doi/10.1/paper2"))
        XCTAssertEqual(rc, 4, out)
        XCTAssertEqual(out, "moved\n")
        XCTAssertEqual(calls, [Self.documents])
        XCTAssertEqual(file("k1.url"), "https://b.example/signin?paper=1\n", "沒有收下鄰居的網址")
        // 右邊還有別的分頁時也一樣（清單變短，滑進來的仍是緊鄰的那一篇）
        let longer = held + [row(1, 9005, 5, "https://c.example/x")]
        try write(longer, to: "k1.held.json")
        (rc, out, _) = try run(try retakeBlock(site: "b.example"),
                               docs: tabs("https://news.example/", "https://a.example/article", "https://b.example/doi/10.1/paper2", "https://c.example/x"))
        XCTAssertEqual(rc, 4, out)
        XCTAssertEqual(out, "moved\n")
        // 對照：鄰居留在原位、交出去的那一個分頁登入之後換到這一篇的網址——收
        try write(held, to: "k1.held.json")
        (rc, out, _) = try run(try retakeBlock(site: "b.example"),
                               docs: tabs("https://news.example/", "https://a.example/article", "https://b.example/doi/10.1/paper1", "https://b.example/doi/10.1/paper2"))
        XCTAssertEqual(rc, 0, out)
        XCTAssertEqual(out, "retake=ok url-changed=true host=b.example vsvc=false\n")
    }

    // spec-example: fulltext-division-of-labour / A hand-over whose tab cannot be found is not made
    func testAHandOverWhoseTabCannotBeFoundIsNotMade() throws {
        // 版面沒有量過：驗證頁在等的當中自己換了網址（設想的情形）
        try deferred("k1", url: "https://pub.example/captcha?t=1", position: 2, held: [])
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.clicked"))
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.held.json"))
        let (rc, _, calls) = try run(try handOverStep(key: "k1"), docs: tabs("https://news.example/", "https://pub.example/captcha?t=2"))
        XCTAssertEqual(rc, 4)
        XCTAssertEqual(calls, [Self.documents])
        XCTAssertFalse(exists("k1.held.json") || exists("k1.handover"), "沒有交出去")
    }

    /// 第 1 步讀的時候就交出去（還沒按）：批次結束時照樣認得到、交得出去、接得回來。
    func testAHandOverBeforeAnyClickCanBeTakenAgain() throws {
        let rows = tabs(Self.user, Self.article + "#" + Self.mark)   // M1；再接的那一步沒有量過
        var (rc, _, _) = try run(try startBlock(position: 2, mark: Self.mark), docs: rows)
        XCTAssertEqual(rc, 0)
        (rc, _, _) = try run(try lockBlock(mark: Self.mark), docs: rows)
        XCTAssertEqual(rc, 0)
        (rc, _, _) = try run(try handOverStep(key: "k1"), docs: rows)
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(exists("k1.held.json"))
        let out: String
        (rc, out, _) = try run(try retakeBlock(site: "www.sd.example"), docs: tabs(Self.user, "https://www.sd.example/science/article/pii/S1/pdf"))
        XCTAssertEqual(rc, 0, out)
        XCTAssertTrue(out.hasPrefix("retake=ok url-changed=true host=www.sd.example"), out)
        XCTAssertEqual(file("k1.mark"), "", "那個分頁的網址不再帶記號")
    }

    // spec-example: fulltext-division-of-labour / A missing state file is its own stop
    func testAMissingStateFileIsItsOwnStop() throws {
        let rows = tabs(Self.user, Self.page)   // M1
        // 落點：基準不在
        try clicked(before: rows, keptURL: Self.page, mark: Self.mark)
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.before.json"))
        var (rc, _, calls) = try run(try afterBlock(), docs: rows)
        XCTAssertEqual(rc, 6, "落點")
        XCTAssertEqual(calls, [])
        // 落點：位置的檔不在
        try clicked(before: rows, keptURL: Self.page, mark: Self.mark)
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.pos"))
        (rc, _, calls) = try run(try afterBlock(), docs: rows)
        XCTAssertEqual(rc, 6, "落點（位置）")
        XCTAssertEqual(calls, [])
        try clicked(before: rows, keptURL: Self.page, mark: Self.mark)
        // 鎖分頁：視窗 id 的檔不在（起點那一段沒跑）
        var script = try lockBlock(mark: Self.mark)
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.w"))
        (rc, _, calls) = try run(script.replacingOccurrences(of: "W=9005; ", with: ""), docs: rows)
        XCTAssertEqual(rc, 6, "鎖分頁")
        XCTAssertEqual(calls, [])
        // 收下新分頁：沒有按了之後的那一份清單
        (rc, _, _) = try run(try adoptBlock(position: 3), docs: [])
        XCTAssertEqual(rc, 6, "收下新分頁")
        XCTAssertEqual(file("k1.mark"), Self.mark + "\n", "沒有先清掉記號")
        // 交出去之後再接：沒有交出去那一刻的狀態，或位置的檔不在
        script = try retakeBlock(site: "pub.example")
        (rc, _, calls) = try run(script, docs: rows)
        XCTAssertEqual(rc, 6, "再接")
        XCTAssertEqual(calls, [])
        try write(rows, to: "k1.held.json")
        try FileManager.default.removeItem(at: base.appendingPathComponent("k1.pos"))
        (rc, _, calls) = try run(script, docs: rows)
        XCTAssertEqual(rc, 6, "再接（位置）")
        XCTAssertEqual(calls, [])
        let skill = try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        let step3 = SkillText.section(skill, "### 3. 在使用者的 Safari 裡走到 PDF")
        XCTAssertTrue(step3.contains("不當成 (e)"), "基準檔不在是程序漏了一步，不是 (e)")
    }

    // MARK: 收下新分頁

    // spec-example: fulltext-division-of-labour / The lock follows an adopted tab
    func testTheLockFollowsAnAdoptedTab() throws {
        // M1：文章分頁帶著記號、是最後一個；M2：連結開的新分頁在最後面
        let (rc0, out, _) = try startAndClick(before: tabs(Self.user, Self.page), after: [tabs(Self.user, Self.page, Self.target)])
        XCTAssertEqual(rc0, 0, out)
        var (rc, _, _) = try run(try adoptBlock(position: 3), docs: [])
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(file("k1.mark"), "", "收下新分頁時清空記號")
        var lock = try block(Self.lockMarkers)
        lock[0] = vars(mark: Self.mark)   // 63a87a98 的鎖從第一行讀記號；現在的從 .mark 讀（已經清空）
        let calls: [String]
        (rc, _, calls) = try run(lock.joined(separator: "\n"), docs: tabs(Self.user, Self.page, Self.target))
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
