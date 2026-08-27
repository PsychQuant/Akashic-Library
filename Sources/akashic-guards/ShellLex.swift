// `shlex.shlex(cmd, posix: true, punctuation_chars: true)` ＋ `whitespace_split = true`
// 的等價實作。
//
// **為什麼需要它**（#407 R22c 的量測）：對字串直接 split 會在三種形式上出錯——
// `cat x.txt | bash b.sh`（管線不在切分符裡 → b.sh 真的執行卻零可見度）、
// `FOO=1 bash a.sh`（head 不是直譯器）、`echo "見 a.sh && bash b.sh"`（引號內的
// `&&` 被當成分隔符 → 誤報）。懂引號的 tokenizer 是判斷「命令位置」的前提。
//
// **`punctuationChars` 讓 `;`／`|`／`&&`／`||` 成為獨立 token**：沒有它
// `bash a.sh; bash b.sh` 會切成 `["bash", "a.sh;", …]`——分號黏在檔名尾巴上，
// 於是整行變成單段而兩支都認不出（#407 R22c 六格驗證裡就這一格紅）。
//
// **未閉合引號拋錯**，呼叫端退回粗略切法（與 Python 的 `except ValueError` 同）。

import Foundation

struct UnterminatedQuote: Error {}

/// `();<>|&` —— Python `shlex` 在 `punctuation_chars=True` 時從 wordchars 移除的那組。
private let punct: Set<Character> = ["(", ")", ";", "<", ">", "|", "&"]

func shellLex(_ cmd: String) throws -> [String] {
    var out: [String] = []
    var cur = ""
    var hasCur = false          // 空 token 也算數（`""` → 一個空字串 token）
    let it = Array(cmd)
    var i = 0
    while i < it.count {
        let c = it[i]
        if c == "\\" {          // 引號外的逃脫：吃下一個字元的字面
            i += 1
            if i < it.count { cur.append(it[i]); hasCur = true; i += 1 }
            continue
        }
        if c == "'" {           // 單引號內無逃脫
            i += 1
            var closed = false
            while i < it.count {
                if it[i] == "'" { closed = true; i += 1; break }
                cur.append(it[i]); i += 1
            }
            if !closed { throw UnterminatedQuote() }
            hasCur = true
            continue
        }
        if c == "\"" {          // 雙引號在 escapedquotes 裡：`\` 只逃脫 `\` 與 `"`
            i += 1
            var closed = false
            while i < it.count {
                if it[i] == "\"" { closed = true; i += 1; break }
                if it[i] == "\\" && i + 1 < it.count && (it[i+1] == "\"" || it[i+1] == "\\") {
                    cur.append(it[i+1]); i += 2; continue
                }
                cur.append(it[i]); i += 1
            }
            if !closed { throw UnterminatedQuote() }
            hasCur = true
            continue
        }
        if c.isWhitespace {
            if hasCur { out.append(cur); cur = ""; hasCur = false }
            i += 1
            continue
        }
        if punct.contains(c) {
            if hasCur { out.append(cur); cur = ""; hasCur = false }
            var p = ""          // 連續的 punctuation 併成一個 token（`&&`／`||`）
            while i < it.count && punct.contains(it[i]) { p.append(it[i]); i += 1 }
            out.append(p)
            continue
        }
        cur.append(c); hasCur = true; i += 1
    }
    if hasCur { out.append(cur) }
    return out
}
