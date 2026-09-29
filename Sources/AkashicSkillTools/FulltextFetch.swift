import Foundation
import AkashicCore
import AkashicStoreIO

/// 透過使用者自己的 Safari session 取一篇 work 的全文 PDF（#629 由 `fetch-fulltext.sh` 移植）。
///
/// PDF 是從**文章頁內部**取的（同源、頁面自己的 cookie），不是導航到 PDF 網址：Safari 的 PDF 檢視器不是頁面 JavaScript
/// 讀得到的頁面，而 headless 取得在使用者的 session 讀得到的網站上被拒（403／JS 挑戰；2026-09-23 觀察）。
///
/// # 結束碼是它對 agent 的契約
///
///     0 取得，且（有 --title 時）驗證通過      3 頁面上找不到 PDF 連結
///     1 自動化失敗（見 stderr）                4 無權限（網站給了登入殼）
///     2 回應不是 PDF（本文存成 FILE.response.txt 給人看）
///     5 是 PDF，但驗證不是這篇（存成 FILE.unverified.pdf）
///     6 **整批停止**（SKILL.md〈中止條款〉）：網站出現懷疑是自動化的跡象——挑戰／封鎖頁、HTTP 403／429、分頁跑到別的
///       網站、卡住或空的回應、或讀不到頁面而無從檢查。「沒辦法檢查」被當成起疑，不是乾淨。分頁留著給使用者看。
///
/// **落錯碼就是把中止條款悄悄變成重試**——2026-09-24 審查在三處找到這個缺陷。測試（`FulltextFetchPathTests`）逐條路徑釘住
/// 「這條路徑落在哪個碼、留下什麼副作用」：6 時我們的分頁**不**被關、請求的檔名下什麼都沒寫；0 時只關自己開的分頁、使用者的
/// 分頁不動。
///
/// # 這一版做了什麼、沒做什麼
///
/// - 流程逐步照舊：同樣的引數向量（`open --new-tab --window N`、`js --window N --tab-in-window T`、`wait … --timeout`），
///   同樣的等待秒數，同樣的判斷順序。領域判斷（起疑訊號、出版商網址規則、驗證）不再是外部腳本，直接呼叫同一個模組的型別。
/// - **鎖分頁的方式沒有改**：仍是 `--window N` 加它自己開的分頁位置（`--tab-in-window`，#613 的作法，理由見
///   `references/publishers.md`：使用者已開著同一頁時 URL 鎖會對到兩個分頁、safari-browser fail-closed），**不是**
///   `web-access-via-safari-browser.md` 的 `--profile`＋`--url-endswith`。這是規則檔〈例外〉第二種形狀的 grandfathered 項目；
///   改成 `--url-endswith` 要使用者裁決、而且要實跑 Safari（規則檔記著便宜的解：對 `--landing` 加一次性 fragment）。
/// - 環境變數 `FETCH_FULLTEXT_NAP`（路徑測試用來把等待歸零）不再存在——等待由建構子的 `sleeper` 注入。
///
/// # 不變量（#629 R1 verify 之後由程式強制，不只寫在文件裡）
///
/// - **輸出目的地**（`--out`、`*.unverified.pdf`、`*.response.txt`）在碰瀏覽器之前 `lstat`：只有「不存在」或「普通檔」放行；目錄、symlink、
///   特殊檔具名拒絕。覆寫普通檔是同目錄暫存＋`rename` 的原子替換（`OutputFile`）——不遞迴刪任何東西、失敗時原檔還在。
/// - **git 閘 fail-closed**：輸出目錄的祖先有 `.git` 時，git 執行不起來、`rev-parse` 非零、`check-ignore` 不是 0／1，一律拒絕。git 一律走
///   `LibraryStore.hardenedGit`（#585 的同一支）。
/// - `--landing`、`--prime` 只收 `https://`；頁面自己給的 PDF 連結（DOM 來的）origin 要與頁面相同才發 `credentials:'include'` 的 fetch，
///   出版商規則（`PdfUrlRules`）產生的網址不受此限。`--expect-profile` 在命令列層必填。
/// - 暫存目錄 0700；poppler 對第三方 PDF 有逾時（`ToolRunner.popplerTimeout`）。
///
/// **仍沒有的**：沒對真的 `safari-browser` 跑過（只對記憶體內的假瀏覽器與舊 Python stub）；`siteGuard` 的七個呼叫點沒有逐一被測試單獨釘住
/// （相鄰的守衛互相遮蔽，拿掉任一個測試都不變紅——舊 shell 的 `guard;` 同樣沒有；退出點 `botStop` 則逐一有測試，R1 verify 第 55 則）。
public final class FulltextFetch {
    public struct Options {
        public var window: Int
        public var landing: String
        public var out: String
        public var title: String?
        public var pages: String?
        public var doi: String?
        public var prime: String?
        public var expectProfile: String?
        public init(window: Int, landing: String, out: String, title: String? = nil, pages: String? = nil,
                    doi: String? = nil, prime: String? = nil, expectProfile: String? = nil) {
            self.window = window; self.landing = landing; self.out = out; self.title = title; self.pages = pages
            self.doi = doi; self.prime = prime; self.expectProfile = expectProfile
        }
    }

    /// 以某個結束碼結束（訊息已經印出）。
    struct Stop: Error { let code: Int32 }

    /// 在目錄裡跑一次 git；nil＝執行不起來。預設是 repo 既有的加固 helper（`/usr/bin/git` 絕對路徑、剝 `GIT_*`、
    /// `core.fsmonitor=false`、`core.attributesFile=/dev/null`，#585）；測試注入「起不來」的版本。
    public typealias GitRunner = ([String], URL) -> (status: Int32, out: String)?

    private let browser: SafariBrowser
    private let sleeper: (Double) -> Void
    private let out: (String) -> Void
    private let err: (String) -> Void
    private let git: GitRunner

    private var window = 0
    /// 我們自己開的分頁在視窗裡的位置；空字串＝目前沒有。
    private var ownTab = ""
    private var scratch = URL(fileURLWithPath: "/")

    public init(browser: SafariBrowser, sleeper: @escaping (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
                out: @escaping (String) -> Void, err: @escaping (String) -> Void,
                git: @escaping GitRunner = { LibraryStore.hardenedGit($0, in: $1) }) {
        self.browser = browser; self.sleeper = sleeper; self.out = out; self.err = err; self.git = git
    }

    /// 跑完整條流程，回結束碼。
    public func run(_ o: Options) -> Int32 {
        do {
            try execute(o)
            return 0
        } catch let stop as Stop {
            return stop.code
        } catch {
            err("✗ \(displaySafeErrorText(error))")
            return 1
        }
    }

    // MARK: 輸出與結束

    /// 一般的自動化失敗。它說明我們的分頁在哪裡，因為人在重試之前應該先看一眼：頁面若讀起來像起疑，即使腳本自己分不出來，那也是
    /// 結束碼 6 的領域。
    private func fail(_ message: String) -> Stop {
        err("✗ \(displaySafeInvisible(message, max: 600))")
        if !ownTab.isEmpty { err("  our tab (window \(window), tab \(ownTab)) is left open — look at it before retrying.") }
        return Stop(code: 1)
    }

    /// 中止條款。不重試、不換來源，分頁留著當證據。
    private func botStop(_ signal: String, _ site: String) -> Stop {
        err("✋ SITE SUSPECTS AUTOMATION (\(displaySafeInvisible(signal, max: 600))) on \(site.isEmpty ? "?" : displaySafeInvisible(site, max: 300)) — STOP THE WHOLE RUN.")
        err("  our tab was window \(window), tab \(ownTab.isEmpty ? "?" : ownTab); it is left open for you to look at")
        err("  (if tabs were closed meanwhile, its position may have shifted).")
        return Stop(code: 6)
    }

    private func nap(_ seconds: Double) { sleeper(seconds) }

    // MARK: Safari 輔助：一律走 `documents --json`，不讀人看的表格

    private struct Tab {
        var window: Int
        var tabInWindow: Int
        var url: String
        var title: String
        var profile: String?
        var isCurrent: Bool
    }

    private func docs() -> [Tab] {
        let r = browser.run(["documents", "--json"])
        guard let root = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)), let items = root as? [[String: Any]] else { return [] }
        return items.compactMap { d in
            guard let w = FulltextFetch.int(d["window"]), let t = FulltextFetch.int(d["tab_in_window"]) else { return nil }
            return Tab(window: w, tabInWindow: t, url: (d["url"] as? String) ?? "", title: (d["title"] as? String) ?? "",
                       profile: d["profile"] as? String, isCurrent: (d["is_current"] as? Bool) ?? false)
        }
    }

    private static func int(_ any: Any?) -> Int? {
        if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        return nil
    }

    private func tab(_ n: String) -> Tab? { docs().first { $0.window == window && String($0.tabInWindow) == n } }
    private func tabURL(_ n: String) -> String { tab(n)?.url ?? "" }
    private func tabTitle(_ n: String) -> String { tab(n)?.title ?? "" }
    private func currentTab() -> String { docs().first { $0.window == window && $0.isCurrent }.map { String($0.tabInWindow) } ?? "" }
    private func origin(_ url: String) -> String { URLSplit(url).origin }

    /// 開一個分頁，用**位置**記住是哪一個，之後只關它。用位置而不是 URL：使用者已開著同一頁時，URL 鎖會對到兩個分頁、
    /// safari-browser 會 fail-closed（2026-09-23 觀察）。
    private func openOwnTab(_ url: String) throws {
        let r = browser.run(["open", "--new-tab", "--window", String(window), url])
        if r.status != 0 { throw fail("open: \(r.stderr.trimmingTrailingNewlines())") }
        ownTab = currentTab()
        if ownTab.isEmpty { throw fail("cannot identify the tab just opened") }
    }

    /// 只在分頁還顯示我們開的那個站時才關。
    private func closeOwnTab(_ expectedOrigin: String) {
        let u = tabURL(ownTab)
        if !u.isEmpty, origin(u) == expectedOrigin {
            let r = browser.run(["close", "--window", String(window), "--tab-in-window", ownTab])
            if r.status == 0 {
                out("tab closed")
                ownTab = ""
            }
        } else {
            err("⚠ tab \(ownTab) no longer shows \(displaySafeInvisible(expectedOrigin, max: 300)) — left open, not closed (tabs may have moved)")
        }
    }

    /// 我們分頁的標題與前 3000 字。兩次嘗試；失敗被回報，絕不當成「頁面乾淨」。
    private func pageText() -> String? {
        for _ in 1...2 {
            let r = browser.run(["js", "--window", String(window), "--tab-in-window", ownTab,
                                 "return document.title + '\\n' + (document.body ? document.body.innerText.slice(0, 3000) : '')"])
            if r.status == 0 { return r.value }
            nap(2)
        }
        return nil
    }

    /// `site`：站的標籤；`pdfOK`：預期 Safari 的 PDF 檢視器（prime）——它不是可腳本的頁面，標題（不經 JS 讀）就是全部的檢查。
    private func botCheckPage(_ site: String, pdfOK: Bool = false) throws {
        let title = tabTitle(ownTab)
        if let text = pageText() {
            if let hit = BotSignals.detect(title + "\n" + text) { throw botStop(hit, site) }
            return
        }
        if let hit = BotSignals.detect(title) { throw botStop(hit, site) }
        // 其他地方「讀不到頁面」等於「無從檢查」，而那不等於「乾淨」
        if pdfOK { return }
        throw botStop("page-unreadable: could not check it for suspicion", site)
    }

    /// 每個進一步動作之前：我們的分頁必須還顯示文章的站。分頁在流程中途跑到別的站（驗證子網域、登入／SSO 頁）是中止條款，
    /// 不是自動化的小故障。
    private func siteGuard(_ site: String) throws {
        let u = tabURL(ownTab)
        if !u.isEmpty, origin(u) == site { return }
        let hit = BotSignals.detect(tabTitle(ownTab) + "\n" + u)
        throw botStop("\((hit ?? "site changed")) → \(u.isEmpty ? "<our tab is gone>" : u)", site)
    }

    // MARK: 流程

    private func execute(_ o: Options) throws {
        window = o.window
        var doi = o.doi ?? ""
        if doi.isEmpty { doi = FulltextFetch.doiFromLanding(o.landing) ?? "" }

        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-fulltext-\(UUID().uuidString)")
        // 0700：暫存目錄裡有下載來的第三方全文（舊 `mktemp -d` 是 0700；預設屬性會是 0755，R1 verify 第 50 則）
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }

        // --- 網址與檔案落在哪裡：在碰瀏覽器**之前**檢查 ---
        // 兩個網址都會在使用者已登入的 profile 裡開：只收 https（`file:`、`javascript:`、`http:` 一律拒絕，R1 verify 第 31 則）
        for (flag, value) in [("--landing", o.landing), ("--prime", o.prime ?? "")] where !value.isEmpty {
            guard value.lowercased().hasPrefix("https://") else {
                throw fail("\(flag) must be an https:// URL: \(displaySafeInvisible(value, max: 300))")
            }
        }
        let outURL = URL(fileURLWithPath: o.out)
        let outDirURL = outURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outDirURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw fail("--out directory does not exist: \(displaySafeInvisible(outDirURL.path, max: 400))")
        }
        let outDir = FulltextFetch.physicalPath(outDirURL.path)   // `pwd -P`：`resolvingSymlinksInPath` 會把 `/private/var` 縮成 `/var`，與 `pwd -P` 不同
        let outPath = outDir + "/" + outURL.lastPathComponent
        let stem = outPath.hasSuffix(".pdf") ? String(outPath.dropLast(4)) : outPath
        let unverified = stem + ".unverified.pdf"
        let response = stem + ".response.txt"
        // 三個目的地都得是「不存在或普通檔」：目錄、symlink、特殊檔具名拒絕。第一版對已存在的目的地「先 removeItem 再 moveItem」，
        // `--out` 指著非空目錄時遞迴刪掉整個目錄（R1 verify 第 1 則）
        for f in [outPath, unverified, response] {
            if case .other(let kind) = try OutputFile.inspect(f) {
                err("✗ refusing: \(displaySafeInvisible(f, max: 400)) already exists and is a \(displaySafeInvisible(kind, max: 40)), not a regular file — this command only writes regular files and never deletes a directory or follows a symlink.")
                throw Stop(code: 1)
            }
        }
        try outputGitGate(outDir: outDir, files: [outPath, unverified, response])

        // 視窗不存在，或它的分頁都沒有 profile 欄位：兩者對這支程式是同一件事——無從確認它屬於誰，不碰
        let profile = Set(docs().filter { $0.window == window }.compactMap(\.profile).filter { !$0.isEmpty }).sorted().joined(separator: ",")
        guard !profile.isEmpty else {
            err("✗ Safari window \(window) not found")
            throw Stop(code: 1)
        }
        out("window \(window) profile: \(displaySafeInvisible(profile, max: 200))")
        if let expected = o.expectProfile, !expected.isEmpty, profile != expected {
            err("✗ window \(window) belongs to profile '\(displaySafeInvisible(profile, max: 200))', not '\(displaySafeInvisible(expected, max: 200))' — refusing to touch it")
            throw Stop(code: 1)
        }

        if let prime = o.prime, !prime.isEmpty {
            try openOwnTab(prime); nap(12)
            let primeOrigin = origin(prime)
            let u = tabURL(ownTab)
            if u.isEmpty || origin(u) != primeOrigin { throw botStop("primed tab left the site → \(u.isEmpty ? "<gone>" : u)", primeOrigin) }
            try botCheckPage(primeOrigin, pdfOK: true)
            closeOwnTab(primeOrigin)
        }

        try openOwnTab(o.landing)
        let lock = ["--window", String(window), "--tab-in-window", ownTab]

        // 等頁面落定：越過 doi.org，DOM 越過 "loading"。插頁可以在文章頁取代它之前就回報 readyState=complete，所以真正的關卡是下一步
        // （PDF 連結出現），不是這一步。60 秒沒落定算「卡住的回應」——中止條款，不是重試。
        var final = ""
        for _ in 1...30 {
            nap(2)
            let u = tabURL(ownTab)
            if u.isEmpty || u.contains("://doi.org/") || u.contains("://dx.doi.org/") { continue }
            let rs = browser.run(["js"] + lock + ["return document.readyState"]).value
            if rs == "complete" || rs == "interactive" { final = u; break }
        }
        if final.isEmpty { throw botStop("page did not settle in 60 s (stalled) → \(tabURL(ownTab))", origin(o.landing)) }
        let site = origin(final)
        out("page: \(displaySafeInvisible(final, max: 600))")
        try botCheckPage(site)

        try writeScratch("haslink.js", FulltextFetch.hasLinkJS)
        try siteGuard(site)
        _ = browser.run(["wait"] + lock + ["--js", FulltextFetch.hasLinkJS.trimmingTrailingNewlines(), "--timeout", "45000"])
        try siteGuard(site)
        try botCheckPage(site)   // 插頁在我們等的時候可以變成挑戰頁

        let linkFile = try writeScratch("link.js", FulltextFetch.linkJS)
        try siteGuard(site)
        let linkRun = browser.run(["js"] + lock + ["--file", linkFile.path])
        if linkRun.status != 0 { throw fail("could not read the page's links: \(linkRun.stderr.trimmingTrailingNewlines())") }
        let link = linkRun.value
        var method = link.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let pageLink = link.contains(" ") ? String(link[link.index(after: link.firstIndex(of: " ")!)...]) : link
        let pdfURL: String
        if let rule = PdfUrlRules.pdfURL(finalURL: final, pageLink: pageLink), !rule.isEmpty {
            pdfURL = rule
            method = "GET"
        } else if !link.isEmpty, !pageLink.contains("/record/") {
            pdfURL = pageLink
            // 頁面自己的連結來自 DOM（`citation_pdf_url`、`a[href]`、表單的 `action`），下面的 fetch 帶 `credentials:'include'`：
            // 頁面說了算的目標若不是這個站，就會用使用者的 session 打到頁面選的位置（R1 verify 第 31 則）。規則檔（出版商網址規則）
            // 產生的網址不受此限——它們是本 repo 寫死的。拒絕不是中止條款（不是網站起疑，是頁面給了一個不能照做的連結）：結束碼 1，分頁留著。
            let target = FulltextFetch.fetchTargetOrigin(pdfURL, page: final)
            if target?.lowercased() != site.lowercased() {
                throw fail("the page's PDF link points off-site (\(displaySafeInvisible(target ?? "not an http(s) URL", max: 200)), page origin \(displaySafeInvisible(site, max: 200))): \(displaySafeInvisible(pdfURL, max: 400)) — refusing a credentialed fetch to a target the page chose")
            }
        } else {
            err("no PDF link on \(displaySafeInvisible(final, max: 600))")
            closeOwnTab(site)
            throw Stop(code: 3)
        }
        out("pdf:  \(displaySafeInvisible(method, max: 20)) \(displaySafeInvisible(pdfURL, max: 600))")

        let fetchFile = try writeScratch("fetch.js", FulltextFetch.fetchJS(url: pdfURL, method: method))
        try siteGuard(site)
        let start = browser.run(["js"] + lock + ["--file", fetchFile.path])
        if start.status != 0 { throw fail("fetch start: \(start.stderr.trimmingTrailingNewlines())") }
        let waited = browser.run(["wait"] + lock + ["--js", "window.__aff && window.__aff.done", "--timeout", "120000"])
        if waited.status != 0 {
            try siteGuard(site)
            throw botStop("fetch stalled: no answer in 120 s", site)
        }
        try siteGuard(site)
        let meta = browser.run(["js"] + lock + ["return JSON.stringify({s:window.__aff.status,c:window.__aff.ctype,l:window.__aff.len,e:window.__aff.err||null})"]).value
        out("response: \(meta.isEmpty ? "<unreadable>" : displaySafeInvisible(meta, max: 600))")
        guard let parsed = FulltextFetch.parseMeta(meta) else { throw botStop("response unreadable: could not check it", site) }
        // 拋錯的 fetch 通常是請求被轉到站外或被拒——與挑戰同一族。空本文是卡住的回應。
        if parsed.hadError { throw botStop("fetch error: \(meta)", site) }
        if parsed.length == 0 { throw botStop("empty response", site) }
        try siteGuard(site)
        let b64 = scratch.appendingPathComponent("b64").path
        let read = browser.run(["js"] + lock + ["--large", "--output", b64, "window.__aff.b64||''"])
        if read.status != 0 { throw fail("read: \(read.stderr.trimmingTrailingNewlines())") }
        let body = try decodeBase64File(b64)
        _ = browser.run(["js"] + lock + ["delete window.__aff; return 'ok'"])

        if !body.starts(with: Data("%PDF-".utf8)) {
            // 起疑優先：挑戰頁也是「不是 PDF」，不得被報成呼叫端可能重試的一般失敗
            if let hit = BotSignals.detect(String(decoding: body, as: UTF8.self), status: parsed.status) {
                throw botStop("\(hit) (fetch response)", site)
            }
            let saved = savedResponse(body, at: response)
            closeOwnTab(site)
            // PsycNet 無權限時對每篇文章回 200 與約 8 KB、寫著「Loading…」的 app 外殼（2026-09-23 觀察）：「無權限」，停這個站。
            if body.count < 20000, FulltextFetch.containsLoading(body) {
                err("no access: \(body.count)-byte shell from \(displaySafeInvisible(site, max: 300)) (\(saved))")
                throw Stop(code: 4)
            }
            let head = String(String(decoding: body.prefix(80), as: UTF8.self).unicodeScalars.filter { (0x20...0x7E).contains($0.value) })
            err("not a PDF (\(body.count) bytes, HTTP \(parsed.status); \(saved)): \(displaySafeInvisible(head, max: 120))")
            throw Stop(code: 2)
        }

        closeOwnTab(site)
        let staged = scratch.appendingPathComponent("out.pdf")
        try body.write(to: staged)
        if let title = o.title, !title.isEmpty {
            let (verdict, ok) = FulltextFetch.verdictJSON(path: staged.path, title: title, pages: o.pages, doi: doi)
            out("verify: \(verdict)")
            if !ok {
                try OutputFile.replace(path: unverified, with: body)
                err("kept as \(displaySafeInvisible(unverified, max: 400))")
                throw Stop(code: 5)
            }
        }
        try OutputFile.replace(path: outPath, with: body)
        out("OK \(body.count) bytes -> \(displaySafeInvisible(outPath, max: 400))")
    }

    // MARK: 輸出路徑的 git 閘

    /// 全文是第三方內容，不得落進沒有忽略它的 git 工作樹（`.claude/rules` 的隱私邊界）。**fail-closed**（R1 verify 第 8、10、28 則）：
    ///
    /// - 用檔案系統事實先問「輸出目錄的祖先有沒有 `.git`」（`LibraryStore.isInsideVersionedWorkTree`，不呼叫 git）。**沒有**＝不在任何
    ///   repo 裡，不需要 git 回答，直接放行。
    /// - **有**——之後每一步 git 答不出來都拒絕、說原因：`git` 執行不起來（`/usr/bin/git` 不在）、`rev-parse` 非零（`.git` 指向不存在
    ///   的 gitdir、`safe.directory` 的 dubious ownership 回 128、`.git` 壞了）、`rev-parse` 不是 `true`、`check-ignore` 是 0（已忽略）
    ///   與 1（沒忽略）以外的碼。第一版與舊 shell 一樣把「git 答不出來」讀成「不在工作樹」而放行——那是隱私閘，方向錯了。
    /// - git 一律走 `LibraryStore.hardenedGit`（#585 的同一支：絕對路徑、剝 `GIT_*`、`core.fsmonitor=false`、`core.attributesFile`），
    ///   所以 PATH 上的 shim 不能替 `check-ignore` 作答、目標 repo 的 `core.fsmonitor` 不會在閘裡執行。
    ///
    /// **範圍照實寫**：這道閘擋的是「輸出目錄的某個祖先有 `.git`、而那個 repo 沒有忽略這三個檔」。它不管 git 的環境變數之外的事：
    /// repo 自己的 `.gitattributes`、`info/attributes`、global config 裡被它點名的 filter driver 仍是 `hardenedGit` 記著的邊界。
    private func outputGitGate(outDir: String, files: [String]) throws {
        let dir = URL(fileURLWithPath: outDir)
        guard LibraryStore.isInsideVersionedWorkTree(dir) else { return }
        func refuse(_ why: String) -> Stop {
            err("✗ refusing: \(displaySafeInvisible(outDir, max: 400)) is inside a git working tree and \(why).")
            err("  Full text is third-party content. Write to a scratch directory outside git, then store it with akashic store-source.")
            return Stop(code: 1)
        }
        guard let inside = git(["rev-parse", "--is-inside-work-tree"], dir) else {
            throw refuse("git cannot be run, so it cannot be confirmed that the output files are ignored")
        }
        guard inside.status == 0, inside.out.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw refuse("git could not confirm the working tree (rev-parse exit \(inside.status))")   // display-safe-exempt: inside：status 是 Int32 結束碼
        }
        for f in files {
            guard let r = git(["check-ignore", "-q", "--", f], dir) else {
                throw refuse("git cannot be run, so it cannot be confirmed that \(displaySafeInvisible(f, max: 400)) is ignored")
            }
            switch r.status {
            case 0: continue
            case 1:
                let top = git(["rev-parse", "--show-toplevel"], dir).map { $0.out.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                err("✗ refusing: \(displaySafeInvisible(f, max: 400)) would land in the git working tree \(displaySafeInvisible(top, max: 400)), which does not ignore it.")
                err("  Full text is third-party content. Write to a scratch directory outside git, then store it with akashic store-source.")
                throw Stop(code: 1)
            default:
                throw refuse("git could not answer whether \(displaySafeInvisible(f, max: 400)) is ignored (check-ignore exit \(r.status))")   // display-safe-exempt: r：status 是 Int32 結束碼
            }
        }
    }

    /// 存不是 PDF 的回應本文給人看。存不成不改變結束碼（2／4 仍是那個意思），但不能說「saved」。
    private func savedResponse(_ body: Data, at path: String) -> String {
        do {
            try OutputFile.replace(path: path, with: body)
            return "saved as \(displaySafeInvisible(path, max: 400))"
        } catch {
            err("⚠ could not save the response body: \(displaySafeErrorText(error))")
            return "the body was NOT saved"
        }
    }

    /// `fetch(url)` 會打到哪個 origin：相對路徑落在頁面的 origin；`//host/…` 用頁面的 scheme；有 scheme 卻沒有主機
    /// （`javascript:`、`data:`、`blob:`）不是任何網站，回 nil。
    static func fetchTargetOrigin(_ url: String, page: String) -> String? {
        let parts = URLSplit(url)
        if parts.netloc.isEmpty { return parts.scheme.isEmpty ? URLSplit(page).origin : nil }
        let scheme = parts.scheme.isEmpty ? URLSplit(page).scheme : parts.scheme
        return "\(PyText.string(scheme))://\(PyText.string(parts.netloc))"
    }

    // MARK: 純函式（測試直接呼叫）

    /// `cd dir && pwd -P`：解開全部 symlink 的實體路徑（`realpath(3)`）。解不開時原樣回傳。
    static func physicalPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        return realpath(path, &buffer) != nil ? String(cString: buffer) : path
    }

    /// `--landing` 是 doi.org 網址時的 DOI：`${LANDING#*doi.org/}` 再去掉第一個 `?` 或 `#` 起的部分。只認這三個前綴、區分大小寫
    /// （舊實作是 bash 的 `case`）。
    static func doiFromLanding(_ landing: String) -> String? {
        guard ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/"].contains(where: landing.hasPrefix),
              let r = landing.range(of: "doi.org/") else { return nil }
        var doi = String(landing[r.upperBound...])
        if let cut = doi.firstIndex(where: { $0 == "?" || $0 == "#" }) { doi = String(doi[..<cut]) }
        return doi
    }

    /// `JSON.stringify({s,c,l,e})` 的回傳。解析失敗（空、不是 JSON、不是物件）回 nil＝「讀不到」。
    struct Meta { var status: Int; var length: Int; var hadError: Bool }

    static func parseMeta(_ text: String) -> Meta? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [])) as? [String: Any] else { return nil }
        func number(_ any: Any?) -> Int {
            if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
            if let s = any as? String, let v = Int(s) { return v }
            return 0
        }
        func truthy(_ any: Any?) -> Bool {
            switch any {
            case nil, is NSNull: return false
            case let b as Bool: return b
            case let n as NSNumber: return n.doubleValue != 0
            case let s as String: return !s.isEmpty
            case let a as [Any]: return !a.isEmpty
            case let d as [String: Any]: return !d.isEmpty
            default: return true
            }
        }
        return Meta(status: number(obj["s"]), length: number(obj["l"]), hadError: truthy(obj["e"]))
    }

    /// `grep -qi loading`（位元組層、不分大小寫的 ASCII）。
    static func containsLoading(_ data: Data) -> Bool {
        let needle = Array("loading".utf8)
        let bytes = Array(data)
        guard bytes.count >= needle.count else { return false }
        for i in 0...(bytes.count - needle.count) {
            var match = true
            for k in 0..<needle.count {
                var b = bytes[i + k]
                if b >= 0x41, b <= 0x5A { b += 0x20 }
                if b != needle[k] { match = false; break }
            }
            if match { return true }
        }
        return false
    }

    /// 驗證步驟：回（判定 JSON 一行，是否通過）。讀不到 PDF 或外部工具失敗時判定是 `{"error": …, "is_article": false}`。
    public static func verdictJSON(path: String, title: String, pages: String?, doi: String) -> (String, Bool) {
        do {
            let content = try PDFReader.read(path: path)
            let meta = try PDFReader.metadataDOI(path: path)
            let a = FulltextVerify.assess(firstPage: content.firstPages, pageCount: content.pageCount, title: title,
                                          pages: pages?.isEmpty == false ? pages : nil, doi: doi.isEmpty ? nil : doi, metaDOI: meta)
            return (a.json.dumps(), a.isArticle)
        } catch {
            return (PyJSON.object([("error", .string(displaySafeErrorText(error))), ("is_article", .bool(false))]).dumps(), false)
        }
    }

    private func decodeBase64File(_ path: String) throws -> Data {
        guard let raw = FileManager.default.contents(atPath: path) else { throw fail("read: no output file") }
        // 舊實作的 `base64 -D` 容忍任意位置的換行；`Data(base64Encoded:)` 預設不容忍（R1 verify 第 37 則）。只拿掉換行與頭尾空白、其餘照嚴格解碼：
        // 不用 `.ignoreUnknownCharacters`（它會把任何非 base64 字元靜默丟掉，一段錯誤頁文字會「解」成垃圾位元組而不是明確失敗）
        var bytes = Array(raw).filter { $0 != 0x0A && $0 != 0x0D }
        while let f = bytes.first, f == 0x20 { bytes.removeFirst() }
        while let l = bytes.last, l == 0x20 { bytes.removeLast() }
        guard let decoded = Data(base64Encoded: Data(bytes)) else { throw fail("base64 decode failed") }
        return decoded
    }

    @discardableResult
    private func writeScratch(_ name: String, _ content: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    /// 頁面上有沒有 PDF 連結（`wait --js` 的條件）。
    static let hasLinkJS = """
    !!(document.querySelector('meta[name=citation_pdf_url]')
      || document.querySelector('a[href*="/doi/pdf/"],a[href*="pdfdirect"],a[href$=".pdf"],a[href*=".pdf?"],a[href^="/record/"]')
      || document.querySelector('form.ft-download-content__form--pdf'))

    """

    /// 讀頁面的 PDF 連結：表單（POST）、`citation_pdf_url` 中繼標籤、或幾種連結樣式（GET）。
    static let linkJS = """
    const f = document.querySelector('form.ft-download-content__form--pdf');
    if (f) return 'POST ' + f.action;
    const m = document.querySelector('meta[name=citation_pdf_url]');
    if (m && m.content) return 'GET ' + m.content;
    for (const s of ['a[href*="/doi/pdf/"]','a[href*="pdfdirect"]','a[href$=".pdf"]','a[href*=".pdf?"]','a[href^="/record/"]']) {
      const a = document.querySelector(s); if (a) return 'GET ' + a.href;
    }
    return '';

    """

    /// 頁內取 PDF 的 JS。`url` 以 JS 字串字面值（ASCII 逃脫）寫入，不做字串拼接式的內插。
    static func fetchJS(url: String, method: String) -> String {
        let body = method == "POST" ? "new FormData(document.querySelector('form.ft-download-content__form--pdf'))" : "undefined"
        return """

        window.__aff = {done:false};
        fetch(\(PyJSON.javaScriptLiteral(url)), {method:\(PyJSON.javaScriptLiteral(method)), credentials:'include', body:\(body)})
         .then(r => { window.__aff.status = r.status; window.__aff.ctype = r.headers.get('content-type'); return r.arrayBuffer(); })
         .then(b => { const u = new Uint8Array(b); let s = '';
           for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
           window.__aff.b64 = btoa(s); window.__aff.len = u.length; window.__aff.done = true; })
         .catch(e => { window.__aff.err = String(e); window.__aff.done = true; });
        return 'started';

        """
    }
}
