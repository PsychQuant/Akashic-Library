// `plugin-shell-version-mutations`：`plugin-shell-version` 真的會紅嗎？（#613 b41；b43 補上被推送的 commit、只增不改、內容在表之外改了、
// symlink 解不開、檔案模式、分支落後 main 等格——b42 第 1–3、6、11、14、15、17、19、21 則）
//
// **為什麼需要它**：這支守衛最可能的失效是永遠綠——摘要漏算一類檔（未追蹤的、symlink 之後的）、已發布的那一半沒接上、表的格式錯了
// 被略過、看的是工作樹而推上去的是另一份。綠看起來與「殼的內容與版號一致」一模一樣。所以逐格注入，看它紅不紅、紅的理由對不對。
//
// **全部在暫存的 git repo 裡**：兩個 plugin 根（`plugin/` 與 `plugins/disc/`，後者的 `rules` 是指向 `plugin/rules` 的 symlink，與 repo 的
// akashic-discovery 同形；`plugin/bin/` 有一個可執行檔）、一份版號表，commit 之後把 `refs/remotes/origin/main` 指到那個 commit——「已推上 main」。
// 每一格複製那個 repo、改一件事、在那裡跑守衛；推送的那幾格另給 `AKASHIC_PUSH_REFS`／`AKASHIC_PUSH_REMOTE`（pre-push 交給守衛的同一組值）。
// **git 一律剝除 `GIT_*`**（`pluginShellGit`；pre-push 裡 git 注入的 `GIT_DIR` 會讓 fixture 的 git 作用在真實 repo，2026-08-12 發生過），
// `git init` 之後另驗 git dir 在暫存目錄裡（第二道圍籬）。真實 repo 的版號表與兩份 `plugin.json` 前後逐位元比對。
//
// **摘要不由這裡算**：第一格在空表上跑守衛，從它的失敗訊息裡取要記的那一列——那也驗了訊息印出的列可以照抄。
//
// 每一格：守衛的 rc 符合預期（經 `runGuardProcess`，留執行紀錄），紅的那幾格另要求輸出含指名的那一句——紅的理由不對，這一格不算；
// 有幾格另要求輸出**不含**某一句（例如內容在表之外改了的那一格不得建議改表）。

import Foundation

func pluginShellVersionMutations() -> Int32 {
    let fm = FileManager.default
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    guard fm.isExecutableFile(atPath: BIN) else { print("✗ \(BIN) 不存在——先 swift build --product akashic-guards"); return 2 }
    let work = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path + "/plugin-shell-version-mut-" + UUID().uuidString
    defer { try? fm.removeItem(atPath: work) }
    guard (try? fm.createDirectory(atPath: work, withIntermediateDirectories: true)) != nil else { print("✗ 建不了暫存目錄"); return 2 }

    // ── 真實 repo 的快照（最後比對）──────────────────────────────────────
    let watched = [pluginShellVersionsPath] + pluginRoots().map { "\($0)/\(pluginManifestRel)" }
    func snapshot() -> [String: Data] {
        var s: [String: Data] = [:]
        for p in watched { s[p] = fm.contents(atPath: "\(repoRoot)/\(p)") ?? Data() }
        return s
    }
    let before = snapshot()

    // ── 小工具 ────────────────────────────────────────────────────────────
    func write(_ dir: String, _ rel: String, _ text: String) -> Bool {
        let path = "\(dir)/\(rel)"
        guard (try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)) != nil else { return false }
        return (try? text.write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }
    func read(_ dir: String, _ rel: String) -> String { (try? String(contentsOfFile: "\(dir)/\(rel)", encoding: .utf8)) ?? "" }
    func replace(_ dir: String, _ rel: String, _ old: String, _ new: String) -> Bool {
        let t = read(dir, rel)
        guard t.contains(old) else { return false }
        return write(dir, rel, t.replacingOccurrences(of: old, with: new))
    }
    func chmod(_ dir: String, _ rel: String, _ mode: Int) -> Bool {
        (try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: "\(dir)/\(rel)")) != nil
    }
    func symlink(_ dir: String, _ rel: String, to dest: String) -> Bool {
        let path = "\(dir)/\(rel)"
        guard (try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)) != nil else { return false }
        return (try? fm.createSymbolicLink(atPath: path, withDestinationPath: dest)) != nil
    }
    let gitIdentity = ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"]
    func commit(_ dir: String, _ message: String) -> Bool {
        pluginShellGit(["add", "-A"], in: dir) != nil && pluginShellGit(gitIdentity + ["commit", "-q", "-m", message], in: dir) != nil
    }
    /// 只 commit 指名的幾個檔（部分 commit；其餘的改動留在工作樹）
    func commitOnly(_ dir: String, _ paths: [String], _ message: String) -> Bool {
        pluginShellGit(["add", "--"] + paths, in: dir) != nil && pluginShellGit(gitIdentity + ["commit", "-q", "-m", message], in: dir) != nil
    }
    func sha(_ dir: String, _ ref: String) -> String? {
        pluginShellGit(["rev-parse", "--verify", "--quiet", ref], in: dir).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    func head(_ dir: String) -> String? { sha(dir, "HEAD") }
    func publish(_ dir: String) -> Bool { pluginShellGit(["update-ref", pluginShellPublishedRef, "HEAD"], in: dir) != nil }
    func publish(_ dir: String, _ sha: String) -> Bool { pluginShellGit(["update-ref", pluginShellPublishedRef, sha], in: dir) != nil }
    func resetHard(_ dir: String, _ sha: String) -> Bool { pluginShellGit(["reset", "-q", "--hard", sha], in: dir) != nil }
    let zero = String(repeating: "0", count: 40)
    /// pre-push 交給守衛的推送資訊（一行）
    func push(_ local: String, to remoteRef: String = "refs/heads/feat", remoteSHA: String) -> [String: String] {
        [pluginShellPushRefsEnv: "refs/heads/feat \(local) \(remoteRef) \(remoteSHA)\n", pluginShellPushRemoteEnv: "origin"]
    }
    func runGuard(_ dir: String, _ label: String, _ expect: GuardExpectation, env: [String: String] = [:]) -> (Int32, String) {
        let r = runGuardProcess([BIN, "plugin-shell-version"], cwd: dir, env: env, mergeOutput: true, label: label, expect: expect)
        return (r.status, r.combined)
    }
    func digests(_ out: String) -> [String: (version: String, digest: String)] {
        var d: [String: (String, String)] = [:]
        for m in matches(out, "`(plugin|plugins/disc)\t([0-9]+\\.[0-9]+\\.[0-9]+)\t([0-9a-f]{64})`") {
            let ns = out as NSString
            d[ns.substring(with: m.range(at: 1))] = (ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 3)))
        }
        return d
    }
    func reportedDigest(_ out: String, _ root: String) -> String? {
        firstGroup(out, NSRegularExpression.escapedPattern(for: root) + " 的殼內容與 [0-9.]+ 記下的不同（摘要 ([0-9a-f]{64})")
    }

    // ── 基準 repo ─────────────────────────────────────────────────────────
    // 路徑以變數組出來：寫成字面的話 trigger-coverage 會把它們當成「守衛引用了 repo 裡的檔」（這些只存在於 fixture）
    let mcp = "plugin", disc = "plugins/disc"
    let skillA = "\(mcp)/skills/a/SKILL.md", ruleR = "\(mcp)/rules/r.md", tool = "\(mcp)/bin/w.sh", manifest = "\(mcp)/\(pluginManifestRel)"
    let base = work + "/base"
    let header = "# 版號表（fixture）\n"
    let files: [(String, String)] = [
        (manifest, #"{"name": "fixture-mcp", "version": "1.0.0", "binary_version": "0.1.0", "description": "fixture"}"# + "\n"),
        (skillA, "step 0\n"),
        (ruleR, "rule one\n"),
        (tool, "#!/bin/sh\necho fixture\n"),
        ("\(mcp)/CHANGELOG.md", "# Changelog\n"),
        ("\(disc)/\(pluginManifestRel)", #"{"name": "fixture-disc", "version": "0.1.0"}"# + "\n"),
        ("\(disc)/skills/b/SKILL.md", "discover\n"),
        (pluginShellVersionsPath, header),
    ]
    guard files.allSatisfy({ write(base, $0.0, $0.1) }), chmod(base, tool, 0o755),
          symlink(base, "\(disc)/rules", to: "../../\(mcp)/rules"),
          pluginShellGit(["init", "-q"], in: base) != nil else { print("✗ 建不了基準 repo"); return 2 }
    // 第二道圍籬：git dir 必須在暫存目錄裡（剝除 GIT_* 是第一道）
    guard let gitDir = pluginShellGit(["rev-parse", "--absolute-git-dir"], in: base).map({ String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }),
          URL(fileURLWithPath: gitDir).resolvingSymlinksInPath().path.hasPrefix(base + "/") else {
        print("✗ fixture 的 git dir 不在暫存目錄裡——停在這裡，後面每一句 git 都可能落到別處"); return 2
    }

    var passed = 0, total = 0
    func expect(_ label: String, _ want: GuardExpectation, in dir: String, env: [String: String] = [:], says needle: String? = nil,
                not unwanted: String? = nil, also: (String) -> Bool = { _ in true }) {
        total += 1
        let (rc, out) = runGuard(dir, label, want, env: env)
        let rcOK = want.isMet(rc: rc, stdout: "")
        let sayOK = needle.map { out.contains($0) } ?? true
        let notOK = unwanted.map { !out.contains($0) } ?? true
        if rcOK && sayOK && notOK && also(out) {
            passed += 1; print("✓ \(label) → rc=\(rc)")
        } else {
            let first = out.split(separator: "\n").prefix(4).joined(separator: " / ")
            print("✗ \(label) → rc=\(rc)" + (sayOK ? "" : "，輸出沒有「\(needle!)」") + (notOK ? "" : "，輸出卻有「\(unwanted!)」") + "：\(String(first.prefix(500)))")
        }
    }

    // 空表：紅，訊息印出要記的列（也取出摘要）
    total += 1
    let (rc0, out0) = runGuard(base, "空表：訊息印出要記的列", .red)
    let seed = digests(out0)
    guard rc0 != 0, let p0 = seed["plugin"], let d0 = seed["plugins/disc"], p0.version == "1.0.0", d0.version == "0.1.0" else {
        print("✗ 空表 → rc=\(rc0)，訊息沒有印出兩個根要記的列：\(String(out0.prefix(400)))"); return 1
    }
    passed += 1; print("✓ 空表 → rc=\(rc0)，訊息印出兩個根要記的列")
    let rows = "plugin\t1.0.0\t\(p0.digest)\nplugins/disc\t0.1.0\t\(d0.digest)\n"
    guard write(base, pluginShellVersionsPath, header + rows), commit(base, "seed"), publish(base), let seedSHA = head(base) else { print("✗ 基準 repo commit 不了"); return 2 }

    var n = 0
    func copy(_ edit: (String) -> Bool) -> String? {
        n += 1
        let dir = "\(work)/case\(n)"
        guard (try? fm.copyItem(atPath: base, toPath: dir)) != nil, edit(dir) else { return nil }
        return dir
    }
    func invalid(_ label: String) { total += 1; print("✗ \(label) → 注入套不上，這一格無效") }

    // 已發布的 commit 就是受測的（CI 對 push 的淺 checkout 同形）：綠，並說出這一半比的是它自己
    expect("原樣（已推上 main；origin/main 就是 HEAD）", .green, in: base, says: "就是受測的 commit")

    // 已發布的版號送出新內容
    let skillEdit: (String) -> Bool = { replace($0, skillA, "step 0\n", "step 0, contract 7\n") }
    var newDigest: String? = nil
    if let d = copy(skillEdit) {
        total += 1
        let (rc, out) = runGuard(d, "已發布的 1.0.0 改了 skill、版號沒升", .red)
        newDigest = reportedDigest(out, "plugin")
        if rc != 0, out.contains("1.0.0 已推上 main"), out.contains("只能升版"), newDigest != nil { passed += 1; print("✓ 已發布的 1.0.0 改了 skill、版號沒升 → rc=\(rc)，說只能升版") }
        else { print("✗ 已發布的 1.0.0 改了 skill、版號沒升 → rc=\(rc)：\(String(out.prefix(400)))") }
    } else { invalid("已發布的 1.0.0 改了 skill") }
    guard let nd = newDigest else { print("✗ 取不到改過 skill 之後的摘要，後面幾格無從建"); return 1 }

    if let d = copy({ skillEdit($0) && replace($0, pluginShellVersionsPath, "plugin\t1.0.0\t\(p0.digest)", "plugin\t1.0.0\t\(nd)") }) {
        expect("已發布的 1.0.0 改了 skill，把表的 1.0.0 改記成新摘要", .red, in: d, says: "表只增不改，已發布的列改回 \(p0.digest)")
    } else { invalid("改記已發布的列") }

    let bumped: (String) -> Bool = { d in
        skillEdit(d) && replace(d, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#)
            && write(d, pluginShellVersionsPath, header + rows + "plugin\t1.0.1\t\(nd)\n")
    }
    if let d = copy(bumped) { expect("升到 1.0.1、表接一列", .green, in: d) } else { invalid("升版") }

    // 還沒推上 main 的 1.0.1：可以重記
    if let d = copy({ bumped($0) && replace($0, skillA, "contract 7", "contract 8") }) {
        total += 1
        let (rc, out) = runGuard(d, "未發布的 1.0.1 又改了 skill、沒重記", .red)
        let again = reportedDigest(out, "plugin")
        if rc != 0, out.contains("1.0.1 還沒推上 main"), let a = again { passed += 1; print("✓ 未發布的 1.0.1 又改了 skill、沒重記 → rc=\(rc)，說可以重記")
            if replace(d, pluginShellVersionsPath, "plugin\t1.0.1\t\(nd)", "plugin\t1.0.1\t\(a)") {
                expect("未發布的 1.0.1 重記摘要", .green, in: d)
            } else { invalid("重記未發布的 1.0.1") }
        } else { print("✗ 未發布的 1.0.1 又改了 skill、沒重記 → rc=\(rc)：\(String(out.prefix(400)))"); total += 1 }
    } else { invalid("未發布的 1.0.1"); total += 1 }

    // symlink 之後的規則改了：兩個根都紅
    if let d = copy({ replace($0, ruleR, "rule one", "rule two") }) {
        expect("plugin/rules 改了（disc 經 symlink 送出它）", .red, in: d, says: "plugins/disc 的殼內容與 0.1.0 記下的不同",
               also: { $0.contains("plugin 的殼內容與 1.0.0 記下的不同") })
    } else { invalid("改規則") }
    if let d = copy({ replace($0, "\(disc)/skills/b/SKILL.md", "discover", "discover more") }) {
        expect("disc 自己的 skill 改了", .red, in: d, says: "plugins/disc 的殼內容與 0.1.0 記下的不同",
               also: { !$0.contains("plugin 的殼內容與") })
    } else { invalid("改 disc 的 skill") }

    // 其他會改變內容的
    if let d = copy({ write($0, "\(mcp)/skills/c/SKILL.md", "new skill, not yet git-added\n") }) {
        expect("plugin 底下多一個未追蹤的檔", .red, in: d, says: "plugin 的殼內容與 1.0.0 記下的不同")
    } else { invalid("未追蹤的檔") }
    if let d = copy({ replace($0, manifest, #""description": "fixture""#, #""description": "fixture!""#) }) {
        expect("plugin.json 的 description 改了", .red, in: d, says: "plugin 的殼內容與 1.0.0 記下的不同")
    } else { invalid("改 description") }
    if let d = copy({ (try? fm.removeItem(atPath: $0 + "/\(ruleR)")) != nil }) {
        expect("plugin 底下刪了一個已追蹤的檔", .red, in: d, says: "plugin 的殼內容與 1.0.0 記下的不同")
    } else { invalid("刪檔") }
    // 不算內容的：CHANGELOG
    if let d = copy({ replace($0, "\(mcp)/CHANGELOG.md", "# Changelog", "# Changelog\n\n- 1.0.0") }) {
        expect("只改 CHANGELOG.md", .green, in: d)
    } else { invalid("改 CHANGELOG") }

    // 版號與表
    if let d = copy({ replace($0, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#) }) {
        expect("升到 1.0.1 卻沒接一列", .red, in: d, says: "最後接一列 `plugin\t1.0.1\t")
    } else { invalid("升版沒接列") }
    if let d = copy({ replace($0, manifest, #""version": "1.0.0""#, #""version": "0.9.0""#) }) {
        expect("版號往下（0.9.0）", .red, in: d, says: "版號只能往上")
    } else { invalid("版號往下") }
    if let d = copy({ replace($0, manifest, #""version": "1.0.0""#, #""version": "1.0.1-rc1""#) }) {
        expect("版號不是 N.N.N（1.0.1-rc1）", .red, in: d, says: "不是 N.N.N——版號表只收這個形狀")
    } else { invalid("版號不是 N.N.N") }
    if let d = copy({ write($0, pluginShellVersionsPath, header + "plugins/disc\t0.1.0\t\(d0.digest)\n") }) {
        expect("表裡沒有 plugin 的列", .red, in: d, says: "沒有 plugin 的任何一列")
    } else { invalid("沒有 plugin 的列") }
    if let d = copy({ replace($0, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#)
            && write($0, pluginShellVersionsPath, header + "plugin\t1.0.1\t\(p0.digest)\nplugins/disc\t0.1.0\t\(d0.digest)\n") }) {
        expect("origin/main 送出的 1.0.0 從表裡被拿掉", .red, in: d, says: "送出的 1.0.0 不在表裡", also: { $0.contains("不見了") })
    } else { invalid("拿掉已發布的列") }
    if let d = copy({ write($0, pluginShellVersionsPath, header + rows + "plugin\t1.0\tabc\n") }) {
        expect("表有一行格式錯", .red, in: d, says: "不是 N.N.N")
    } else { invalid("格式錯的行") }
    if let d = copy({ write($0, pluginShellVersionsPath, header + "plugin\t1.0.1\t\(p0.digest)\nplugin\t1.0.0\t\(p0.digest)\nplugins/disc\t0.1.0\t\(d0.digest)\n") }) {
        expect("表的版號沒有遞增", .red, in: d, says: "版號沒有依序遞增")
    } else { invalid("沒有遞增") }

    // ── main 已送出 1.0.1（內容與 1.0.0 相同），這一格的分支停在 seed：落後 main ──
    let mainAt101: (String) -> Bool = { d in
        replace(d, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#)
            && write(d, pluginShellVersionsPath, header + rows + "plugin\t1.0.1\t\(p0.digest)\n") && commit(d, "1.0.1") && publish(d)
            && resetHard(d, seedSHA)
    }
    if let d = copy(mainAt101), let main101 = sha(d, pluginShellPublishedRef) {
        expect("分支落後 origin/main、沒碰 plugin（推的不是 main）", .green, in: d, says: "這個分支落後 main")
        expect("分支落後 origin/main，推上 main", .red, in: d, env: push(seedSHA, to: "refs/heads/main", remoteSHA: main101), says: "推上去版號會倒退")
    } else { invalid("落後 main"); total += 1 }
    // 落後 main 的分支自己升到 1.0.1、內容卻不同：同一個版號兩份內容
    if let d = copy({ mainAt101($0) && skillEdit($0) && replace($0, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#)
            && write($0, pluginShellVersionsPath, header + rows + "plugin\t1.0.1\t\(nd)\n") }) {
        expect("落後 main 的分支升到 main 已發布的 1.0.1、內容不同", .red, in: d, says: "同一個版號兩份內容")
    } else { invalid("同一個版號兩份內容") }

    // ── 只增不改：main 已送出 1.0.1，改或刪較舊的 1.0.0 那一列（b42 第 1、21 則）──
    let published101: (String) -> Bool = { d in
        bumped(d) && commit(d, "1.0.1") && publish(d)
    }
    if let d = copy({ published101($0) && replace($0, pluginShellVersionsPath, "plugin\t1.0.0\t\(p0.digest)", "plugin\t1.0.0\t\(String(repeating: "0", count: 64))") }) {
        expect("main 已在 1.0.1，改了較舊的 1.0.0 那一列", .red, in: d, says: "表只增不改，已發布的列改回 \(p0.digest)")
    } else { invalid("改舊的列") }
    if let d = copy({ published101($0) && replace($0, pluginShellVersionsPath, "plugin\t1.0.0\t\(p0.digest)\n", "") }) {
        expect("main 已在 1.0.1，刪了較舊的 1.0.0 那一列", .red, in: d, says: "不見了")
    } else { invalid("刪舊的列") }
    if let d = copy({ published101($0) && replace($0, pluginShellVersionsPath, "plugins/disc\t0.1.0\t\(d0.digest)\n", "") }) {
        expect("main 已在 1.0.1，刪了 disc 唯一的一列", .red, in: d, says: "plugins/disc 0.1.0（已發布的表")
    } else { invalid("刪 disc 的列") }

    // ── 內容在表之外改了（b42 第 6 則）：main 上的 skill 改了而 1.0.0 沒升，表也沒動 ──
    let changedOutsideTable: (String) -> Bool = { d in skillEdit(d) && commit(d, "skill only") && publish(d) }
    if let d = copy(changedOutsideTable) {
        expect("main 上的內容在表之外改了（表與 main 的表相同）", .red, in: d, says: "內容在表之外改了", not: "改回")
    } else { invalid("內容在表之外改了") }
    if let d = copy({ changedOutsideTable($0) && replace($0, pluginShellVersionsPath, "plugin\t1.0.0\t\(p0.digest)", "plugin\t1.0.0\t\(nd)") }) {
        expect("同上，再照已發布的摘要改記表（洗白）", .red, in: d, says: "表只增不改，已發布的列改回 \(p0.digest)")
    } else { invalid("洗白") }

    // ── 被推送的 commit，不是工作樹（b42 第 3、17、27 則）──
    // 部分 commit：只 commit 了 skill；升版與表的那一列還在工作樹
    let partial: (String) -> Bool = { d in
        skillEdit(d) && commitOnly(d, [skillA], "skill only")
            && replace(d, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#)
            && write(d, pluginShellVersionsPath, header + rows + "plugin\t1.0.1\t\(nd)\n")
    }
    if let d = copy(partial), let tip = head(d) {
        expect("部分 commit：手動執行只看得到工作樹（一致）", .green, in: d)
        expect("部分 commit：推送 branch（比被推送的 commit）", .red, in: d, env: push(tip, remoteSHA: zero), says: "只能升版",
               also: { $0.contains("commit \(tip.prefix(12))") })
        expect("部分 commit：推上 main（遠端回報 seed）", .red, in: d, env: push(tip, to: "refs/heads/main", remoteSHA: seedSHA), says: "只能升版",
               also: { $0.contains("推送時遠端回報的") })
    } else { invalid("部分 commit"); total += 2 }
    // 新的 skill 檔沒有 git add：工作樹的摘要算了它、表也記了它，推上去的 commit 沒有它
    if let d = copy({ write($0, "\(mcp)/skills/c/SKILL.md", "new skill\n") && replace($0, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#) }) {
        total += 1
        let (_, out) = runGuard(d, "取未追蹤的新 skill 算進去的摘要", .none)
        if let row = digests(out)["plugin"], row.version == "1.0.1",
           write(d, pluginShellVersionsPath, header + rows + "plugin\t1.0.1\t\(row.digest)\n"),
           commitOnly(d, [manifest, pluginShellVersionsPath], "bump without the new skill"), let tip = head(d) {
            passed += 1; print("✓ 取未追蹤的新 skill 算進去的摘要")
            expect("新 skill 沒 add：手動執行（一致）", .green, in: d)
            expect("新 skill 沒 add：推送 branch（推上去的 commit 沒有它）", .red, in: d, env: push(tip, remoteSHA: zero),
                   says: "plugin 的殼內容與 1.0.1 記下的不同")
        } else { print("✗ 取未追蹤的新 skill 算進去的摘要：\(String(out.prefix(300)))"); total += 2 }
    } else { invalid("新 skill 沒 add"); total += 3 }
    // 本機的 origin/main 落後：遠端此刻的 main 已送出 1.0.1
    if let d = copy({ published101($0) && publish($0, seedSHA) && replace($0, skillA, "contract 7", "contract 8") && commit($0, "again") }),
       let tip = head(d), let p101 = sha(d, "HEAD~1") {
        expect("origin/main 落後：推上 main（遠端回報 1.0.1）", .red, in: d, env: push(tip, to: "refs/heads/main", remoteSHA: p101),
               says: "1.0.1 已推上 main", also: { $0.contains("只能升版") })
        expect("origin/main 落後：推送 branch 只看得到本機的 origin/main（誠實邊界）", .red, in: d, env: push(tip, remoteSHA: zero),
               says: "1.0.1 還沒推上 main")
        expect("遠端的 main 這個 repo 沒有", .red, in: d, env: push(tip, to: "refs/heads/main", remoteSHA: String(repeating: "a", count: 40)), says: "先 `git fetch`")
        expect("遠端還沒有 main", .green, in: d, env: push(seedSHA, to: "refs/heads/main", remoteSHA: zero), says: "遠端還沒有 main")
    } else { invalid("origin/main 落後"); total += 3 }
    if let d = copy({ _ in true }) {
        expect("推送只有 tag", .green, in: d, env: [pluginShellPushRefsEnv: "refs/tags/v1 \(seedSHA) refs/tags/v1 \(zero)\n", pluginShellPushRemoteEnv: "origin"],
               says: "沒有 branch")
        expect("推送資訊看不懂", .red, in: d, env: [pluginShellPushRefsEnv: "refs/heads/x not-a-sha refs/heads/x\n", pluginShellPushRemoteEnv: "origin"],
               says: "不是「local ref、local sha、remote ref、remote sha」")
    } else { invalid("tag／看不懂"); total += 1 }

    // ── symlink 解不開：具名拒絕（b42 第 2、14、23 則）──
    if let d = copy({ symlink($0, "\(mcp)/rules/alias.md", to: "r.md") }) {
        expect("symlink 目標底下又有 symlink（兩層）", .red, in: d, says: "又是 symlink")
        if commit(d, "alias"), let tip = head(d) {
            expect("同上，推送那個 commit", .red, in: d, env: push(tip, remoteSHA: zero), says: "又是 symlink")
        } else { invalid("兩層 symlink commit") }
    } else { invalid("兩層 symlink"); total += 1 }
    if let d = copy({ symlink($0, "\(mcp)/skills/dangling", to: "../nonexistent") }) {
        expect("懸空的 symlink", .red, in: d, says: "git 在那裡沒有任何檔")
    } else { invalid("懸空的 symlink") }
    if let d = copy({ symlink($0, "\(mcp)/rules2", to: "rules") && (try? fm.removeItem(atPath: $0 + "/\(disc)/rules")) != nil
            && symlink($0, "\(disc)/rules", to: "../../\(mcp)/rules2") }) {
        expect("symlink 指向另一個 symlink", .red, in: d, says: "目標本身是 symlink")
    } else { invalid("symlink 鏈") }

    // ── 檔案模式（b42 第 11 則）：已發布的 1.0.0 的可執行檔失去 x 位元 ──
    if let d = copy({ chmod($0, tool, 0o644) }) {
        expect("已發布的 1.0.0 的可執行檔 chmod -x", .red, in: d, says: "檔案模式改了")
        if commit(d, "chmod"), let tip = head(d) {
            expect("同上，推送那個 commit", .red, in: d, env: push(tip, remoteSHA: zero), says: "檔案模式改了")
        } else { invalid("chmod commit") }
    } else { invalid("chmod"); total += 1 }
    if let d = copy({ chmod($0, tool, 0o644) && replace($0, manifest, #""version": "1.0.0""#, #""version": "1.0.1""#)
            && write($0, pluginShellVersionsPath, header + rows + "plugin\t1.0.1\t\(p0.digest)\n") }) {
        expect("chmod -x 並升到 1.0.1", .green, in: d)
    } else { invalid("chmod 升版") }

    // ── 新的 plugin 根，origin/main 上沒有（b42 第 15 則）──
    let newRoot = disc.replacingOccurrences(of: "disc", with: "newp")
    if let d = copy({ write($0, "\(newRoot)/\(pluginManifestRel)", #"{"name": "newp", "version": "0.1.0"}"# + "\n")
            && write($0, pluginShellVersionsPath, header + rows + "\(newRoot)\t0.1.0\t\(String(repeating: "0", count: 64))\n") }) {
        expect("新的 plugin 根、摘要沒記對", .red, in: d, says: "還沒發布過的 plugin 根")
    } else { invalid("新的根") }

    // origin/main 不在：只照表判斷，說出來
    let unpublish: (String) -> Bool = { pluginShellGit(["update-ref", "-d", pluginShellPublishedRef], in: $0) != nil }
    if let d = copy(unpublish) {
        expect("origin/main 不在、內容沒變", .green, in: d, says: "ℹ \(pluginShellPublishedRef) 不在")
    } else { invalid("刪 origin/main") }
    if let d = copy({ unpublish($0) && skillEdit($0) }) {
        expect("origin/main 不在、改了 skill", .red, in: d, says: "升版一定安全")
    } else { invalid("刪 origin/main 再改 skill") }

    // ── 真實 repo 沒有被寫入 ─────────────────────────────────────────────
    let untouched = snapshot() == before
    print(untouched ? "✓ 真實 repo 的版號表與 plugin.json 前後逐位元相同" : "✗ 真實 repo 的版號表或 plugin.json 被改了")
    print("\n══ \(passed)/\(total) 格符合預期 ══")
    return passed == total && untouched ? 0 : 1
}
