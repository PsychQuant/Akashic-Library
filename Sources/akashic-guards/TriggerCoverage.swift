// 每個受保護的檔案，改動時真的會有讀它的守衛跑起來嗎？
//
// **判準是逐對的，不是聯集的。** `census-parity.yml` 自己的檔頭寫著：
//
//   > 兩個檔案的註解都寫「兩者合起來涵蓋五支」。那句話在「檔案集合的聯集」意義上
//   > 成立，在「任一次變更」意義上不成立——而後者才是觸發點要保證的事。
//
// 所以：對每個受保護檔案 f、每個讀 f 的守衛 g，必須存在一個 workflow 同時
// (a) 在 f 改動時觸發、(b) 執行 g。
//
// **三個踩過的坑**（都在寫這支腳本的當天，#407 R19）：
//   1. **憑記憶寫路徑**——受保護清單裡寫了 `Sources/AkashicCore/StoreVersion.swift`，
//      真實位置是 `Sources/AkashicStoreIO/`。一個指不到東西的守衛比沒有守衛更糟。
//   2. **regex 漏掉 YAML anchor**——`paths: &parity_paths` 不匹配 `paths:$`。
//   3. **「讀取」的謂詞太寬**——拿整個檔案比 basename，「註解裡提到姊妹 harness」
//      被算成「讀取它」。現在先剝註解行。

import Foundation

// ── glob / fnmatch ───────────────────────────────────────────────────────
// Python 的 `fnmatch.fnmatch` 在 POSIX 上等價於 `fnmatch(p, s, 0)`——`*` 會跨越
// `/`（沒有 FNM_PATHNAME），這正是 `plugin/skills/*/scripts/tests/*.sh` 這類
// pattern 需要的語意。
func globMatch(_ path: String, _ pattern: String) -> Bool {
    fnmatch(pattern, path, 0) == 0
}

/// repo-relative 的 glob，回傳排序後的相對路徑。
///
/// **只走訪「第一個萬用字元之前」的目錄前綴，不是整個 repo。** 天真的全樹 enumerate 在
/// 這個 repo 要 **1.7 秒一次**——`.claude/worktrees/` 有 2.0 GB／25,519 個檔（IDD 的隔離
/// 工作樹）。`.claude/rules/*.md` 的答案完全落在一個 144 KB 的目錄裡，沒有理由為它走遍
/// 那 2 GB；而 `trigger-coverage` 一支就呼叫本函式五次以上。
func globFiles(_ pattern: String) -> [String] {
    let segs = pattern.components(separatedBy: "/")
    let fixed = Array(segs.prefix(while: { !$0.contains("*") && !$0.contains("?") }))
    if fixed.count == segs.count {          // 沒有萬用字元——就是一個路徑
        return fileExists(pattern) ? [pattern] : []
    }
    let prefix = fixed.joined(separator: "/")
    let root = prefix.isEmpty ? repoRoot : "\(repoRoot)/\(prefix)"
    let rel = { (p: String) in prefix.isEmpty ? p : "\(prefix)/\(p)" }
    var out: [String] = []
    if fixed.count == segs.count - 1 {      // 只有最後一段有萬用字元：不必遞迴
        for f in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] {
            if globMatch(rel(f), pattern) { out.append(rel(f)) }
        }
    } else {
        guard let e = FileManager.default.enumerator(atPath: root) else { return [] }
        for case let p as String in e {
            let r = rel(p)
            // `.build` 與 `.git` 底下沒有受保護檔，跳過可省下大量走訪
            if r.hasPrefix(".build") || r.hasPrefix(".git/") { e.skipDescendants(); continue }
            if globMatch(r, pattern) { out.append(r) }
        }
    }
    return out.sorted()
}

func fileExists(_ rel: String) -> Bool {
    FileManager.default.fileExists(atPath: "\(repoRoot)/\(rel)")
}

func rawFile(_ rel: String) -> String {
    (try? String(contentsOfFile: "\(repoRoot)/\(rel)", encoding: .utf8)) ?? ""
}

func base(_ p: String) -> String { (p as NSString).lastPathComponent }
func dirOf(_ p: String) -> String { (p as NSString).deletingLastPathComponent }

// ── 剝註解（坑 3）─────────────────────────────────────────────────────────
/// 剝掉整行註解與行尾註解。
///
/// **`.swift` 的行尾 `//` 先前不剝**，而 docstring 說剝——一句沒被量測過的斷言，
/// 出現在一支為了防那件事而寫的腳本裡（#407 R20）。量測顯示當下零實例，但成本是
/// 一個分支，而「零實例、成本一行、前件精確」在 `zero-instance-guards` 第 1 列是「寫」。
func codeOnly(_ rel: String) -> String {
    var out: [String] = []
    for var line in rawFile(rel).components(separatedBy: "\n") {
        let s = line.drop(while: { $0 == " " || $0 == "\t" })
        if s.hasPrefix("#") || s.hasPrefix("//") { continue }
        if rel.hasSuffix(".sh") || rel.hasSuffix(".py") {
            if let r = line.range(of: " # ") { line = String(line[..<r.lowerBound]) }
        } else if rel.hasSuffix(".swift") {
            if let r = line.range(of: " // ") { line = String(line[..<r.lowerBound]) }
        }
        out.append(line)
    }
    return out.joined(separator: "\n")
}

/// `paths:` / `paths-ignore:` 底下的清單。**anchor 形式也要認**（坑 2）。
func yamlPaths(_ rel: String) -> [String: [String]] {
    let text = rawFile(rel)
    var got: [String: [String]] = [:]
    for key in ["paths", "paths-ignore"] {
        let re = "(?m)^[ \\t]*\(key):[ \\t]*(?:&\\w+)?[ \\t]*$((?:\\n[ \\t]*(?:#.*|-.*))+)"
        if let m = matches(text, re).first {
            let block = (text as NSString).substring(with: m.range(at: 1))
            got[key] = matches(block, #"(?m)^\s*-\s*(.+)$"#).map {
                (block as NSString).substring(with: $0.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        } else { got[key] = [] }
    }
    return got
}

func pathsMatch(_ patterns: [String], _ f: String) -> Bool {
    patterns.contains { globMatch(f, $0) || ($0.hasSuffix("/**") && f.hasPrefix(String($0.dropLast(2)))) }
}

// ── workflow 裡**真的被執行**的腳本檔名 ─────────────────────────────────
//
// **判準是命令位置，不是同一行出現。** 上一版匹配 `run:` 之後同一行的任何檔名，
// 於是 `run: echo "見 plugin/tests/rule-coverage.sh 的說明"` 會讓它被算成執行了
// ——實測把一個真的 run 步驟換成那行 echo，守衛照樣報綠（#407 R20）。
//
// **真實輸入集合已量過**（2026-08-22，#407 R23e，數字於 R24d 更正）：三個 workflow
// 共 19 行 `run:`（13 行單行——其中 10 行是 `<直譯器> <腳本>`、2 行 `swift build`、
// 1 行 `swift --version`——加 6 行 block scalar）。也就是說下面為 `||`／管線／
// `FOO=1 bash`／`cat X | bash` 寫的分支**在真實輸入上一次都沒走過**。寫下來不是要
// 刪掉它們（workflow 會改），是讓下一個維護者知道**哪些路徑只由負控保證**。
func invoked(_ text: String) -> Set<String> {
    var found = Set<String>()
    var blocks: [String] = [], chained: [String] = [], conditional: [String] = []

    // **block scalar 的續行也要讀**（#407 R43）。先前只讀單行形式並把「讀不到續行」
    // 寫成揭露——而揭露擋不住它咬人：把一個守衛改成區塊形式呼叫，覆蓋表立刻報 11 個
    // 缺口，而那個呼叫其實就寫在區塊裡。
    let srcLines = text.components(separatedBy: "\n")
    var expanded: [String] = []
    var i = 0
    while i < srcLines.count {
        let line = srcLines[i]
        if let m = matches(line, #"^(\s*)(?:-\s*)?run:\s*(.+)$"#).first,
           (line as NSString).substring(with: m.range(at: 2))
               .trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            let indent = (line as NSString).substring(with: m.range(at: 1)).count
            blocks.append(line)
            i += 1
            var heredoc: String? = nil      // heredoc 的結束字，nil ＝ 不在 heredoc 內
            while i < srcLines.count {
                let nxt = srcLines[i]
                let trimmed = nxt.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && (nxt.count - nxt.drop(while: { $0 == " " || $0 == "\t" }).count) <= indent { break }
                if let h = heredoc {
                    // **heredoc 主體是被寫進檔案的字面文字，不是被執行的命令**（#407 R44）。
                    // 不跳過的話，`cat > w.sh <<'EOF' … python3 plugin/tests/X.py … EOF`
                    // 會讓 X.py 被算成「CI 有跑」——**假綠**，方向與本函式其餘部分刻意
                    // 選的漏報相反，所以要特別擋。
                    if trimmed == h { heredoc = nil }
                    i += 1
                    continue
                }
                // 結束字要**整個**抓到。上一版 `[A-Za-z0-9_]*` 在第一個非字元停住，
                // 於是 `<<SETUP-EOF` 只抓到 `SETUP`、結束行永遠對不上，其後**整段被
                // 當成 heredoc 吞掉**——真的呼叫因此隱形（#407 R45）。
                if let hm = matches(trimmed, #"<<-?\s*(?:'([^']+)'|"([^"]+)"|([A-Za-z_][A-Za-z0-9_.-]*))"#).first {
                    let ns = trimmed as NSString
                    for g in 1...3 where hm.range(at: g).location != NSNotFound {
                        heredoc = ns.substring(with: hm.range(at: g)); break
                    }
                }
                if !trimmed.isEmpty { expanded.append("run: " + trimmed) }
                i += 1
            }
            continue
        }
        expanded.append(line)
        i += 1
    }

    for line in expanded {
        guard let m = matches(line, #"^\s*(?:-\s*)?run:\s*(.+)$"#).first else { continue }
        let cmd = (line as NSString).substring(with: m.range(at: 1))
            .trimmingCharacters(in: .whitespaces)
        if cmd == "|" || cmd.hasPrefix("|") { continue }
        // **只認第一個 token。** 上一版對 `./X` 分支仍掃全行，於是
        // `run: echo "見 ./rule-coverage.sh"` 照樣被算成執行了它（#407 R20c）。
        // 代價是 `cd A && bash X` 會漏——**方向是漏報**，讓守衛紅而非假綠。
        let tokens = (try? shellLex(cmd)) ?? cmd.split(separator: " ").map(String.init)
        if tokens.isEmpty { continue }

        // **記住每段前面的分隔符——`||` 的語意與其他三個不同。**
        // `bash A || bash B` 的 B **只在 A 失敗時跑**。R22c 把 `||` 加進切分符時
        // 讓兩段同等對待，於是 B 被算成「執行了」——而在正常（綠）的 CI 狀態下它
        // 根本不跑（#407 R23，跨模型審查的 logic 席指名）。
        var segments: [(String?, [String])] = []
        var cur: [String] = []
        var sep: String? = nil
        for tok in tokens {
            if ["&&", "||", ";", "|"].contains(tok) {
                segments.append((sep, cur)); cur = []; sep = tok
            } else { cur.append(tok) }
        }
        segments.append((sep, cur))
        segments = segments.filter { !$0.1.isEmpty }

        // **認出「執行的形式」，不列舉「不執行的命令」。** 上一版維護一份 NON_EXEC
        // 白名單，那是在用封閉列舉描述一個**開放集合**——實測 13 個常見 CI 命令全部
        // 觸發假警報（`grep -n`／`shellcheck`／`wc -l`／`chmod +x`／`git add`／`cp`…）。
        // 每加一個進白名單，下一個仍在外面（#407 R22d）。
        let INTERP = ["bash", "sh", "python3", "python", "swift"]
        for (sepBefore, st) in segments {
            let h = st[0]
            // **`||` 有兩種讀法，靜態判不出是哪一種**（#407 R23d）：
            //   error-fallback：`main || handle_failure`      → RHS 只在失敗時跑
            //   **skip-flag**：`[ -f .done ] || bash setup.sh` → RHS **每次都跑**
            // 判不出來就不假裝判得出來：不計入覆蓋（寧可假紅不可假綠），但訊息要說明
            // 它**可能是假警報**，由人裁決。
            if sepBefore == "||" {
                if st.contains(where: { INTERP.contains($0) || $0.hasPrefix("./") })
                    || st.contains(where: { !matches($0, #"\S+\.(?:sh|py|swift)\b"#).isEmpty }) {
                    conditional.append(st.joined(separator: " "))
                }
                continue
            }
            if INTERP.contains(h) {
                // 跳過旗標找腳本（`bash -x a.sh` 是常見的除錯形式）。
                // `-m` 例外：`python3 -m mod x.py` 跑的是模組，x.py 是它的引數。
                if !st.contains("-m") {
                    if let script = st.dropFirst().first(where: {
                        !$0.hasPrefix("-") && ($0.hasSuffix(".sh") || $0.hasSuffix(".py") || $0.hasSuffix(".swift"))
                    }) { found.insert(base(script)); continue }
                }
                // **只有在管線下游才是 stdin 執行。** 判準是**位置**不是旗標列舉：
                // `cat d.sh | bash` 的 bash 有來源，`bash --version` 沒有。上一版問
                // 「引數裡有沒有非旗標的東西」，於是 `bash --version`／`python3 -V`
                // 這些 CI 極常見的環境檢查全部被當成 stdin 執行而印假警報（#407 R23b）。
                // 用旗標白名單修是錯的方向——那正是 R22d 剛從 NON_EXEC 拆掉的開放集合形狀。
                if sepBefore == "|" && !st.dropFirst().contains(where: { !$0.hasPrefix("-") }) {
                    chained.append(st.joined(separator: " ")); continue
                }
                continue    // `-m` 或引數裡沒有腳本——跑的不是我們關心的東西，靜默
            }
            if h.hasPrefix("./") && (h.hasSuffix(".sh") || h.hasSuffix(".py") || h.hasSuffix(".swift")) {
                found.insert(base(h)); continue
            }
            // head 不是直譯器。只有當**段內**仍出現直譯器 token 時，才可能有一個
            // 我們看不到的執行（`FOO=1 bash a.sh`、`env bash a.sh`）。
            if st.dropFirst().contains(where: { INTERP.contains($0) }) {
                chained.append(st.joined(separator: " "))
            }
        }
    }

    if !conditional.isEmpty {
        // **逐筆具名，不彙總。**（#407 R24，DA 席的 cry-wolf 論證）上一版印一則不指名
        // 的旁白，而主判定訊息在「真的是例外路徑」與「skip-flag 幾乎必跑」兩種情況下
        // **完全相同**。人看過幾次假警報之後，會學會對所有帶 ℹ 的判定一起打折扣。
        print("   ℹ `||` 後的段（語意靜態判不出，保守不計入覆蓋）：")
        for c in conditional { print("      · \(c)") }
        print("      ↑ 可能是例外路徑（`main || handle_failure`，缺口為真），"
              + "也可能是正常路徑（`[ -f flag ] || do_work`，LHS 通常為假 → "
              + "**缺口是假警報**）。逐筆確認上面那幾行，或改寫成 `&&`／分行")
    }
    if !chained.isEmpty {
        // `cd A && bash X` 這類串接：第一個 token 不是直譯器，所以認不出來。**方向是
        // 漏報**（守衛會紅、不會假綠），但仍要印——R20c 才立下的原則是「寫在註解裡的
        // 已知限制，對讀輸出的人等於沒人知道」（#407 R20e）。
        print("   ℹ 有 \(chained.count) 個串接段帶著腳本檔名卻認不出執行形式"
              + "（變數展開、前置賦值等）——那些呼叫看不到（漏報，會讓守衛紅）")
    }
    if !blocks.isEmpty {
        print("   ℹ 有 \(blocks.count) 個 `run: |` 區塊，續行已展開後逐行解析（#407 R43）；"
              + "仍不解析 shell 控制流（`if`／`case` 內的分支一律當成會執行）——"
              + "若守衛改用區塊形式呼叫，這裡會看不到它（漏報，會讓守衛紅）")
    }
    // **Swift 版守衛的呼叫算數**（#433）：遷移期間 `plugin/tests/X.py` 仍在樹裡當
    // oracle，而呼叫的是 `.build/debug/akashic-guards X`。本函式以**檔名**辨識守衛，
    // 所以要把子命令名翻回 `X.py`——否則每遷一支就多一個假缺口。
    //
    // **翻回 `.py` 而不是新增一個 Swift 守衛清單**：`plugin/tests/X.py` 在整個遷移期間
    // 都是那支守衛的**身分**，直到它被刪除為止。
    //
    // ⚠ **刪除 Python 之前必須改這裡與 `GUARDS`**——見 #433 的 comment：`GUARDS` 是
    // glob `plugin/tests/*.py` 得出的，所以刪檔會讓那支守衛**整個離開覆蓋表**（實測
    // 21 支 → 6 支），而輸出仍印 `✓ 涵蓋 6/6`。「不留孤兒」為真，但保護範圍會安靜縮小。
    for m in matches(text, #"akashic-guards\s+([A-Za-z0-9_-]+)"#) {
        let sub = (text as NSString).substring(with: m.range(at: 1))
        found.insert(sub + ".py")                  // 遷移期：Python 版仍是那支守衛的身分
        found.insert(pascal(sub) + ".swift")       // 刪掉 Python 之後這一個接手
    }
    return found
}

/// Python `os.path.dirname` 的語意：最後一個 `/` 之前的部分，沒有 `/` 則空字串。
///
/// **不能用 `NSString.deletingLastPathComponent`**：它對 `a/b/` 回 `a`，Python 回
/// `a/b`。宣告的 glob 可以寫成 `plugin/tests/`（`DECLARE` 的 `(\S+)` 照抓），所以
/// 這個差異是**可達的**，不是理論邊界。
private func pyDirname(_ p: String) -> String {
    guard let i = p.lastIndex(of: "/") else { return "" }
    return String(p[p.startIndex..<i])
}

/// `measured-numbers-audit` → `MeasuredNumbersAudit`（子命令名 ↔ 檔名的唯一對映）。
/// （`MigratedGuardControl` 也用它，故非 private。）
func pascal(_ sub: String) -> String {
    sub.components(separatedBy: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

/// **Swift 守衛的身分是 `main.swift` 的 dispatch 表，不是目錄 glob**（#433）。
///
/// `Sources/akashic-guards/` 裡有三個**不是守衛**的檔案：`main.swift`（dispatch）、
/// `ShellLex.swift`（共用工具）、`BacklinkRatchetData.swift`（生成的資料）。glob 會把它們
/// 一起收進來，而 `case "X":` 是「它是一支守衛」的定義——比檔案存在準。
///
/// **為什麼非加不可**：`GUARDS` 原本只 glob `plugin/tests/*.{sh,py}`，所以 Python 版一刪，
/// 那支守衛就**整個離開覆蓋表**——不是留下壞掉的條目，是消失。實測 21 支 → 6 支，
/// 而輸出仍印 `✓ pre-push 涵蓋 6/6 支守衛`。
private func swiftGuards() -> [String] {
    let main = "Sources/akashic-guards/main.swift"
    guard fileExists(main) else { return [] }
    let src = rawFile(main)
    var out: [String] = []
    for m in matches(src, #"(?m)^\s*case "([a-z][a-z0-9-]*)":"#) {
        let sub = (src as NSString).substring(with: m.range(at: 1))
        let p = "Sources/akashic-guards/" + pascal(sub) + ".swift"
        if fileExists(p) { out.append(p) }
    }
    return out
}

func triggerCoverage(argv: [String]) -> Int32 {
    // 生成器不是守衛——它由 hash-table-drift.sh 呼叫，自己不做斷言。
    let GENERATORS: Set<String> = ["derive-hash-extenders.swift"]
    let GUARDS = ((globFiles("plugin/tests/*.sh") + globFiles("plugin/tests/*.py")
        + globFiles("plugin/skills/*/scripts/tests/*.sh")
        + globFiles("plugin/skills/*/scripts/tests/*.py")
        + globFiles("plugin/skills/*/scripts/tests/*.swift"))
        .filter { !GENERATORS.contains(base($0)) } + swiftGuards()).sorted()

    // 守衛之外，還被守衛讀的東西。**每一條都必須存在**（坑 1）。
    var DATA = [
        "plugin/skills/akashic-promote-literals/scripts/literal-census.sh",
        "plugin/skills/akashic-promote-literals/scripts/hash-merging-ranges.txt",
        "plugin/skills/akashic-promote-literals/scripts/tests/derive-hash-extenders.swift",
        // ── 以下八條是 #518 補進來的 ─────────────────────────────────────────
        //
        // **為什麼是顯式條目而不是放寬 glob。** 兩個方案各有一個沉默方向：
        //   · 顯式條目 —— 新增（守衛開始讀一個沒被保護的檔）靜默 ← 就是 #518
        //   · 放寬 glob —— 刪除（受保護檔被刪掉）靜默；glob 只是回傳更少的檔，
        //     而 `#433` 的註解已記過同型：「刪檔會讓那支守衛整個離開覆蓋表，
        //     而輸出仍印 ✓ 涵蓋 6/6」
        // 裁決：**顯式條目 ＋ 一道會紅的檢查**（下方「守衛讀的檔必須在受保護集合」）。
        //
        // **但「兩個方向都不沉默」是假的。** 那句話是 #518 的第一版寫在這裡與 changelog
        // 裡的，被 R1 verify 的 Devil's Advocate 用實測推翻、coordinator 獨立重現。三個量測：
        //
        //   1. **刪檔方向只涵蓋顯式字面。** `missing`（下方）檢查的是「清單裡列的路徑還在
        //      不在磁碟上」，而 glob 產生的成員永遠不會「列了卻不存在」——它只會變少。
        //      `PROTECTED` 的 55 條組成（實測，#521 後）：**顯式 20**、`GUARDS` **23**
        //      （**7 個 glob ＋ 16 個由 `swiftGuards()` 解析 `main.swift` 的 `case` 分派**——
        //      不是「整組 glob」，那是本檔上一版寫錯的機制描述）、rules glob **12**
        //      （`.claude/rules/*.md` 11 ＋ `plugin/rules/*.md` 1）。
        //      **這道守衛自己對 32 條刪檔沉默**（35 條 glob 成員裡 3 條會出聲：
        //      `entity-backlink-completeness.md` 與 `mcp-cli-parity.md` 被**具名宣告**指到、
        //      `assertions-must-be-measured.md` 是 `plugin/rules/*.md` 的唯一成員故 glob 解析到零）。
        //      實測刪掉一整支守衛 `plugin/tests/review-claim-audit.sh` → 守衛 23→22、
        //      **rc=0、照印「無缺口」**。
        //
        //      **但「32 條可以無聲消失」對整條 pre-push 是過度悲觀的**（R2 verify 更正）：
        //      那 32 條裡 **23 條在 pre-push 的別的階段是大聲的**——16 支 Swift 守衛的檔一刪，
        //      `main.swift` 的 `case` 分派就找不到符號、`swift build` 直接失敗（pre-push 第一
        //      階段就是它）；7 支腳本守衛一刪，`run-guards.sh` 以路徑呼叫它們、rc=127。
        //      **整條 pre-push 都靜默的只剩 9 個 `.claude/rules/*.md`（9/55，16%）。**
        //
        //   2. **「從 `DATA` 拿掉一條」與「檔案被刪掉」是兩件事**，而前者只有在**某支守衛的
        //      程式碼裡有那條路徑的引號字面**時才會紅。實測 20 條顯式條目裡 **10 條看不見**。
        //      **`MarkerParityMutationsData.swift` 是最尖的一格**：它是本輪自己補進來的、
        //      是真依賴（`RuleProseGuards.swift:285` 真的讀它），而拿掉它一聲不吭——
        //      #518 的標題所描述的形狀，發生在 #518 自己修完之後、在它自己加的條目上。
        //
        //      **10/20 這個比例比修法前更差，而那是本輪自己造成的**：R2 補進來的那 5 條
        //      （下方 `AuditGuardsMutationsData` 那一段）唯一的讀者就是那個**不被掃描的資料
        //      檔**，所以它們一進來就全部落在盲區。修法前是 5/14。把它寫出來而不是只報
        //      「受保護 55」，因為後者看起來像單調的進步。
        //
        //   3. **新增方向只涵蓋「引號緊鄰完整路徑」的寫法。** 見下方檢查處的盲點清單。
        //
        // **裁決仍然成立，而且比上一版寫的更強**（R2 verify 更正——上一版寫「刪除那一軸兩案
        // 同樣沉默」，那是從「兩個方向都不沉默」過度擺盪到另一端，而且同樣沒量過 glob 那一側）：
        //   · **刪除軸**：顯式條目 **20/20 由 `missing` 逐條具名**；glob 成員 **0**
        //     （結構上不可能——glob 不會「列了卻不存在」）。顯式嚴格更優 20 個檔。
        //   · **新增軸**：同形放寬 glob（`plugin/skills/*/scripts/*.{sh,py}`）只涵蓋得到本輪
        //     8 個新檔裡的 **1 個**；要涵蓋 8/8 得同時放寬六條 glob 根、**156 個檔進
        //     `PROTECTED`**（54 → 191）。只放寬 `Sources/*/*.swift` 一條實跑就是
        //     **rc=1、受保護 172、72 條缺口**。
        // 兩軸都是顯式勝，所以裁決不必改；要改的是**別把它說成完整的保證**。
        //
        // 這裡選擇把覆蓋率降級成誠實的散文而不是當場補一道機制，理由**不是**「零實例」——
        // `GUARDS.count` 下降有實測前例，本檔 `#433` 那段就記著「21 支 → 6 支而輸出照印
        // ✓ 涵蓋 6/6」。真正的理由是：根治要先分開「守衛自己讀的路徑」與「注入用的 payload
        // 路徑」（見下方第六個盲點），那是判準問題不是一行改動。追蹤 #522。
        //
        // **量測（逐項，#518 R1 重量）**：這道檢查**自己**找出 **5 支守衛／8 對／7 個檔**；
        // 第 8 個檔 `MarkerParityMutationsData.swift` 是**照報表手補的**——它真正的讀者
        // `RuleProseGuards.swift:285` 把路徑組出來，引號不緊鄰，這道檢查看不到。
        // 合計 **6 支守衛／9 對／8 個相異檔**（`.githooks/run-guards.sh` 被兩支守衛引用，
        // 在對數裡算兩次、在檔數裡算一次）。受保護 41 → 49。
        // 手維護清單不自我維持，自此不再是推論而是 n=6 的量測。
        "plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py",
        "plugin/.claude-plugin/plugin.json",
        "Sources/akashic-mcp/Server.swift",
        "Sources/akashic/CLI.swift",
        "Sources/akashic-guards/MarkerParityMutationsData.swift",
        "Sources/akashic-guards/main.swift",
        ".githooks/run-guards.sh",
        // `mcpb/manifest.json` 這一條由新檢查自己找出來（立案時的手工掃描漏了那個路徑根）——
        // 而它是 store format 的**第三份宣告來源**、且是出貨物（`release-signed.sh`
        // 會 zip 進 `.mcpb`）。`census-parity.yml` 的 paths 早就列了它，逐對迴圈卻
        // 一直看不到這一對。檢查上線的第一次執行就抓到自己的作者漏掉的那一個。
        "mcpb/manifest.json",
        // ── R2 verify 找到的第六個盲點：守衛的**資料檔**完全不被掃描 ──────────
        //
        // 下方那道檢查只掃 `GUARDS`，而 `Sources/akashic-guards/*Data.swift`（四個：
        // `AuditGuardsMutations`／`BacklinkRatchet`／`MarkerParityMutations`／
        // `TriggerCoverageMutations`）**不是守衛**——`main.swift` 沒有對應的 `case`，
        // 所以整個檔一行都不會被看到。而 `AuditGuardsMutationsData.swift` 用
        // `AGMEdit(path: "…")` 逐字寫著 20 個路徑，其中 **5 個存在卻未受保護**。
        //
        // **這一格特別要記**：上面那份「五種寫法會靜默繞過」的清單**全部零實例**
        // （示範用的是構造出來的例子），而這第六種**今天就有 5 個實例**，且它們全都
        // 已在 `census-parity.yml` 的 `paths:` 裡——與 `mcpb/manifest.json` 完全同型。
        // 誠實邊界列滿了假想的洞，漏掉唯一一個真的。
        //
        // **為什麼不直接把 `*Data.swift` 納入掃描（那才是根治）**：
        // `TriggerCoverageMutationsData.swift` 裡有 `"Sources/akashic-guards/ShellLex.swift"`
        // ——那是**負控刻意選的、必須永遠不在 `PROTECTED` 的目標**。納入掃描會讓這支
        // 守衛因為自己的負控 payload 而永久變紅。要根治得先分開「守衛自己讀的路徑」與
        // 「注入用的 payload 路徑」，那是判準問題不是一行改動——#522。
        ".github/workflows/census-parity.yml",
        "Sources/AkashicCore/Models.swift",
        "Sources/AkashicCore/Temporal.swift",
        "Sources/akashic/CreateEntryCommand.swift",
        "plugin/skills/akashic-promote-literals/SKILL.md",
        // #521：`MeasuredClaimsAudit` 的檢查 ③ 改指向這裡之後，它成了一條**真依賴**
        // ——而新加的「檔案不存在」那一半正是靠它才把舊的死引用抓出來的。
        // 這也補上 #518 regression 席指出的不對稱：`MarkerParityMutationsData.swift`
        // 早就在表裡，它的姊妹檔卻不在（而本輪的 diff 就改了它）。
        "Sources/akashic-guards/TriggerCoverageMutationsData.swift",
    ]
    // **兩個 glob 根要對稱**（#407 R50）：`.claude/rules/*.md` 已升成 live glob，而
    // 這一側曾是單一寫死路徑。`plugin/rules/` 一長出第二個檔，`declared()` 就會再次
    // **少解析**——正是那次改動要修的病，只是換到另一側。
    DATA += globFiles("plugin/rules/*.md").sorted()
    DATA += ["Sources/AkashicStoreIO/StoreVersion.swift", "Sources/AkashicCore/Venue.swift"]
    // repo 規則檔是 `measured-numbers-audit` 的輸入（#407 R48）。先前不在此列，於是
    // 那支守衛對 `.claude/rules/*.md` 的宣告**解析不到任何受保護檔**——宣告寫了卻等於
    // 沒寫，而既有的「有宣告但解析不到」只在**全部**宣告都落空時才報。
    DATA += globFiles(".claude/rules/*.md").sorted()
    // CLAUDE.md 是資料而非守衛：`decision-matrix-drift` 拿它的決策矩陣當輸入（#407 R27）。
    DATA += ["CLAUDE.md"]

    var fails: [String] = []
    // ── 兩個出口的界線：**可判定性**，不是嚴重度（#407 R24c 量過並固化）──────
    //
    //   fails（6 條）    機械可判定的事實
    //     · 宣告解析不到任何受保護檔（機制失效）／宣告第一段是萬用字元（結構）
    //     · 多於一行宣告（計數）／宣告命中全部受保護檔（計數）
    //     · **改 X 時讀 X 的守衛不在任何 CI 跑**  ← 本腳本的核心職責
    //     · **守衛不在 pre-push 裡**              ← 本腳本的核心職責
    //
    //   warnings（2 條）  啟發式判斷，兩個方向都會錯
    //     · 宣告指向守衛自己所在的目錄／宣告的目錄名在原始碼裡沒有明顯痕跡
    //
    // **核心職責永遠在 fails 這一側。** 降級的不是嚴重度，是**我們有沒有能力判定**。
    // **警告與缺口分開**：把兩者混在同一個出口，會讓人對整份輸出一起打折扣（#407 R24）。
    var warnings: [String] = []

    // ── 前置：清單自己不得含不存在的路徑 ────────────────────────────────
    let missing = (GUARDS + DATA).filter { !fileExists($0) }
    if !missing.isEmpty {
        print("✗ 受保護清單裡有不存在的路徑（守衛指不到東西比沒有守衛更糟）：")
        for p in missing { print("    · \(p)") }
        return 1
    }
    let PROTECTED = Array(Set(GUARDS + DATA)).sorted()

    // ── 撞名消歧（#518）───────────────────────────────────────────────────
    //
    // 報表原本一律印 `base(f)`，而**守衛與它的被測檔可以同名**——
    // `plugin/tests/ndjson-abstracts-to-proposals.py`（守衛）與
    // `plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py`
    // （被測腳本）就是。同名時報表會印出兩列逐字相同的結果，而在被測檔還沒進
    // `PROTECTED` 的那段期間更糟：唯一那列是**守衛在保護它自己**，卻讀起來像被測檔被涵蓋了
    // ——缺口不是沉默，是**偽裝成一個通過**。
    //
    // 這份報表的價值全在人讀得懂（見上方「把它攤開來——讓漏掉的那條在人眼前缺席」），
    // 所以只修收錄而不修顯示，等於把隱形的缺口換成讀不懂的報表。
    // **只在撞名時**加後綴：不撞名的一律維持 basename，既有輸出寬度不變。
    let dupBases: Set<String> = {
        var c: [String: Int] = [:]
        for p in PROTECTED { c[base(p), default: 0] += 1 }
        return Set(c.filter { $0.value > 1 }.keys)
    }()
    func label(_ p: String) -> String {
        guard dupBases.contains(base(p)) else { return base(p) }
        let parts = p.components(separatedBy: "/")
        var n = 2
        while n < parts.count {
            let suffix = parts.suffix(n).joined(separator: "/")
            if PROTECTED.filter({ $0.hasSuffix("/" + suffix) || $0 == suffix }).count == 1 { return suffix }
            n += 1
        }
        return p
    }

    // **整行就是宣告**——行首是註解標記、行尾沒有別的東西。上一版是裸的子串，它認不出
    // 「這是宣告」與「這是在談論宣告」：一個把該字面寫進**字串**或 docstring 說明的檔案
    // 都會被算成有宣告。實測（#407 R21）：特例排除追不上，因為每個談論它的地方都會再撞
    // 一次。收窄謂詞才是根治。
    let DECLARE = #"^\s*(?:#|//)\s*trigger-coverage:\s*reads\s+(\S+)\s*$"#

    /// 守衛可以顯式宣告它讀什麼，補上啟發式看不見的依賴。
    ///
    /// **這裡刻意讀 raw file，不經 `codeOnly()`——那不是漏改，是必要的。** 宣告只能寫在
    /// 註解裡（寫在程式碼裡它就會被執行），所以讀宣告必須看得到註解；而 `codeOnly()`
    /// 服務的是另一個判定（「這個 basename 是真的被讀，還是只在註解裡被提到」）。
    /// 兩者對註解的態度相反是設計，把它們「統一」會讓宣告機制整個失效。
    func declared(_ path: String) -> Set<String> {
        var out = Set<String>()
        for line in rawFile(path).components(separatedBy: "\n") {
            guard let m = matches(line, DECLARE).first else { continue }
            let pat = (line as NSString).substring(with: m.range(at: 1))
            out.formUnion(PROTECTED.filter { globMatch($0, pat) })
        }
        return out
    }

    // **這是啟發式，而它的失敗方向是漏報**（#407 R20）：一個把路徑組出來的守衛不會讓
    // basename 逐字出現，於是那條依賴**整個不被考慮**。靜態分析救不了這件事，所以改為把
    // 它**攤開來**：下面印出每個守衛被判定讀了什麼，讓漏掉的那條在人眼前缺席。
    var READS: [String: Set<String>] = [:]
    for g in GUARDS {
        let code = codeOnly(g)
        READS[g] = Set([g]).union(declared(g))
            .union(PROTECTED.filter { code.contains(base($0)) })
    }

    var WORKFLOWS: [(name: String, paths: [String: [String]], runs: Set<String>)] = []
    for y in globFiles(".github/workflows/*.yml").sorted() {
        let text = rawFile(y)
        var inv = invoked(text)
        // **workflow 經 `run-guards.sh` 間接呼叫的守衛也算涵蓋**（#432）。第一版把腳本
        // 內容**串接進 workflow 文字**再交給 `invoked()`——那沒用，因為它解析的是 YAML 的
        // `run:` 行，而腳本裡是裸的 shell 命令。HOOK 那半能過是因為它用純子字串比對；
        // **同一個 indirection，兩種讀法，只有一種被我改對**（實測第一版：pre-push 21/21
        // 綠，而 CI 側 90 個缺口）。正確做法是擴充**回傳的集合**。
        //
        // **一層，不遞迴**：追蹤任意深度會讓「哪些守衛會跑」變成需要模擬 shell 的問題。
        if inv.contains("run-guards.sh") && fileExists(".githooks/run-guards.sh") {
            let rg = codeOnly(".githooks/run-guards.sh")
            for m in matches(rg, #"(?:python3|bash|swift)\s+(\S+\.(?:py|sh|swift))"#) {
                inv.insert(base((rg as NSString).substring(with: m.range(at: 1))))
            }
            // **Swift 版守衛也要展開**（#433）——腳本裡是 `.build/debug/akashic-guards X`，
            // 而 `invoked()` 只認 `<直譯器> <腳本>`。第三次補同一個 indirection。
            for m in matches(rg, #"akashic-guards\s+([A-Za-z0-9_-]+)"#) {
                let s = (rg as NSString).substring(with: m.range(at: 1))
                inv.insert(s + ".py"); inv.insert(pascal(s) + ".swift")
            }
        }
        WORKFLOWS.append((base(y), yamlPaths(y), inv))
    }

    // **也要剝註解。** 上一版這裡讀 raw text，而 `codeOnly()` 就在同一個檔案裡、正是為了
    // 修「坑 3」而寫的——READS 用了它，這裡沒用。**修了一半**（#407 R20）。
    //
    // **pre-push 的守衛清單住在 `run-guards.sh`**（#432）。hook 只呼叫它一行，所以只讀
    // hook 會判定「每一支都不在 pre-push 裡」。兩個檔都讀，因為 hook 本身仍可能直接列守衛。
    var HOOK = (fileExists(".githooks/pre-push") ? codeOnly(".githooks/pre-push") : "")
             + (fileExists(".githooks/run-guards.sh") ? codeOnly(".githooks/run-guards.sh") : "")
    // **Swift 版守衛的呼叫也算數**（#433）。HOOK 用純子字串比對，所以把子命令名補成
    // `X.py` 塞進這個字串即可。**兩種讀法各補一次**：#432 就是因為只改對一種而讓 CI 側
    // 漏了 90 格。
    //
    // （`HOOK += f(HOOK)` 在 Swift 是 exclusivity 衝突——`+=` 是 inout 存取而右側讀同一
    //   個變數。先算進臨時變數再併，這是 Swift 端才有的形狀，不是語意差異。）
    let hookSuffix = matches(HOOK, #"akashic-guards\s+([A-Za-z0-9_-]+)"#)
        .map { m -> String in
            let s = (HOOK as NSString).substring(with: m.range(at: 1))
            return "\n" + s + ".py" + "\n" + pascal(s) + ".swift"
        }.joined()
    HOOK += hookSuffix

    print("守衛 \(GUARDS.count) 支｜受保護 \(PROTECTED.count) 個｜workflow \(WORKFLOWS.count) 份\n")

    // **有宣告就必須解析得到。** 若有人把 `declared()`「統一」成走 `codeOnly()`，宣告行
    // （是註解）會被剝掉、機制整個失效——而守衛**不會紅**：它只是少考慮幾個 pair，沉默地。
    // 所以在這裡把它變成會紅的（#407 R20b）。
    //
    // 一行**看起來就是在宣告**卻不是合法宣告 → 它是啞的。上一版只認「少了註解標記」一種，
    // 實測還有三種同樣安靜：行尾多一句註記、沒給 glob、關鍵字打成 `read`（#407 R28）。
    // 標記寫成 `[#/]*` 而非 `(?:#|//)?`（#407 R30）：後者只吃**一個** `#` 或**恰好兩個**
    // `/`，於是 Swift 慣用的 `///` 與 shell 的段標 `##` 對 DECLARE 與本條**同時**隱形。
    let DECL_SHAPED = #"^\s*[#/]*\s*trigger-coverage:"#

    // ── 守衛讀的檔必須在受保護集合（#518）──────────────────────────────────
    //
    // **這道檢查是收錄判準本身。** 在它之前，`PROTECTED` 是 glob ＋ 手維護清單，而
    // 「有沒有漏收」沒有任何東西在看——漏收的後果是那一對**結構上進不了**下方的逐對
    // 迴圈（`for f in PROTECTED`），於是報表照印「無缺口」。#516 就是這樣過去的。
    //
    // 判準：守衛的**程式碼**（`codeOnly()`，註解已剝掉）裡逐字出現一個 repo 相對路徑，
    // 而那個檔**存在於磁碟**卻不在 `PROTECTED`。三個條件都是機械可判定的事實，所以進
    // `fails` 而非 `warnings`（分界見上方：降級的是「我們有沒有能力判定」，不是嚴重度）。
    //
    // **抓不到的東西明寫出來（#518 R1 重量，五種寫法逐一實測）。** 這道 ratchet 保證的
    // **不是**「守衛的依賴都受保護」，而是「**恰好用引號緊鄰完整路徑寫出來的**依賴都受
    // 保護」。以下全部靜默通過（目標都是一個真的存在、未受保護的檔）：字串串接
    // （`"docs/" + "store-format.md"`）、`./` 前綴（過不了 `PATH_ROOTS`）、雙斜線
    // （過不了 regex）、`os.path.join("docs", "store-format.md")`、以及組出來的路徑
    // （`abspath("\(plugin)/../Sources/…")`——本表就有一條踩到）。
    //
    // **`# trigger-coverage: reads` 宣告機制補不了這個洞——上一版的註解把它說反了。**
    // `declared()`（上方）最後一步是 `PROTECTED.filter { globMatch($0, pat) }`：宣告只能
    // 在 `PROTECTED` **內部做選取**，永遠無法把一個檔**帶進** `PROTECTED`。實測對一個
    // 未受保護的檔只寫宣告 → **多兩條紅**（「宣告機制失效了」＋「它等於沒寫」），不是
    // 覆蓋。宣告機制互補的是**歸屬**（把一個已在集合裡的檔正確算給某支守衛），不是
    // **收錄**——而 #518 從頭到尾講的是收錄。
    //
    // **檔案不存在那一半已於 #521 補上**（上一版寫「直接跳過——那一半是 #521，不是防呆」，
    // 現在它是 `fails`）。刻意跳過的只剩**一個**：含 `*` 的字面（glob 樣式）屬 `globFiles`
    // 的領域。另有一個**豁免**：同一行寫著 `fileExists(...)` 之類的 absence probe——
    // 刻意檢查某檔在不在是合法形狀，理由見下方檢查處。
    //
    // `PATH_ROOTS` 本身也是一份手維護白名單，而**它已經漏過一次**（`mcpb/` 是這道檢查
    // 上線第一次執行才補的）。目前漏著 repo 根目錄的 `AkashicApp/`、`Tools/`、`Vendor/`、
    // `mcps/`、`repos/`、`scripts/` 六個——零實例，但同一個失效搬了一層。
    let PATH_ROOTS = ["plugin/", "Sources/", ".claude/", ".githooks/", ".github/",
                      "docs/", "openspec/", "changelog/", "Tests/", "mcpb/"]
    // absence probe 的前綴 token：**封閉列舉，恰三個，不得依性質相似類推第四個。**
    // 全樹量過（2026-09-08）：`fileExists(` 21 處、`Path(` 11 處、`os.path.exists(` 3 處。
    let PROBE_PREFIXES = ["fileExists(", "os.path.exists(", "Path("]
    let PATH_LITERAL = #"["'`]([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.*-]+)+\.[A-Za-z0-9]+)["'`]"#
    for g in GUARDS {
        let code = codeOnly(g)
        let ns = code as NSString
        var seen = Set<String>()
        for m in matches(code, PATH_LITERAL) {
            let pth = (code as NSString).substring(with: m.range(at: 1))
            guard PATH_ROOTS.contains(where: { pth.hasPrefix($0) }) else { continue }
            guard !pth.contains("*"), pth != g, !seen.contains(pth) else { continue }
            seen.insert(pth)
            // ── 檔案不存在的那一半（#521）────────────────────────────────────
            //
            // 上一版在這裡 `continue`，並在下方註解寫「那一半是 #521，不是防呆」。
            // 現在補上：守衛的程式碼裡逐字寫著一個路徑，而**那個檔不存在**。
            //
            // 為什麼這是 fails 而不是可以忽略的雜訊：`rawFile` 對不存在的檔回**空字串**，
            // 於是走訪它的迴圈零次迭代、檢查靜默通過。#521 實測 `MeasuredClaimsAudit` 的
            // 檢查 ③ 就是這樣——標題印了、本體一行都沒有、rc 仍是 0。**比檢查失敗更壞，
            // 因為它看起來像通過了。**
            //
            // 與下方「存在但未受保護」是同一個問題的兩半，共用同一個出口。
            if !fileExists(pth) {
                // **absence probe 豁免**（#521 R1 verify，Codex 跨模型席指名）。
                // 一個守衛**刻意**檢查某個檔在不在，是合法的形狀——本 repo 真的用過：
                // `MigratedGuardControl` 原本就有 `fileExists("plugin/tests/…py")`，
                // 而沒有這個豁免時新規則會把那種寫法一律判紅。
                //
                // **只看同一行——這是實測過的限制，不是疏漏。** `fileExists("…")` 與
                // `(ROOT / "…").exists()` 兩種同行形狀都已驗證豁免；而先賦值再檢查
                // （`_x = ROOT / "…"` 換行 `if _x.exists()`）**不會**豁免。要跨行判斷得做
                // 資料流分析，那不是這個層次做得到的事；訊息因此明寫「用 `fileExists(...)`
                // 之類的形狀寫」——這條出路是可執行的（對照 #518 那條「或確認那不是真的
                // 依賴」，它沒有任何落點）。
                // 豁免綁在**這一個字面**上，不是整行（#521 R2 verify，Codex 跨模型席）。
                // 上一版問「這行有沒有 probe token」，於是同行的**無關** probe 會消音真正的
                // 死引用——實測 `let dead = rawFile("deleted.py"); let ok = fileExists("在的檔")`
                // 直接被跳過。`.exists()` 更寬：`database.exists()` 也算。那是我自己引入的
                // false negative，方向正是這道檢查要防的那個。
                //
                // 現在看的是字面**前後緊鄰**的文字（比對前把中間的空白與換行去掉——
                // 前綴側只去尾端、後綴側全去，理由見下面第三段），所以
                // 跨行寫的 `fileExists(\n  "path"\n)` 也豁免——上一版的訊息承諾了這件事
                // 而程式碼做不到，那是第二個錯（同席指名）。
                //
                // **窗是先取原始字元、再剝空白，所以窗長算的是原始長度**（#521 R3）。上一版
                // 取 40，而 40 含縮排——`fileExists(` 換行後縮排 40 格的寫法就掉出窗外、報紅，
                // 而上面那句承諾了那個形狀。實測：縮排 40 格的跨行 `fileExists` 得 1 條缺口。
                // 改成 400，並用 NSRange 界定（順帶收掉「每次 match 都建整個前綴字串」的
                // O(n²)）。**400 是條件不是保證**：token 與字面之間若隔了 400 個以上的原始
                // 字元仍不豁免——那個方向是報紅不是消音，而中間只可能是空白（別的東西會讓
                // 下面的 hasSuffix／hasPrefix 失敗）。
                //
                // **probe token 是封閉列舉，恰三個前綴 ＋ 兩個後綴，不得依性質相似類推。**
                // 上一版另有一支**裸的** `exists(`，它以任意接收者結尾都算數——實測
                // `database.exists("plugin/tests/gone.py")` 得 0 缺口，也就是被消音。全樹量過
                // （2026-09-08）：`fileExists(` 21 處、`Path(` 11 處、`os.path.exists(` 3 處，而
                // 裸 `exists(` **零合法實例**（唯二命中在本檔註解裡，`codeOnly()` 已剝掉）。
                // 一個零實例的**放寬**換到的只有 false negative，而它本來要涵蓋的 Python 形狀
                // 已經由 `os.path.exists(` 自己那一支涵蓋。這是 R2 剛修掉的「過寬比對」換個
                // 位置再犯一次——同一輪的修法自己帶進來的，第四次。
                // **`hasSuffix` 本身沒有 identifier 邊界**（#521 R3，Codex 跨模型席）：
                // `profileExists(` 以 `fileExists(` 結尾、`XPath(` 以 `Path(` 結尾，兩者實測
                // 都得 0 缺口——也就是一個叫 `profileExists` 的自家函式可以消音死引用。所以
                // 前綴命中後還要看 token **前一個字元不是 identifier 字元**。
                //
                // **而那個檢查不能做在剝光空白的字串上**（同席指名的陷阱）：`if fileExists(`
                // 剝完是 `iffileExists(`，前一個字元變成 `if` 的 `f`，最常見的合法形狀會被
                // 判掉。所以前綴側只剝**尾端**空白——token 與字面之間本來就只能是空白
                // （夾別的東西 `hasSuffix` 自然不成立），內部的空白留著才保得住邊界。
                //
                // **後綴側維持全剝，這個不對稱是有理由的**：它的 token 以 `.`／`)` 開頭，
                // identifier 字元撞不進去，沒有對應的邊界問題；而全剝順帶涵蓋
                // `"path"\n  ).exists()` 這種把 `)` 與方法拆行寫的形狀。
                let WIN = 400
                let preLoc = max(0, m.range.location - WIN)
                var preRaw = ns.substring(with: NSRange(location: preLoc,
                                                       length: m.range.location - preLoc))
                while let l = preRaw.last, l.isWhitespace { preRaw.removeLast() }
                let preHit = PROBE_PREFIXES.contains { tok in
                    guard preRaw.hasSuffix(tok) else { return false }
                    let before = preRaw.dropLast(tok.count)
                    // 窗被截到 token 頭上時無從判斷邊界 → 保守地不豁免。
                    // 那個方向是報紅、不是消音，而它要求 token 與字面之間有 ~390 個空白。
                    guard let c = before.last else { return preLoc == 0 }
                    return !(c.isLetter || c.isNumber || c == "_")
                }
                let sufLoc = m.range.location + m.range.length
                let suf = ns.substring(with: NSRange(location: sufLoc,
                                                    length: min(WIN, ns.length - sufLoc)))
                            .filter { !$0.isWhitespace }
                let isAbsenceProbe = preHit
                    || suf.hasPrefix(").exists()") || suf.hasPrefix(".exists()")
                    || suf.hasPrefix(").is_file()") || suf.hasPrefix(".is_file()")
                if isAbsenceProbe { continue }
                // **訊息只說觀察到的事，不宣稱「讀」**（同席）。這道掃描找到的是**路徑字面**，
                // 它**沒有**證明那個字面流進 `rawFile` 或任何讀取 API——實測本 issue 自己的
                // 負控就是反例：`_gone = ROOT / "…"` 只建了一個 Path，一個字都沒讀。
                // 上一版的訊息寫「`rawFile` 會回空字串，讀它的檢查會靜默通過」，那對那段
                // 程式碼是**假的**。保留這道檢查的理由不是「它證明了有人讀」，而是：守衛裡
                // 出現一個不存在的路徑字面，**幾乎總是**遷移沒掃乾淨的殘骸（#433 留下四處），
                // 而分辨真讀與只提到需要資料流分析，不是這個層次做得到的事。
                fails.append("\(label(g)) 引用了 `\(pth)`，而**那個檔不存在**"
                           + "——#521 找到的四處實例全部是 `989ac64` 遷移後留下的引用。"
                           + "退場即刪、改指新來源；若那是刻意的 absence probe，"
                           + "把路徑直接寫成 `fileExists(\"…\")`／`os.path.exists(\"…\")`／"
                           + "`Path(\"…\")` 的引數，或緊接 `.exists()`／`.is_file()`，本檢查會豁免")
                continue
            }
            guard !PROTECTED.contains(pth) else { continue }
            // **這裡印完整路徑，不用 `label()`**（#518 R1，三席獨立命中）。`label()` 的
            // 唯一性是相對 `PROTECTED` 求的，而 `pth` 依定義**不在** `PROTECTED` 裡：
            // 同 basename 時它會印出另一個、而且是**已受保護**的檔，於是訊息叫人做的事
            // （把它加進 `DATA`）照做無效——本 change 要消滅的「缺口偽裝成通過」，換到
            // 失敗訊息裡又長一次。印完整路徑同時解決另一半：那就是要貼進 `DATA` 的字串。
            // **不再提供「或確認那不是真的依賴」這條出路**——實測它沒有落點（無 ignore
            // 清單、無反向宣告），寫出來只會讓人去找一個不存在的機制。
            fails.append("\(label(g)) 讀 `\(pth)`，但它不在受保護集合"
                       + "——逐對迴圈跑不到這一對，報表會照印「無缺口」。"
                       + "把 \"\(pth)\" 加進 `DATA`")
        }
    }

    for g in GUARDS {
        let raw = rawFile(g)
        let lines = raw.components(separatedBy: "\n")
        // **用同一個謂詞。** 裸子串會把「談論宣告」算成「有宣告」——那正是 DECLARE 收窄
        // 要解決的事，而存在性檢查若還用舊謂詞，兩者就會分岔。
        let hasDecl = lines.contains { !matches($0, DECLARE).isEmpty }
        for line in lines where !matches(line, DECL_SHAPED).isEmpty && matches(line, DECLARE).isEmpty {
            let s = line.trimmingCharacters(in: .whitespaces)
            fails.append("\(base(g)) 有一行 `\(String(s.prefix(56)))`，但 DECLARE 不匹配——**這一行是啞的**")
        }
        if hasDecl && declared(g).isEmpty {
            fails.append("\(base(g)) 有 `# trigger-coverage: reads` 宣告，"
                       + "但 declared() 解析不到任何受保護檔——宣告機制失效了")
        }
        // **逐條宣告都要解析得到**（#407 R48）：上面那條的前件是「**全部**落空」，於是一個
        // 檔案寫兩條宣告、其中一條落空時完全無聲——實地踩到。
        for line in lines {
            guard let m = matches(line, DECLARE).first else { continue }
            let pat = (line as NSString).substring(with: m.range(at: 1))
            if !PROTECTED.contains(where: { globMatch($0, pat) }) {
                fails.append("\(base(g)) 的宣告 `\(pat)` 解析不到任何受保護檔——它等於沒寫")
            }
        }
        // **判準是「第一段必須是字面」，不是「含有斜線」。** R21b 從比例判準換成結構判準時
        // 方向對了（不隨集合漂移），但判準取得太表面：`*/*.sh` 含斜線、命中 5/16，兩道檢查
        // 都放它過——而它與被擋掉的 `*.sh` **同樣不具體**（#407 R22）。「指認位置」的性質
        // 是：起點是一個**真的目錄名**。
        for line in lines {
            guard let m = matches(line, DECLARE).first else { continue }
            let pat = (line as NSString).substring(with: m.range(at: 1))
            let first = pat.components(separatedBy: "/")[0]
            if first.contains("*") || first.contains("?") {
                fails.append("\(base(g)) 的宣告 `\(pat)` 的第一段是萬用字元——那是在說"
                           + "「任何地方的這類檔案」，不是在指認依賴的位置；請從一個真的目錄名開始")
            }
        }
        let declLines = lines.filter { !matches($0, DECLARE).isEmpty }
        // **第一個真實例出現了**（#407 R48）：`measured-numbers-audit` 掃 `.claude/rules/*.md`
        // 與 `plugin/rules/*.md` **兩個路徑根**，沒有語法能併成一條。上一版把「多於一行」整個
        // 判成失敗。放寬但不失去保護：**每一條都必須解析得到**（上方），而重複的樣式仍然擋
        // ——一個教學範例最可能的形狀就是把既有那條再抄一次。
        if declLines.count != Set(declLines).count {
            fails.append("\(base(g)) 有重複的宣告樣式——多半是教學範例，請改寫成佔位形式")
        }
        // **宣告的目標，守衛自己得提過。** 沒有便宜的機制能驗「宣告是否屬實」（那要執行或
        // 靜態分析）。但有一個便宜的**必要條件**：宣告存在的理由是補啟發式的漏（守衛用 glob
        // 組路徑），而那種守衛通常仍會提到**目錄名**。實測 `rule-coverage.sh` 去掉宣告行後
        // 仍提到 `rules` 兩次；一條編造的宣告則零次。
        let body = lines.filter { matches($0, DECLARE).isEmpty }.joined(separator: "\n")
        for line in declLines {
            let g_ = (line as NSString).substring(with: matches(line, DECLARE)[0].range(at: 1))
            // **宣告指向守衛自己所在的目錄 ⇒ 它補不了任何漏。** 同目錄的東西啟發式本來就
            // 看得到。更糟的是痕跡檢查對這一類**沒有鑑別力**：守衛住在 `plugin/tests/`，那個
            // 字串必然出現在它自己的註解裡（#407 R23c）。
            let declDir = pyDirname(g_).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
            if !declDir.isEmpty && pyDirname(g).replacingOccurrences(of: "/+$", with: "", options: .regularExpression) == declDir {
                // **這說的是「不必要」，不是「假的」——所以是警告不是缺口。** R23c 把它寫成
                // fail 並 continue，於是它與「編造的宣告」拿到同一種嚴重度。跨模型審查指出
                // 反例（#407 R24）：GUARDS 只枚舉 `.sh`/`.py`，所以同目錄的**資料檔**不在
                // 啟發式的視野裡；若守衛又以 runtime 組路徑讀它，那條宣告就是**真的且必要**的。
                warnings.append("\(base(g)) 宣告讀 `\(g_)`，而那正是它自己所在的目錄——"
                              + "同目錄的**腳本**啟發式本來就看得到，這條宣告多半多餘；"
                              + "但同目錄的**資料檔**（非 .sh/.py）不在枚舉範圍內，"
                              + "那種依賴的宣告是必要的。請人確認")
                continue
            }
            // **往前找第一個非萬用字元的段。** `Sources/*/*.swift` 的 dirname 是 `Sources/*`，
            // 取最後一段會得到 `*`，於是下面的萬用字元條件讓整條宣告**跳過檢查**——而它的
            // 第一段是字面 `Sources`，前一道也放它過，於是完全不被驗（#407 R22e）。
            let parts = pyDirname(g_).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
                .components(separatedBy: "/").filter { !$0.isEmpty }
            let seg = parts.reversed().first { !$0.contains("*") && !$0.contains("?") } ?? ""
            // **要在路徑脈絡裡出現，不只是一個詞。** 詞邊界擋掉了 `rulesets` 那種巧合子串
            // （R22f），但擋不住**散文**：`# TODO: add more tests` 裡的 `tests` 是完整的詞
            // （#407 R23d）。要求它出現在**看起來像路徑或賦值**的位置。
            let esc = NSRegularExpression.escapedPattern(for: seg)
            let traced = !seg.isEmpty && !matches(body,
                "[/\"'$=]\(esc)(?![A-Za-z0-9_-])|(?<![A-Za-z0-9_-])\(esc)[/\"']").isEmpty
            // **退回兩級：一律 warning。**（#407 R24f——撤銷 R24d 的三級化）
            //
            // 這個檢查走過三版近似，每一版都被證明兩頭不對：子串（`rulesets` 含 `rules`）、
            // 詞邊界（`# TODO: add more tests`）、路徑脈絡（太鬆仍匹配散文／太緊拒掉
            // `find Sources -name`）。最後兩個方向**本質上衝突**——那是靜態分析問題。
            //
            // R24d 曾把「seg 連子串都沒出現」升為 fail（理由：那是可證偽的假陳述）。**理由對，
            // 但判準抓不到它**——`for f in "$BASE"/*/*.md` 這種純 glob、從不寫目錄名的守衛
            // 會被誤殺，而那正是宣告機制的**目標使用者**。裁決：
            //   誤殺的代價 → 擋住目標使用者（動態路徑的守衛作者）
            //   漏放的代價 → 一條假陳述留在 codebase，而真實實例**為零**（R23e 量過）
            // 選擇不誤殺。**這是已知且刻意接受的限制**，不是沒想到。
            //
            // **兩種證據狀態保留各自的文字，但同屬 warning**（#407 R25）：R24f 併成同一則
            // 訊息時，「seg 一次都沒出現」與「seg 出現但不在路徑脈絡」對讀輸出的人**長得
            // 一樣**——而前者是強得多的編造訊號。保留區別但不重新分層。
            if !seg.isEmpty && !seg.contains("*") && !seg.contains("?") && !traced {
                if !body.contains(seg) {
                    warnings.append("\(base(g)) 宣告讀 `\(g_)`，而 `\(seg)` 在它的原始碼裡"
                                  + "（扣掉宣告行本身）**一次都沒出現過**——編造訊號最強的一種。"
                                  + "但守衛也可能用純 glob／動態路徑讀它（那正是宣告要補的漏），"
                                  + "所以仍是警告而非缺口（理由見上方 R24f 的裁決）。請人確認")
                } else {
                    warnings.append("\(base(g)) 宣告讀 `\(g_)`，`\(seg)` 有出現但不在路徑脈絡裡"
                                  + "——**訊號較弱**（可能是散文巧合，也可能是裸目錄名的真實用法）。請人確認")
                }
            }
        }
        // **這一條目前不可獨立觸發，保留是有條件的。** 要命中全部受保護檔就得跨 `plugin/`
        // 與 `Sources/` 兩個前綴，而那需要第一段是萬用字元——於是一定先被上面那條抓。
        // 不刪的理由是它**條件性可達**：若日後 Sources 那兩個受保護檔退場、全部集中到
        // `plugin/` 底下，`plugin/**` 就會是「第一段字面 ＋ 命中全部」。這與
        // `no-compat-fallback` 的「退場即刪」不同——那條管的是用途已歸零的相容路徑，
        // 這裡是用途取決於集合形狀。**負控裡沒有它的格子**，因為它現在不可獨立觸發。
        let hits = declared(g)
        if !hits.isEmpty && hits.count == PROTECTED.count {
            fails.append("\(base(g)) 的宣告命中全部 \(PROTECTED.count) 個受保護檔"
                       + "——那不是宣告依賴，是在描述整個 repo")
        }
    }

    // Python 的 `f'{s:<n}'`：不足補空白，超長不截斷。檔名都是 ASCII，grapheme 數等同
    // Python 的 code-point 數。
    func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }

    print("每支守衛被判定讀了哪些受保護檔（啟發式，漏報方向——見 READS 上方註解）：")
    for g in GUARDS {
        let decl = declared(g)
        // 標出來源：宣告來的加 ⟨宣⟩。一個誤宣告（教學範例被當成宣告）會在這裡顯示成
        // 「這個守衛讀了它其實不讀的東西」——約定被違反時的可見性。
        let parts = READS[g]!.sorted().filter { $0 != g }
            .map { label($0) + (decl.contains($0) ? "⟨宣⟩" : "") }
        print("   \(pad(label(g), 40)) → \(parts.isEmpty ? "（只有自己）" : parts.joined(separator: "、"))")
    }
    print("")

    for f in PROTECTED {
        let readers = GUARDS.filter { READS[$0]!.contains(f) }
        if readers.isEmpty { continue }
        var covered: [String] = []
        for w in WORKFLOWS {
            guard let p = w.paths["paths"], !p.isEmpty, pathsMatch(p, f) else { continue }
            if pathsMatch(w.paths["paths-ignore"] ?? [], f) { continue }
            covered += readers.filter { w.runs.contains(base($0)) }
        }
        let gap = readers.filter { !covered.contains($0) }
        print("\(gap.isEmpty ? "✓" : "✗") \(pad(label(f), 40)) 讀它的守衛 \(readers.count)｜CI 未覆蓋 \(gap.count)")
        for g in gap {
            let whereS = HOOK.contains(base(g)) ? "pre-push 有" : "pre-push 也沒有"
            fails.append("改 \(label(f)) 時 \(label(g)) 不在任何 CI workflow 跑（\(whereS)）")
        }
    }

    // pre-push 是唯一目前真的會跑的路徑（CLAUDE.md 的觸發點表有量測），所以它必須涵蓋
    // 全部守衛——這一條與上面的逐對檢查是不同的性質。
    let uncoveredHook = GUARDS.filter { !HOOK.contains(base($0)) }
    print("\n\(uncoveredHook.isEmpty ? "✓" : "✗") pre-push 涵蓋 "
        + "\(GUARDS.count - uncoveredHook.count)/\(GUARDS.count) 支守衛")
    for g in uncoveredHook { fails.append("\(base(g)) 不在 pre-push 裡") }

    if !warnings.isEmpty {
        print("\n══ 待人確認 \(warnings.count)（啟發式警告，不構成缺口）══")
        for m in warnings { print("  ? \(m)") }
    }
    if !fails.isEmpty {
        print("\n══ 缺口 \(fails.count) ══")
        for m in fails { print("  · \(m)") }
        return 1
    }
    print("\n══ 觸發點覆蓋無缺口（逐對意義，非聯集）══")
    return 0
}
