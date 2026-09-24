// `official-validate`：官方 plugin／marketplace 驗證，加上一條封閉的允許清單（#625）。
//
// **為什麼不直接用 `claude plugin validate --strict .`**：`--strict` 把「未知欄位」警告
// 當成錯誤——這正是我們要的：manifest 冒出一個 Claude Code 不認得的欄位，多半是打錯字或
// 誤會了 schema，而 runtime 只會默默忽略它。但 akashic-mcp 的 `plugin.json` 有一個**刻意
// 保留**的未知欄位 `binary_version`：MCP wrapper 用它選擇要下載的 server binary release
// （#275），harness-devtools 也讀它。於是 `--strict` **永遠**失敗（2026-09-24 實測，
// Claude Code 2.1.281）；放棄 strict 又會讓任何新的未知欄位安靜通過。所以改成跑 `--json`、
// 逐條比對。
//
// **允許清單（封閉列舉，只有一項，不得依性質相似類推第二項）**：akashic-mcp 的
// `plugin.json` 的 `binary_version` 未知欄位警告。以 plugin **名稱**定位（從 marketplace
// 算出索引），不寫死 `plugins[0]`——條目順序變了照樣精確，discovery 若也冒出
// `binary_version` 會紅。允許清單那一條**不再出現**也紅：欄位已被移除時，這條豁免就成了
// 沒人記得的放行。
//
// 沒有 claude CLI 時（CI runner）印出略過並通過——略過要看得見，不靜默。
//
// 第一版寫成 Python（`plugin/tests/`），與 #433「守衛改用 Swift、單一 toolchain」的方向
// 相反，同一輪改寫成本子命令。

import Foundation

func officialValidate() -> Int32 {
    let allowedPlugin = "akashic-mcp", allowedField = "binary_version"
    let fm = FileManager.default

    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    guard let claude = path.split(separator: ":").map({ "\($0)/claude" })
            .first(where: { fm.isExecutableFile(atPath: $0) }) else {
        print("ℹ claude plugin validate 已略過：這台機器沒有 claude CLI（CI runner 屬於這種情況；本機 pre-push 會跑）")
        return 0
    }

    let marketRel = ".claude-plugin/marketplace.json"
    guard let md = fm.contents(atPath: "\(repoRoot)/\(marketRel)"),
          let market = (try? JSONSerialization.jsonObject(with: md)) as? [String: Any],
          let entries = market["plugins"] as? [[String: Any]] else {
        print("✗ 讀不到或解析不了 \(marketRel)"); return 1
    }
    guard let idx = entries.firstIndex(where: { $0["name"] as? String == allowedPlugin }) else {
        print("✗ marketplace 沒有 \(allowedPlugin)——允許清單指向一個不存在的條目"); return 1
    }
    let allowedPath = "plugins[\(idx)] plugin.json → \(allowedField)"

    let p = Process()
    p.executableURL = URL(fileURLWithPath: claude)
    p.arguments = ["plugin", "validate", "--json", repoRoot]
    p.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
    let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
    guard (try? p.run()) != nil else { print("✗ 無法執行 \(claude)"); return 1 }
    let out = o.fileHandleForReading.readDataToEndOfFile()
    let err = e.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let report = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any] else {
        print("✗ claude plugin validate --json 的輸出不是 JSON（rc=\(p.terminationStatus)）：\n"
              + (String(data: out, encoding: .utf8) ?? "") + (String(data: err, encoding: .utf8) ?? ""))
        return 1
    }

    let sections = [report["manifest"] as? [String: Any] ?? [:]]
                 + (report["contents"] as? [[String: Any]] ?? [])
    let items = { (key: String) -> [[String: Any]] in sections.flatMap { $0[key] as? [[String: Any]] ?? [] } }
    let describe = { (x: [String: Any]) -> String in
        "\(x["path"] as? String ?? "?") — \(x["message"] as? String ?? "?")"
    }
    let warnings = items("warnings")
    var fails = items("errors").map { "error：" + describe($0) }
    fails += warnings.filter { $0["path"] as? String != allowedPath }
                     .map { "warning（不在允許清單）：" + describe($0) }
    if !warnings.contains(where: { $0["path"] as? String == allowedPath }) {
        fails.append("允許清單那一條（\(allowedPath)）不再出現——若 \(allowedField) 已從 "
                     + "\(allowedPlugin) 的 plugin.json 移除，把它從本檔的允許清單拿掉")
    }
    if !fails.isEmpty {
        print("══ 官方驗證不通過：\(fails.count) 條 ══")
        for f in fails { print("  ✗ " + f) }
        return 1
    }
    print("══ claude plugin validate 通過：0 error，唯一的 warning 是允許清單那一條（\(allowedPath)）══")
    return 0
}
