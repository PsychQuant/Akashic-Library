// `marketplace-consistency`：檔案系統上的 plugin 與 marketplace manifest 列出的 plugin
// 是同一組嗎？（#625）
//
// **為什麼要雙向核對**：plugin 根以檔案系統為準（`pluginRoots()`），但使用者裝得到的是
// manifest 列出的東西。兩者各有一個安靜的失效方向——建了沒列（守衛看得見、使用者裝不到）、
// 列了沒建（manifest 指向空氣，要到使用者安裝時才壞）。這道守衛讓兩個方向都變紅。
//
// **違規是封閉列舉，只有下列五類，不得依性質相似類推第六類**（spec
// `plugin-root-guard-coverage`）：
//   1. 某個 plugin 根沒有任何條目的 source 指向它
//   2. 某個條目的 source 指向的不是 plugin 根（含：目錄不存在、非字串 source、指出 repo 外）
//   3. 條目的 name 與其 source 處 manifest 的 name 不同
//   4. `plugins/` 底下有沒有 manifest 的直接子目錄
//   5. 某個 plugin manifest 的 dependencies 列了這個 marketplace 裡沒有的 plugin 名
//
// 名字一律以反引號包住輸出：`akashic-discover` 是 `akashic-discovery` 的子字串，不包的話
// 負對照會把任何提到後者的輸出誤判為指名了前者。

import Foundation

func marketplaceConsistency() -> Int32 {
    let fm = FileManager.default
    let marketRel = ".claude-plugin/marketplace.json"

    guard let data = fm.contents(atPath: "\(repoRoot)/\(marketRel)") else {
        FileHandle.standardError.write(Data("✗ 讀不到 \(marketRel)——不是「沒有 plugin」，是 marketplace 不存在\n".utf8))
        return 1
    }
    guard let market = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let entries = market["plugins"] as? [[String: Any]] else {
        FileHandle.standardError.write(Data("✗ \(marketRel) 不是含 `plugins` 陣列的 JSON 物件\n".utf8))
        return 1
    }

    func manifest(at root: String) -> [String: Any]? {
        guard let d = fm.contents(atPath: "\(repoRoot)/\(root)/\(pluginManifestRel)") else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    /// `./plugin`、`plugin/`、`./plugins/x` → repo 相對路徑；非字串或指出 repo 外 → nil
    func normalize(_ source: Any?) -> String? {
        guard var s = source as? String else { return nil }
        while s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty || s.hasPrefix("/") || s.split(separator: "/").contains("..") { return nil }
        return s
    }

    let roots = pluginRoots()
    let names = Set(entries.compactMap { $0["name"] as? String })
    var v = Verdict()
    var claimed = Set<String>()

    for e in entries {
        let name = e["name"] as? String ?? "（無名稱）"
        guard let src = normalize(e["source"]), roots.contains(src) else {
            _ = v.check(false, "[2] 條目 `\(name)` 的 source \(String(describing: e["source"] ?? "（缺）")) 不指向任何 plugin 根"
                             + "（根：\(roots.joined(separator: "、"))）")
            continue
        }
        claimed.insert(src)
        guard let m = manifest(at: src) else {
            _ = v.check(false, "[2] 條目 `\(name)` 的 \(src)/\(pluginManifestRel) 讀不到或不是 JSON 物件")
            continue
        }
        let mName = m["name"] as? String ?? "（無名稱）"
        _ = v.check(mName == name, "[3] 條目名稱 `\(name)` 與 \(src) 的 manifest 名稱 `\(mName)` 不一致")
    }

    for r in roots {
        _ = v.check(claimed.contains(r), "[1] \(r) 有 manifest，但 marketplace 沒有任何條目的 source 指向它")
        guard let m = manifest(at: r) else { continue }
        for dep in (m["dependencies"] as? [Any]) ?? [] {
            let depName = (dep as? String) ?? ((dep as? [String: Any])?["name"] as? String) ?? "（無法解析）"
            _ = v.check(names.contains(depName),
                        "[5] \(r) 依賴 `\(depName)`，但 marketplace 裡沒有這個 plugin")
        }
    }

    let parent = "\(repoRoot)/plugins"
    for child in ((try? fm.contentsOfDirectory(atPath: parent)) ?? []).sorted() {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: "\(parent)/\(child)", isDirectory: &isDir), isDir.boolValue else { continue }
        _ = v.check(roots.contains("plugins/\(child)"),
                    "[4] plugins/\(child) 沒有 \(pluginManifestRel)——plugins/ 底下只放 plugin")
    }

    return v.exitCode("marketplace 與檔案系統一致：\(entries.count) 個條目、\(roots.count) 個 plugin 根")
}
