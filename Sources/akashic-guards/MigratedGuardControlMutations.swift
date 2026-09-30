// `migrated-guard-control-mutations`：`migrated-guard-control` 讀執行紀錄之後，#689 那些掏空的寫法它真的看得見嗎？（#707）
//
// **每一格都是真的執行，不是文字比對**。`migrated-guard-control` 的判準是「這次執行裡，哪支 harness 真的讓哪支守衛
// 如預期變紅過」，所以它的負控也要**真的建置、真的執行**：
//
//   1. **掏空的原始碼**（#689 R2 的四種、#707 comment 的第 3–5 種）：把 `Sources/akashic-guards/*.swift` 複製到暫存
//      目錄、套上那個寫法、以 `swiftc` 編成一支 scratch binary，用它跑一個迷你 runner（那支守衛＋它的 harness），
//      再讓 `migrated-guard-control` 讀那次執行的紀錄——必須紅，而且指名那支守衛。
//   2. **runner 的寫法**（#707 comment 的第 6–8 種）：迷你 runner 用那個寫法呼叫。`if false`／heredoc 包住的那一行
//      必須紅；目錄或名字放進變數、換一個路徑的同一支 binary，執行期照樣看得見（第 7、8 種現在無關緊要）——而跑的
//      binary 不寫紀錄時，runner 文字裡那一行必須被報出來。
//   3. **改壞的紀錄**：從健康那一格的紀錄出發，逐格改一處（刪 `end`、刪 `declare`、改 rc、改 `met`、換 binary、
//      加一行不是 JSON 的……），讀者必須紅並說出是哪一處。紀錄讀不到、是空的、不是這一次的，也各一格。
//   4. **記錄端**（一格）：寫紀錄的共用函式 `runGuardProcess` 不能把沒跑起來的子行程記成「如預期變紅」
//      （`spawn-probe` 帶自己的紀錄檔執行它，讀回那一筆 `invoke` 的 `met`）。
//
// **對照組**：健康的迷你 runner（`decision-matrix-drift`＋`decision-matrix-mutations`，出貨的 binary）必須綠；
// 第 7 種的「目錄放進變數」也必須綠（寫法換了，執行照樣被記下、照樣有負控）。對照組不綠，其餘各格證明不了任何事。
//
// **每份迷你紀錄開頭有一支假 harness 替 `migrated-guard-control` 本身作證**：讀者自己永遠在它讀的紀錄裡（它自己的
// `start`），而這些格子要測的是別的守衛。那四行是固定的測試資料（`fixture-harness`），不是任何行程寫的。
//
// **成本**：七支 scratch binary 平行建置（`xcrun swiftc -Onone`，每支單執行緒約 7 秒），十四個迷你 runner 平行跑
// （最慢的是 O1——被掏空的 `plugin-roots-mutations` 照樣跑完它所有格子）。量測見 `changelog/2026-10-01-guard-control-runtime-evidence.md`。
//
// **只寫暫存目錄**：scratch 原始碼、binary、迷你 runner 與紀錄全在 `NSTemporaryDirectory()` 底下；工作樹的
// `run-guards.sh` 與 `Sources/akashic-guards/` 最後逐位元比對一次。

import Foundation

private struct ScratchEdit {
    let file: String          // `Sources/akashic-guards/` 底下的檔名
    let old: String
    let new: String
    let all: Bool
}

private struct ScratchShape {
    let id: String
    let edits: [ScratchEdit]
}

private struct MiniCell {
    let id: String
    let desc: String
    /// 用哪一支 binary：nil＝出貨的那支，否則是 `ScratchShape.id`
    let scratch: String?
    /// 迷你 runner 的每一行。`@B@`＝這一格的 binary 路徑、`@WORK@`＝暫存目錄
    let lines: [String]
    let wantRC: Int32
    let expect: [String]
    let mustNot: [String]
}

private struct LogCell {
    let desc: String
    /// 從健康紀錄（已解析的行）改出這一格的紀錄內容；nil＝這一格有自己的做法（見下）
    let mutate: (([[String: Any]]) -> [[String: Any]]?)?
    /// 直接寫進檔的原文（空檔、壞行）
    let raw: ((String) -> String)?
    let expect: [String]
}

func migratedGuardControlMutations() -> Int32 {
    let fm = FileManager.default
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    guard fm.isExecutableFile(atPath: BIN) else {
        print("✗ \(BIN) 不存在——先 swift build --product akashic-guards"); return 2
    }
    let guardsDir = "Sources/akashic-guards"
    let work = NSTemporaryDirectory() + "mgc-mut-" + UUID().uuidString
    guard (try? fm.createDirectory(atPath: work, withIntermediateDirectories: true)) != nil else {
        print("✗ 建不了暫存目錄 \(work)"); return 2
    }
    defer { try? fm.removeItem(atPath: work) }
    let ownExe = GuardRunLog.resolvedExecutable(BIN)
    let logName = "run" + ".jsonl"
    let runnerName = "runner" + ".sh"

    // 工作樹的快照：runner 與守衛的原始碼，最後逐位元比對
    let watched = [".githooks/run-guards.sh"]
        + ((try? fm.contentsOfDirectory(atPath: "\(repoRoot)/\(guardsDir)")) ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted().map { "\(guardsDir)/\($0)" }
    func snapshot() -> [String: Data] {
        var s: [String: Data] = [:]
        for r in watched { s[r] = fm.contents(atPath: "\(repoRoot)/\(r)") ?? Data() }
        return s
    }
    let before = snapshot()

    func jsonLine(_ obj: [String: Any]) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(data: d, encoding: .utf8) ?? ""
    }
    let fixtureRun = "fixture-" + UUID().uuidString
    let preamble: [[String: Any]] = [
        ["v": 1, "event": "start", "run": fixtureRun, "self": "fixture-harness"],
        ["v": 1, "event": "declare", "run": fixtureRun, "self": "fixture-harness", "for": ["migrated-guard-control"]],
        ["v": 1, "event": "invoke", "run": fixtureRun, "self": "fixture-harness", "target": "migrated-guard-control",
         "exe": ownExe, "expect": "red", "met": true, "rc": 1, "case": "fixture", "argv": ["migrated-guard-control"]],
        ["v": 1, "event": "end", "run": fixtureRun, "self": "fixture-harness", "rc": 0],
    ]

    // ── 1. 掏空的原始碼：每一種一支 scratch binary ─────────────────────────────
    let shapes: [ScratchShape] = [
        // #689 R2（DA）第 1 種＝#707 的原始第 1 種：case 表重構後只剩變數宣告，七處 `guardArgv: consistency` 全換掉
        .init(id: "o1", edits: [
            .init(file: "PluginRootsMutations.swift", old: "guardArgv: consistency,",
                  new: #"guardArgv: ["protected-ratchet"],"#, all: true),
        ]),
        // #707 comment 第 3 種：宣告換行、改成巢狀陣列，真正執行的那一處換成別的守衛
        .init(id: "c3", edits: [
            .init(file: "OfficialValidateMutations.swift",
                  old: #"let r = runGuardProcess([BIN, "official-validate"], cwd: root,"#,
                  new: #"""
                  let officialArgv =
                              [["official-validate"]]
                          _ = officialArgv
                          let r = runGuardProcess([BIN, "plugin-roots"], cwd: root,
                  """#, all: false),
        ]),
        // #707 原始第 2 種：刪掉一支守衛的整條負控鏈，在別的 harness 加宣告註解、死的變數宣告與一個沒人呼叫的函式
        // （裡面是執行期的宣告與一次預期變紅的執行）
        .init(id: "o2", edits: [
            .init(file: "DecisionMatrixMutations.swift", old: "import Foundation\n", new: #"""
                  import Foundation

                  // negative-control-for: rule-prose-guards
                  let _deadDeclaration = ["rule-prose-guards"]
                  func _deadNegativeControl() {
                      declareNegativeControl(for: ["rule-prose-guards"])
                      _ = runGuardProcess(["\(repoRoot)/.build/debug/akashic-guards", "rule-prose-guards"], cwd: repoRoot,
                                          label: "死碼", expect: .red)
                  }

                  """#, all: false),
        ]),
        // #707 原始第 3 種：分派改成 `exit(0)`
        .init(id: "o3", edits: [
            .init(file: "main.swift", old: "case \"decision-matrix-mutations\":\n    finishGuard(decisionMatrixMutations())",
                  new: "case \"decision-matrix-mutations\":\n    exit(0)", all: false),
        ]),
        // #707 原始第 4 種：一般守衛在自己的 source 塞 `Process()` 與 binary 路徑，冒充「自己就是負控」
        .init(id: "o4", edits: [
            .init(file: "WorkflowRunScripts.swift", old: "import Foundation\n", new: #"""
                  import Foundation
                  func _unusedNeverCalled() { let p = Process(); _ = p; _ = ".build/debug/akashic-guards" }

                  """#, all: false),
        ]),
        // #707 comment 第 4 種：函式本體先 `return 0`，其餘包進 `#if false … #endif`
        .init(id: "c4", edits: [
            .init(file: "NetworkConfinementMutations.swift", old: "func networkConfinementMutations() -> Int32 {\n",
                  new: "func networkConfinementMutations() -> Int32 {\n    return 0\n#if false\n", all: false),
            .init(file: "NetworkConfinementMutations.swift",
                  old: "    return passed == total && untouched ? 0 : 1\n}",
                  new: "    return passed == total && untouched ? 0 : 1\n#endif\n}", all: false),
        ]),
        // #707 comment 第 5 種：照常被分派、被執行，但只 `return 0`；執行的寫法全放在 `"""` 字串裡
        .init(id: "c5", edits: [
            .init(file: "TriggerCoverageMutations.swift", old: "func triggerCoverageMutations() -> Int32 {\n", new: #"""
                  func triggerCoverageMutations() -> Int32 {
                      _ = """
                          let p = Process()
                          p.executableURL = URL(fileURLWithPath: "/.build/debug/akashic-guards")
                          p.arguments = ["trigger-coverage"]
                          _ = runGuardProcess([BIN, "trigger-coverage"], cwd: root, label: "x", expect: .red)
                          """
                      return 0

                  """#, all: false),
        ]),
    ]

    // 建置：複製原始碼、套寫法、平行編譯。套不上的寫法（目標文字不在）＝那一格無效，不是被抓到
    let sources = ((try? fm.contentsOfDirectory(atPath: "\(repoRoot)/\(guardsDir)")) ?? []).filter { $0.hasSuffix(".swift") }
    var scratchBin: [String: String] = [:]
    var scratchBroken: [String: String] = [:]
    var builds: [(String, Process, String)] = []
    let buildStart = Date()
    for s in shapes {
        let src = "\(work)/\(s.id)/src", bin = "\(work)/\(s.id)/bin"
        try? fm.createDirectory(atPath: src, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
        for f in sources { try? fm.copyItem(atPath: "\(repoRoot)/\(guardsDir)/\(f)", toPath: "\(src)/\(f)") }
        var applied = true
        for e in s.edits {
            let p = "\(src)/\(e.file)"
            guard let t = try? String(contentsOfFile: p, encoding: .utf8), t.contains(e.old) else {
                scratchBroken[s.id] = "寫法套不上（\(e.file) 裡找不到要改的那段）"; applied = false; break
            }
            let u: String
            if e.all { u = t.replacingOccurrences(of: e.old, with: e.new) }
            else { u = t.replacingCharacters(in: t.range(of: e.old)!, with: e.new) }
            try? u.write(toFile: p, atomically: true, encoding: .utf8)
        }
        guard applied else { continue }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["swiftc", "-Onone", "-module-name", "akashic_guards", "-o", "\(bin)/akashic-guards"]
            + sources.sorted().map { "\(src)/\($0)" }
        let logf = "\(work)/\(s.id)/build.txt"
        fm.createFile(atPath: logf, contents: nil)
        let h = FileHandle(forWritingAtPath: logf) ?? FileHandle.nullDevice
        p.standardOutput = h; p.standardError = h
        if (try? p.run()) != nil { builds.append((s.id, p, logf)) }
        else { scratchBroken[s.id] = "xcrun swiftc 啟動不了" }
    }
    for (id, p, logf) in builds {
        p.waitUntilExit()
        let bin = "\(work)/\(id)/bin/akashic-guards"
        if p.terminationStatus == 0, fm.isExecutableFile(atPath: bin) {
            scratchBin[id] = bin
        } else {
            let msg = (try? String(contentsOfFile: logf, encoding: .utf8)) ?? ""
            let firstError = msg.split(separator: "\n").first(where: { $0.contains("error:") }).map(String.init) ?? "（沒有 error 行）"
            scratchBroken[id] = "編不起來（rc=\(p.terminationStatus)）：\(String(firstError.prefix(200)))"
        }
    }
    let buildSeconds = Date().timeIntervalSince(buildStart)
    print("scratch binary：\(scratchBin.count)/\(shapes.count) 支建置完成（平行，\(String(format: "%.1f", buildSeconds)) 秒）")

    // ── 2. 迷你 runner ─────────────────────────────────────────────────────
    // C8 的兩支替身：同一支 binary 放在另一個路徑（`.build/release` 的替身），與一支不寫紀錄的舊 binary
    let releaseDir = "\(work)/release", staleDir = "\(work)/stale"
    try? fm.createDirectory(atPath: releaseDir, withIntermediateDirectories: true)
    try? fm.createDirectory(atPath: staleDir, withIntermediateDirectories: true)
    try? fm.copyItem(atPath: BIN, toPath: "\(releaseDir)/akashic-guards")
    let stale = "\(staleDir)/akashic-guards"
    try? "#!/bin/sh\nexit 0\n".write(toFile: stale, atomically: true, encoding: .utf8)
    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stale)

    let dmm = [#""@B@" decision-matrix-drift"#, #""@B@" decision-matrix-mutations"#]
    let ranButUncovered = { (g: String) in "`akashic-guards \(g)` 這次執行跑了" }
    let notStarted = { (g: String) in "呼叫 `akashic-guards \(g)`，但這次執行的紀錄裡沒有它的 start" }
    let cells: [MiniCell] = [
        .init(id: "healthy", desc: "對照組：守衛＋它的 harness，出貨的 binary", scratch: nil, lines: dmm,
              wantRC: 0, expect: ["`decision-matrix-drift` ← decision-matrix-mutations", "無缺口"], mustNot: []),
        .init(id: "o1", desc: "#707-1：負控只剩變數宣告，沒有任何一格再執行它（plugin-roots-mutations）", scratch: "o1",
              lines: [#""@B@" marketplace-consistency"#, #""@B@" plugin-roots-mutations"#],
              wantRC: 1, expect: [ranButUncovered("marketplace-consistency")], mustNot: []),
        .init(id: "c3", desc: "#707 comment 3：宣告換行、改成巢狀陣列，真正執行的換成別的守衛（official-validate-mutations）",
              scratch: "c3",
              lines: [#"PATH=/usr/bin:/bin "@B@" official-validate"#, #""@B@" official-validate-mutations"#],
              wantRC: 1, expect: [ranButUncovered("official-validate")], mustNot: []),
        .init(id: "o2", desc: "#707-2：負控鏈刪掉，別的 harness 加宣告註解、死的宣告與沒人呼叫的執行", scratch: "o2",
              lines: dmm + [#""@B@" rule-prose-guards --venue Sources/AkashicCore/Venue.swift"#],
              wantRC: 1, expect: [ranButUncovered("rule-prose-guards"), "`decision-matrix-drift` ← decision-matrix-mutations"],
              mustNot: []),
        .init(id: "o3", desc: "#707-3：main.swift 把 harness 的分派改成 exit(0)", scratch: "o3", lines: dmm,
              wantRC: 1, expect: [ranButUncovered("decision-matrix-drift")], mustNot: []),
        .init(id: "o4", desc: "#707-4：守衛本體塞 Process() 與 binary 路徑，冒充自己就是負控", scratch: "o4",
              lines: [#""@B@" workflow-run-scripts"#],
              wantRC: 1, expect: [ranButUncovered("workflow-run-scripts")],
              mustNot: ["`akashic-guards workflow-run-scripts` 沒有負控，但它**自己就是**負控"]),
        .init(id: "c4", desc: "#707 comment 4：harness 本體先 return 0，其餘包進 #if false", scratch: "c4",
              lines: [#""@B@" network-confinement"#, #""@B@" network-confinement-mutations"#],
              wantRC: 1, expect: [ranButUncovered("network-confinement"), "宣告是空的"], mustNot: []),
        .init(id: "c5", desc: "#707 comment 5：harness 只 return 0，執行的寫法全在 \"\"\" 字串裡", scratch: "c5",
              lines: [#""@B@" trigger-coverage"#, #""@B@" trigger-coverage-mutations"#],
              wantRC: 1, expect: [ranButUncovered("trigger-coverage"), "宣告是空的"], mustNot: []),
        .init(id: "c6a", desc: "#707 comment 6：runner 把 harness 那一行包進 if false", scratch: nil,
              lines: [dmm[0], "if false; then", dmm[1], "fi"],
              wantRC: 1, expect: [ranButUncovered("decision-matrix-drift"), notStarted("decision-matrix-mutations")],
              mustNot: []),
        .init(id: "c6b", desc: "#707 comment 6：runner 把 harness 那一行放進 heredoc", scratch: nil,
              lines: [dmm[0], ": <<'SKIP'", dmm[1], "SKIP"],
              wantRC: 1, expect: [ranButUncovered("decision-matrix-drift"), notStarted("decision-matrix-mutations")],
              mustNot: []),
        .init(id: "c7a", desc: "#707 comment 7：目錄放進變數——執行照樣被記下、照樣有負控（對照組）", scratch: nil,
              lines: ["B=.build/debug", #""$B/akashic-guards" decision-matrix-drift"#,
                      #""$B/akashic-guards" decision-matrix-mutations"#],
              wantRC: 0, expect: ["`decision-matrix-drift` ← decision-matrix-mutations", "無缺口"], mustNot: []),
        .init(id: "c7b", desc: "#707 comment 7：連名字都放進變數（文字看不到）——執行期看得到，沒有負控就紅", scratch: nil,
              lines: ["G=akashic-guards", #"".build/debug/$G" workflow-run-scripts"#],
              wantRC: 1, expect: [ranButUncovered("workflow-run-scripts")], mustNot: []),
        .init(id: "c8a", desc: "#707 comment 8：同一支 binary 換一個路徑（.build/release 的替身）——照樣被記下", scratch: nil,
              lines: ["R=@WORK@/release", #""$R/akashic-guards" workflow-run-scripts"#],
              wantRC: 1, expect: [ranButUncovered("workflow-run-scripts")], mustNot: []),
        .init(id: "c8b", desc: "#707 comment 8：跑的是不寫紀錄的舊 binary——runner 文字裡那一行被報出來", scratch: nil,
              lines: ["S=@WORK@/stale", #""$S/akashic-guards" decision-matrix-drift"#],
              wantRC: 1, expect: [notStarted("decision-matrix-drift")], mustNot: []),
    ]

    var runs: [(MiniCell, Process, String, String)] = []    // cell, bash, 紀錄, runner
    var skipped: [String: String] = [:]
    let runStart = Date()
    for c in cells {
        let dir = "\(work)/cell-\(c.id)"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let b: String
        if let s = c.scratch {
            guard let sb = scratchBin[s] else { skipped[c.id] = scratchBroken[s] ?? "scratch binary 不在"; continue }
            b = sb
        } else { b = BIN }
        let log = "\(dir)/\(logName)", runner = "\(dir)/\(runnerName)"
        let body = c.lines.map { $0.replacingOccurrences(of: "@B@", with: b).replacingOccurrences(of: "@WORK@", with: work) }
        try? (["#!/bin/bash"] + body).joined(separator: "\n").appending("\n")
            .write(toFile: runner, atomically: true, encoding: .utf8)
        try? (preamble.map(jsonLine).joined(separator: "\n") + "\n").write(toFile: log, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [runner]
        p.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        var env = ProcessInfo.processInfo.environment
        env[GuardRunLog.envKey] = log
        p.environment = env
        let outf = "\(dir)/out.txt"
        fm.createFile(atPath: outf, contents: nil)
        let h = FileHandle(forWritingAtPath: outf) ?? FileHandle.nullDevice
        p.standardOutput = h; p.standardError = h
        if (try? p.run()) != nil { runs.append((c, p, log, runner)) } else { skipped[c.id] = "bash 啟動不了" }
    }
    for (_, p, _, _) in runs { p.waitUntilExit() }
    print("迷你 runner：\(runs.count)/\(cells.count) 個跑完（平行，\(String(format: "%.1f", Date().timeIntervalSince(runStart))) 秒）\n")

    // ── 3. 讀者：每一格讓 migrated-guard-control 讀那份紀錄 ────────────────────
    var passed = 0, total = 0
    func control(log: String, runner: String, envLog: String, _ label: String, wantRC: Int32) -> GuardSpawn {
        runGuardProcess([BIN, "migrated-guard-control", "--log", log, "--runner", runner], cwd: repoRoot,
                        env: [GuardRunLog.envKey: envLog], mergeOutput: true,
                        label: label, expect: wantRC == 0 ? .green : .red)
    }
    func judge(_ desc: String, _ r: GuardSpawn, wantRC: Int32, expect: [String], mustNot: [String]) {
        total += 1
        let miss = expect.filter { !r.combined.contains($0) }
        let stray = mustNot.filter { r.combined.contains($0) }
        let gap = r.combined.split(separator: "\n").filter { $0.contains("✗") }.prefix(2)
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(160)) }.joined(separator: " / ")
        if r.status == wantRC && miss.isEmpty && stray.isEmpty {
            print("✓ \(desc) → rc=\(r.status)" + (wantRC == 0 ? "（綠）" : "，指名了它")); passed += 1
        } else if r.status != wantRC {
            print("✗ \(desc) → rc=\(r.status)，預期 \(wantRC)：\(gap)")
        } else if !miss.isEmpty {
            print("✗ \(desc) → rc=\(r.status)，但輸出缺 \(pyRepr(miss))：\(gap)")
        } else {
            print("✗ \(desc) → rc=\(r.status)，但輸出不該有 \(pyRepr(stray))")
        }
    }

    var pristine: [[String: Any]]? = nil
    var healthyRunner: String? = nil
    for c in cells {
        if let why = skipped[c.id] {
            total += 1; print("✗ \(c.desc) → 這一格沒有跑起來：\(why)"); continue
        }
        guard let (_, _, log, runner) = runs.first(where: { $0.0.id == c.id }) else { continue }
        if c.id == "healthy" {
            // 讀者會在紀錄尾端加上自己的 start／end——先留一份乾淨的，給第 3 組改
            let text = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
            pristine = text.split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
            healthyRunner = runner
        }
        judge(c.desc, control(log: log, runner: runner, envLog: log, c.desc, wantRC: c.wantRC),
              wantRC: c.wantRC, expect: c.expect, mustNot: c.mustNot)
    }

    // ── 改壞的紀錄（從健康那一格出發）────────────────────────────────────────
    func isDMM(_ o: [String: Any]) -> Bool { o["self"] as? String == "decision-matrix-mutations" }
    let dmmDrift = ranButUncovered("decision-matrix-drift")
    let logCells: [LogCell] = [
        .init(desc: "紀錄：harness 沒有結束紀錄（沒經過 finishGuard）",
              mutate: { ls in ls.filter { !(isDMM($0) && $0["event"] as? String == "end") } }, raw: nil,
              expect: ["沒有結束紀錄", dmmDrift]),
        .init(desc: "紀錄：harness 以 rc=1 結束（runner 以 || true 遮掉）",
              mutate: { ls in ls.map { o in
                  var o = o; if isDMM(o) && o["event"] as? String == "end" { o["rc"] = 1 }; return o } },
              raw: nil, expect: ["以 rc=1 結束", dmmDrift]),
        .init(desc: "紀錄：harness 沒有宣告那支守衛（順帶跑不算）",
              mutate: { ls in ls.filter { !(isDMM($0) && $0["event"] as? String == "declare") } }, raw: nil,
              expect: ["沒有宣告它——順帶跑不算", dmmDrift]),
        .init(desc: "紀錄：一次預期紅、實際綠，harness 仍以 rc=0 跑完（它沒有比對結果）",
              mutate: { ls in
                  guard let i = ls.firstIndex(where: { isDMM($0) && $0["event"] as? String == "invoke"
                      && $0["expect"] as? String == "red" }) else { return nil }
                  var out = ls; out[i]["met"] = false; out[i]["rc"] = 0; return out
              }, raw: nil, expect: ["沒有照它自己的預期"]),
        .init(desc: "紀錄：harness 執行的不是這一支 binary",
              mutate: { ls in ls.map { o in
                  var o = o; if isDMM(o) && o["event"] as? String == "invoke" { o["exe"] = "/nonexistent/akashic-guards" }
                  return o } },
              raw: nil, expect: ["不是這一支 binary", dmmDrift]),
        .init(desc: "紀錄：harness 宣告它是自己的負控",
              mutate: { ls in
                  guard let run = ls.first(where: isDMM)?["run"] else { return nil }
                  return ls + [["v": 1, "event": "declare", "run": run, "self": "decision-matrix-mutations",
                                "for": ["decision-matrix-mutations"]]]
              }, raw: nil, expect: ["宣告它是自己的負控"]),
        .init(desc: "紀錄：harness 宣告一支這次沒跑的守衛",
              mutate: { ls in
                  guard let run = ls.first(where: isDMM)?["run"] else { return nil }
                  return ls + [["v": 1, "event": "declare", "run": run, "self": "decision-matrix-mutations",
                                "for": ["no-such-guard"]]]
              }, raw: nil, expect: ["`no-such-guard` 這次沒有跑"]),
        .init(desc: "紀錄：有一筆 invoke 找不到它的 start",
              mutate: { ls in
                  guard var inv = ls.first(where: { isDMM($0) && $0["event"] as? String == "invoke" }) else { return nil }
                  inv["run"] = "orphan-run"; return ls + [inv]
              }, raw: nil, expect: ["有 0 筆 start", "紀錄不可信"]),
        .init(desc: "紀錄：有一行不是 JSON", mutate: nil, raw: { $0 + "not json\n" },
              expect: ["不是 JSON 物件", "紀錄不可信"]),
        .init(desc: "紀錄：是空的", mutate: nil, raw: { _ in "" }, expect: ["執行紀錄是空的"]),
    ]
    let pristineOK = pristine.map { !$0.isEmpty } ?? false
    for (i, lc) in logCells.enumerated() {
        guard pristineOK, let base = pristine, let runner = healthyRunner else {
            total += 1; print("✗ \(lc.desc) → 健康那一格沒有留下紀錄，這一格無從改起"); continue
        }
        let path = "\(work)/log-\(i)-" + logName
        let baseText = base.map(jsonLine).joined(separator: "\n") + "\n"
        let text: String
        if let raw = lc.raw { text = raw(baseText) }
        else if let m = lc.mutate, let ls = m(base) { text = ls.map(jsonLine).joined(separator: "\n") + "\n" }
        else { total += 1; print("✗ \(lc.desc) → 改動套不上（健康紀錄裡沒有要改的那一行），這一格無效"); continue }
        if lc.raw == nil && text == baseText {
            total += 1; print("✗ \(lc.desc) → 改動沒有改到任何東西，這一格無效"); continue
        }
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        judge(lc.desc, control(log: path, runner: runner, envLog: path, lc.desc, wantRC: 1),
              wantRC: 1, expect: lc.expect, mustNot: [])
    }
    // 讀不到的紀錄、以及 --log 不是本支正在寫的那一份（環境變數指向別處）
    if let runner = healthyRunner, let base = pristine {
        let missing = "\(work)/no-such-" + logName
        judge("紀錄：--log 指向不存在的檔", control(log: missing, runner: runner, envLog: "\(work)/elsewhere-" + logName,
                                               "紀錄：--log 指向不存在的檔", wantRC: 1),
              wantRC: 1, expect: ["讀不到執行紀錄"], mustNot: [])
        let copy = "\(work)/copy-" + logName, elsewhere = "\(work)/elsewhere2-" + logName
        try? (base.map(jsonLine).joined(separator: "\n") + "\n").write(toFile: copy, atomically: true, encoding: .utf8)
        judge("紀錄：--log 不是本支正在寫的那一份（別次執行留下的）",
              control(log: copy, runner: runner, envLog: elsewhere, "紀錄：--log 不是本支正在寫的那一份", wantRC: 1),
              wantRC: 1, expect: ["沒有本支這一次執行的 start"], mustNot: [])
    } else {
        total += 2; print("✗ 讀不到／不是這一次的紀錄兩格 → 健康那一格沒有留下紀錄，無從做起")
    }

    // ── 記錄端：子行程根本沒跑起來，`runGuardProcess` 不能把它記成「如預期變紅」──────────
    // 這一格測的不是讀者而是寫紀錄的那個共用函式：harness 若讓一次沒有發生的執行（binary 不在、spawn 失敗）
    // 進紀錄成「守衛紅了」，它就替自己說了一次沒做過的執行。`spawn-probe` 帶自己的紀錄檔（不是這一次的）執行它。
    do {
        total += 1
        let probeLog = "\(work)/probe-" + logName
        try? "".write(toFile: probeLog, atomically: true, encoding: .utf8)
        let r = runGuardProcess([BIN, "spawn-probe"], cwd: repoRoot, env: [GuardRunLog.envKey: probeLog],
                                mergeOutput: true, label: "記錄端：spawn 不起來的子行程", expect: .green)
        let recorded = ((try? String(contentsOfFile: probeLog, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
        let inv = recorded.first { $0["event"] as? String == "invoke" }
        if r.status == 0, let inv, inv["rc"] as? Int == 127, inv["expect"] as? String == "red", inv["met"] as? Bool == false {
            print("✓ 記錄端：spawn 不起來的子行程記成 rc=127、met=false（不會被算成「如預期變紅」）"); passed += 1
        } else {
            print("✗ 記錄端：spawn 不起來的子行程 → probe rc=\(r.status)，紀錄 \(recorded.count) 行，invoke=\(inv.map(jsonLine) ?? "無")")
        }
    }

    let untouched = snapshot() == before
    print(untouched ? "✓ 工作樹沒有被寫入：\(watched.count) 個檔前後逐位元相同"
                    : "✗ 工作樹被改了：\(watched.filter { fm.contents(atPath: "\(repoRoot)/\($0)") != before[$0] })")
    let green = cells.filter { $0.wantRC == 0 }.count
    print("\n=== negative control \(passed)/\(total)（\(green) 格須綠、\(total - green - 1) 格須紅、1 格記錄端；"
        + "scratch 建置 \(shapes.count) 支、迷你 runner \(cells.count) 個、改壞的紀錄 \(logCells.count + 2) 份）===")
    return passed == total && untouched ? 0 : 1
}
