import Foundation
import XCTest

/// #706：workflow 裡的每一個 `uses:` 都釘到 commit SHA，行尾註解寫它對應的版本標籤。
///
/// 版本標籤可以被移動，SHA 不行。更新是手動的（使用者 2026-09-30 裁決：不加 Dependabot），
/// 所以沒有任何機制會在有人改回 `@v4` 時出聲——這支測試就是那個機制。
///
/// **它只擋形狀**：SHA 是否屬於上游 repo、行尾註解的版本是否對得上那個 SHA，這裡驗不到
///（要連網）。那兩件事在更新程序裡核對（workflow 註解寫著 `compare <SHA>...<tag>` 要是 identical）。
final class WorkflowActionPinningTests: XCTestCase {

    /// 一個 `uses:` 的值是否合法（#706 R1 verify：本機 action 與 docker 映像不是「沒釘」）。
    ///
    /// - `./…`：本機的 action，隨本 repo 一起版本控制，沒有 SHA 可釘——放行
    /// - `docker://…`：要釘到 image digest（`@sha256:<64 位>`）
    /// - 其餘：`owner/repo[/path]@<40 位 commit SHA>`，且同一行有 `# vX.Y.Z` 的版本註解
    static func isPinned(value: String, line: String) -> Bool {
        if value.hasPrefix("./") { return true }
        if value.hasPrefix("docker://") {
            return value.range(of: #"@sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil
        }
        guard value.range(of: #"^[A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-/]+@[0-9a-f]{40}$"#,
                          options: .regularExpression) != nil else { return false }
        return line.range(of: #"#\s*v\d+(\.\d+)*\b"#, options: .regularExpression) != nil
    }

    /// 一段 workflow 文字裡所有的 `uses` 值（連同所在行號與原行）。
    ///
    /// 認得 block-style（`- uses: x`、`uses: x`）、加引號的鍵（`"uses": x`）與 flow-style（`- {uses: x}`）；
    /// 行尾的 `\r`（CRLF 檔）先剝掉。R1 verify：只認行首 `uses:` 時，flow-style 與加引號的鍵完全看不見，
    /// 而 CRLF 檔會整份讀成一行、被誤判成「判準寫錯了」。
    static func usesValues(in text: String) -> [(line: Int, value: String, raw: String)] {
        let key = try! NSRegularExpression(
            pattern: #"(?:^|[\s{,\-])["']?uses["']?\s*:\s*["']?([^\s"',}]+)"#)
        var found: [(Int, String, String)] = []
        // `String.split(separator: "\n")` 切不開 CRLF：Swift 把 `\r\n` 當成一個 Character。以 NSString 的
        // UTF-16 單位切，行尾剩下的 `\r` 再剝掉。
        for (i, rawLine) in (text as NSString).components(separatedBy: "\n").enumerated() {
            var s = rawLine
            if s.hasSuffix("\r") { s.removeLast() }
            let code = s.range(of: #"^\s*#"#, options: .regularExpression) != nil ? "" : s
            let ns = code as NSString
            for m in key.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                found.append((i + 1, ns.substring(with: m.range(at: 1)), s))
            }
        }
        return found
    }

    func testEveryWorkflowActionIsPinnedToACommitSHA() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fm = FileManager.default
        let workflows = root.appendingPathComponent(".github/workflows")
        var files = try fm.contentsOfDirectory(atPath: workflows.path)
            .filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
            .map { workflows.appendingPathComponent($0) }
        XCTAssertFalse(files.isEmpty, "找不到任何 workflow——掃描空集合不是通過")
        // composite action 內的 `uses:` 一樣會被引入（目前沒有這個目錄）
        let actions = root.appendingPathComponent(".github/actions")
        if let walker = fm.enumerator(at: actions, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where ["action.yml", "action.yaml"].contains(url.lastPathComponent) {
                files.append(url)
            }
        }

        var uses = 0
        var unpinned: [String] = []
        for url in files.sorted(by: { $0.path < $1.path }) {
            let text = try String(contentsOf: url, encoding: .utf8)
            for u in Self.usesValues(in: text) {
                uses += 1
                if !Self.isPinned(value: u.value, line: u.raw) {
                    let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                    unpinned.append("\(rel):\(u.line): \(u.raw.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertGreaterThan(uses, 0, "沒有掃到任何 uses——辨識寫錯了，不是全部都釘好了")
        XCTAssertEqual(unpinned, [], "這些 action 沒有釘到 commit SHA（或行尾缺版本註解、docker 映像缺 digest）")
    }

    /// 辨識與判準本身的固定案例——每一種形狀各一格，免得辨識寫錯時上面那支因為「剛好沒有這種寫法」而綠。
    /// CRLF 檔要逐行切開：先前整份讀成一行時，檔內任何一處 `# v` 都能讓沒有版本註解的那一行過關。
    func testCRLFFileIsSplitIntoLines() {
        let sha = String(repeating: "a", count: 40)
        let text = "      - uses: actions/checkout@\(sha) # v4.4.0\r\n      - uses: actions/cache@\(sha)\r\n"
        let found = Self.usesValues(in: text)
        XCTAssertEqual(found.map(\.line), [1, 2], "CRLF 檔要切成兩行")
        XCTAssertEqual(found.map { Self.isPinned(value: $0.value, line: $0.raw) }, [true, false],
                       "第二行沒有版本註解——不得借用第一行的註解過關")
    }

    func testRecognitionAndPinningCases() {
        let sha = String(repeating: "a", count: 40)
        let text = [
            "      - uses: actions/checkout@\(sha) # v4.4.0",
            "      - uses: actions/checkout@v4",
            "      - \"uses\": actions/cache@v4",
            "      - {uses: actions/cache@v4, with: {path: x}}",
            "      - uses: './.github/actions/local'",
            "      - uses: docker://alpine:3",
            "      - uses: docker://alpine@sha256:\(String(repeating: "b", count: 64))",
            "      - uses: actions/checkout@\(sha)",
            "      # - uses: actions/checkout@v4",
            "      - uses: actions/setup@\(sha) # v1\r",
        ].joined(separator: "\n")
        let found = Self.usesValues(in: text)
        XCTAssertEqual(found.map(\.value), [
            "actions/checkout@\(sha)", "actions/checkout@v4", "actions/cache@v4", "actions/cache@v4",
            "./.github/actions/local", "docker://alpine:3",
            "docker://alpine@sha256:\(String(repeating: "b", count: 64))",
            "actions/checkout@\(sha)", "actions/setup@\(sha)",
        ], "註解行不算；CRLF 的 \\r 不進值")
        XCTAssertEqual(found.map { Self.isPinned(value: $0.value, line: $0.raw) },
                       [true, false, false, false, true, false, true, false, true],
                       "標籤、flow-style、加引號的鍵都要被抓到；本機 action 放行；docker 要 digest；SHA 沒有版本註解不算")
    }
}
