// `akashic-guards <name>` —— 守衛的 Swift 實作（#433）。
//
// **為什麼是一個 executable ＋ 子命令，而不是 21 個 target**：21 個 target 會讓
// `Package.swift` 與建置時間都不成比例地成長，而每支守衛的入口都只是「讀幾個檔、
// 印判定、回 exit code」。共用一個 process 也讓它們能共用下面那組小工具。
//
// **`run-guards.sh` 是唯一的呼叫點**（#432）：那裡一行 `python3 X.py` 換成
// `.build/debug/akashic-guards X`，hook 與 CI 因此同時切換。
//
// ## 遷移紀律（#433）
//
// 每一支的 Swift 版都要對照 **`guards-python-final`** 這個 tag 的 Python 版：
// 乾淨樹上同 verdict、既有負控下兩版都紅、**同一批 mutation 上逐一比對**，
// 以及**各自對照該守衛明說的契約**（第 3b 步——刺激意義相同不蘊含意義相同）。

import Foundation

// MARK: - 共用的最小工具

/// 判定累積器。**印出來的每一行都是一個可否證的宣稱**，而不是進度回報。
struct Verdict {
    private var failures: [String] = []
    private(set) var checks = 0

    mutating func check(_ ok: Bool, _ whenFalse: @autoclosure () -> String) -> String {
        checks += 1
        if ok { return "✓" }
        failures.append(whenFalse())
        return "✗"
    }

    /// 具名列出不成立的宣稱後回 1；全成立回 0。
    /// **不印「全部通過」以外的成功摘要**——那會讓輸出隨守衛數量膨脹（#394 R9 的
    /// pipe 死鎖正是輸出成長越過 8 KB 造成的）。
    func exitCode(_ summary: String) -> Int32 {
        if failures.isEmpty {
            FileHandle.standardOutput.write(Data("══ \(summary) ══\n".utf8))
            return 0
        }
        var out = "══ \(failures.count) 個宣稱不成立 ══\n"
        for f in failures { out += "  ✗ \(f)\n" }
        FileHandle.standardError.write(Data(out.utf8))
        return 1
    }
}

/// repo 根目錄。**由 cwd 決定**——`run-guards.sh` 保證在根目錄執行，
/// 而寫死路徑會讓守衛在 worktree（#433 的 oracle 比對要用）裡指到錯的地方。
let repoRoot = FileManager.default.currentDirectoryPath

func readFile(_ rel: String) -> String? {
    try? String(contentsOfFile: "\(repoRoot)/\(rel)", encoding: .utf8)
}

// MARK: - regex 小工具
//
// **每支守衛都在做同一件事**：抽 capture group、數命中。寫成共用的三個函式，
// 而不是每支各自 `try!` 一次——那會讓「regex 寫錯」的失敗方式在每支各不相同。

func matches(_ s: String, _ pattern: String, multiline: Bool = false,
             dotAll: Bool = false) -> [NSTextCheckingResult] {
    var opts: NSRegularExpression.Options = []
    if multiline { opts.insert(.anchorsMatchLines) }
    if dotAll { opts.insert(.dotMatchesLineSeparators) }
    guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return [] }
    return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
}

/// 每個命中的第 1 個 capture group。
func captures(_ s: String, _ pattern: String, multiline: Bool = false,
              dotAll: Bool = false) -> [String] {
    let ns = s as NSString
    return matches(s, pattern, multiline: multiline, dotAll: dotAll).compactMap {
        $0.numberOfRanges > 1 && $0.range(at: 1).location != NSNotFound
            ? ns.substring(with: $0.range(at: 1)) : nil
    }
}

/// 第一個命中的第 1 個 capture group；沒命中回 nil。
func firstGroup(_ s: String, _ pattern: String, multiline: Bool = false,
                dotAll: Bool = false) -> String? {
    captures(s, pattern, multiline: multiline, dotAll: dotAll).first
}

func swiftSources() -> [String] {
    guard let e = FileManager.default.enumerator(atPath: "\(repoRoot)/Sources") else { return [] }
    return e.compactMap { ($0 as? String).flatMap { $0.hasSuffix(".swift") ? "Sources/\($0)" : nil } }
}

// MARK: - 分派

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("用法：akashic-guards <守衛名>\n".utf8))
    exit(64)
}

switch args[1] {
case "zero-instance-rows-audit":
    exit(zeroInstanceRowsAudit())
case "__shlex-probe":   // 內部：tokenizer 對照用，不在 run-guards 裡
    while let line = readLine(strippingNewline: true) {
        if line.isEmpty { continue }
        if let t = try? shellLex(line) { print(t.joined(separator: "\u{1F}")) }
        else { print("<ValueError>") }
    }
    exit(0)
case "trigger-coverage":
    exit(triggerCoverage(argv: Array(CommandLine.arguments.dropFirst(2))))
case "rule-prose-guards":
    exit(ruleProseGuards(argv: Array(CommandLine.arguments.dropFirst(2))))
case "measured-numbers-audit":
    exit(measuredNumbersAudit())
case "backlink-field-ratchet":
    exit(backlinkFieldRatchet())
case "parity-table-drift":
    exit(parityTableDrift())
case "decision-matrix-drift":
    // 第二個參數可覆寫要讀的 markdown——**唯一的用途是負控**（在 pristine copy 上
    // mutate，不得就地改出貨檔）。由 `decision-matrix-mutations.py` 實際行使。
    exit(decisionMatrixDrift(args.count > 2 ? args[2] : nil))
default:
    // **不預設通過**：未知名字回非零。一個打錯的守衛名若靜默回 0，
    // `run-guards.sh` 會照樣往下跑而那一格等於不存在。
    FileHandle.standardError.write(Data("✗ 未知的守衛：\(args[1])\n".utf8))
    exit(64)
}
