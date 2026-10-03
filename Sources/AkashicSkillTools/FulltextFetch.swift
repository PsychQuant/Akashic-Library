import Foundation
import AkashicCore
import AkashicStoreIO

/// 在使用者自己的 Safari 裡，把一篇 work 從 DOI 走到頁面自己的 PDF 連結，然後**交給人**（#613；#629 由 `fetch-fulltext.sh` 移植）。
///
/// # 最高原則：跟真人一樣（使用者 2026-09-28）
///
/// 每一個對網站的動作都要是真人也會做的動作；下面的規則都是它的展開，衝突時以它為準。2026-09-28 一晚三次 CAPTCHA，每一次都緊跟在
/// 一個真人不會做的動作之後（頁內以 JS fetch PDF 端點、PDF 已顯示又對同一個簽章網址多送一次請求、導航前先以 curl 打了網站）。所以：
///
/// - **只用瀏覽器導航**：開 `--landing`、等頁面落定、讀頁面**自己的** PDF 連結、把同一個分頁導過去。**不在頁內以 JS 取檔**（`fetch()`
///   帶 `Sec-Fetch-Mode: cors`，看得出來），不用任何 HTTP 客戶端，**不自己拼出版商的 PDF 網址**（#613 起刪掉 SAGE `?download=true`、
///   Wiley `pdfdirect`、PsycNet `/fulltext/<id>.pdf` 三條規則與 `url-rule` 子命令）。
/// - **不取位元組、不寫任何輸出檔**：PDF 顯示出來之後就交給人（結束碼 7）。人存檔之後交給 `fulltext take`（不碰瀏覽器、不連網）。
///   **不重抓已載入的檔**——不對顯示中的 PDF 再發請求。
/// - **按鈕與驗證交給人**：頁面的下載是表單按鈕、連結通到 HTML 閱讀器、出現 CAPTCHA，都停下來交給使用者。
/// - **每站每天 10 次嘗試**（`FulltextAttemptLedger`）：準備導航到 PDF（或把按鈕交給人）就記一次；到上限就停那個站（結束碼 9）。
/// - **頁面上執行的 JS 少而且正確**：每一段都寫成**運算式**。`safari-browser js` 先把程式碼包成運算式試一次、解析失敗才退回函式本體
///   （它的 `JSWrapper`），所以寫成 `return …` 的敘述，第一次注入就是一段解析不了的程式碼。頁面的錯誤處理器看不看得到 `do JavaScript`
///   的解析錯誤沒有實測；2026-09-28 NVA 的 Matomo 記錄了 agent 的 SyntaxError，是使用者訂這一條的理由。`FulltextJavaScriptTests` 用
///   JavaScriptCore 照那個包法驗每一段都能當運算式解析。
///
/// # 結束碼是它對 agent 的契約
///
///     7 交給人：分頁已導到頁面自己的 PDF 連結（或該按的按鈕已找到），這個命令沒有取位元組、沒有寫檔。分頁留著。**批次繼續**：
///       這一筆交給人，不是整批停。原因（`handover:` 一行）：`pdf-shown`（含另一個主機上顯示的 PDF）、`html-page`、`unverifiable`、
///       `tab-unchanged`、`button`，以及 2026-10-02 加的 `left-site`（導航之後分頁到了別的主機、沒有任何驗證／封鎖／登入的標記）
///       與 `doi-not-resolved`（DOI 解不開，停在 doi.org 自己的頁面）。
///     8 等人驗證：出現 CAPTCHA／人類檢查／Cloudflare「Just a moment」／按住驗證，**而且在文章站本身或已知的驗證服務上**
///       （`BotSignals.isKnownVerificationService`；其他主機上的驗證字樣是結束碼 6）。暫停這一篇；使用者驗證完，以
///       `--resume-tab`／`--resume-origin`（導航之後的驗證另帶 `--resume-stage followed`）在**同一個分頁**接著走（不重新載入）。分頁留著。
///     9 這個站今天已經 10 次嘗試（Asia/Taipei）：停這個站，隔天再跑。沒有導航到 PDF。
///     6 **整批暫停**（SKILL.md〈中止條款〉）：其他起疑訊號——封鎖頁、HTTP 403／429、異常流量、PMC 的下載前驗證頁、ScienceDirect
///       的「Preparing your download」、其他主機上的驗證字樣、分頁跑到別的網站而那一頁是登入／驗證頁的長相、卡住、讀不到頁面而無從
///       檢查。分頁留著給使用者看。
///     3 頁面上找不到 PDF 連結（我們的分頁關掉）
///     1 自動化失敗（見 stderr）；或頁面給的 PDF 連結不是同站的絕對 https 網址（`points off-site`）；或帳本讀不懂
///
/// **沒有結束碼 0**：這個命令的正常終點就是交給人。先前的 0（「取得並驗證」）、2（回應不是 PDF）、4（無權限的登入殼）、5（驗證不過）
/// 都跟著取位元組一起離開這個命令——2 與 5 在 `take`，4 由看分頁的人判斷。舊的呼叫端把 0 當成「檔案存好了」，新的碼不會被它讀錯。
///
/// # 鎖分頁
///
/// 仍是 `--window N` 加它自己開的分頁位置（`--tab-in-window`，#613 的作法：使用者已開著同一頁時 URL 鎖會對到兩個分頁、
/// safari-browser fail-closed），**不是** `web-access-via-safari-browser.md` 的 `--profile`＋`--url-endswith`；規則檔〈例外〉形狀 (b) 的
/// grandfathered 項目。`--resume-tab` 沿用同一種鎖，另外要求那個分頁此刻顯示：導航之前的接續（`article`）是 `--resume-origin`；
/// 導航之後的接續（`followed`）是 `--resume-origin`、已知的驗證服務、或 PDF（只讀 `document.contentType` 判斷，不讀頁面文字）——
/// 使用者驗證時把視窗拉到前面，視窗編號會變；對不上就停（結束碼 1），不猜是哪一個分頁。**`--resume-origin` 是呼叫端給的**：接續時
/// 「文章站」就是它，主機的判斷信任這個參數。
///
/// **仍沒有的**：沒對真的 `safari-browser` 跑過（只對記憶體內的假瀏覽器）；Safari 的 PDF 檢視器能不能執行頁面 JS、`document.contentType`
/// 在那裡回什麼、`PerformanceNavigationTiming.responseStatus` 在 Safari 有沒有值，都沒有實測——讀不到時照「無從檢查」處理（交給人或暫停），
/// 不當成乾淨。
public final class FulltextFetch {
    public struct Options {
        public var window: Int
        public var landing: String
        /// 每日嘗試帳本的路徑（`FulltextAttemptLedger.defaultPath()`；測試指到暫存目錄）。
        public var ledger: String
        public var expectProfile: String?
        /// 等人驗證之後在同一個分頁接著走：分頁位置與它此刻必須顯示的 origin。兩個一起給。
        public var resumeTab: Int?
        public var resumeOrigin: String?
        /// 等人驗證發生在哪一步（結束碼 8 印出的 `--resume-stage`；沒印就是 `article`）。
        public var resumeStage: ResumeStage
        public init(window: Int, landing: String, ledger: String, expectProfile: String? = nil,
                    resumeTab: Int? = nil, resumeOrigin: String? = nil, resumeStage: ResumeStage = .article) {
            self.window = window; self.landing = landing; self.ledger = ledger; self.expectProfile = expectProfile
            self.resumeTab = resumeTab; self.resumeOrigin = resumeOrigin; self.resumeStage = resumeStage
        }
    }

    /// 等人驗證發生在哪一步（#613 修正輪，使用者 2026-10-02）。驗證完之後接著走**同一步**，不是回到文章頁重來。
    public enum ResumeStage: String {
        /// 導航到 PDF 連結**之前**（文章頁上的驗證）：接著讀頁面的連結、記一次嘗試、導過去
        case article
        /// 導航到 PDF 連結**之後**（嘗試已經記過、已經導航過）：回到「分頁顯示什麼」的判斷——PDF → 交給人，HTML 閱讀器 → 交給人；
        /// 不再讀連結、不再導航、不再記嘗試。分頁此刻可以在別的主機（PDF 放在另一個主機）；這一步只讀、不導航、不關分頁
        case followed
    }

    /// 新的三個結束碼（#613）。其餘沿用：1、3、6。
    public enum Code {
        public static let handedOver: Int32 = 7
        public static let humanVerification: Int32 = 8
        public static let dailyCapReached: Int32 = 9
    }

    /// 交給人的原因（結束碼 7；stdout 的 `handover:` 一行印它的 `rawValue`）。
    public enum Handover: String {
        /// 分頁顯示 PDF（`document.contentType` 含 pdf）
        case pdfShown = "pdf-shown"
        /// 頁面自己的 PDF 連結通到 HTML 頁（閱讀器、登入頁、無權限的外殼）
        case htmlPage = "html-page"
        /// 讀不到分頁（Safari 的 PDF 檢視器不能跑頁面 JS，或頁面拒絕）；標題沒有起疑訊號
        case unverifiable = "unverifiable"
        /// 導航之後分頁沒有離開文章頁（連結可能直接觸發下載）
        case tabUnchanged = "tab-unchanged"
        /// 頁面的 PDF 下載是表單按鈕（Annual Reviews 型）
        case button = "button"
        /// 分頁到了別的主機（跨主機的中繼頁、CDN 的檔案主機），而且沒有任何驗證／封鎖／登入的標記；那裡顯示的是 PDF 時是 `pdf-shown`
        /// （使用者 2026-10-02）。這一筆交給人，批次繼續
        case leftSite = "left-site"
        /// DOI 解不開：分頁停在 doi.org 自己的頁面（查無此 DOI）。這是資料問題，不是起疑訊號
        case doiNotResolved = "doi-not-resolved"
    }

    /// 以某個結束碼結束（訊息已經印出）。
    struct Stop: Error { let code: Int32 }

    private let browser: SafariBrowser
    private let sleeper: (Double) -> Void
    private let now: () -> Date
    private let out: (String) -> Void
    private let err: (String) -> Void

    private var window = 0
    /// 我們的分頁在視窗裡的位置；空字串＝目前沒有。
    private var ownTab = ""
    private var landing = ""
    /// 目前走到哪一步；等人驗證時印進 `--resume-stage`（導航到 PDF 連結之後是 `followed`）。
    private var stage: ResumeStage = .article

    public init(browser: SafariBrowser, sleeper: @escaping (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
                now: @escaping () -> Date = Date.init,
                out: @escaping (String) -> Void, err: @escaping (String) -> Void) {
        self.browser = browser; self.sleeper = sleeper; self.now = now; self.out = out; self.err = err
    }

    /// 跑完整條流程，回結束碼。
    public func run(_ o: Options) -> Int32 {
        do {
            try execute(o)
            // 每一條終點都以 Stop 帶著結束碼離開；正常返回是程式錯誤，不能被讀成任何一種成功
            err("✗ internal: the flow ended without an exit code")
            return 1
        } catch let stop as Stop {
            return stop.code
        } catch {
            err("✗ \(displaySafeErrorText(error))")
            return 1
        }
    }

    // MARK: 輸出與結束

    /// 一般的自動化失敗。它說明我們的分頁在哪裡，因為人在重試之前應該先看一眼：頁面若讀起來像起疑，即使程式自己分不出來，那也是
    /// 結束碼 6 的領域。
    private func fail(_ message: String) -> Stop {
        err("✗ \(displaySafeInvisible(message, max: 600))")
        if !ownTab.isEmpty { err("  our tab (window \(window), tab \(ownTab)) is left open — look at it before retrying.") }
        return Stop(code: 1)
    }

    /// 中止條款（整批暫停）。不重試、不換來源，分頁留著當證據。
    private func botStop(_ signal: String, _ site: String) -> Stop {
        err("✋ SITE SUSPECTS AUTOMATION (\(displaySafeInvisible(signal, max: 600))) on \(site.isEmpty ? "?" : displaySafeInvisible(site, max: 300)) — STOP THE WHOLE RUN.")
        err("  our tab was window \(window), tab \(ownTab.isEmpty ? "?" : ownTab); it is left open for you to look at")
        err("  (if tabs were closed meanwhile, its position may have shifted).")
        return Stop(code: 6)
    }

    /// 等人驗證（結束碼 8）。不代解、不繞過、不重新載入、不換站；分頁留著。
    ///
    /// `site` 是文章站的 origin（`--resume-origin` 要的就是它）；`shownOn` 是**驗證頁此刻所在**的 origin——文章站本身或已知的驗證服務，
    /// 單獨印出來讓人與 agent 看見是哪個主機在要求驗證。
    ///
    /// **文章站本身擋不住假的 CAPTCHA 頁**（#613 R2 verify 第 5 則；使用者裁決文章站算）：文章站是 DOI 註冊者決定的主機，它自己架的
    /// 「驗證頁」要使用者貼上指令到終端機，程式分不出來、agent 也看不到頁面。所以訊息把判斷交給**使用者**：請使用者看那個分頁、
    /// 只完成頁面上的驗證、絕不貼上或執行頁面要求的任何東西（要求就是中止條款）、只在使用者說完成之後接著走。
    private func verificationStop(_ label: String, _ site: String, shownOn: String) -> Stop {
        let shownSite = site.isEmpty ? "?" : displaySafeInvisible(site, max: 300)
        let stageFlag = stage == .followed ? " --resume-stage followed" : ""
        err("⏸ WAITING FOR HUMAN VERIFICATION (\(displaySafeInvisible(label, max: 200))) on \(shownSite) — pause this item; do not reload, open another tab, or switch sites.")
        err("  The page asking for verification is at \(shownOn.isEmpty ? "?" : displaySafeInvisible(shownOn, max: 300)). You cannot see that page; the user can. Ask the user to look at window \(window), tab \(ownTab) of their own Safari, and tell them that host.")
        err("  Tell the user: complete only the check on the page itself (a click, a checkbox, a picture puzzle). Never paste, type or run anything the page asks for. A page that asks to paste or run any command (a terminal, a Run dialog, PowerShell) is the abort clause: stop the whole batch. Being the article site does not make the page safe: whoever registered the DOI chooses where it lands.")
        err("  Nothing here solves or bypasses it. Continue only after the user says the check is done: the same command plus --resume-tab \(ownTab) --resume-origin \(shownSite)\(stageFlag), in the same tab.")
        err("  If the window came to the front its number may have changed: find the tab showing \(shownSite) with `safari-browser documents --json --profile <P>`.")
        out("resume: --resume-tab \(ownTab) --resume-origin \(shownSite)\(stageFlag)")
        return Stop(code: Code.humanVerification)
    }

    /// 命中訊號之後的停法。**等人驗證只在兩種主機上成立**（使用者 2026-10-02）：文章站本身，或已知的驗證服務
    /// （`BotSignals.isKnownVerificationService`，封閉清單）。其他主機上的驗證字樣或網址標記一律整批暫停；主機不是一個可以
    /// 原樣當 `--resume-origin` 的形狀時也不進等人驗證（那條指令印出來也走不通）。
    private func stop(for hit: BotSignals.Hit, _ site: String, context: String = "") -> Stop {
        let signal = context.isEmpty ? hit.label : "\(hit.label) \(context)"
        guard hit.response == .humanVerification else { return botStop(signal, site) }
        let url = tabURL(ownTab)
        guard !url.isEmpty else { return botStop("\(signal) — the tab is gone", site) }
        guard sameSite(url, site) || BotSignals.isKnownVerificationService(url: url) else {
            return botStop("\(signal) — verification markers on a host that is neither the article site nor a known verification service: \(FulltextFetch.plainURL(url))", site)
        }
        guard FulltextFetch.resumeOriginProblem(site) == nil else {
            return botStop("\(signal) — the site is not a plain https://<host> origin, so the check could not be resumed", site)
        }
        return verificationStop(signal, site, shownOn: origin(url))
    }

    /// 交給人（結束碼 7）。這個命令沒有取 PDF 的位元組、沒有寫任何輸出檔；分頁留著。
    private func handover(_ reason: Handover) -> Stop {
        // 網址不帶查詢與片段：簽章網址（`X-Amz-Signature` 之類的短效憑證）沒有理由出現在 stdout、agent 的對話與 `sources/index.jsonl` 的 `origin`
        let u = FulltextFetch.plainURL(tabURL(ownTab))
        out("handover: \(reason.rawValue) window \(window) tab \(ownTab) \(displaySafeInvisible(u, max: 1000))")
        err("✋ HANDED OVER TO YOU (\(reason.rawValue)) — window \(window), tab \(ownTab).")
        switch reason {
        case .pdfShown:
            err("  The tab shows the PDF. Save it yourself (which Safari control is the standard one is being settled in safari-browser#210).")
        case .htmlPage:
            err("  The page's own PDF link opened an HTML page — a reader, a login page, or an access shell. If it has a download button, press it yourself; if it says there is no access, report that.")
        case .unverifiable:
            err("  This command could not read the tab (Safari's PDF viewer may not run page scripts). Look at it: save the PDF if it shows one; a challenge or block page is the abort clause.")
        case .tabUnchanged:
            err("  The tab did not leave the article page after following the PDF link — the link may have started a download (check Safari's downloads) or needs a click.")
        case .button:
            err("  The page's PDF download is a form button. Press it yourself; the site may download the file.")
        case .leftSite:
            err("  The tab left the article site for \(displaySafeInvisible(origin(tabURL(ownTab)), max: 300)); the page finished loading and matched none of the closed lists of verification, block or login markers — that does not mean it is not one. Look at it: if it shows the PDF, save it; a login, verification or block page is the abort clause. This item is handed to you; the rest of the batch can go on once you have looked at it.")
        case .doiNotResolved:
            err("  doi.org did not resolve this DOI (the tab stayed on doi.org's own not-found page). Check the DOI in the record; there is no file to save. This item is handed to you — the rest of the batch can go on.")
        }
        // DOI 解不開時沒有任何檔可存：不叫人把「存下的檔」交給 take（R2 verify 第 14 則）
        if reason != .doiNotResolved { err("  Then pass the saved file to `akashic fulltext take --from <file> --out <path> --title … --doi …`.") }
        err("  Nothing requested the PDF bytes and no file was written. The tab is left open.")
        return Stop(code: Code.handedOver)
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
    /// 分頁的網址是不是還在這個 origin（主機不分大小寫）。
    private func sameSite(_ url: String, _ site: String) -> Bool { origin(url).lowercased() == site.lowercased() }
    private var lock: [String] { ["--window", String(window), "--tab-in-window", ownTab] }

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
        if !u.isEmpty, sameSite(u, expectedOrigin) {
            let r = browser.run(["close", "--window", String(window), "--tab-in-window", ownTab])
            if r.status == 0 {
                out("tab closed")
                ownTab = ""
            }
        } else {
            err("⚠ tab \(ownTab) no longer shows \(displaySafeInvisible(expectedOrigin, max: 300)) — left open, not closed (tabs may have moved)")
        }
    }

    /// 我們分頁的（HTTP 狀態碼，標題與前 3000 字）。兩次嘗試；失敗回 nil，絕不當成「頁面乾淨」。狀態碼取自頁面自己的
    /// `PerformanceNavigationTiming.responseStatus`（已載入的資料，不發請求）；瀏覽器沒有這個值時是 nil。
    private func pageText() -> (status: Int?, text: String)? {
        for _ in 1...2 {
            let r = browser.run(["js"] + lock + [FulltextFetch.pageTextJS])
            if r.status == 0 {
                let value = r.value
                let firstLine = value.prefix { $0 != "\n" }
                let rest = value.dropFirst(firstLine.count).drop { $0 == "\n" }
                return (Int(firstLine), String(rest))
            }
            nap(2)
        }
        return nil
    }

    /// 我們的分頁有沒有起疑訊號。等人驗證的訊號 → 結束碼 8；其他 → 6；讀不到頁面 → 6（無從檢查不等於乾淨）。
    private func botCheckPage(_ site: String) throws {
        let title = tabTitle(ownTab)
        if let page = pageText() {
            if let hit = BotSignals.classify(title + "\n" + page.text, status: page.status) { throw stop(for: hit, site) }
            return
        }
        if let hit = BotSignals.classify(title) { throw stop(for: hit, site) }
        throw botStop("page-unreadable: could not check it for suspicion", site)
    }

    /// 每個進一步動作之前：我們的分頁必須還顯示文章的站。分頁離開了文章站（使用者 2026-10-02），照 `leftSite` 判；分頁在等它落定的
    /// 時候回到文章站就照常往下走。
    private func siteGuard(_ site: String) throws {
        let u = tabURL(ownTab)
        if !u.isEmpty, sameSite(u, site) { return }
        guard !u.isEmpty else { throw botStop("site changed → <our tab is gone>", site) }
        if let stop = try leftSite(from: site) { throw stop }
    }

    /// 分頁離開了文章站。順序（#613 R2 verify 第 0、1、2、3、6、7、8、10 則）：
    /// 1. **先問 PDF**（`document.contentType`，由回應決定、不是頁面文字）→ 交給人（`pdf-shown`）。Safari 的 PDF 分頁標題通常就是文章標題，
    ///    先前標題與網址的長相排在前面，`Research design in …` 這種標題讓 PDF 變成整批暫停。
    /// 2. 不是 PDF 的頁面**要等它落定**（readyState 是 complete／interactive，與文章站上的 `decideShown` 同樣最多 30 次）：還在載入的頁面
    ///    說不出「沒有標記」。一直沒落定 → 卡住，整批暫停。等的時候分頁又換了網址就重新看（換到登入頁就判登入頁；回到文章站就照常往下走）。
    /// 3. 落定之後，**標題、網址、頁面文字與 HTTP 狀態一起**判起疑訊號（`classify`）：429 一律整批暫停，所以已知驗證服務上的 429 頁不會進
    ///    等人驗證；等人驗證只在已知的驗證服務上成立，其他主機一律整批暫停。
    /// 4. 登入／驗證頁的長相（`BotSignals.gateLook`：網址的主機與整段路徑、標題的整字片語）→ 整批暫停。
    /// 5. 其他（CDN 的檔案主機、跨主機的中繼頁）→ 這一筆交給人（`left-site`），批次繼續。沒命中封閉清單不代表不是登入頁，訊息照說。
    ///
    /// 頁面 JS 連三次讀不到（Safari 的 PDF 檢視器可能不跑頁面 JS）：只剩標題與網址——訊號、登入頁長相照判，沒有就交給人看（`unverifiable`）。
    /// 回 nil＝分頁在等的時候回到了文章站。
    private func leftSite(from site: String) throws -> Stop? {
        var unreadable = 0
        for _ in 1...30 {
            let before = tabURL(ownTab)
            let shown = browser.run(["js"] + lock + [FulltextFetch.shownJS])
            let url = tabURL(ownTab)
            if url.isEmpty { return botStop("site changed → <our tab is gone>", site) }
            if sameSite(url, site) { return nil }
            if url == before {   // 看的這一下分頁沒有換頁：這個回答屬於這個網址
                if shown.status == 0, FulltextFetch.contentTypeIsPDF(shown.value) { return handover(.pdfShown) }
                if shown.status != 0 || FulltextFetch.isUnreadableShown(shown.value) {
                    unreadable += 1
                    if unreadable >= 3 { return offSiteUnreadable(url, site) }
                } else if FulltextFetch.isSettled(shown.value) {
                    return offSiteSettled(url, site)
                }
            }
            nap(2)
        }
        return botStop("the tab left the article site and the page did not settle (stalled) → \(FulltextFetch.plainURL(tabURL(ownTab)))", site)
    }

    /// 別的主機上的頁面落定了：標題、網址、頁面文字與狀態碼一起判訊號，再看登入／驗證頁的長相，都沒有就交給人。
    private func offSiteSettled(_ url: String, _ site: String) -> Stop {
        let title = tabTitle(ownTab)
        let moved = "→ \(FulltextFetch.plainURL(url))"
        guard let page = pageText() else {
            // 讀不到頁面文字：狀態碼也不知道，只剩標題與網址
            if let hit = BotSignals.classify(title + "\n" + url) { return stop(for: hit, site, context: moved) }
            return botStop("page-unreadable \(moved): could not check it for suspicion", site)
        }
        if let hit = BotSignals.classify(title + "\n" + url + "\n" + page.text, status: page.status) { return stop(for: hit, site, context: moved) }
        if let gate = BotSignals.gateLook(url: url, title: title) { return botStop("site changed \(moved) (\(gate) page)", site) }
        return handover(.leftSite)
    }

    /// 別的主機上的分頁讀不到（頁面 JS 跑不起來）：只剩標題與網址。
    private func offSiteUnreadable(_ url: String, _ site: String) -> Stop {
        let title = tabTitle(ownTab)
        let moved = "→ \(FulltextFetch.plainURL(url))"
        if let hit = BotSignals.classify(title + "\n" + url) { return stop(for: hit, site, context: moved) }
        if let gate = BotSignals.gateLook(url: url, title: title) { return botStop("site changed \(moved) (\(gate) page)", site) }
        return handover(.unverifiable)
    }

    // MARK: 流程

    private func execute(_ o: Options) throws {
        window = o.window
        landing = o.landing

        // --- 網址、帳本、視窗：在開任何分頁之前檢查 ---
        // `--landing` 在使用者已登入的 profile 裡開：只收 https，主機要**長得像**公開的網域名稱（字面的形狀檢查，不解析 DNS）
        if let why = FulltextFetch.landingShapeProblem(o.landing) {
            throw fail("--landing must be an https:// URL whose host looks like a plain DNS name (\(why)): \(o.landing)")
        }
        if (o.resumeTab == nil) != (o.resumeOrigin == nil) {
            throw fail("--resume-tab and --resume-origin go together")
        }
        if let origin = o.resumeOrigin, let why = FulltextFetch.resumeOriginProblem(origin) {
            throw fail("--resume-origin must be https://<host> exactly (\(why)): \(origin)")
        }
        let ledger = FulltextAttemptLedger(path: o.ledger)
        do { _ = try ledger.load() } catch { throw fail("\(displaySafeErrorText(error))") }   // 數不出今天的次數，就不能保證沒超過上限

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

        if let resumeTab = o.resumeTab, let resumeOrigin = o.resumeOrigin {
            try resume(tab: resumeTab, origin: resumeOrigin, stage: o.resumeStage, ledger: ledger)
            return
        }
        try openOwnTab(o.landing)
        let landed = try settleLanding()
        try botCheckPage(landed.site)
        // 落地頁的網址是登入／驗證頁的長相（EZproxy、SAML、IdP 把 DOI 帶在查詢字串裡的那一種）：登入頁維持整批暫停（使用者 2026-10-02）。
        // 只看網址：落地頁的標題是文章標題，標題片語在這裡只會誤判。訊號先判（文章站上的 CAPTCHA 是等人驗證），長相後判
        if let gate = BotSignals.urlGateLook(landed.url) {
            throw botStop("the DOI landed on a page with the look of a \(gate) page → \(FulltextFetch.plainURL(landed.url)) (\(gate) page)", landed.site)
        }
        try followThePagesOwnLink(site: landed.site, ledger: ledger)
    }

    /// 等頁面落定：越過 doi.org，DOM 越過 "loading"。插頁可以在文章頁取代它之前就回報 readyState=complete，所以真正的關卡是下一步
    /// （PDF 連結出現），不是這一步。60 秒沒落定算「卡住的回應」——中止條款，不是重試。回（文章站的 origin，落地頁的網址）。
    ///
    /// 「還在 doi.org」看的是**主機**（`isDOIResolver`），不是網址字串裡有沒有 `://doi.org/`（#613 R2 verify 第 9、20 則：把 DOI 帶在查詢
    /// 字串裡的登入頁、或任何網址裡提到 doi.org 的頁面，都被當成 doi.org）。
    private func settleLanding() throws -> (site: String, url: String) {
        var final = ""
        for _ in 1...30 {
            nap(2)
            let u = tabURL(ownTab)
            if u.isEmpty || FulltextFetch.isDOIResolver(u) { continue }
            let rs = browser.run(["js"] + lock + [FulltextFetch.readyStateJS]).value
            if rs == "complete" || rs == "interactive" { final = u; break }
        }
        if final.isEmpty {
            let u = tabURL(ownTab)
            if FulltextFetch.isDOIResolver(u) { try stillOnTheDOIResolver(u) }
            throw botStop("page did not settle in 60 s (stalled) → \(FulltextFetch.plainURL(u))", origin(landing))
        }
        out("page: \(displaySafeInvisible(FulltextFetch.plainURL(final), max: 600))")
        return (origin(final), final)
    }

    /// 60 秒之後分頁還在 doi.org。DOI 解不開時 doi.org 留在自己的「查無」頁——那是記錄的資料問題，不是起疑訊號（使用者 2026-10-02）：
    /// 這一筆交給人（`doi-not-resolved`），批次繼續。但只在**看得到 doi.org 自己的「查無」證據**時（標題或頁面文字有 `DOI Not Found`，
    /// 或 HTTP 404）——Safari 離線時在同一個網址上顯示自己的錯誤頁，那不是 DOI 的問題，是整批暫停（R2 verify 第 9 則）。
    ///
    /// 這裡的起疑訊號一律整批暫停，**包括等人驗證的那四種**：doi.org 不是文章站，驗證完它會轉到出版商，`--resume-origin https://doi.org`
    /// 接不回去（R2 verify 第 17 則）。登入／驗證頁的長相同樣整批暫停。還在載入是卡住（整批暫停）。
    private func stillOnTheDOIResolver(_ u: String) throws -> Never {
        let site = origin(u)
        let here = "→ \(FulltextFetch.plainURL(u))"
        let rs = browser.run(["js"] + lock + [FulltextFetch.readyStateJS]).value
        guard rs == "complete" || rs == "interactive" else { throw botStop("page did not settle in 60 s (stalled) \(here)", site) }
        let title = tabTitle(ownTab)
        guard let page = pageText() else {
            throw botStop("page-unreadable on doi.org \(here): could not check it for suspicion or for doi.org's own not-found page", site)
        }
        if let hit = BotSignals.classify(title + "\n" + u + "\n" + page.text, status: page.status) {
            throw botStop("\(hit.label) on doi.org \(here) — doi.org is not the article site, so this cannot be resumed", site)
        }
        if let gate = BotSignals.gateLook(url: u, title: title) { throw botStop("doi.org showed a page with the look of a \(gate) page \(here) (\(gate) page)", site) }
        guard FulltextFetch.isDOINotFound(title: title, text: page.text, status: page.status) else {
            throw botStop("the tab stayed on doi.org for 60 s without doi.org's own not-found page (offline, or the resolver did not answer) \(here)", site)
        }
        throw handover(.doiNotResolved)
    }

    /// 等人驗證之後，在同一個分頁接著走（使用者 2026-10-01：不重新載入文章頁；2026-10-02：接著走**同一步**）。
    ///
    /// - `article`（導航到 PDF 連結之前的驗證）：分頁必須還顯示文章站；接著讀頁面的連結、記一次嘗試、導過去。
    /// - `followed`（導航到 PDF 連結**之後**的驗證）：嘗試已經記過、已經導航過——**不讀連結、不導航、不記嘗試**，回到「分頁顯示什麼」
    ///   的判斷（PDF → 交給人；HTML 閱讀器 → 交給人）。分頁此刻可以在別的主機（PDF 放在另一個主機，驗證完瀏覽器把分頁帶過去），所以
    ///   這一步不要求分頁顯示文章站；它只讀分頁、不導航、不關分頁。但分頁要是這三種之一：文章站（`--resume-origin`）、已知的驗證服務、
    ///   或此刻顯示 PDF——其他分頁（使用者驗證時開關分頁，位置漂移到他自己的信箱或銀行）拒絕（結束碼 1）。判斷 PDF 只讀
    ///   `document.contentType`，不讀那個分頁的文字（#613 R2 verify 第 12、16、19、21 則：先前只要網址非空就對它跑讀頁文字的 JS）。
    private func resume(tab position: Int, origin expected: String, stage resumeStage: ResumeStage, ledger: FulltextAttemptLedger) throws {
        guard let t = tab(String(position)) else {
            err("✗ window \(window) has no tab \(position) — the tab may have moved; find the one showing \(displaySafeInvisible(expected, max: 300)) with `safari-browser documents --json --profile <P>`")
            throw Stop(code: 1)
        }
        ownTab = String(position)
        stage = resumeStage
        switch resumeStage {
        case .followed:
            guard !t.url.isEmpty else { throw fail("window \(window) tab \(position) shows nothing — not resuming there.") }
            if !sameSite(t.url, expected), !BotSignals.isKnownVerificationService(url: t.url) {
                let shown = browser.run(["js"] + lock + [FulltextFetch.shownJS])
                guard shown.status == 0, FulltextFetch.contentTypeIsPDF(shown.value) else {
                    ownTab = ""   // 那不是我們的分頁
                    throw fail("window \(window) tab \(position) shows \(FulltextFetch.plainURL(t.url)) — not \(expected), a known verification service, or a PDF; not resuming there. Find the tab you verified in with `safari-browser documents --json --profile <P>` and pass its window/tab; if it is that tab, look at it yourself.")
                }
            }
            out("resuming: window \(window) tab \(ownTab) \(displaySafeInvisible(FulltextFetch.plainURL(t.url), max: 600)) (after the PDF link was followed)")
            try decideShown(site: expected)
        case .article:
            guard !t.url.isEmpty, sameSite(t.url, expected) else {
                ownTab = ""   // 那不是我們的分頁
                throw fail("window \(window) tab \(position) shows \(t.url.isEmpty ? "nothing" : FulltextFetch.plainURL(t.url)), not \(expected) — not resuming there. Find the tab showing \(expected) with `safari-browser documents --json --profile <P>` and pass its window/tab.")
            }
            let site = origin(t.url)
            out("resuming: window \(window) tab \(ownTab) \(displaySafeInvisible(FulltextFetch.plainURL(t.url), max: 600))")
            // 舊的呼叫端沒帶 `--resume-stage`：驗證若發生在導航之後、分頁已經顯示 PDF，直接交給人（嘗試已經記過）
            let shown = browser.run(["js"] + lock + [FulltextFetch.shownJS])
            if shown.status != 0 { throw try unscriptable(site) }
            if FulltextFetch.contentTypeIsPDF(shown.value) { throw handover(.pdfShown) }
            try botCheckPage(site)   // 還在驗證頁 → 8；別的訊號 → 6
            try followThePagesOwnLink(site: site, ledger: ledger)
        }
    }

    /// 讀頁面自己的 PDF 連結、記一次嘗試、把同一個分頁導過去、交給人。
    private func followThePagesOwnLink(site: String, ledger: FulltextAttemptLedger) throws {
        try siteGuard(site)
        _ = browser.run(["wait"] + lock + ["--js", FulltextFetch.hasLinkJS, "--timeout", "45000"])
        try siteGuard(site)
        try botCheckPage(site)   // 插頁在我們等的時候可以變成挑戰頁
        try siteGuard(site)
        let linkRun = browser.run(["js"] + lock + [FulltextFetch.linkJS])
        if linkRun.status != 0 { throw fail("could not read the page's links: \(linkRun.stderr.trimmingTrailingNewlines())") }
        let link = linkRun.value
        guard let space = link.firstIndex(of: " ") else {
            err("no PDF link on \(displaySafeInvisible(FulltextFetch.plainURL(tabURL(ownTab)), max: 600))")
            closeOwnTab(site)
            throw Stop(code: 3)
        }
        let method = String(link[..<space])
        let target = String(link[link.index(after: space)...])
        guard method == "GET" || method == "POST" else { throw fail("unexpected answer from the link script: \(FulltextFetch.plainURL(link))") }
        // 頁面自己的連結來自 DOM（`citation_pdf_url`、`a[href]`、表單的 `action`）：只跟同一個站的絕對 https 網址走。拒絕不是中止條款
        // （不是網站起疑，是頁面給了一個不能照做的連結）：結束碼 1，分頁留著。
        let linkOrigin = FulltextFetch.linkTargetOrigin(target)
        if linkOrigin != site.lowercased() {
            throw fail("the page's PDF link points off-site (\(linkOrigin ?? "not an absolute https URL"), page origin \(site)): \(FulltextFetch.plainURL(target)) — not following a link the page chose to another site")
        }

        // --- 每站每天 10 次嘗試：準備取 PDF 的這一刻就算 ---
        // 查數與記錄是一步（`reserve`：跨行程的鎖之下重讀帳本、數今天的次數、沒到上限就記）；之後才導航。兩個行程同時搶最後一格時
        // 只有一個拿到（先前 `count` 與 `append` 之間沒有鎖，兩個行程都讀到 9、各自記成第 10 次）
        let host = FulltextFetch.siteKey(site)
        let at = now()
        let day = FulltextAttemptLedger.taipeiDay(at)
        let reservation: FulltextAttemptLedger.Reservation
        do { reservation = try ledger.reserve(site: host, landing: landing, at: at) } catch { throw fail("\(displaySafeErrorText(error))") }
        switch reservation {
        case .capReached(let used):
            err("⏹ DAILY CAP: \(displaySafeInvisible(host, max: 300)) already has \(used) attempts on \(day) (Asia/Taipei) — stop this site for today; it has not been asked for the PDF (the article page itself was already loaded).")
            out("cap: \(displaySafeInvisible(host, max: 300)) \(used)/\(FulltextAttemptLedger.dailyCap) \(day)")
            closeOwnTab(site)
            throw Stop(code: Code.dailyCapReached)
        case .granted(let used):
            out("attempt: \(displaySafeInvisible(host, max: 300)) \(used)/\(FulltextAttemptLedger.dailyCap) \(day)")
        }

        if method == "POST" { throw handover(.button) }   // 表單按鈕交給人按，不代按、不代送

        out("pdf:  \(displaySafeInvisible(FulltextFetch.plainURL(target), max: 600))")
        let before = tabURL(ownTab)
        stage = .followed   // 從這裡起，等人驗證之後接著走的是「分頁顯示什麼」，不是再讀一次連結
        let navigation = browser.run(["open"] + lock + [target])
        if navigation.status != 0 { throw fail("could not navigate the tab to the PDF link: \(navigation.stderr.trimmingTrailingNewlines())") }
        try awaitShown(site: site, before: before)
    }

    /// 導航之後：等分頁離開文章頁（20 秒），再看它顯示什麼。
    private func awaitShown(site: String, before: String) throws {
        var moved = false
        for _ in 1...10 {
            nap(2)
            let u = tabURL(ownTab)
            if u.isEmpty || u != before { moved = true; break }
        }
        try siteGuard(site)   // 分頁不見了 → 6；到了別的主機 → 照 `leftSite`（PDF／沒有標記的頁面交給人，訊號與登入頁停）
        if !moved {
            try botCheckPage(site)
            throw handover(.tabUnchanged)
        }
        try decideShown(site: site)
    }

    /// 分頁顯示什麼：PDF → 交給人；HTML 頁落定 → 查訊號、交給人；讀不到 → 交給人看。導航之後的判斷與等人驗證之後接著走
    /// （`resume --resume-stage followed`）是同一段——驗證完不重新讀連結、不再導航。
    private func decideShown(site: String) throws {
        var failures = 0
        for _ in 1...30 {
            try siteGuard(site)
            let r = browser.run(["js"] + lock + [FulltextFetch.shownJS])
            if r.status == 0, FulltextFetch.contentTypeIsPDF(r.value) {
                throw handover(.pdfShown)
            } else if r.status != 0 || FulltextFetch.isUnreadableShown(r.value) {
                // 空的或 `undefined` 的回答（對非 HTML 文件跑 `do JavaScript` 的可能結果）與失敗同樣算「讀不到」，不是「還在載入」
                failures += 1
                if failures >= 3 { throw try unscriptable(site) }
            } else if FulltextFetch.isSettled(r.value) {
                try botCheckPage(site)
                throw handover(.htmlPage)
            }
            nap(2)
        }
        throw botStop("the tab did not settle after following the PDF link (stalled) → \(FulltextFetch.plainURL(tabURL(ownTab)))", site)
    }

    /// 讀不到分頁（頁面 JS 跑不起來）：只剩標題與網址可以看。有起疑訊號照訊號處理，沒有就交給人看——交給人本身就是停下。
    private func unscriptable(_ site: String) throws -> Stop {
        if let hit = BotSignals.classify(tabTitle(ownTab) + "\n" + tabURL(ownTab)) { return stop(for: hit, site) }
        return handover(.unverifiable)
    }

    // MARK: 純函式（測試直接呼叫）

    /// 帳本用的站名：origin 的主機，小寫。
    static func siteKey(_ origin: String) -> String { PyText.string(URLSplit(origin).netloc).lowercased() }

    /// 網址去掉會帶憑證的部分，才印進 stdout、stderr 與 `origin`：查詢與片段（簽章網址的短效憑證、SSO 的票）、主機前的帳密（`user:pw@`）、
    /// 路徑上的 `;jsessionid=…`（#613 R2 verify 第 11、15、18、22、33 則：先前只有 `handover:`／`pdf:`／`resuming:` 三行去查詢，停止訊息與
    /// `page:` 一行照印）。以 Unicode scalar 找 `?`／`#`：`?` 後面接組合字元時，以 `Character` 找會找不到。
    ///
    /// **代價**：查詢字串本身就是文件身分的網址（`viewcontent.cgi?article=…`、`doiLanding?doi=…`）在 `origin` 裡也少了那一段——只剝
    /// 已知的憑證參數要一份會漏的清單，這裡選擇全剝（R2 verify 第 22 則，留給使用者裁決）。
    static func plainURL(_ url: String) -> String {
        var s = url
        if let cut = s.unicodeScalars.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            s = String(String.UnicodeScalarView(s.unicodeScalars[..<cut]))
        }
        if let schemeEnd = s.range(of: "://") {
            let rest = s[schemeEnd.upperBound...]
            let authorityEnd = rest.firstIndex(of: "/") ?? rest.endIndex
            if let at = rest[..<authorityEnd].lastIndex(of: "@") {
                s = String(s[..<schemeEnd.upperBound]) + String(rest[rest.index(after: at)...])
            }
        }
        return s.replacingOccurrences(of: #";jsessionid=[^/;]*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// `shownJS` 的回答（第二行是 readyState）是不是已經落定：complete 或 interactive。
    static func isSettled(_ value: String) -> Bool {
        let readyState = value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return readyState == "complete" || readyState == "interactive"
    }

    /// 這個網址的**主機**是不是 doi.org 或 dx.doi.org（大小寫不分）。不是看網址字串裡有沒有 `://doi.org/`：把 DOI 帶在查詢字串裡的
    /// 登入頁也有那一段（#613 R2 verify 第 9、20 則）。
    static func isDOIResolver(_ url: String) -> Bool {
        let parts = URLSplit(url)
        let scheme = PyText.string(parts.scheme)
        let host = PyText.string(parts.netloc).lowercased()
        return (scheme == "https" || scheme == "http") && (host == "doi.org" || host == "dx.doi.org")
    }

    /// doi.org 自己的「查無」證據：標題或頁面文字寫著 `DOI Not Found`，或 HTTP 404。只在主機已確認是 doi.org 時問。
    static func isDOINotFound(title: String, text: String, status: Int?) -> Bool {
        status == 404 || title.range(of: "doi not found", options: .caseInsensitive) != nil
            || text.range(of: "doi not found", options: .caseInsensitive) != nil
    }

    /// `shownJS` 的回答是不是「讀不到」：第一行（content type）或第二行（readyState）是空的或 `undefined`。
    static func isUnreadableShown(_ value: String) -> Bool {
        let lines = value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let bad: (String) -> Bool = { $0.isEmpty || $0 == "undefined" || $0 == "null" }
        return lines.count < 2 || bad(lines[0]) || bad(lines[1])
    }

    /// `document.contentType + '\n' + …` 的第一行是不是 PDF。
    static func contentTypeIsPDF(_ value: String) -> Bool {
        (value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "").lowercased().contains("pdf")
    }

    /// 頁面給的 PDF 連結的 origin（小寫）；不是「可以照字面比 origin 的絕對 https 網址」就回 nil＝拒絕。
    ///
    /// **只收 `linkJS` 在頁面裡解析好的絕對網址**（#629 R2 verify 第 0、9、12、20 則）：開頭必須是 `https://`；整串不得有反斜線、
    /// 空白或控制字元（WHATWG 序列化出來的網址不會有）；`://` 之後到第一個 `/?#` 的主機段不得是空的。主機段含 `@`（帶帳密）或埠號時照字面比，
    /// 與頁面 origin 對不上＝拒絕。
    static func linkTargetOrigin(_ url: String) -> String? {
        guard url.lowercased().hasPrefix("https://"),
              !url.unicodeScalars.contains(where: { $0 == "\\" || $0.value < 0x21 || (0x7F...0x9F).contains($0.value) || $0.properties.isWhitespace })
        else { return nil }
        let parts = URLSplit(url)
        guard !parts.netloc.isEmpty else { return nil }
        return "https://\(PyText.string(parts.netloc))".lowercased()
    }

    /// `--landing` 的形狀：web-access.md〈插值前先驗形狀〉「完整網址」一列的**主機部分與禁用字元**（#629 R2 verify 第 34 則）。回 nil＝通過。
    ///
    /// - 只收 `https://`；整串不得有 `'`、`"`、反斜線、反引號、`$`、`#`、空白或控制字元；
    /// - 主機＝`([A-Za-z0-9-]+\.)+[A-Za-z]{2,}`（至少一個點、最後一段是字母——擋掉 `localhost`、IP 位址、帶埠號或 `user@` 的主機），最後一段
    ///   不是 `local`、`localhost`、`internal`、`lan`、`intranet`、`corp`、`arpa`；
    /// - 路徑段（百分比解碼後）不是 `.` 或 `..`。
    ///
    /// **這是字面的形狀檢查，不保證主機是公開的**（R3 verify）：不解析 DNS。**路徑的字元集不套那一列**：`--landing` 通常是
    /// `https://doi.org/<DOI>`，SICI 式 DOI 的 `<`、`>` 在那裡是合法的（DOI 一列管它）。
    static func landingShapeProblem(_ url: String) -> String? {
        guard url.lowercased().hasPrefix("https://") else { return "not https://" }
        let forbidden = Set("'\"\\`$#".unicodeScalars)
        if let bad = url.unicodeScalars.first(where: { forbidden.contains($0) || $0.value < 0x21 || (0x7F...0x9F).contains($0.value) || $0.properties.isWhitespace }) {
            return String(format: "contains U+%04X", bad.value)
        }
        let parts = URLSplit(url)
        let host = PyText.string(parts.netloc)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isLabel: (Substring) -> Bool = { !$0.isEmpty && $0.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "-") } }
        guard labels.count >= 2, labels.allSatisfy(isLabel), let last = labels.last, last.count >= 2,
              last.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isAlphabetic }) else {
            return "the host is not a plain DNS name: no localhost, IP address, port, user@, and the last label must be letters"
        }
        if ["local", "localhost", "internal", "lan", "intranet", "corp", "arpa"].contains(last.lowercased()) {
            return "the host ends in a private-network name"
        }
        for segment in parts.path.split(separator: "/", omittingEmptySubsequences: false) {
            let decoded = String(segment).removingPercentEncoding ?? String(segment)
            if decoded == "." || decoded == ".." { return "a path segment is . or .." }
        }
        return nil
    }

    /// `--resume-origin` 的形狀：`https://<主機>`，主機過 `landingShapeProblem` 的同一道檢查，後面沒有路徑、查詢或片段。
    public static func resumeOriginProblem(_ origin: String) -> String? {
        if let why = landingShapeProblem(origin) { return why }
        if origin.contains("?") { return "it has a query" }
        let parts = URLSplit(origin)
        guard parts.path.isEmpty else { return "it has a path" }
        return nil
    }

    // MARK: 注入頁面的 JS——每一段都是**運算式**（見型別註解；`FulltextJavaScriptTests` 驗能不能當運算式解析）

    /// 文件是否載完。
    static let readyStateJS = "document.readyState"

    /// 第一行：HTTP 狀態碼（頁面自己的 navigation timing；沒有就空）；之後：標題與前 3000 字。
    static let pageTextJS = """
    (function () { var s = ''; try { var n = performance.getEntriesByType('navigation')[0]; if (n && n.responseStatus) { s = String(n.responseStatus); } } catch (e) {} return s + '\\n' + document.title + '\\n' + (document.body ? document.body.innerText.slice(0, 3000) : ''); })()
    """

    /// 頁面上有沒有 PDF 連結（`wait --js` 的條件）。#613 起不再找 PsycNet 的 `/record/` 連結——那只是給被刪掉的拼網址規則取 id 用的。
    static let hasLinkJS = """
    !!(document.querySelector('meta[name=citation_pdf_url]') || document.querySelector('a[href*="/doi/pdf/"],a[href*="pdfdirect"],a[href$=".pdf"],a[href*=".pdf?"]') || document.querySelector('form.ft-download-content__form--pdf'))
    """

    /// 讀頁面的 PDF 連結：表單（POST）、`citation_pdf_url` 中繼標籤、或幾種連結樣式（GET）。`f.action` 與 `a.href` 瀏覽器已解析成絕對網址；
    /// 中繼標籤的 `content` 是原始字串，用 `new URL(…, document.baseURI)` 解析（頁面的 `<base href>` 指到別站時解析出來就是別站，由
    /// `linkTargetOrigin` 拒絕）。解析失敗時原樣交回，Swift 側拒絕。
    static let linkJS = """
    (function () {
      var f = document.querySelector('form.ft-download-content__form--pdf');
      if (f) { return 'POST ' + f.action; }
      var m = document.querySelector('meta[name=citation_pdf_url]');
      if (m && m.content) { try { return 'GET ' + new URL(m.content, document.baseURI).href; } catch (e) { return 'GET ' + m.content; } }
      var s = ['a[href*="/doi/pdf/"]', 'a[href*="pdfdirect"]', 'a[href$=".pdf"]', 'a[href*=".pdf?"]'];
      for (var i = 0; i < s.length; i++) { var a = document.querySelector(s[i]); if (a) { return 'GET ' + a.href; } }
      return '';
    })()
    """

    /// 導航之後分頁顯示什麼：第一行 content type、第二行 readyState。
    static let shownJS = "document.contentType + '\\n' + document.readyState"

    /// 注入頁面的全部 JS（測試逐段驗解析）。
    static let injectedExpressions: [String] = [readyStateJS, pageTextJS, hasLinkJS, linkJS, shownJS]
}
