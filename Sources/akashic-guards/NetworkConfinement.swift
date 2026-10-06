// `network-confinement`：網路與 keychain API 只准出現在 `Sources/AkashicS2/`（#664）。
//
// **為什麼有這支**：Akashic 的核心是離線的——store 在本機，外部查詢走 safari-browser、
// 由人在場（`web-access-via-safari-browser.md`）。#664 開了唯一一個例外：帶金鑰的
// Semantic Scholar 呼叫，而它被收在獨立的 target `AkashicS2`。這支把「只有那一個 target」
// 變成機械可判定的事：之後的改動若在別處用到下面清單上的字樣來開出第二條網路路徑或讀 keychain，這裡會紅。
// **它是字面的封閉清單，不是證明**：它**只擋清單上的字樣**：子行程（`Process` 以任何方式叫 `curl`，包括 `/usr/bin/env`、`/opt/homebrew/bin/curl`、拼出來的路徑——清單只有字面的 `/usr/bin/curl`）、動態載入、清單上沒有的 API，它都看不到——那些靠程式審查。
//
// **判準是字樣，不是語意**：下面九個字樣只准出現在 `Sources/AkashicS2/`。**註解也計入**
// ——量測（2026-09-29，`grep -rnF` 對 `Sources/` 下全部 `.swift`）：這些字樣在 AkashicS2
// 以外是 0 處，所以保守的判準不會誤報現有程式；而「只看程式碼」得先剝註解，剝註解本身
// 就是一個會錯的啟發式（`codeOnly` 的行尾 `//` 漏剝過一次，#407 R20）。
//
// **清單是封閉列舉**（spec）：新字樣要逐項加一列，不得依相似性推導——同屬網路或 keychain
// 的其他 API 名稱不在清單裡就不算，要擋它就加一列。加列時 `network-confinement-mutations`
// 會因為對帳不上而紅，直到它也補上那一格。
//
// **豁免恰好兩個檔**：守衛自己與它的負對照，因為它們把這些字樣寫成模式。以完整相對路徑
// 比對，不以目錄或檔名——`Sources/akashic-guards/` 的其他檔照樣被掃（負對照有一格注入
// `main.swift` 驗這件事）。
//
// **失敗訊息指名檔案、行號與字樣**，一條違規一行；rc=1。讀不到輸入（`Sources/` 下沒有
// Swift 檔、某個檔不是 UTF-8）是 rc=2——守衛跑不起來，不是查到問題，更不是通過。
//
// trigger-coverage: reads Sources/*/*.swift

import Foundation

/// 封閉列舉：九個字樣，逐項列出（spec〈Networking and keychain APIs are confined to
/// AkashicS2〉）。`kind` 只用於訊息。負對照逐項對帳這份清單。
let networkConfinementPatterns: [(pattern: String, kind: String)] = [
    ("URLSession", "網路"),
    ("URLRequest", "網路"),
    ("NWConnection", "網路"),
    ("import Network", "網路"),
    ("/usr/bin/curl", "網路"),
    ("import Security", "keychain"),
    ("SecItem", "keychain"),
    ("import LocalAuthentication", "keychain"),
    ("/usr/bin/security", "keychain"),
]

/// 唯一准許這些字樣的目錄。**尾斜線是判準的一部分**：沒有它，名字以 `AkashicS2` 開頭的
/// 另一個 target 也會被當成豁免。
let networkConfinementHome = "Sources/AkashicS2/"

/// 豁免：恰好兩個檔，完整相對路徑。
let networkConfinementExempt: Set<String> = [
    "Sources/akashic-guards/NetworkConfinement.swift",
    "Sources/akashic-guards/NetworkConfinementMutations.swift",
]

func networkConfinement() -> Int32 {
    let files = swiftSources().sorted()
    // **空集合不得冒充通過**：`Sources/` 不在或走訪不到時，掃描零個檔會印成「沒有違規」。
    guard !files.isEmpty else {
        print("✗ Sources/ 底下一個 Swift 檔都找不到——掃描零個檔不是通過，是守衛的輸入不在")
        return 2
    }
    var v = Verdict()
    var scanned = 0, inHome = 0, exempt = 0
    for rel in files {
        if rel.hasPrefix(networkConfinementHome) { inHome += 1; continue }
        if networkConfinementExempt.contains(rel) { exempt += 1; continue }
        // 讀不到就停，不跳過——跳過的檔等於沒被掃，而輸出照樣會說「沒有違規」
        guard let text = readFile(rel) else {
            print("✗ 讀不到 \(rel)（無法開啟或不是 UTF-8）——守衛無法判定它，不當成乾淨")
            return 2
        }
        scanned += 1
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            for (pattern, kind) in networkConfinementPatterns where line.contains(pattern) {
                let shown = line.trimmingCharacters(in: .whitespaces)
                _ = v.check(false, "\(rel):\(i + 1)：含 `\(pattern)`（\(kind)）——"
                    + "只准出現在 \(networkConfinementHome)｜\(String(shown.prefix(80)))")
            }
        }
    }
    return v.exitCode("網路與 keychain API 只出現在 \(networkConfinementHome)："
        + "掃描 \(scanned) 個 Swift 檔（另有 \(networkConfinementHome) 內 \(inHome) 個、"
        + "豁免 \(exempt) 個）")
}
