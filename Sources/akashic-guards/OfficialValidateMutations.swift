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
// **假 `claude` 驗引數**（#689 R1 verify）：它只在收到守衛實際會傳的四個引數（`plugin validate --json <repo 根>`）時
// 才印報告，否則 exit 2、印一句不是 JSON 的話——守衛就會紅。所以守衛把引數改掉（丟掉 `--json`、指向別的路徑），
// 綠的那幾格會轉紅。腳本不內插任何路徑：報告放在腳本旁邊，以 `${0%/*}` 找到它。
//
// **PATH 只有這一格造的 bin 目錄**（#689 R1 verify）：先前是「假 claude 的目錄＋`/usr/bin:/bin`」，而「PATH 上沒有 claude」
// 那一格的前提自驗會在 `/usr/bin` 或 `/bin` 裝了 claude 的機器上判這一格無效，整支 harness 因此 rc=1——那是安裝位置
// 造成的假紅。守衛本身只用 `claude`，假 `claude` 只用 `/bin/sh`、`/bin/cat`、`/bin/pwd` 這幾個絕對路徑，都不經 PATH。
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

    /// 一份 `claude plugin validate --json` 形狀的報告（只放守衛讀的欄位）。`contentErrors` 放進 `contents[]` 的一個段落——
    /// 守衛要讀 manifest 與 contents 兩處（R1 verify：先前每一格的 `contents` 都是空的，守衛只讀 manifest 也全綠）。
    func report(warnings: [String], errors: [String] = [], contentErrors: [String] = []) -> String {
        func items(_ paths: [String]) -> [[String: Any]] {
            paths.map { ["path": $0, "message": "probe", "code": NSNull()] }
        }
        let manifest: [String: Any] = ["errors": items(errors), "warnings": items(warnings)]
        var contents: [Any] = []
        if !contentErrors.isEmpty {
            let section: [String: Any] = ["errors": items(contentErrors), "warnings": items([])]
            contents.append(section)
        }
        let obj: [String: Any] = [
            "success": errors.isEmpty && contentErrors.isEmpty,
            "manifest": manifest,
            "contents": contents,
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
        .init(desc: "報告的 contents[] 裡有一條 error（不只 manifest）",
              report: report(warnings: [allowedPath], contentErrors: ["plugins[\(idx)] skills/probe → description"]),
              editMarket: nil, wantRC: 1,
              expect: ["error：", "skills/probe"]),
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
        let searchPath = bin
        if let r = c.report {
            let stub = bin + "/claude"
            // 引數與守衛實際傳的不同就不印報告（見檔頭）。第四個引數與 cwd 比真實路徑：守衛傳的是它自己的 cwd，
            // 而暫存目錄經過 symlink（`/var` → `/private/var`），逐字比會誤判。
            let script = """
                #!/bin/sh
                if [ "$#" -ne 4 ] || [ "$1" != plugin ] || [ "$2" != validate ] || [ "$3" != --json ] \\
                   || [ "$(cd "$4" 2>/dev/null && /bin/pwd -P)" != "$(/bin/pwd -P)" ]; then
                  echo "假 claude：引數不是 plugin validate --json <repo 根>（收到 $*）"
                  exit 2
                fi
                exec /bin/cat "${0%/*}/report.json"

                """
            guard (try? r.write(toFile: bin + "/report.json", atomically: true, encoding: .utf8)) != nil,
                  (try? script.write(toFile: stub, atomically: true, encoding: .utf8)) != nil,
                  (try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)) != nil
            else { return nil }
        }
        // 前提要自己驗：沒有假 claude 的那一格，PATH 上也不能有真的 claude
        if c.report == nil,
           searchPath.split(separator: ":").contains(where: { fm.isExecutableFile(atPath: "\($0)/claude") }) {
            return nil
        }
        // 經 `runGuardProcess` 執行（#707）：它留下執行紀錄，並自己比對 rc 與這一格的預期。
        let r = runGuardProcess([BIN, "official-validate"], cwd: root, env: ["PATH": searchPath],
                                mergeOutput: true, label: c.desc, expect: c.wantRC == 0 ? .green : .red)
        return (r.status, r.combined)
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
    let green = cells.filter { $0.wantRC == 0 }.count
    print("\n══ \(passed)/\(cells.count) 格符合預期（\(green) 格須綠、\(cells.count - green) 格須紅）══")
    return passed == cells.count && untouched ? 0 : 1
}
