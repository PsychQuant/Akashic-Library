import Foundation
import XCTest
@testable import AkashicStoreIO

/// #239 的第二層：**架構測試**，不是 runtime 斷言。
///
/// 每一處 spawn git 都必須剝除 `GIT_*`——`-C <dir>` 擋不住 `GIT_DIR`，後者優先權
/// 更高。曾試圖在 `assertSourcesExcluded` 加 runtime containment 斷言，兩個探針都
/// 不可用（見該處註解）；真正的復發風險本來就是靜態的：**新增一個呼叫點時忘記
/// 剝除**。那用讀原始碼的測試驗，比在 runtime 再驗一次同一件事誠實。
///
/// **範圍含 `Sources/` 與 `Tests/`**（2026-08-12 擴大）。原本只走 `Sources/`——那條
/// 線沒有理由，只是「產品程式碼要嚴謹」的直覺。而 #234 的原始 bug 就在 `Tests/`
/// (`GitFixture`)，同類的第三處 (`CorpusValidationTests` 的兩個 helper) 正好被切在
/// 範圍外，於是漏掉，直到完整套件在模擬 hook 環境下把三個 fixture commit 寫進目標
/// repo 才現形。**測試碼的 git 呼叫危險性不低於產品碼**：它會 `init`／`commit`／
/// `checkout -b`，都是寫入。
///
/// 這個測試會在「有人新增 git 呼叫點」時變紅——那正是它的作用，不是誤報。
/// 修法：讓新呼叫點走既有的剝除 helper，或在該型別加自己的 `scrubbedGitEnvironment`
/// 並在此登記。
final class GitSpawnHygieneTests: XCTestCase {

    /// 從本檔位置往上找 repo root（同時含 `Sources/` 與 `Tests/` 的那層）。
    private var repoRoot: URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            let hasSources = fm.fileExists(
                atPath: dir.appendingPathComponent("Sources").path, isDirectory: &isDir)
                && isDir.boolValue
            let hasTests = fm.fileExists(
                atPath: dir.appendingPathComponent("Tests").path, isDirectory: &isDir)
                && isDir.boolValue
            if hasSources && hasTests { return dir }
            dir = dir.deletingLastPathComponent()
        }
        XCTFail("找不到同時含 Sources/ 與 Tests/ 的目錄——測試無法定位原始碼樹")
        return URL(fileURLWithPath: "/nonexistent")
    }

    /// 已知會 spawn git 且**已剝除環境**的檔案（封閉列舉）。
    ///
    /// 新增檔案到這裡之前，先確認它真的設了 `environment`——這份清單是「已檢視過」
    /// 的紀錄，不是豁免權。
    private let auditedFiles: Set<String> = [
        // Sources/
        "DivergenceResolve.swift",     // 共用 helper git(_:in:)；SourceStore 與刪除閘都走它
        "Validation.swift",            // TractatusDocs 的歷史驗證（兩處），隨 #237 進 main
        // Tests/
        "GitFixture.swift",            // #234 的原始現場
        "CorpusValidationTests.swift", // history 測試的 runGit／gitOutput（#234 同類）
        "PrePushHookTests.swift",      // #585 擴大偵測後才看見；當時沒剝 GIT_*，同輪補上
        "StoreGitCommit.swift",        // #573 的測試 helper：repoint／demote 前先 commit
        // 這條清單是封閉列舉：多了會紅（stale），少了也會紅（spawn git 卻未登記——#585 R1 verify 第 16／36 列：先前只有
        // 「沒剝環境」才紅，有剝環境但沒登記的檔安靜通過，於是清單與實際分岔而守衛照綠）。
        //
        // 後兩者的來歷值得記：PR #243 從 `idd/230-xcrun-toolchain` 抽出 #234／#239 時，
        // TractatusDocs 還不在 main 上，所以那兩處的修法與清單條目都留給了 #237，並在
        // 原位寫下「#237 合併時必須加回來」。#237 併入 main 的當下守衛就紅了，
        // **而且訊息指名了正是那兩個檔**——封閉列舉讓一個跨 PR 的交接變成機械可檢。
    ]

    func testEveryGitSpawnScrubsGitEnvironment() throws {
        let fm = FileManager.default
        let root = repoRoot
        var offenders: [String] = []
        var found: Set<String> = []

        for treeName in ["Sources", "Tests"] {
            let tree = root.appendingPathComponent(treeName)
            guard let walker = fm.enumerator(at: tree, includingPropertiesForKeys: nil) else {
                return XCTFail("無法走訪 \(tree.path)")
            }
            for case let url as URL in walker where url.pathExtension == "swift" {
                // 本檔談論 spawn git 但自己不 spawn——排除，免得討論自己的字面值。
                guard url.lastPathComponent != (#filePath as NSString).lastPathComponent else {
                    continue
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                // spawn git 的判準：arguments 陣列裡出現 "git" 這個字面 argv[0]，或直接執行 git 的絕對路徑（#585 起 store 與
                // fixture 改走 `/usr/bin/git`——只認 argv[0] 的話，改完之後這兩處就從守衛的視野消失了）。
                guard text.contains("\"git\",") || text.contains("[\"git\"]") || text.contains("\"/usr/bin/git\"") else { continue }
                found.insert(url.lastPathComponent)
                if !text.contains("scrubbedGitEnvironment") {
                    offenders.append("\(treeName)/…/\(url.lastPathComponent)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            以下檔案 spawn git 但沒有剝除 `GIT_*`（#234／#239）：\(offenders.sorted().joined(separator: "、"))

            `-C <dir>` 擋不住 `GIT_DIR`——從 git hook 執行時，這些呼叫會對**錯的 repo**
            動作。在 Sources/ 的後果是 `sources/` 排除閘 fail-open（放行不該放行的寫入，
            外流不可逆）；在 Tests/ 的後果是 fixture 的 init／commit／checkout 寫進
            使用者的真實 repo。讓新呼叫點走剝除環境的 helper。
            """
        )

        let unlisted = found.subtracting(auditedFiles)
        XCTAssertTrue(
            unlisted.isEmpty,
            "以下檔案 spawn git 但不在 auditedFiles：\(unlisted.sorted().joined(separator: "、"))——確認它剝除了環境後登記"
        )

        // 反向：登記過的檔案若不再 spawn git，清單就該縮——否則它會慢慢變成一份
        // 沒人維護的名單，然後某天有人以為「在清單裡＝安全」。
        let stale = auditedFiles.subtracting(found)
        XCTAssertTrue(
            stale.isEmpty,
            "以下檔案已不再 spawn git，請從 auditedFiles 移除：\(stale.sorted().joined(separator: "、"))"
        )
    }

    /// #585：store 的 git 呼叫不經 `PATH`。#558 R3 verify 用一個排在 `PATH` 前面的 `git` shim 讓可回溯性閘從拒絕變成
    /// 靜默放行；現在答案固定來自 `LibraryStore.gitExecutable`。
    func testAShimEarlierInPathDoesNotAnswerForGit() throws {
        let fm = FileManager.default
        let shimDir = fm.temporaryDirectory.appendingPathComponent("git-shim-\(UUID().uuidString)")
        try fm.createDirectory(at: shimDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: shimDir) }
        let shim = shimDir.appendingPathComponent("git")
        try "#!/bin/sh\necho SHIM-ANSWERED\n".write(to: shim, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)

        let saved = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", shimDir.path + ":" + saved, 1)
        defer { setenv("PATH", saved, 1) }
        XCTAssertTrue(ProcessInfo.processInfo.environment["PATH"]?.hasPrefix(shimDir.path) ?? false, "前提：shim 排在 PATH 最前面")

        let r = try XCTUnwrap(LibraryStore.git(["--version"], in: shimDir))
        XCTAssertFalse(r.out.contains("SHIM-ANSWERED"), "PATH 前面的 shim 回答了 git 的問題：\(r.out)")
        XCTAssertTrue(r.out.hasPrefix("git version"), r.out)
    }

    /// #573／#585 R1 verify DA 第 13 列：`HOME` 下的 `.gitconfig` 不得改變可回溯性閘的答案。攻擊形：global attributes 把 `*.yaml`
    /// 對到一個 clean filter，filter 從 HEAD 取內容——`diff HEAD` 於是把 dirty 的檔判成 clean。閘只讀 repo 自己的設定時照樣報出來。
    func testGlobalGitconfigCannotMakeADirtyFileLookClean() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("git-home-\(UUID().uuidString)")
        let repo = base.appendingPathComponent("repo"), home = base.appendingPathComponent("home")
        try fm.createDirectory(at: repo.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let file = repo.appendingPathComponent("entities/a.yaml")
        try "v: 1\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(GitFixture.run(["init", "-q"], in: repo), 0)
        XCTAssertEqual(GitFixture.run(["add", "-A"], in: repo), 0)
        XCTAssertEqual(GitFixture.run(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed"], in: repo), 0)
        try "v: 2\n".write(to: file, atomically: true, encoding: .utf8)

        let attrs = home.appendingPathComponent("attrs")
        try "*.yaml filter=lie\n".write(to: attrs, atomically: true, encoding: .utf8)
        try """
            [core]
            \tattributesFile = \(attrs.path)
            [filter "lie"]
            \tclean = git cat-file -p HEAD:%f
            """.write(to: home.appendingPathComponent(".gitconfig"), atomically: true, encoding: .utf8)
        let saved = ProcessInfo.processInfo.environment["HOME"] ?? ""
        setenv("HOME", home.path, 1)
        defer { setenv("HOME", saved, 1) }
        // 前提：這份 gitconfig 真的會讓一個不設防的 git 說謊——否則下面的斷言是空的
        let naive = Process()
        naive.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        naive.arguments = ["-C", repo.path, "diff", "--name-only", "HEAD"]
        naive.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let pipe = Pipe(); naive.standardOutput = pipe; naive.standardError = FileHandle.nullDevice
        try naive.run(); naive.waitUntilExit()
        let naiveOut = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertFalse(naiveOut.contains("entities/a.yaml"), "前提：只剝 GIT_* 的 git 被這份 gitconfig 騙過")

        let bad = LibraryStore.filesNotSafelyRecoverable(root: repo, relativePaths: ["entities/a.yaml"])
        XCTAssertEqual(bad.map(\.path), ["entities/a.yaml"], "global gitconfig 讓閘把 dirty 的檔判成 clean")
        XCTAssertTrue(bad.first?.why.contains("未提交") ?? false, "\(bad)")
    }

}
