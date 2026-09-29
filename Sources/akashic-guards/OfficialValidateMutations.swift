// `official-validate-mutations`：`official-validate` 真的會開火嗎？（#689）
//
// **為什麼現在才有**：`official-validate`（#625）從寫成那天就沒有負控。`migrated-guard-control`
// 本來該抓到這件事，但它把 `main.swift` 的 `case "official-validate":` 算成「有負控」——#689 修掉
// 那個判準之後，這支是它第一個指出的缺口。
//
// **為什麼用假的 `claude`**：守衛的判定邏輯是「讀 `claude plugin validate --json` 的報告，對一條
// 允許清單逐條比對」。要讓它紅，得讓報告長成錯的樣子——而真的 CLI 只會報真的 repo。所以每一格
// 在暫存目錄放一支假的 `claude`（只把一份預先寫好的報告印出來），把它放在 PATH 最前面。
// 這樣也不依賴這台機器有沒有裝 claude CLI：CI runner 沒有，這支照樣每一格都跑得到。
//
// 代價寫出來：真的 CLI 改了 `--json` 的格式，這支不會知道——那一種由守衛自己的「輸出不是 JSON」
// 那條路擋（這裡有一格驗那條路），以及 pre-push 在本機用真的 CLI 跑守衛。
//
// **允許清單照守衛檔頭的文字獨立寫**（`akashic-mcp` 的 `plugin.json` 的 `binary_version`），不取
// 守衛的常數——取了的話，守衛把名字寫錯時這裡會跟著錯、照樣綠。允許那一條的 `path` 由這裡從
// marketplace 獨立算出（`plugins[<索引>] plugin.json → binary_version`）。
//
// **每一格的預期都寫死 rc**：紅的格必須是 1（守衛「查到問題」的碼），綠的格必須是 0。只看
// 「非零」的話，假 `claude` 寫壞了（spawn 失敗、權限不對）也會被算成「被抓到」。
//
// **只複製 `.claude-plugin/`**：守衛只讀那裡的 marketplace。工作樹有沒有被寫入，最後逐位元比對一次。

import Foundation

private struct ValidateCell {
    let desc: String
    /// 假 `claude` 印出的報告；nil 表示這一格 PATH 上**沒有** claude
    let report: String?
    /// 對副本裡的 marketplace 做的改動；nil 表示不改
    let editMarket: ((String) -> String?)?
    /// 0：必須綠；1：必須紅
    let wantRC: Int32
    /// 輸出必須包含的字串（全部）
    let expect: [String]
}

func officialValidateMutations() -> Int32 {
    let fm = FileManager.default
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    let marketRel = ".claude-plugin/marketplace.json"
    // 守衛檔頭的文字，刻意不取守衛的常數（理由見檔頭）
    let allowedPlugin = "akashic-mcp", allowedField = "binary_version"

    guard fm.isExecutableFile(atPath: BIN) else {
        print("✗ \(BIN) 不存在——先 swift build --product akashic-guards"); return 2
    }
    guard let md = fm.contents(atPath: "\(repoRoot)/\(marketRel)"),
          let market = (try? JSONSerialization.jsonObject(with: md)) as? [String: Any],
          let entries = market["plugins"] as? [[String: Any]],
          let idx = entries.firstIndex(where: { $0["name"] as? String == allowedPlugin }) else {
        print("✗ 讀不到 \(marketRel) 或其中沒有 \(allowedPlugin)——算不出允許那一條的 path，每一格都無從比對")
        return 2
    }
    let allowedPath = "plugins[\(idx)] plugin.json → \(allowedField)"
    // 另一個 plugin 的索引（同一個欄位出現在它身上必須紅）；只有一個條目時這一格改用不存在的索引
    let otherIdx = entries.indices.first(where: { $0 != idx }) ?? entries.count

    /// 一份 `claude plugin validate --json` 形狀的報告（只放守衛讀的欄位）
    func report(warnings: [String], errors: [String] = []) -> String {
        func items(_ paths: [String]) -> [[String: Any]] {
            paths.map { ["path": $0, "message": "probe", "code": NSNull()] }
        }
        let obj: [String: Any] = [
            "success": errors.isEmpty,
            "manifest": ["errors": items(errors), "warnings": items(warnings)],
            "contents": [Any](),
        ]
        let d = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return String(data: d, encoding: .utf8) ?? ""
    }

    let cells: [ValidateCell] = [
        .init(desc: "對照組：報告只有允許的那一條 warning",
              report: report(warnings: [allowedPath]), editMarket: nil, wantRC: 0,
              expect: ["通過", allowedPath]),
        .init(desc: "多一條不在允許清單的 warning",
              report: report(warnings: [allowedPath, "plugins[\(idx)] plugin.json → probe_field"]),
              editMarket: nil, wantRC: 1,
              expect: ["不在允許清單", "probe_field"]),
        .init(desc: "同一個欄位出現在別的 plugin（允許清單以名稱定位，不是以欄位）",
              report: report(warnings: [allowedPath, "plugins[\(otherIdx)] plugin.json → \(allowedField)"]),
              editMarket: nil, wantRC: 1,
              expect: ["不在允許清單", "plugins[\(otherIdx)]"]),
        .init(desc: "允許的那一條不再出現（允許清單過期）",
              report: report(warnings: []), editMarket: nil, wantRC: 1,
              expect: ["不再出現"]),
        .init(desc: "報告有一條 error",
              report: report(warnings: [allowedPath], errors: ["plugins[\(idx)] plugin.json → name"]),
              editMarket: nil, wantRC: 1,
              expect: ["error："]),
        .init(desc: "CLI 的輸出不是 JSON",
              report: "not json\n", editMarket: nil, wantRC: 1,
              expect: ["不是 JSON"]),
        .init(desc: "marketplace 沒有 \(allowedPlugin) 這個條目",
              report: report(warnings: [allowedPath]),
              editMarket: { t in
                  let from = "\"name\": \"\(allowedPlugin)\""
                  guard t.contains(from) else { return nil }
                  return t.replacingOccurrences(of: from, with: "\"name\": \"\(allowedPlugin)-renamed\"")
              }, wantRC: 1,
              expect: ["marketplace 沒有 \(allowedPlugin)"]),
        .init(desc: "PATH 上沒有 claude（CI runner 的情況）：略過要看得見",
              report: nil, editMarket: nil, wantRC: 0,
              expect: ["已略過"]),
    ]

    /// 在副本裡跑守衛。副本建不起來、改動套不上時回 nil——該格無效，不算被抓到。
    func run(_ c: ValidateCell) -> (Int32, String)? {
        let tmp = NSTemporaryDirectory() + "official-validate-mut-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: tmp) }
        let root = tmp + "/repo", bin = tmp + "/bin"
        guard (try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)) != nil,
              (try? fm.createDirectory(atPath: bin, withIntermediateDirectories: true)) != nil,
              (try? fm.copyItem(atPath: "\(repoRoot)/.claude-plugin", toPath: root + "/.claude-plugin")) != nil
        else { return nil }
        if let edit = c.editMarket {
            let p = root + "/" + marketRel
            guard let t = try? String(contentsOfFile: p, encoding: .utf8), let n = edit(t),
                  (try? n.write(toFile: p, atomically: true, encoding: .utf8)) != nil else { return nil }
        }
        var searchPath = "/usr/bin:/bin"
        if let r = c.report {
            let reportFile = bin + "/report.json"
            let stub = bin + "/claude"
            guard (try? r.write(toFile: reportFile, atomically: true, encoding: .utf8)) != nil,
                  (try? "#!/bin/sh\n/bin/cat '\(reportFile)'\n".write(toFile: stub, atomically: true, encoding: .utf8)) != nil,
                  (try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)) != nil
            else { return nil }
            searchPath = bin + ":" + searchPath
        }
        // 前提要自己驗：沒有假 claude 的那一格，PATH 上也不能有真的 claude
        if c.report == nil,
           searchPath.split(separator: ":").contains(where: { fm.isExecutableFile(atPath: "\($0)/claude") }) {
            return nil
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: BIN)
        p.arguments = ["official-validate"]
        p.currentDirectoryURL = URL(fileURLWithPath: root)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return (127, "spawn 失敗：\(BIN)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // 工作樹的快照：跑完所有格子之後逐位元比對
    let watched = marketRel
    let before = fm.contents(atPath: "\(repoRoot)/\(watched)")

    var passed = 0
    for c in cells {
        guard let (rc, out) = run(c) else {
            print("✗ \(c.desc) → 副本或假 claude 建不起來、改動套不上，這一格無效"); continue
        }
        let miss = c.expect.filter { !out.contains($0) }
        let head = out.split(separator: "\n").prefix(2).joined(separator: " / ")
        if rc == c.wantRC && miss.isEmpty {
            print("✓ \(c.desc) → rc=\(rc)" + (c.wantRC == 0 ? "（綠）" : "，指名了它")); passed += 1
        } else if rc != c.wantRC {
            print("✗ \(c.desc) → rc=\(rc)，預期 \(c.wantRC)：\(head)")
        } else {
            print("✗ \(c.desc) → rc=\(rc)，但輸出缺 \(pyRepr(miss))：\(head)")
        }
    }

    let untouched = fm.contents(atPath: "\(repoRoot)/\(watched)") == before
    print(untouched ? "✓ 工作樹沒有被寫入：\(watched) 前後逐位元相同"
                    : "✗ 工作樹被改了：\(watched)")
    print("\n══ \(passed)/\(cells.count) 格符合預期（2 格須綠、\(cells.count - 2) 格須紅）══")
    return passed == cells.count && untouched ? 0 : 1
}
