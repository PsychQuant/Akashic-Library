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

// **執行期證據**（#707）：`AKASHIC_GUARD_RUN_LOG` 設定時，這個行程在分派之前寫一筆 `start`，經 `finishGuard` 結束時寫 `end`。
// `migrated-guard-control` 讀這份紀錄判定「這次跑了哪些守衛、哪支負控真的讓它們變紅過」——不讀任何原始碼。
// 下面每個分派都走 `finishGuard(...)` 而不是 `exit(...)`：直接 `exit` 的行程沒有 `end`，它執行過的東西不算數。
recordGuardStart()

switch args[1] {
case "zero-instance-rows-audit":
    finishGuard(zeroInstanceRowsAudit())
case "__shlex-probe":   // 內部：tokenizer 對照用，不在 run-guards 裡
    while let line = readLine(strippingNewline: true) {
        if line.isEmpty { continue }
        if let t = try? shellLex(line) { print(t.joined(separator: "\u{1F}")) }
        else { print("<ValueError>") }
    }
    finishGuard(0)
case "protected-ratchet":
    finishGuard(protectedRatchet(argv: Array(CommandLine.arguments.dropFirst(2))))
case "workflow-run-scripts":
    finishGuard(workflowRunScriptsGuard())
case "trigger-coverage":
    finishGuard(triggerCoverage(argv: Array(CommandLine.arguments.dropFirst(2))))
case "rule-prose-guards":
    finishGuard(ruleProseGuards(argv: Array(CommandLine.arguments.dropFirst(2))))
case "measured-claims-audit":
    finishGuard(measuredClaimsAudit())
case "migrated-guard-control":   // #707：讀 `--log` 指的執行紀錄（run-guards.sh 最後一行才跑它）
    finishGuard(migratedGuardControl(argv: Array(CommandLine.arguments.dropFirst(2))))
case "migrated-guard-control-mutations":   // #707：它的負控——迷你 runner、掏空的 scratch 建置、改壞的紀錄
    finishGuard(migratedGuardControlMutations())
case "spawn-probe":   // #707：內部——`runGuardProcess` 對沒跑起來的子行程怎麼記（不在 run-guards 裡，由上一支帶自己的紀錄檔執行）
    finishGuard(spawnProbe())
case "decision-matrix-mutations":
    finishGuard(decisionMatrixMutations())
case "rule-prose-guards-mutations":
    finishGuard(ruleProseGuardsMutations())
case "trigger-coverage-mutations":
    finishGuard(triggerCoverageMutations())
case "plugin-roots":   // #625：plugin 根目錄的唯一來源，給 shell 端用
    finishGuard(pluginRootsCommand())
case "official-validate":   // #625：claude plugin validate ＋ 只有一項的封閉允許清單
    finishGuard(officialValidate())
case "official-validate-mutations":   // #689：假的 claude 印出錯的報告，official-validate 會紅嗎
    finishGuard(officialValidateMutations())
case "marketplace-consistency":   // #625：plugin 根與 marketplace manifest 雙向一致
    finishGuard(marketplaceConsistency())
case "plugin-roots-mutations":   // #625：plugin/ 以外的 plugin 根，守衛看得見嗎
    finishGuard(pluginRootsMutations())
case "plugin-store-format-parity":   // #408／#629：宣告的 store format 必須等於 StoreVersion.supported
    finishGuard(pluginStoreFormatParity())
case "rule-coverage":   // #407／#629：plugin 根的每條規則被每個 skill 掛到（`rule-coverage [plugin-root]`）
    finishGuard(ruleCoverage(argv: Array(CommandLine.arguments.dropFirst(2))))
case "network-confinement":   // #664：網路與 keychain API 只准出現在 Sources/AkashicS2/
    finishGuard(networkConfinement())
case "network-confinement-mutations":   // #664：九個字樣各注入一次，守衛會紅嗎
    finishGuard(networkConfinementMutations())
case "audit-guards-mutations":
    finishGuard(auditGuardsMutations())
case "oracle-precondition-control":
    finishGuard(oraclePreconditionControl())
case "measured-numbers-audit":
    finishGuard(measuredNumbersAudit())
case "backlink-field-ratchet":
    finishGuard(backlinkFieldRatchet())
case "parity-table-drift":
    finishGuard(parityTableDrift())
case "decision-matrix-drift":
    // 第二個參數可覆寫要讀的 markdown——**唯一的用途是負控**（在 pristine copy 上
    // mutate，不得就地改出貨檔）。由 `decision-matrix-mutations.py` 實際行使。
    finishGuard(decisionMatrixDrift(args.count > 2 ? args[2] : nil))
default:
    // **不預設通過**：未知名字回非零。一個打錯的守衛名若靜默回 0，
    // `run-guards.sh` 會照樣往下跑而那一格等於不存在。
    FileHandle.standardError.write(Data("✗ 未知的守衛：\(args[1])\n".utf8))
    exit(64)
}
