// plugin 根目錄的唯一來源（#625）。
//
// **為什麼要有唯一來源**：受保護清單、trigger-coverage、rule-coverage 都要知道「repo 裡有
// 哪些 plugin」。各自寫死 `plugin/` 的結果是：`plugins/<name>/` 底下的測試被刪、沒接線、
// skill 漏引規則，沒有一道守衛會出聲——而且是安靜的。bash 端（rule-coverage）不另存清單，
// 經由 `akashic-guards plugin-roots` 取得同一份。
//
// **判準是檔案系統，不是 marketplace manifest**：只信 manifest 的話，建了還沒列進去的
// plugin 會得到零涵蓋。兩者是否一致由 `marketplace-consistency` 另外核對——那一道把
// 「建了沒列」與「列了沒建」都變紅。

import Foundation

/// `plugin`（akashic-mcp，位置不動——#617 定案），加上 `plugins/` 底下含
/// `.claude-plugin/plugin.json` 的直接子目錄。repo 相對路徑，排序。
///
/// 沒有 manifest 的子目錄**不是**根；它是否該存在，由 `marketplace-consistency` 判定。
func pluginRoots() -> [String] {
    let fm = FileManager.default
    let parent = "\(repoRoot)/plugins"
    var roots = ["plugin"]
    for name in (try? fm.contentsOfDirectory(atPath: parent)) ?? [] {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: "\(parent)/\(name)", isDirectory: &isDir), isDir.boolValue else { continue }
        if fm.fileExists(atPath: "\(parent)/\(name)/\(pluginManifestRel)") {
            roots.append("plugins/\(name)")
        }
    }
    return roots.sorted()
}

/// plugin manifest 相對於 plugin 根的位置
let pluginManifestRel = [".claude-plugin", "plugin" + ".json"].joined(separator: "/")

/// `akashic-guards plugin-roots`：每行一個根，給 shell 端用。
///
/// **名字含空白或控制字元的根讀不回來**（#613 b47，b46 LOW 12）：`run-guards.sh` 以空白分開這份輸出（`for root in $plugin_roots`），根名裡的空白
/// 把它切成幾個不存在的根；控制字元原樣印出會把終端機控制序列送到終端機，逸出（`shownFromTree`）之後又不是原來的目錄名。兩種都不印清單、rc=1、
/// 在 stderr 具名（逸出過的名字）——`run-guards.sh` 的 `set -e` 因此在這一行就停，不會拿一個讀錯的根去跑 `rule-coverage`。
func pluginRootsCommand() -> Int32 {
    let roots = pluginRoots()
    let unusable = roots.filter { r in r.unicodeScalars.contains { $0.properties.isWhitespace } || shownFromTree(r) != r }
    guard unusable.isEmpty else {
        FileHandle.standardError.write(Data(("✗ plugin 根的名字含空白或控制字元：\(unusable.map(shownFromTree).joined(separator: "、"))——"
            + "run-guards.sh 以空白分開這份清單，這種名字讀不回原來的目錄（逸出之後也不是）：改名\n").utf8))
        return 1
    }
    for r in roots { print(r) }
    return 0
}
