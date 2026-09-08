// workflow 的 `run:` 跑的腳本必須存在（#526）。
//
// #521 的四個實例裡**有兩個**是這個形狀（`census-parity.yml` 與 `ci.yml` 各跑一支已刪的
// `.py`），而當時新加的檢查只涵蓋**守衛原始碼裡的路徑字面**。實例 4 是 verify 席找到的
// ——這個缺口已經讓一次封閉列舉出錯。後果不對稱：一個掛掉的 step 會擋住其後**全部**步驟；
// `ci.yml:94` 那次擋掉的包含 AkashicApp（`swift test` 涵蓋不到的那塊，#101 的立案理由）。
//
// **為什麼是獨立守衛而不是併進 `trigger-coverage`。** 併進去的第一版實測讓該支的
// mutation harness **5 個既有 case 同時失敗**：那些 case 刻意在 workflow 裡注入指向
// 不存在腳本的假命令（`plugin/tests/DELETED-numbers-audit.py`）來測 `invoked()` 的剖析，
// 而本檢查會如實報那些引用——於是每個 case 都「另有無關缺口」。一支守衛的 harness 偽造
// 某種內容，另一道檢查又對那種內容做存在性斷言，兩者永久互相干擾。#526 的 Expected 說的是
// 「納入**某個**守衛的視野」，沒有指定哪一支。
//
// trigger-coverage: reads .github/workflows/*.yml

import Foundation

/// 一個 workflow 的 `run:` 區塊裡跑到的腳本路徑。
struct RunScriptRef { let wf: String; let line: Int; let path: String }


/// **只看 `run:` 的內容，且剝掉 shell 註解**（#526 Expected 2 的第一個坑）。
///
/// `ci.yml` 自己就有反例：一段註解逐字寫著「原本是 `python3 …/marker-parity-mutations.py`」
/// ——掃全檔會把那個**刻意記下的已刪檔名**當成引用。修好的東西不得因為被寫進註解而重新變紅。
func collectRunScripts() -> [RunScriptRef] {
    var out: [RunScriptRef] = []
    for wf in globFiles(".github/workflows/*.yml").sorted() {
        let lines = rawFile(wf).components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard let m = matches(line, #"^(\s*)(?:-\s+)?run:\s*(.*)$"#).first else { i += 1; continue }
            let ns = line as NSString
            let indent = ns.substring(with: m.range(at: 1)).count
            let rest = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            var body: [(Int, String)] = []
            if rest == "|" || rest == ">" || rest == "|-" || rest == ">-" {
                var j = i + 1
                while j < lines.count {
                    let l = lines[j]
                    if l.trimmingCharacters(in: .whitespaces).isEmpty { j += 1; continue }
                    let ind = l.prefix(while: { $0 == " " }).count
                    if ind <= indent { break }
                    body.append((j + 1, l)); j += 1
                }
                i = j
            } else {
                body = [(i + 1, rest)]; i += 1
            }
            for (ln, raw) in body {
                // shell 註解剝掉——見上方 docstring 的反例
                var cmd = raw
                if let h = cmd.range(of: "#") {
                    let before = cmd[..<h.lowerBound]
                    // 只有當 `#` 前是行首或空白時才算註解起點（避免砍掉 `a#b` 這種）
                    if before.isEmpty || before.hasSuffix(" ") { cmd = String(before) }
                }
                out += runScriptTokens(cmd).map { RunScriptRef(wf: wf, line: ln, path: $0) }
            }
        }
    }
    return out
}

/// 一條命令裡「被當成腳本跑」的路徑。
///
/// **`swift` 要特別處理**：`swift build`／`swift test`／`swift run <target>` 的下一個 token
/// 是**子命令**不是路徑，只有 `swift foo.swift` 是跑一個檔。把它們一視同仁會把 `build`
/// 當成不存在的檔而製造假紅——比漏報更貴（`zero-instance-guards` 第 6 列：假紅會讓所有
/// 紅燈失效）。
func runScriptTokens(_ cmd: String) -> [String] {
    let toks = cmd.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    var out: [String] = []
    var k = 0
    // **shell 運算子不是路徑**（實測：`cat x | bash && echo` 讓 `bash` 的下一個 token 是
    // `&&`，於是報「跑 &&，而那個檔不在」——假紅，而假紅會讓所有紅燈失效
    // （`zero-instance-guards` 第 6 列））。`| bash` 這種「直譯器從 stdin 讀」的形狀因此
    // 也自然得到零個路徑，那是對的：沒有腳本檔可以檢查存在性。
    let OPERATORS: Set<String> = ["&&", "||", ";", "|", "&", ">", ">>", "<", "2>", "2>&1"]
    func plausible(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix("-") && !s.contains("$") && !s.contains("{{")
            && !s.contains("*") && !s.contains("\"") && !s.contains("'")
            && !OPERATORS.contains(s)
    }
    while k < toks.count {
        let t = toks[k]
        if ["bash", "sh", "zsh", "python3", "python"].contains(t) {
            var j = k + 1
            while j < toks.count, toks[j].hasPrefix("-") { j += 1 }   // 跳過 -e／-o pipefail 等
            if j < toks.count, plausible(toks[j]) { out.append(toks[j]) }
            k = j + 1; continue
        }
        if t == "swift", k + 1 < toks.count, toks[k + 1].hasSuffix(".swift"),
           plausible(toks[k + 1]) {
            out.append(toks[k + 1]); k += 2; continue
        }
        if t.hasPrefix("./"), plausible(t) { out.append(String(t.dropFirst(2))) }
        k += 1
    }
    return out
}


func workflowRunScriptsGuard() -> Int32 {
    let refs = collectRunScripts()
    if refs.isEmpty {
        // **空集合不得冒充通過**（#526 Expected 2 的第二個坑，#521 close 時我自己踩過：
        // 第一版掃描回報「0 個引用、0 個不存在」——那不是綠，是掃描壞了）。
        // **兩個原因分得開**：沒有 workflow 檔是 repo 的狀態，有 workflow 卻掃不到是掃描壞了。
        let wfs = globFiles(".github/workflows/*.yml")
        let why = wfs.isEmpty ? "`.github/workflows/*.yml` 一個檔都沒有"
                              : "\(wfs.count) 個 workflow 檔在，卻掃不到任何腳本引用——掃描壞了"
        FileHandle.standardError.write(Data("══ 1 個宣稱不成立 ══\n  ✗ \(why)\n".utf8))
        return 1
    }
    let missing = refs.filter { !fileExists($0.path) }
    guard missing.isEmpty else {
        var out = "══ \(missing.count) 個宣稱不成立 ══\n"
        for r in missing {
            out += "  ✗ \(base(r.wf)):\(r.line) 跑 \(r.path)，而那個檔不在"
                 + "——該 step 會掛掉並擋住其後全部步驟\n"
        }
        FileHandle.standardError.write(Data(out.utf8))
        return 1
    }
    print("══ workflow `run:` 引用的 \(refs.count) 個腳本全部存在 ══")
    return 0
}
