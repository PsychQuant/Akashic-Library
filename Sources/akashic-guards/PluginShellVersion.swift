// `plugin-shell-version`：plugin 殼送出的內容改了，`plugin.json` 的 `version` 就要升（#729；#613 b39＝b38 Z2 第 0 則、b41＝b40 Z2 第 1–3、6、16、18 則、
// b43＝b42 第 1–3、6、9–11、14、15、17–19、21、23、27 則）。
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
//   0. **受測的是哪一份內容**（b43，b42 第 3、17、27 則）：pre-push 把 git 餵它的 `<local ref> <local sha> <remote ref> <remote sha>` 與 remote 名
//      經環境變數 `AKASHIC_PUSH_REFS`、`AKASHIC_PUSH_REMOTE` 交給這支——**受測的是每一個被推送的 branch 的那個 commit 的樹**，版號、表、檔都從
//      那個樹讀。b41 讀工作樹：只 commit 了 skill、版號與表的改動還留在工作樹時，推上去的 commit 兩者不一致而這支印綠；`git push origin x:main`
//      推的也不是簽出的那一份。沒有這兩個變數（手動執行、CI）才讀工作樹（已追蹤的，加上未追蹤而沒被忽略的）。
//   1. **版號表** `.githooks/plugin-shell-versions.txt`：每個 plugin 根的每個版號送出的殼內容摘要，**只增不改**（`<根> TAB <版號> TAB <摘要>`）。
//      每個根的版號依序遞增；最後一列是那個根現在的版號。受測內容的版號要等於最後一列、摘要要等於那一列的摘要。
//   2. **已發布的那個 commit**：推上 main 時是 git 給的 remote sha（遠端此刻的 main——b41 用本機的 `origin/main`，它可能落後、也可能不是
//      GitHub，b42 第 10、18 則；本機沒有那個 commit 就紅、先 fetch）；推別的 branch、手動執行、CI 時是本機的 `refs/remotes/<被推送的 remote>/main`，
//      沒有就是 `refs/remotes/origin/main`（不連網）。用的是哪一個，印在訊息裡。
//      a. **只增不改**（b42 第 1、21 則）：受測 commit 與已發布 commit 的 merge-base 上的表，每一列受測的表都要原樣還在——改了或刪了都紅。比
//         merge-base 而不比已發布的表本身：分支落後 main 時，main 之後才加的列不算被刪。main 之後才加、受測的表也有同一個版號卻記別的摘要＝同一個
//         版號兩份內容，紅。
//      b. 已發布的每個根的版號與摘要，表裡要有那一列、摘要相同。**那一列與已發布的表相同、摘要卻與已發布的內容不同＝內容在表之外改了**（部分
//         commit、`--no-verify`、直接在 GitHub 上改）：只能升版（b42 第 6 則：b41 的第一句建議叫人把那一列改成已發布的摘要，照做就洗白了）。
//      c. 受測內容的版號等於已發布的版號而內容不同、或檔案模式不同（可執行位元、一般檔換成 symlink——b42 第 11 則），只能升版。
//      d. 分支落後 main（main 已送出比表的最後一列新的版號）：推的不是 main 時只印一行說明、不擋（b42 第 19 則：與 plugin 無關的 push 先前也被擋）；
//         推 main 時紅。
//
// **送出的內容**＝根底下 git 認得的檔，除了根的 `CHANGELOG.md`（版本史，不是 Claude Code 載入的東西）；`plugin.json` 去掉 `version` 本身再算（其餘
// 欄位改了同樣要升）。**symlink 解開一層**：`plugins/akashic-discovery/rules` 指向 `plugin/rules`，那些規則檔以 `plugins/akashic-discovery/rules/<檔>`
// 計入 discovery 的內容（b40 Z2 第 6、18 則）。**解不開的具名拒絕**（b43，b42 第 2、14、23 則）：symlink 的目標本身是 symlink 或路徑經過 symlink、
// 目標底下又有 symlink、目標在 git 裡沒有任何檔、submodule——這些形狀工作樹與 git 樹的讀法不同（工作樹跟著讀進去、樹只有連結的文字或什麼都沒有），
// 同一個 commit 兩邊算出兩個摘要，發布之後第 1 項與第 2 項要的摘要互相矛盾、永遠滿足不了。摘要的演算法與 b39 的 `PluginShellVersionTests` 相同，
// 所以 0.13.4 的 `f6dfba69…` 照樣算得出來。
//
// **誠實邊界**：
//   · 推 main 以外的情形，「已發布」是本機記得的 remote-tracking ref：沒 fetch 時落後，落後那一段推上去的版號被當成還沒發布；被推送的 remote
//     不是 GitHub 時（隔離 clone 的 origin 是本機主 repo），它的 main 也不是 GitHub 的 main。
//   · 已發布的 commit 就是受測的 commit 時（CI 對 push 的淺 checkout：`origin/main` 就是 HEAD），已發布的那一半比的是它自己，「推上去之前已發布的
//     列被改了」看不出來——印一行說明（b42 第 9、18 則）。CI 要比，得把推送之前的 main 交給它（`census-parity.yml` 目前沒有，帳務擱置中無法驗）。
//   · 檔案模式只對已發布的版號比（表只記摘要、不記模式）；讀工作樹且 `core.fileMode` 是 false 時不比。
//   · `plugin.json` 以 Foundation 的 `JSONSerialization`（排序鍵、`/` 逸出成 `\/`）重新序列化再算；換工具鏈改了這個預設時摘要會無故變（第 29 則）。
//   · push 用 `--no-verify` 繞過 pre-push 時，這支只在 CI（`census-parity.yml` 對 `plugin/**`、`plugins/**` 觸發，跑 `run-guards.sh`）會跑——
//     而 CI 的帳務目前擱置（見 CLAUDE.md）。
//
// 負對照：`plugin-shell-version-mutations`（在暫存的 git repo 裡逐格注入）。

import CryptoKit
import Foundation

/// 版號表的位置（repo 相對）。
let pluginShellVersionsPath = ".githooks/plugin-shell-versions.txt"
/// 沒有推送的資訊時（手動執行、CI）「已發布」的參照：本機的 remote-tracking ref。推上 main 就是發布（本 repo 是 marketplace）。
let pluginShellPublishedRef = "refs/remotes/origin/main"
/// pre-push 交給這支的推送資訊（b43）：git 餵 hook 的 stdin，一行一個 ref（`<local ref> <local sha> <remote ref> <remote sha>`）。
let pluginShellPushRefsEnv = "AKASHIC_PUSH_REFS"
/// pre-push 的第一個參數：被推送的 remote 名（直接給網址時是網址）。
let pluginShellPushRemoteEnv = "AKASHIC_PUSH_REMOTE"

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

/// 一次讀很多個 blob（`git cat-file --batch`；b43：先前每個檔一個 `cat-file` 行程，pre-push 與負對照的耗時大半花在開行程）。
/// 任一個讀不到、或 git 叫不起來回 nil。環境與 `pluginShellGit` 同樣剝除 `GIT_*`。
func pluginShellBlobs(_ shas: [String], in dir: String = repoRoot) -> [String: Data]? {
    let wanted = Array(Set(shas))
    if wanted.isEmpty { return [:] }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", dir, "cat-file", "--batch"]
    p.environment = scrubbedGitEnvironment
    let input = Pipe(), out = Pipe()
    p.standardInput = input
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let request = Data(Array(wanted.joined(separator: "\n").utf8) + [0x0A])
    let writer = input.fileHandleForWriting
    DispatchQueue.global().async { writer.write(request); try? writer.close() }   // 另一條執行緒寫：輸出塞滿 pipe 時兩邊不互等
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    var blobs: [String: Data] = [:], i = data.startIndex
    for _ in wanted {
        guard let nl = data[i...].firstIndex(of: 0x0A) else { return nil }
        let head = String(decoding: data[i..<nl], as: UTF8.self).split(separator: " ")
        guard head.count == 3, let size = Int(head[2]), nl + 1 + size + 1 <= data.endIndex else { return nil }   // `<sha> missing` 只有兩欄
        blobs[String(head[0])] = Data(data[(nl + 1)..<(nl + 1 + size)])
        i = nl + 1 + size + 1   // 內容之後一個換行
    }
    return blobs.count == wanted.count ? blobs : nil
}

private func nulSeparated(_ data: Data) -> [String] {
    data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
}

/// 版號是不是 `N.N.N`（表只收這個形狀；比大小也只比數字）。
func pluginShellIsVersion(_ v: String) -> Bool { !matches(v, #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#).isEmpty }

/// `a` 在 `b` 之前（數字逐段比）。兩個都要是 `N.N.N`（呼叫之前先以 `pluginShellIsVersion` 擋掉別的形狀）。
func pluginShellVersionLess(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: ".").compactMap { Int($0) }, y = b.split(separator: ".").compactMap { Int($0) }
    return x.lexicographicallyPrecedes(y)
}

/// 一個 commit（或 ref）解析成完整的 sha；不在回 nil。
func pluginShellResolve(_ ref: String) -> String? {
    pluginShellGit(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"])
        .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : $0 }
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

/// `target` 的每一個前綴（含它自己）：`a/b/c` → `a`、`a/b`、`a/b/c`。
private func pathPrefixes(_ target: String) -> [String] {
    let parts = target.split(separator: "/").map(String.init)
    return parts.indices.map { parts[...$0].joined(separator: "/") }
}

/// 一個送出的檔：邏輯路徑、內容（工作樹裡被刪掉的已追蹤檔是 nil）、種類（只拿來跟已發布的同一個版號比，不進摘要）。
struct PluginShellFile {
    enum Kind: String { case regular = "一般檔", executable = "可執行檔", symlink = "symlink" }
    let path: String
    let data: Data?
    let kind: Kind
}

/// 一個根送出的檔，加上解不開的 symlink 與 submodule（具名拒絕，不靜默略過——見檔頭）。
struct PluginShellListing {
    var files: [PluginShellFile] = []
    var refusals: [String] = []
}

/// 解不開的形狀的訊息（工作樹與 git 樹兩邊同一句）。
enum PluginShellRefusal {
    static let why = "工作樹與 git 樹對它的讀法不同，同一個 commit 會算出兩個摘要，發布之後表與已發布的內容永遠對不上"
    static func chain(_ link: String, _ target: String) -> String {
        "\(link) 是指向 \(target) 的 symlink，而目標本身是 symlink、或路徑經過 symlink——只解開一層（\(why)）：改成直接指向真正的檔或目錄"
    }
    static func nested(_ link: String, _ inner: String) -> String {
        "\(link) 指向的目錄裡 \(inner) 又是 symlink——只解開一層（\(why)）：把 \(inner) 換成一般檔"
    }
    static func dangling(_ link: String, _ target: String) -> String {
        "\(link) 指向 \(target)，git 在那裡沒有任何檔（不存在，或沒有追蹤任何檔的目錄；\(why)）：刪掉它或指到存在的地方"
    }
    static func submodule(_ path: String) -> String { "\(path) 是 submodule——摘要讀不到它的內容；plugin 殼裡不放 submodule" }
}

/// 工作樹裡一個根送出的檔（已追蹤的，加上未追蹤而沒被忽略的）。git 叫不起來回 nil。
func pluginShellWorkingTreeFiles(root: String) -> PluginShellListing? {
    let fm = FileManager.default
    func listed(_ path: String) -> [String]? {
        pluginShellGit(["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", path]).map { Array(Set(nulSeparated($0))).sorted() }
    }
    func link(_ rel: String) -> String? { try? fm.destinationOfSymbolicLink(atPath: "\(repoRoot)/\(rel)") }
    func kind(_ rel: String) -> PluginShellFile.Kind {
        let perm = ((try? fm.attributesOfItem(atPath: "\(repoRoot)/\(rel)"))?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return perm & 0o100 != 0 ? .executable : .regular   // git 看擁有者的 x 位元
    }
    func isDirectory(_ rel: String) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: "\(repoRoot)/\(rel)", isDirectory: &d) && d.boolValue
    }
    guard let paths = listed(root) else { return nil }
    var out = PluginShellListing()
    for p in paths where p != "\(root)/CHANGELOG.md" {
        guard let dest = link(p) else {
            if isDirectory(p) { out.refusals.append(PluginShellRefusal.submodule(p)); continue }   // ls-files 列出目錄＝gitlink
            out.files.append(.init(path: p, data: fm.contents(atPath: "\(repoRoot)/\(p)"), kind: kind(p)))
            continue
        }
        guard let target = repoRelativeTarget(link: p, destination: dest) else {
            out.files.append(.init(path: p, data: Data("<symlink outside the repo> \(dest)".utf8), kind: .symlink)); continue
        }
        if pathPrefixes(target).contains(where: { link($0) != nil }) { out.refusals.append(PluginShellRefusal.chain(p, target)); continue }
        if isDirectory(target) {
            guard let inner = listed(target) else { return nil }
            if inner.isEmpty { out.refusals.append(PluginShellRefusal.dangling(p, target)); continue }
            for f in inner {
                if link(f) != nil { out.refusals.append(PluginShellRefusal.nested(p, f)); continue }
                if isDirectory(f) { out.refusals.append(PluginShellRefusal.submodule(f)); continue }
                out.files.append(.init(path: logicalPath(f, target: target, link: p), data: fm.contents(atPath: "\(repoRoot)/\(f)"), kind: kind(f)))
            }
        } else if fm.fileExists(atPath: "\(repoRoot)/\(target)") {
            out.files.append(.init(path: p, data: fm.contents(atPath: "\(repoRoot)/\(target)"), kind: .symlink))
        } else {
            out.refusals.append(PluginShellRefusal.dangling(p, target))
        }
    }
    return out
}

/// `ref` 的樹裡一個根送出的檔。根在那裡不存在時檔是空的；git 叫不起來或物件讀不到回 nil。
func pluginShellTreeFiles(root: String, ref: String) -> PluginShellListing? {
    /// `ls-tree` 的一行：mode type sha TAB path
    func entries(_ path: String, recursive: Bool = true) -> [(mode: String, sha: String, path: String)]? {
        guard let d = pluginShellGit(["ls-tree"] + (recursive ? ["-r"] : []) + ["-z", ref, "--", path]) else { return nil }
        return nulSeparated(d).compactMap { line in
            guard let tab = line.firstIndex(of: "\t") else { return nil }
            let head = line[..<tab].split(separator: " ")
            guard head.count == 3 else { return nil }
            return (String(head[0]), String(head[2]), String(line[line.index(after: tab)...]))
        }
    }
    func kind(_ mode: String) -> PluginShellFile.Kind { mode == "100755" ? .executable : .regular }
    guard let top = entries(root) else { return nil }
    let shipped = top.filter { $0.path != "\(root)/CHANGELOG.md" }
    guard let blobs = pluginShellBlobs(shipped.filter { $0.mode != "160000" }.map(\.sha)) else { return nil }
    var out = PluginShellListing()
    for e in shipped {
        if e.mode == "160000" { out.refusals.append(PluginShellRefusal.submodule(e.path)); continue }
        guard let blob = blobs[e.sha] else { return nil }
        guard e.mode == "120000" else { out.files.append(.init(path: e.path, data: blob, kind: kind(e.mode))); continue }
        let dest = String(decoding: blob, as: UTF8.self)
        guard let target = repoRelativeTarget(link: e.path, destination: dest) else {
            out.files.append(.init(path: e.path, data: Data("<symlink outside the repo> \(dest)".utf8), kind: .symlink)); continue
        }
        var chained = false
        for prefix in pathPrefixes(target) {
            guard let here = entries(prefix, recursive: false) else { return nil }
            if here.contains(where: { $0.path == prefix && $0.mode == "120000" }) { chained = true; break }
        }
        if chained { out.refusals.append(PluginShellRefusal.chain(e.path, target)); continue }
        guard let inner = entries(target) else { return nil }
        if inner.isEmpty { out.refusals.append(PluginShellRefusal.dangling(e.path, target)); continue }
        guard let innerBlobs = pluginShellBlobs(inner.filter { $0.mode != "120000" && $0.mode != "160000" }.map(\.sha)) else { return nil }
        if inner.count == 1, inner[0].path == target {   // 指向一個檔（上面已排除它本身是 symlink）
            guard let b = innerBlobs[inner[0].sha] else { return nil }
            out.files.append(.init(path: e.path, data: b, kind: .symlink)); continue
        }
        for f in inner {
            if f.mode == "120000" { out.refusals.append(PluginShellRefusal.nested(e.path, f.path)); continue }
            if f.mode == "160000" { out.refusals.append(PluginShellRefusal.submodule(f.path)); continue }
            guard let b = innerBlobs[f.sha] else { return nil }
            out.files.append(.init(path: logicalPath(f.path, target: target, link: e.path), data: b, kind: kind(f.mode)))
        }
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

/// 版號表。格式錯的行回在 `problems`（不靜默略過）。`roots` 是 nil 時任何根都收（讀已發布的表與 merge-base 上的表：那邊的根不一定與受測的相同）。
func readPluginShellVersions(_ text: String, roots: [String]?) -> (records: [PluginShellRecord], problems: [String]) {
    var records: [PluginShellRecord] = [], problems: [String] = []
    for (i, raw) in text.components(separatedBy: "\n").enumerated() {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty || line.hasPrefix("#") { continue }
        let f = line.components(separatedBy: "\t")
        guard f.count == 3 else { problems.append("第 \(i + 1) 行不是「根 TAB 版號 TAB 摘要」三欄：\(pyRepr([String(line.prefix(120))]))"); continue }
        if let roots, !roots.contains(f[0]) { problems.append("第 \(i + 1) 行的根 \(pyRepr([f[0]])) 不是 plugin 根（\(roots.joined(separator: "、"))）"); continue }
        guard pluginShellIsVersion(f[1]) else { problems.append("第 \(i + 1) 行的版號 \(pyRepr([f[1]])) 不是 N.N.N"); continue }
        guard !matches(f[2], #"\A[0-9a-f]{64}\z"#).isEmpty else { problems.append("第 \(i + 1) 行的摘要不是 64 位小寫十六進位"); continue }
        records.append(PluginShellRecord(root: f[0], version: f[1], digest: f[2], line: i + 1))
    }
    for root in Set(records.map(\.root)).sorted() {
        let mine = records.filter { $0.root == root }
        for (a, b) in zip(mine, mine.dropFirst()) where !pluginShellVersionLess(a.version, b.version) {
            problems.append("\(root) 的版號沒有依序遞增：第 \(a.line) 行 \(a.version)、第 \(b.line) 行 \(b.version)（表只增不改，新版號接在最後）")
        }
    }
    return (records, problems)
}

/// 受測的內容：工作樹（手動執行、CI），或一個 commit 的樹（pre-push 交給的被推送的 commit）。
enum PluginShellSource {
    case workingTree
    case commit(String)

    var label: String {
        switch self {
        case .workingTree: return "工作樹"
        case .commit(let sha): return "commit \(sha.prefix(12))"   // display-safe-exempt: sha.prefix 是 git 的 commit sha（推送資訊先以 40／64 位十六進位驗過、再 rev-parse 確認），非 store 衍生
        }
    }

    /// 與已發布的 commit 求 merge-base 時用的 commit。
    var commitish: String {
        switch self {
        case .workingTree: return "HEAD"
        case .commit(let sha): return sha
        }
    }

    /// plugin 根：`plugin`，加上 `plugins/` 底下含 `.claude-plugin/plugin.json` 的直接子目錄（與 `pluginRoots()` 同一個判準）。
    func roots() -> [String]? {
        switch self {
        case .workingTree: return pluginRoots()
        case .commit(let sha):
            guard let d = pluginShellGit(["ls-tree", "-r", "-z", "--name-only", sha, "--", "plugins"]) else { return nil }
            var roots: Set<String> = ["plugin"]
            for p in nulSeparated(d) {
                let parts = p.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                if parts.count == 4, parts[0] == "plugins", "\(parts[2])/\(parts[3])" == pluginManifestRel { roots.insert("plugins/\(parts[1])") }
            }
            return roots.sorted()
        }
    }

    func table() -> String? {
        switch self {
        case .workingTree: return readFile(pluginShellVersionsPath)
        case .commit(let sha): return pluginShellTableText(at: sha)
        }
    }

    func listing(_ root: String) -> PluginShellListing? {
        switch self {
        case .workingTree: return pluginShellWorkingTreeFiles(root: root)
        case .commit(let sha): return pluginShellTreeFiles(root: root, ref: sha)
        }
    }
}

/// 一個 commit 上的版號表；那個 commit 沒有表回 nil。
func pluginShellTableText(at sha: String) -> String? {
    pluginShellGit(["cat-file", "blob", "\(sha):\(pluginShellVersionsPath)"]).map { String(decoding: $0, as: UTF8.self) }
}

/// 已發布的那個 commit 與它在訊息裡的名字。
struct PluginShellPublished {
    let commit: String
    let label: String
}

/// 本機的 remote-tracking ref 當成已發布的 commit；不在回 nil。
func pluginShellPublished(ref: String) -> PluginShellPublished? {
    pluginShellResolve(ref).map { PluginShellPublished(commit: $0, label: "本機的 \(ref)（\($0.prefix(12))）") }
}

/// 對一份內容跑全部的判斷（見檔頭第 1、2 項）；印出結果、回 rc。`targetIsMain`：這次推的就是 main（落後 main 時紅；否則只說明）。
func pluginShellCheck(_ source: PluginShellSource, published: PluginShellPublished?, targetIsMain: Bool) -> Int32 {
    guard let roots = source.roots(), !roots.isEmpty else { print("✗ 一個 plugin 根都找不到（\(source.label)）——空掃描不是通過"); return 2 }
    guard let tableText = source.table() else {
        print("✗ 讀不到版號表 \(pluginShellVersionsPath)（\(source.label)）——沒有表就判不了版號送出的是哪一份內容"); return 2
    }
    let (records, problems) = readPluginShellVersions(tableText, roots: roots)
    var v = Verdict()
    for p in problems { _ = v.check(false, "\(pluginShellVersionsPath)：\(p)") }
    func row(_ rows: [PluginShellRecord], _ root: String, _ version: String) -> PluginShellRecord? {
        rows.first { $0.root == root && $0.version == version }
    }

    // 已發布的表，與受測的 commit 跟它的 merge-base 上的表（第 2a 項）
    var publishedRows: [PluginShellRecord] = [], baseRows: [PluginShellRecord] = []
    if let pub = published {
        let tested: String? = { if case .commit(let s) = source { return s }; return pluginShellResolve("HEAD") }()
        if tested == pub.commit {
            print("ℹ 已發布的 commit（\(pub.label)）就是受測的 commit：已發布的那一半比的是它自己——推上去之前已發布的列有沒有被改，這裡看不出來"
                  + ({ if case .workingTree = source { return "（只看得出工作樹裡還沒 commit 的改動）" }; return "" }()))
        }
        publishedRows = pluginShellTableText(at: pub.commit).map { readPluginShellVersions($0, roots: nil).records } ?? []
        let base = pluginShellGit(["merge-base", source.commitish, pub.commit])
            .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        if base == pub.commit {
            baseRows = publishedRows
        } else if let b = base, !b.isEmpty {
            baseRows = pluginShellTableText(at: b).map { readPluginShellVersions($0, roots: nil).records } ?? []
        } else {
            print("ℹ 受測的內容與 \(pub.label) 沒有共同的祖先：只增不改那一項只比已發布的表裡、這裡也有的版號")
        }
        for r in baseRows {
            if let mine = row(records, r.root, r.version) {
                _ = v.check(mine.digest == r.digest,
                    "\(pluginShellVersionsPath) 第 \(mine.line) 行 \(r.root) \(r.version) 記 \(mine.digest)，而它在已發布的表裡記 \(r.digest)："
                    + "表只增不改，已發布的列改回 \(r.digest)；內容要變就升版（接一列新的版號）")
            } else {
                _ = v.check(false, "\(r.root) \(r.version)（已發布的表第 \(r.line) 行，摘要 \(r.digest)）在 \(pluginShellVersionsPath) 裡不見了："
                    + "表只增不改，把 `\(r.root)\t\(r.version)\t\(r.digest)` 放回去（依版號排在對的位置）")
            }
        }
        for r in publishedRows where row(baseRows, r.root, r.version) == nil {
            if let mine = row(records, r.root, r.version), mine.digest != r.digest {
                _ = v.check(false, "\(r.root) \(r.version) 在已發布的表裡記 \(r.digest)，\(pluginShellVersionsPath) 第 \(mine.line) 行卻記 \(mine.digest)："
                    + "同一個版號兩份內容——先合併 main，再升到 \(r.version) 之後的版號")
            }
        }
    }

    var summary: [String] = []
    for root in roots {
        let mine = records.filter { $0.root == root }
        guard let listing = source.listing(root) else {
            print("✗ 讀不到 \(root) 送出的檔（\(source.label)；git ls-files／ls-tree 或 cat-file 失敗）——沒有清單就沒有摘要（空掃描不是通過）"); return 2
        }
        for r in listing.refusals { _ = v.check(false, "\(root)：\(r)") }
        guard listing.refusals.isEmpty else { summary.append("\(root) ?"); continue }
        let files = listing.files.map { (path: $0.path, data: $0.data) }
        let manifest = files.first { $0.path == "\(root)/\(pluginManifestRel)" }?.data
        guard let version = pluginShellManifestVersion(manifest) else {
            _ = v.check(false, "\(root)/\(pluginManifestRel) 讀不到或沒有 version（\(source.label)）"); continue
        }
        guard pluginShellIsVersion(version) else {
            _ = v.check(false, "\(root)/\(pluginManifestRel) 的 version \(pyRepr([version])) 不是 N.N.N——版號表只收這個形狀，比大小也只比數字"); continue
        }
        guard !files.isEmpty, let digest = pluginShellDigest(files, root: root) else {
            _ = v.check(false, "\(root)：送出的檔是空的，或 plugin.json 不是 JSON object"); continue
        }
        let appendLine = "\(root)\t<新版號>\t\(digest)"

        // 已發布的 commit 上的這個根
        var shipped: (version: String, digest: String, kinds: [String: PluginShellFile.Kind])? = nil
        var rootOnPublished = false
        if let pub = published {
            guard let tree = pluginShellTreeFiles(root: root, ref: pub.commit) else {
                print("✗ 讀不到 \(pub.label) 上的 \(root)——git ls-tree 或 cat-file 失敗"); return 2
            }
            rootOnPublished = !tree.files.isEmpty || !tree.refusals.isEmpty
            for r in tree.refusals { _ = v.check(false, "\(pub.label) 上的 \(root)：\(r)") }
            if !tree.files.isEmpty, tree.refusals.isEmpty {
                let m = tree.files.first { $0.path == "\(root)/\(pluginManifestRel)" }?.data
                if let sv = pluginShellManifestVersion(m), pluginShellIsVersion(sv),
                   let sd = pluginShellDigest(tree.files.map { (path: $0.path, data: $0.data) }, root: root) {
                    shipped = (sv, sd, Dictionary(tree.files.map { ($0.path, $0.kind) }, uniquingKeysWith: { a, _ in a }))
                } else {
                    _ = v.check(false, "\(pub.label) 上的 \(root)/\(pluginManifestRel) 讀不懂，或 version 不是 N.N.N")
                }
            }
        }
        let pubName = published?.label ?? ""

        guard let last = mine.last else {
            _ = v.check(false, "\(pluginShellVersionsPath) 沒有 \(root) 的任何一列——把現在的版號記進去：`\(root)\t\(version)\t\(digest)`"
                + (shipped.map { "（\(pubName) 送出的是 \($0.version)，先記 `\(root)\t\($0.version)\t\($0.digest)`）" } ?? ""))
            continue
        }

        // 2b. 已發布的版號，表裡要有、而且是它真的送出的那份內容
        if let s = shipped {
            if let rec = row(mine, root, s.version) {
                if rec.digest != s.digest {
                    if let pr = row(publishedRows, root, s.version) {
                        // 表的這一列與已發布的表不同：多半第 2a 項已經報了（只增不改，或同一個版號兩份內容），這裡不再給第二個說法
                        if pr.digest == rec.digest {
                            _ = v.check(false, "\(root) \(s.version) 已推上 main（\(pubName)），送出的內容摘要是 \(s.digest)；已發布的表與這裡的表（第 \(rec.line) 行）"
                                + "都記 \(rec.digest)：內容在表之外改了（部分 commit、`--no-verify`、直接在 GitHub 上改）。已發布的版號不能換內容、表的這一列也不能改——"
                                + "只能升版：改 \(root)/\(pluginManifestRel) 的 version，並在表最後接一列 `\(appendLine)`")
                        } else if let b = row(baseRows, root, s.version), b.digest == rec.digest, b.digest != pr.digest {
                            // 第 2a 項沒有報：這裡與分開時的表相同，是 main 上的這一列被改過
                            _ = v.check(false, "\(root) \(s.version)：已發布的表記 \(pr.digest)，這裡與分支開出來時的 main 都記 \(rec.digest)——main 上的這一列被改過"
                                + "（表只增不改；那是推上 main 時被繞過的守衛）。先合併 main，再照合併後的訊息處理")
                        }
                    } else {
                        _ = v.check(false, "\(root) \(s.version) 已推上 main（\(pubName)），送出的內容摘要是 \(s.digest)，表的第 \(rec.line) 行卻記 \(rec.digest)；"
                            + "已發布的表沒有這一列：這一列記的要是它真的送出的內容 \(s.digest)；內容要變就升版（接一列新的版號）")
                    }
                }
            } else if pluginShellVersionLess(last.version, s.version) {
                if targetIsMain {
                    _ = v.check(false, "\(root)：\(pubName) 送出的是 \(s.version)，比這次推上 main 的表的最後一列 \(last.version) 新——推上去版號會倒退；先合併 main")
                } else {
                    print("ℹ \(root)：\(pubName) 已送出 \(s.version)，這裡的表最後一列是 \(last.version)——這個分支落後 main。推的不是 main，不擋；合併 main 時把那幾列併進來")
                }
            } else {
                _ = v.check(false, "\(root)：\(pubName) 送出的 \(s.version) 不在表裡——補一列 `\(root)\t\(s.version)\t\(s.digest)`（依版號排在對的位置）")
            }
        }

        // 1. 受測內容的版號是表的最後一列
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

        // 1. 受測的內容是最後一列記下的那一份
        let lastIsPublished = shipped?.version == last.version || row(publishedRows, root, last.version) != nil || row(baseRows, root, last.version) != nil
        if digest != last.digest {
            let why = "\(root) 的殼內容與 \(last.version) 記下的不同（摘要 \(digest)，\(source.label)）：內容改了而版號沒升，`claude plugin update` 會說已是最新、使用者載入舊的 skill（#729）。"
            if lastIsPublished {
                _ = v.check(false, why + "\(last.version) 已推上 main（\(pubName)）——推上 main 就是發布（本 repo 是 marketplace），只能升版："
                    + "改 \(root)/\(pluginManifestRel) 的 version，並在表最後接一列 `\(appendLine)`")
            } else if published != nil, !rootOnPublished {
                _ = v.check(false, why + "\(root) 不在 \(pubName) 上（還沒發布過的 plugin 根）：把表第 \(last.line) 行的摘要改成 \(digest)；或升版、接一列 `\(appendLine)`")
            } else if let s = shipped {
                _ = v.check(false, why + "\(last.version) 還沒推上 main（\(pubName) 是 \(s.version)）：把表第 \(last.line) 行的摘要改成 \(digest)；"
                    + "或升版、接一列 `\(appendLine)`")
            } else {
                _ = v.check(false, why + "沒有已發布的 commit 可比，判不了 \(last.version) 推上 main 了沒——升版一定安全："
                    + "改 \(root)/\(pluginManifestRel) 的 version，並在表最後接一列 `\(appendLine)`；確定 \(last.version) 從沒推上 GitHub main 才可以只改表第 \(last.line) 行的摘要")
            }
        } else if let s = shipped, s.version == version, s.digest == digest {
            // 2c. 內容相同而檔案模式不同（可執行位元、一般檔換成 symlink）：送出的東西變了，摘要看不到
            let fileModeOff: Bool = {
                guard case .workingTree = source else { return false }
                return pluginShellGit(["config", "--bool", "core.fileMode"]).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } == "false"
            }()
            if fileModeOff {
                print("ℹ core.fileMode 是 false：\(root) 的檔案模式（可執行位元）不與 \(pubName) 比")
            } else {
                let mineKinds = Dictionary(listing.files.map { ($0.path, $0.kind) }, uniquingKeysWith: { a, _ in a })
                let changed = mineKinds.keys.sorted().filter { mineKinds[$0] != s.kinds[$0] }
                if !changed.isEmpty {
                    let shown = changed.prefix(5).map { "\($0)（已發布：\(s.kinds[$0]?.rawValue ?? "?")，這裡：\(mineKinds[$0]!.rawValue)）" }.joined(separator: "、")
                    _ = v.check(false, "\(root) \(version) 已推上 main（\(pubName)），內容相同而檔案模式改了：\(shown)\(changed.count > 5 ? "等 \(changed.count) 個" : "")——"
                        + "送出的東西變了（摘要不看模式），只能升版：改 \(root)/\(pluginManifestRel) 的 version，並在表最後接一列 `\(appendLine)`")
                }
            }
        }
        summary.append("\(root) \(version)" + (shipped.map { "（main：\($0.version)）" } ?? ""))
    }
    fflush(stdout)   // 上面的 ℹ 是 `print`（有緩衝），`exitCode` 直接寫——先清掉，順序才對
    return v.exitCode("plugin 殼的版號與送出的內容一致（\(source.label)）：\(summary.joined(separator: "、"))")
}

private func pluginShellIsSHA(_ s: String) -> Bool { !matches(s, #"\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z"#).isEmpty }
private func pluginShellIsZero(_ s: String) -> Bool { s.allSatisfy { $0 == "0" } }

func pluginShellVersion() -> Int32 {
    let env = ProcessInfo.processInfo.environment
    guard let refsText = env[pluginShellPushRefsEnv], !refsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        // 手動執行、CI：工作樹對本機的 origin/main
        let pub = pluginShellPublished(ref: pluginShellPublishedRef)
        if pub == nil { print("ℹ \(pluginShellPublishedRef) 不在（沒有 remote，或淺 checkout）：只照版號表判斷，分不出最後一列推上 main 了沒") }
        return pluginShellCheck(.workingTree, published: pub, targetIsMain: false)
    }
    let remote = env[pluginShellPushRemoteEnv] ?? ""
    var worst: Int32 = 0, branches = 0
    for (n, raw) in refsText.components(separatedBy: "\n").enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard f.count == 4, pluginShellIsSHA(f[1]), pluginShellIsSHA(f[3]) else {
            print("✗ \(pluginShellPushRefsEnv) 第 \(n + 1) 行不是「local ref、local sha、remote ref、remote sha」：\(pyRepr([String(line.prefix(160))]))")
            worst = max(worst, 2); continue
        }
        let (localRef, localSHA, remoteRef, remoteSHA) = (f[0], f[1], f[2], f[3])
        if pluginShellIsZero(localSHA) { continue }                  // 刪除：不送出任何內容
        guard remoteRef.hasPrefix("refs/heads/") else { continue }    // tag 等：marketplace 讀的是 main
        branches += 1
        let toMain = remoteRef == "refs/heads/main"
        print("── 推送 \(localRef) → \(remote.isEmpty ? "" : "\(remote) ")\(remoteRef)（\(localSHA.prefix(12))）──")
        guard pluginShellResolve(localSHA) == localSHA else {
            print("✗ 被推送的 commit \(localSHA.prefix(12)) 在這個 repo 裡讀不到"); worst = max(worst, 2); continue
        }
        var published: PluginShellPublished? = nil
        if toMain {
            if pluginShellIsZero(remoteSHA) {
                print("ℹ 遠端還沒有 main：沒有已發布的內容可比，只照版號表判斷")
            } else if pluginShellResolve(remoteSHA) == remoteSHA {
                published = PluginShellPublished(commit: remoteSHA, label: "\(remote.isEmpty ? "遠端" : remote) 的 main（\(remoteSHA.prefix(12))，推送時遠端回報的）")
            } else {
                print("✗ 遠端的 main 是 \(remoteSHA.prefix(12))，這個 repo 沒有那個 commit——先 `git fetch`，才知道已發布的是哪一份內容")
                worst = max(worst, 1); continue
            }
        } else {
            published = (remote.isEmpty ? nil : pluginShellPublished(ref: "refs/remotes/\(remote)/main")) ?? pluginShellPublished(ref: pluginShellPublishedRef)
            if published == nil { print("ℹ refs/remotes/\(remote.isEmpty ? "origin" : remote)/main 與 \(pluginShellPublishedRef) 都不在：只照版號表判斷，分不出最後一列推上 main 了沒") }
        }
        worst = max(worst, pluginShellCheck(.commit(localSHA), published: published, targetIsMain: toMain))
    }
    if branches == 0, worst == 0 { print("══ 這次推送沒有 branch（只有 tag 或刪除）：沒有送出 plugin 殼的內容 ══") }
    return worst
}
