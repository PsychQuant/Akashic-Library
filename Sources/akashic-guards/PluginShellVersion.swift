// `plugin-shell-version`：plugin 殼送出的內容改了，`plugin.json` 的 `version` 就要升（#729；#613 b39＝b38 Z2 第 0 則、b41＝b40 Z2 第 1–3、6、16、18 則）。
//
// **為什麼有這支**：Claude Code 以 `version` 決定要不要換掉使用者機器上的 plugin 快取。內容改了而版號沒升，`claude plugin update` 回報
// 「已是最新」，使用者載入的仍是舊的 skill。#729（2026-10-08，0.13.2 → 0.13.3）修過一次；之後 #613 b37 與 #692／#700 又改了 skill 而沒升。
//
// **本 repo 自己就是 marketplace**（#625）：`.claude-plugin/marketplace.json` 以 `source: ./plugin`、`./plugins/akashic-discovery` 列出兩個
// plugin，條目沒有版本欄位；使用者 `claude plugin marketplace update` 拉到的就是 GitHub main 上的 `plugin.json`。**推上 main 就是發布，沒有另一個
// 「同步」步驟可以延後**——b39 的訊息與 changelog 把「推上 main」與「同步到 marketplace」寫成兩件事，那是錯的（b40 Z2 第 1–3 則）。
//
// **這支怎麼判**（b39 的 XCTest 只比摘要，紅了之後「升版還是只重記」要讀訊息的人判斷——那正是 #729 失敗的那個判斷）：
//
//   1. **版號表** `.githooks/plugin-shell-versions.txt`：每個 plugin 根的每個版號送出的殼內容摘要，**只增不改**（`<根> TAB <版號> TAB <摘要>`）。
//      每個根的版號依序遞增；最後一列是那個根現在的版號。
//   2. 工作樹的 `plugin.json` 版號要等於表裡那個根的最後一列；工作樹的內容摘要要等於那一列的摘要。
//   3. **`origin/main` 在的時候（只讀本機的 remote-tracking ref，不連網）**：算出它的每個根的版號與摘要，表裡要有那一列、摘要相同——
//      已發布的版號不能被改記成別的內容。工作樹的版號等於 `origin/main` 的版號而內容不同，就是「已發布的版號送出了新內容」，只能升版。
//      `origin/main` 不在（沒有 remote、CI 的淺 checkout）時只照表判斷，印一行說明——不靜默；那時紅了的訊息說升版一定安全。
//
// **送出的內容**＝根底下 git 認得的檔（已追蹤，加上未追蹤而沒被忽略的——還沒 `git add` 的新 skill 檔也算），除了根的 `CHANGELOG.md`
// （版本史，不是 Claude Code 載入的東西）；`plugin.json` 去掉 `version` 本身再算（其餘欄位改了同樣要升）。**symlink 解開**：
// `plugins/akashic-discovery/rules` 指向 `plugin/rules`，那些規則檔以 `plugins/akashic-discovery/rules/<檔>` 計入 discovery 的內容
// （b40 Z2 第 6、18 則：0.2.15 之後規則改了四次、版號沒升）。摘要的演算法與 b39 的 `PluginShellVersionTests` 相同，所以 0.13.4 的
// `f6dfba69…` 照樣算得出來（`plugin/` 裡沒有 symlink）。
//
// **誠實邊界**：
//   · `origin/main` 是本機記得的 remote 狀態，沒 fetch 時會落後——落後的那一段裡被推上去的版號，這支當成還沒發布。
//   · 摘要只看路徑與位元組，不看檔案模式（wrapper 失去可執行位元、換成 symlink，摘要不變——b40 Z2 第 21、34 則，未處理）。
//   · `plugin.json` 以 Foundation 的 `JSONSerialization`（排序鍵、`/` 逸出成 `\/`）重新序列化再算；換工具鏈改了這個預設時摘要會無故變（第 29 則）。
//   · 只比本機 git 看得到的東西：push 用 `--no-verify` 繞過 pre-push 時，這支只在 CI（`census-parity.yml` 對 `plugin/**`、`plugins/**` 觸發，
//     跑 `run-guards.sh`）會跑——而 CI 的帳務目前擱置（見 CLAUDE.md）。
//
// 負對照：`plugin-shell-version-mutations`（在暫存的 git repo 裡逐格注入）。

import CryptoKit
import Foundation

/// 版號表的位置（repo 相對）。
let pluginShellVersionsPath = ".githooks/plugin-shell-versions.txt"
/// 「已發布」的參照：本機的 remote-tracking ref。推上 main 就是發布（本 repo 是 marketplace）。
let pluginShellPublishedRef = "refs/remotes/origin/main"

struct PluginShellRecord: Equatable {
    let root: String
    let version: String
    let digest: String
    let line: Int
}

/// 一次 git 呼叫（`-C <repo 根>`，**剝除全部 `GIT_*`**——pre-push hook 裡 git 會注入 `GIT_DIR`，它的優先權高於 `-C`，見
/// `Tests/AkashicKitTests/GitFixture.swift` 記的 2026-08-12 事故）。回傳 stdout 的位元組；rc≠0 或跑不起來回 nil。
/// git 子行程的環境：剝除全部 `GIT_*`（前綴剝除，不列舉——`GitSpawnHygieneTests` 登記了本檔）。
var scrubbedGitEnvironment: [String: String] {
    ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
}

func pluginShellGit(_ args: [String], in dir: String = repoRoot) -> Data? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", dir] + args
    p.environment = scrubbedGitEnvironment
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? data : nil
}

private func nulSeparated(_ data: Data) -> [String] {
    data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
}

/// `a` 在 `b` 之前（數字逐段比）。兩個都要是 `N.N.N`。
func pluginShellVersionLess(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: ".").compactMap { Int($0) }, y = b.split(separator: ".").compactMap { Int($0) }
    return x.lexicographicallyPrecedes(y)
}

/// symlink 的目標，解成 repo 相對路徑（`.`／`..` 化簡）。落在 repo 外時回 nil。
private func repoRelativeTarget(link: String, destination: String) -> String? {
    var parts = destination.hasPrefix("/") ? [] : link.split(separator: "/").dropLast().map(String.init)
    if destination.hasPrefix("/") {
        let base = URL(fileURLWithPath: repoRoot).resolvingSymlinksInPath().path + "/"
        let real = URL(fileURLWithPath: destination).standardizedFileURL.path
        return real.hasPrefix(base) ? String(real.dropFirst(base.count)) : nil
    }
    for seg in destination.split(separator: "/").map(String.init) {
        if seg == "." || seg.isEmpty { continue }
        if seg == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() } else { parts.append(seg) }
    }
    return parts.isEmpty ? nil : parts.joined(separator: "/")
}

/// 路徑換成在 symlink 之下的邏輯路徑：`target` 本身 → `link`；`target/x` → `link/x`。
private func logicalPath(_ path: String, target: String, link: String) -> String {
    path == target ? link : link + "/" + path.dropFirst(target.count + 1)
}

/// 工作樹裡一個根送出的檔：（邏輯路徑，內容；工作樹裡被刪掉的已追蹤檔是 nil）。git 叫不起來回 nil。
func pluginShellWorkingTreeFiles(root: String) -> [(path: String, data: Data?)]? {
    let fm = FileManager.default
    func listed(_ path: String) -> [String]? {
        pluginShellGit(["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", path]).map { Array(Set(nulSeparated($0))).sorted() }
    }
    guard let paths = listed(root) else { return nil }
    var out: [(String, Data?)] = []
    for p in paths where p != "\(root)/CHANGELOG.md" {
        let full = "\(repoRoot)/\(p)"
        if let dest = try? fm.destinationOfSymbolicLink(atPath: full) {
            guard let target = repoRelativeTarget(link: p, destination: dest) else {
                out.append((p, Data("<symlink outside the repo> \(dest)".utf8))); continue
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: "\(repoRoot)/\(target)", isDirectory: &isDir), isDir.boolValue {
                guard let inner = listed(target) else { return nil }
                for f in inner { out.append((logicalPath(f, target: target, link: p), fm.contents(atPath: "\(repoRoot)/\(f)"))) }
            } else {
                out.append((p, fm.contents(atPath: "\(repoRoot)/\(target)")))
            }
            continue
        }
        out.append((p, fm.contents(atPath: full)))
    }
    return out
}

/// `ref` 的樹裡一個根送出的檔。根在那裡不存在時回空陣列；git 叫不起來或物件讀不到回 nil。
func pluginShellTreeFiles(root: String, ref: String) -> [(path: String, data: Data?)]? {
    /// `ls-tree -r` 的一行：mode type sha TAB path
    func entries(_ path: String) -> [(mode: String, sha: String, path: String)]? {
        guard let d = pluginShellGit(["ls-tree", "-r", "-z", ref, "--", path]) else { return nil }
        return nulSeparated(d).compactMap { line in
            guard let tab = line.firstIndex(of: "\t") else { return nil }
            let head = line[..<tab].split(separator: " ")
            guard head.count == 3 else { return nil }
            return (String(head[0]), String(head[2]), String(line[line.index(after: tab)...]))
        }
    }
    guard let top = entries(root) else { return nil }
    var out: [(String, Data?)] = []
    for e in top where e.path != "\(root)/CHANGELOG.md" {
        guard let blob = pluginShellGit(["cat-file", "blob", e.sha]) else { return nil }
        if e.mode == "120000" {
            let dest = String(decoding: blob, as: UTF8.self)
            guard let target = repoRelativeTarget(link: e.path, destination: dest) else {
                out.append((e.path, Data("<symlink outside the repo> \(dest)".utf8))); continue
            }
            guard let inner = entries(target) else { return nil }
            for f in inner {
                guard let b = pluginShellGit(["cat-file", "blob", f.sha]) else { return nil }
                out.append((logicalPath(f.path, target: target, link: e.path), b))
            }
            continue
        }
        out.append((e.path, blob))
    }
    return out
}

/// 摘要：依路徑排序，每個檔是「路徑、NUL、長度、NUL、內容」；`<根>/.claude-plugin/plugin.json` 去掉 `version` 之後以排序過的鍵重新序列化。
/// 與 b39 的 `PluginShellVersionTests.digest` 逐位元相同（0.13.4 的 `f6dfba69…` 由它算出）。`plugin.json` 讀不懂回 nil。
func pluginShellDigest(_ files: [(path: String, data: Data?)], root: String) -> String? {
    var hasher = SHA256()
    for (path, data) in files.sorted(by: { $0.path < $1.path }) {
        var content = data ?? Data("<missing>".utf8)
        if path == "\(root)/\(pluginManifestRel)", let raw = data {
            guard var object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return nil }
            object.removeValue(forKey: "version")
            guard let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
            content = normalized
        }
        hasher.update(data: Data(path.utf8) + Data([0]) + Data(String(content.count).utf8) + Data([0]))
        hasher.update(data: content)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// 一份 `plugin.json` 的 `version`。
func pluginShellManifestVersion(_ data: Data?) -> String? {
    guard let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return object["version"] as? String
}

/// 版號表。格式錯的行回在 `problems`（不靜默略過）。
func readPluginShellVersions(_ text: String, roots: [String]) -> (records: [PluginShellRecord], problems: [String]) {
    var records: [PluginShellRecord] = [], problems: [String] = []
    for (i, raw) in text.components(separatedBy: "\n").enumerated() {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty || line.hasPrefix("#") { continue }
        let f = line.components(separatedBy: "\t")
        guard f.count == 3 else { problems.append("第 \(i + 1) 行不是「根 TAB 版號 TAB 摘要」三欄：\(pyRepr([String(line.prefix(120))]))"); continue }
        guard roots.contains(f[0]) else { problems.append("第 \(i + 1) 行的根 \(pyRepr([f[0]])) 不是 plugin 根（\(roots.joined(separator: "、"))）"); continue }
        guard !matches(f[1], #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#).isEmpty else { problems.append("第 \(i + 1) 行的版號 \(pyRepr([f[1]])) 不是 N.N.N"); continue }
        guard !matches(f[2], #"\A[0-9a-f]{64}\z"#).isEmpty else { problems.append("第 \(i + 1) 行的摘要不是 64 位小寫十六進位"); continue }
        records.append(PluginShellRecord(root: f[0], version: f[1], digest: f[2], line: i + 1))
    }
    for root in roots {
        let mine = records.filter { $0.root == root }
        for (a, b) in zip(mine, mine.dropFirst()) where !pluginShellVersionLess(a.version, b.version) {
            problems.append("\(root) 的版號沒有依序遞增：第 \(a.line) 行 \(a.version)、第 \(b.line) 行 \(b.version)（表只增不改，新版號接在最後）")
        }
    }
    return (records, problems)
}

func pluginShellVersion() -> Int32 {
    let roots = pluginRoots()
    guard !roots.isEmpty else { print("✗ 一個 plugin 根都找不到——空掃描不是通過"); return 2 }
    guard let tableText = readFile(pluginShellVersionsPath) else {
        print("✗ 讀不到版號表 \(pluginShellVersionsPath)——沒有表就判不了版號送出的是哪一份內容"); return 2
    }
    let (records, problems) = readPluginShellVersions(tableText, roots: roots)
    var v = Verdict()
    for p in problems { _ = v.check(false, "\(pluginShellVersionsPath)：\(p)") }

    // 已發布的狀態：本機的 origin/main（不連網）
    let published = pluginShellGit(["rev-parse", "--verify", "--quiet", "\(pluginShellPublishedRef)^{commit}"]) != nil
    if !published {
        print("ℹ \(pluginShellPublishedRef) 不在（沒有 remote，或淺 checkout）：只照版號表判斷，分不出最後一列推上 main 了沒")
    }

    var summary: [String] = []
    for root in roots {
        let mine = records.filter { $0.root == root }
        guard let manifest = FileManager.default.contents(atPath: "\(repoRoot)/\(root)/\(pluginManifestRel)"),
              let version = pluginShellManifestVersion(manifest) else {
            _ = v.check(false, "\(root)/\(pluginManifestRel) 讀不到或沒有 version"); continue
        }
        guard let files = pluginShellWorkingTreeFiles(root: root) else {
            print("✗ git ls-files 對 \(root) 失敗——沒有清單就沒有摘要（空掃描不是通過）"); return 2
        }
        guard !files.isEmpty, let digest = pluginShellDigest(files, root: root) else {
            _ = v.check(false, "\(root)：送出的檔是空的，或 plugin.json 不是 JSON object"); continue
        }
        let appendLine = "\(root)\t<新版號>\t\(digest)"

        // origin/main 上的這個根
        var shipped: (version: String, digest: String)? = nil
        if published {
            guard let treeFiles = pluginShellTreeFiles(root: root, ref: pluginShellPublishedRef) else {
                print("✗ 讀不到 \(pluginShellPublishedRef) 上的 \(root)——git ls-tree 或 cat-file 失敗"); return 2
            }
            if !treeFiles.isEmpty {
                let m = treeFiles.first { $0.path == "\(root)/\(pluginManifestRel)" }?.data
                if let sv = pluginShellManifestVersion(m), let sd = pluginShellDigest(treeFiles, root: root) { shipped = (sv, sd) }
                else { _ = v.check(false, "\(pluginShellPublishedRef) 上的 \(root)/\(pluginManifestRel) 讀不懂") }
            }
        }

        guard let last = mine.last else {
            _ = v.check(false, "\(pluginShellVersionsPath) 沒有 \(root) 的任何一列——把現在的版號記進去：`\(root)\t\(version)\t\(digest)`"
                + (shipped.map { "（\(pluginShellPublishedRef) 送出的是 \($0.version)，先記 `\(root)\t\($0.version)\t\($0.digest)`）" } ?? ""))
            continue
        }

        // 3. 已發布的版號，表裡要有、而且是它真的送出的那份內容
        if let s = shipped {
            if let rec = mine.first(where: { $0.version == s.version }) {
                _ = v.check(rec.digest == s.digest,
                    "\(root) \(s.version) 已推上 main（\(pluginShellPublishedRef)），送出的內容摘要是 \(s.digest)，表的第 \(rec.line) 行卻記 \(rec.digest)："
                    + "已發布的版號被改記成別的內容——表只增不改，那一行改回 \(s.digest)；內容要變就升版（接一列新的版號）")
            } else if pluginShellVersionLess(last.version, s.version) {
                _ = v.check(false, "\(root)：\(pluginShellPublishedRef) 送出的是 \(s.version)，比表的最後一列 \(last.version) 新——這個分支落後 main，先合併 main")
            } else {
                _ = v.check(false, "\(root)：\(pluginShellPublishedRef) 送出的 \(s.version) 不在表裡——補一列 `\(root)\t\(s.version)\t\(s.digest)`（依版號排在對的位置）")
            }
        }

        // 2. 工作樹的版號是表的最後一列
        if version != last.version {
            if mine.contains(where: { $0.version == version }) || pluginShellVersionLess(version, last.version) {
                _ = v.check(false, "\(root)/\(pluginManifestRel) 的 version 是 \(version)，表的最後一列是 \(last.version)：版號只能往上")
            } else {
                _ = v.check(false, "\(root)/\(pluginManifestRel) 的 version 是 \(version)，表的最後一列是 \(last.version)："
                    + "升版時在 \(pluginShellVersionsPath) 最後接一列 `\(root)\t\(version)\t\(digest)`")
            }
            summary.append("\(root) \(version)")
            continue
        }

        // 2. 工作樹的內容是最後一列記下的那一份
        if digest != last.digest {
            let why = "\(root) 的殼內容與 \(last.version) 記下的不同（摘要 \(digest)）：內容改了而版號沒升，`claude plugin update` 會說已是最新、使用者載入舊的 skill（#729）。"
            if let s = shipped, s.version == last.version {
                _ = v.check(false, why + "\(last.version) 已推上 main——推上 main 就是發布（本 repo 是 marketplace），只能升版："
                    + "改 \(root)/\(pluginManifestRel) 的 version，並在表最後接一列 `\(appendLine)`")
            } else if shipped != nil {
                _ = v.check(false, why + "\(last.version) 還沒推上 main（\(pluginShellPublishedRef) 是 \(shipped!.version)）：把表第 \(last.line) 行的摘要改成 \(digest)；"
                    + "或升版、接一列 `\(appendLine)`")
            } else {
                _ = v.check(false, why + "\(pluginShellPublishedRef) 不在，判不了 \(last.version) 推上 main 了沒——升版一定安全："
                    + "改 \(root)/\(pluginManifestRel) 的 version，並在表最後接一列 `\(appendLine)`；確定 \(last.version) 從沒推上 GitHub main 才可以只改表第 \(last.line) 行的摘要")
            }
        }
        summary.append("\(root) \(version)" + (shipped.map { "（main：\($0.version)）" } ?? ""))
    }
    return v.exitCode("plugin 殼的版號與送出的內容一致：\(summary.joined(separator: "、"))")
}
