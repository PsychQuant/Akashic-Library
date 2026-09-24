// `plugin-roots-mutations`：`plugin/` 以外的 plugin 根，守衛真的看得見嗎？（#625）
//
// **為什麼需要它**：守衛有兩種失效。一種是紅了、你知道；另一種是**根本沒看到那個目錄**
// ——永遠綠，而綠看起來和「沒問題」一模一樣。#625 之前，受保護清單的 glob 全以
// `plugin/` 為根，放進 `plugins/<name>/` 的測試被刪、沒接線、skill 漏引規則，沒有一道
// 守衛會出聲。能排除後者的方法只有一個：故意弄壞，看它紅不紅。
//
// **每一格都有對照組**：同一棵 copy、只做前置（`setup`）不做突變時，守衛必須是綠的——
// 否則紅的原因分不出是突變還是前置本身（`oracle-precondition-control` 的同一個紀律）。
// 對照組不綠，那一格記為無效，不算被抓到。
//
// **探針路徑一律用拼接產生**：trigger-coverage 會掃守衛原始碼裡帶副檔名的路徑字面值，
// 指向不存在的檔即判為缺口。探針只存在於 copy 裡，寫成字面值會讓這支 harness 自己變成缺口。
//
// **複製清單比 `trigger-coverage-mutations` 多 `plugins` 與 `.claude-plugin`**：本 harness
// 的每一格都發生在那兩處。

import Foundation

private struct PluginRootMutation {
    let desc: String
    /// 要跑的守衛。第一個元素是 `akashic-guards` 子命令名，或 `bash` 加腳本路徑
    let guardArgv: [String]
    /// 對照組與突變組共同的前置；回傳 false 表示前置做不出來（該格無效）
    let setup: (String) -> Bool
    /// 突變本身；回傳 false 表示突變套不上（例如目標行不存在）——該格記為未被抓到
    let mutate: (String) -> Bool
    /// 失敗輸出必須包含的字串（肇事者的名字或路徑）
    let expect: String
}

func pluginRootsMutations() -> Int32 {
    let fm = FileManager.default
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    let disc = "plugins/akashic-discovery"
    let probeDir = disc + "/skills/probe/scripts/tests"
    let probe = probeDir + "/probe" + ".sh"
    let guardWorkflow = ".github/workflows/census-parity.yml"
    let entry = ".githooks/run-guards.sh"
    let market = ".claude-plugin/marketplace.json"
    let discManifest = disc + "/.claude-plugin/plugin" + ".json"

    func exec(_ argv: [String], cwd: String) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
        guard (try? p.run()) != nil else { return (127, "spawn 失敗：\(argv[0])") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                (String(data: od, encoding: .utf8) ?? "") + (String(data: ed, encoding: .utf8) ?? ""))
    }

    func runGuard(_ argv: [String], in root: String) -> (Int32, String) {
        argv[0] == "bash" ? exec(["/bin/bash"] + argv.dropFirst(), cwd: root)
                          : exec([BIN] + argv, cwd: root)
    }

    // 檔案操作（全部相對於 copy 的根）
    func write(_ root: String, _ rel: String, _ text: String) -> Bool {
        let path = root + "/" + rel
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        return (try? text.write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }
    func replace(_ root: String, _ rel: String, _ old: String, _ new: String) -> Bool {
        let path = root + "/" + rel
        guard let t = try? String(contentsOfFile: path, encoding: .utf8),
              let r = t.range(of: old) else { return false }
        return (try? t.replacingCharacters(in: r, with: new)
                    .write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }
    func remove(_ root: String, _ rel: String) -> Bool {
        (try? fm.removeItem(atPath: root + "/" + rel)) != nil
    }
    func writeProbe(_ root: String) -> Bool { write(root, probe, "#!/bin/bash\nexit 0\n") }
    func wireProbe(_ root: String) -> Bool {
        let path = root + "/" + entry
        guard let t = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return (try? (t + "\nbash \(probe)\n").write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }
    func acceptRatchet(_ root: String) -> Bool {
        exec([BIN, "protected-ratchet", "--accept"], cwd: root).0 == 0
    }

    /// 複製守衛會讀到的子樹。symlink 以 symlink 複製（`copyItem` 不跟隨），所以 discovery
    /// 的 `rules` 在 copy 裡仍指向 copy 自己的 `plugin/rules`。
    func withCopy(_ body: (String) -> (Int32, String)?) -> (Int32, String)? {
        let tmp = NSTemporaryDirectory() + "plugin-roots-mut-" + UUID().uuidString
        try? fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmp) }
        for sub in ["plugin", "plugins", ".claude-plugin", ".github", ".githooks", "Sources"] {
            let s = "\(repoRoot)/\(sub)"
            if fm.fileExists(atPath: s) { try? fm.copyItem(atPath: s, toPath: tmp + "/" + sub) }
        }
        if fm.fileExists(atPath: "\(repoRoot)/.claude/rules") {
            try? fm.createDirectory(atPath: tmp + "/.claude", withIntermediateDirectories: true)
            try? fm.copyItem(atPath: "\(repoRoot)/.claude/rules", toPath: tmp + "/.claude/rules")
        }
        for f in ["CLAUDE.md", "mcpb/manifest" + ".json"] where fm.fileExists(atPath: "\(repoRoot)/\(f)") {
            try? fm.createDirectory(atPath: tmp + "/" + (f as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
            try? fm.copyItem(atPath: "\(repoRoot)/\(f)", toPath: tmp + "/" + f)
        }
        return body(tmp)
    }

    let consistency = ["marketplace-consistency"]
    let cases: [PluginRootMutation] = [
        .init(desc: "plugins 根下新增未接線的測試",
              guardArgv: ["trigger-coverage"],
              setup: { _ in true },
              mutate: { writeProbe($0) },
              expect: "probe.sh"),
        .init(desc: "刪除 plugins 根下的受保護測試",
              guardArgv: ["protected-ratchet"],
              setup: { writeProbe($0) && wireProbe($0) && acceptRatchet($0) },
              mutate: { remove($0, probe) },
              expect: probe),
        .init(desc: "守衛 workflow 的觸發路徑拿掉 plugins/**",
              guardArgv: ["trigger-coverage"],
              setup: { writeProbe($0) && wireProbe($0) && acceptRatchet($0) },
              mutate: { replace($0, guardWorkflow, "      - \"plugins/**\"\n", "") },
              expect: "probe.sh"),
        .init(desc: "plugins/foo 有 manifest 但沒列入 marketplace",
              guardArgv: consistency,
              setup: { _ in true },
              mutate: { write($0, "plugins/foo" + "/.claude-plugin/plugin" + ".json",
                              "{\"name\": \"foo\", \"version\": \"0.0.1\"}\n") },
              expect: "plugins/foo"),
        .init(desc: "akashic-discovery 條目的 source 指向不存在的目錄",
              guardArgv: consistency,
              setup: { _ in true },
              mutate: { replace($0, market, "\"./plugins/akashic-discovery\"",
                                "\"./plugins/akashic-discovery-missing\"") },
              expect: "akashic-discovery"),
        .init(desc: "discovery 新增一個沒引用任何規則的 skill",
              guardArgv: ["bash", "plugin/tests/rule-coverage.sh", disc],
              setup: { _ in true },
              mutate: { write($0, disc + "/skills/probe-skill/SKILL" + ".md",
                              "---\nname: probe-skill\ndescription: probe\n---\n\n沒有引用任何規則。\n") },
              expect: "probe-skill"),
        .init(desc: "條目名稱與 manifest 名稱不一致",
              guardArgv: consistency,
              setup: { _ in true },
              mutate: { replace($0, discManifest, "\"name\": \"akashic-discovery\"",
                                "\"name\": \"akashic-discover\"") },
              expect: "`akashic-discover`"),
        .init(desc: "plugins 下有沒有 manifest 的雜目錄",
              guardArgv: consistency,
              setup: { _ in true },
              mutate: { write($0, "plugins/scratch" + "/notes" + ".txt", "scratch\n") },
              expect: "plugins/scratch"),
        // 失敗模式（design）：讀不到或解析不了 manifest 必須紅，不得當成「沒有 plugin」而綠
        .init(desc: "marketplace manifest 不存在",
              guardArgv: consistency,
              setup: { _ in true },
              mutate: { remove($0, market) },
              expect: "讀不到"),
        .init(desc: "marketplace manifest 不是 JSON",
              guardArgv: consistency,
              setup: { _ in true },
              mutate: { write($0, market, "not json\n") },
              expect: "不是含 `plugins` 陣列的 JSON 物件"),
        .init(desc: "依賴一個 marketplace 裡不存在的 plugin",
              guardArgv: consistency,
              setup: { _ in true },
              mutate: { replace($0, discManifest, "\"dependencies\": [\"akashic-mcp\"]",
                                "\"dependencies\": [\"akashic-mcp\", \"akashic-core\"]") },
              expect: "akashic-core"),
    ]

    guard fm.isExecutableFile(atPath: BIN) else {
        print("✗ \(BIN) 不存在——先 swift build --product akashic-guards"); return 2
    }
    var caught = 0
    // **plugin-roots 的契約本身**（spec 範例）：沒有 manifest 的子目錄不是根。這是 shell 端
    // 與受保護清單共用的輸出，壞掉時紅在別處——所以在這裡釘住，而不是只在實作時跑一次。
    let rootsOK = withCopy { root -> (Int32, String)? in
        _ = write(root, "plugins/scratch" + "/notes" + ".txt", "scratch\n")
        return exec([BIN, "plugin-roots"], cwd: root)
    }
    let rootsWant = "plugin\n\(disc)\n"
    if let (rc, out) = rootsOK, rc == 0, out == rootsWant {
        print("✓ plugin-roots 只列有 manifest 的根（雜目錄 plugins/scratch 不算）")
    } else {
        print("✗ plugin-roots 的輸出不符 spec 範例：\(pyRepr([rootsOK?.1 ?? "（copy 建不起來）"]))")
        return 1
    }
    // **symlink 規則不重複計數**（spec 情境）：discovery 的 `rules` 指向 `plugin/rules`，
    // 受保護清單裡不得出現經由它的路徑——否則同一條規則是兩個成員，刪一個看不到。
    let viaLink = protectedInventory().data.filter { p in
        pluginRoots().contains { $0 != "plugin" && p.hasPrefix("\($0)/rules/") }
    }
    if viaLink.isEmpty {
        print("✓ 受保護清單沒有經 rules symlink 的路徑（規則以真實路徑計一次）")
    } else {
        print("✗ 受保護清單有經 rules symlink 的路徑：\(pyRepr(viaLink))"); return 1
    }
    for c in cases {
        let label = "\(c.desc)〔\(c.guardArgv.joined(separator: " "))〕"
        // 對照組：只做前置
        guard let (ctlRC, ctlOut) = withCopy({ root in
            c.setup(root) ? runGuard(c.guardArgv, in: root) : nil
        }) else {
            print("✗ \(label) → 前置做不出來，這一格無效"); continue
        }
        guard ctlRC == 0 else {
            // 挑缺口行（`·`／`✗` 開頭）而不是前兩行——守衛常先印 `ℹ` 資訊行，那不是紅的原因
            let lines = ctlOut.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let gapLines = lines.filter { $0.hasPrefix("·") || $0.hasPrefix("✗") }
            let head = (gapLines.isEmpty ? lines : gapLines).prefix(2).joined(separator: " / ")
            print("✗ \(label) → 對照組不是綠的（rc=\(ctlRC)），這一格證明不了任何事：\(head)")
            continue
        }
        // 突變組：前置＋突變
        var applied = true
        guard let (rc, out) = withCopy({ root in
            guard c.setup(root) else { return nil }
            applied = c.mutate(root)
            return applied ? runGuard(c.guardArgv, in: root) : (0, "")
        }) else {
            print("✗ \(label) → 前置做不出來，這一格無效"); continue
        }
        if !applied {
            print("✗ \(label) → 突變套不上（目標不存在），未被抓到"); continue
        }
        if rc != 0 && out.contains(c.expect) {
            print("✓ \(label) → rc=\(rc)，指名了 \(c.expect)"); caught += 1
        } else if rc != 0 {
            print("✗ \(label) → rc=\(rc)，但沒指名 \(c.expect) ← 紅的原因不是這個突變")
        } else {
            print("✗ \(label) → 守衛是綠的 ← 它看不見這個突變")
        }
    }
    print("\n══ \(caught)/\(cases.count) 個突變被抓到 ══")
    return caught == cases.count ? 0 : 1
}
