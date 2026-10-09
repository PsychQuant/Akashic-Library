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
///       這一筆交給人，不是整批停。原因（`handover:` 一行）：`pdf-shown`（含另一個主機上顯示的 PDF——依據是頁面讀得到的
///       `document.contentType`，頁面腳本改得了它）、`html-page`、`unverifiable`（讀不到分頁，什麼都沒檢查；文章站上與別的主機上同一個
///       條件：同一個網址連三次讀不到、而那裡從沒讀到過一般網頁的分頁）、`tab-unchanged`、`button`、`left-site`（導航之後分頁到了別的主機、頁面載完而
///       沒有命中驗證／封鎖／登入的封閉清單——那不代表它不是登入頁）與 `doi-not-resolved`（停在 doi.org，而且看得到 doi.org 自己的
///       查無證據）。
///     8 等人驗證：出現 CAPTCHA／人類檢查／Cloudflare「Just a moment」／按住驗證，**而且在文章站本身或已知的驗證服務上**
///       （`BotSignals.isKnownVerificationService`；其他主機上的驗證字樣是結束碼 6）。暫停這一篇；使用者驗證完，以
///       `--resume-tab`／`--resume-origin`（導航之後的驗證另帶 `--resume-stage followed`）在**同一個分頁**接著走（不重新載入）。分頁留著。
///     9 這個站今天已經 10 次嘗試（Asia/Taipei）：停這個站，隔天再跑。沒有導航到 PDF。
///     6 **整批暫停**（SKILL.md〈中止條款〉）：其他起疑訊號——封鎖頁、HTTP 403／429、異常流量、PMC 的下載前驗證頁、ScienceDirect
///       的「Preparing your download」、其他主機上的驗證字樣、分頁跑到別的網站而那一頁是登入／驗證頁的長相、DOI 落地頁的網址是登入頁
///       的長相、讀不到的分頁停在登入主機的長相上（只看主機）、卡住（落地頁、導航之後、別的主機上的頁面約 60 秒沒落定）、停在 doi.org
///       卻看不到它自己的查無證據（使用者 2026-10-05 第 1 則）、落定的網頁讀不到頁面文字而無從檢查（導航之前的文章頁、導航之後文章站上
///       落定的 HTML 頁、別的主機上落定的頁面；連 `document.contentType` 都讀不到的分頁是 7 `unverifiable`）。分頁留著給使用者看。
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
///
/// # 契約版本
///
/// `contractVersion` 是這個命令（與 `take`）對 skill 的契約版本，`akashic fulltext contract` 印它；SKILL.md 第 0 步要求至少這個值（#613 R3，
/// b31 W4 第 1 則：先前以 `take` 的行為探測，分不出 R1、R2 的 CLI）。結束碼、交給人的原因、或哪些頁面整批暫停改變時就往上調，SKILL 第 0 步
/// 一起調（`SkillToolsCLITests` 比對兩邊相等）。
public final class FulltextFetch {
    /// 1＝#613 只導航、交給人；2＝R1 修正輪（2026-10-02）；3＝R2 修正輪（e5182cf1）；4＝R3（2026-10-04）；5＝b34（2026-10-05：文章站上
    /// 讀不到的分頁與別的主機同一套、讀不到的分頁在登入主機上整批暫停、文章站上同一份快照、使用者 2026-10-05 的主機標籤與路徑段裁決）；
    /// 6＝b37（2026-10-09：複合路徑段只認明確的登入字、讀的當中換到同站登入頁先判登入長相、safari-browser 的錯誤只轉印第一行、`plainURL`
    /// 與站的比對同一個主機）。前三版的 CLI 沒有 `contract` 子命令——數字只是給歷史一個名字，第 0 步擋它們靠的是「沒有這個子命令」。
    public static let contractVersion = 6

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

    /// 等頁面落定的上限（秒，以時鐘計；#613 R3，b31 W4 第 7 則）。落地頁、導航之後、別的主機上的頁面三處都用它，也都不超過 30 次輪詢——
    /// 先前只數輪詢次數，每一次輪詢還有對 safari-browser 的呼叫，真的 Safari 上「60 秒」實際是一百多秒。
    static let settleSeconds: Double = 60

    /// 新的三個結束碼（#613）。其餘沿用：1、3、6。
    public enum Code {
        public static let handedOver: Int32 = 7
        public static let humanVerification: Int32 = 8
        public static let dailyCapReached: Int32 = 9
    }

    /// 交給人的原因（結束碼 7；stdout 的 `handover:` 一行印它的 `rawValue`）。SKILL〈交給人之後〉的表逐一列它們（`FulltextB34Tests.testTheSkillsHandoverTableIsTheHandoverEnum` 對帳）。
    public enum Handover: String, CaseIterable {
        /// 分頁回報它顯示 PDF（`document.contentType` 含 pdf）。那是頁面讀得到的值，頁面腳本改得了它（b31 W4 第 18、33 則）——訊息照實說
        case pdfShown = "pdf-shown"
        /// 頁面自己的 PDF 連結通到 HTML 頁（閱讀器、登入頁、無權限的外殼）
        case htmlPage = "html-page"
        /// 讀不到分頁（Safari 的 PDF 檢視器可能不跑頁面 JS，或頁面拒絕），什麼都沒檢查。文章站上與別的主機上同一個條件（`judgeUnreadable`，
        /// #613 b34）：同一個網址連三次讀不到、那裡從沒讀到過一般網頁，而且網址不在已知的驗證服務上、主機不是登入主機的長相、標題與網址
        /// 沒有驗證服務自己的標記
        case unverifiable = "unverifiable"
        /// 導航之後分頁沒有離開文章頁（連結可能直接觸發下載）
        case tabUnchanged = "tab-unchanged"
        /// 頁面的 PDF 下載是表單按鈕（Annual Reviews 型）
        case button = "button"
        /// 分頁到了別的主機（跨主機的中繼頁、CDN 的檔案主機），頁面載完而沒有命中驗證／封鎖／登入的封閉清單——那不代表它不是登入頁；
        /// 那裡顯示的是 PDF 時是 `pdf-shown`（使用者 2026-10-02）。這一筆交給人，批次繼續
        case leftSite = "left-site"
        /// DOI 解不開：分頁停在 doi.org，而且看得到 doi.org 自己的查無證據（`DOI Not Found` 或 404）。這是資料問題，不是起疑訊號
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
    ///
    /// `context` 以 `→ <網址>` 結尾時（別的主機上的判斷），那個網址就是判斷時的快照：用它判主機，不再讀一次分頁（讀的當中可能換了頁）。
    private func stop(for hit: BotSignals.Hit, _ site: String, context: String = "", at snapshotURL: String? = nil) -> Stop {
        let signal = context.isEmpty ? hit.label : "\(hit.label) \(context)"
        guard hit.response == .humanVerification else { return botStop(signal, site) }
        let url = snapshotURL ?? tabURL(ownTab)
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
    ///
    /// `at`：判斷時那一份快照的網址（別的主機上的判斷傳它，#613 R3，b31 W4 第 0 則）。印出來的網址要是判斷的那一頁，不是判完之後再讀一次的
    /// ——那一下分頁可能已經換了頁。沒傳就讀分頁此刻的網址。
    private func handover(_ reason: Handover, at snapshotURL: String? = nil) -> Stop {
        // 網址不帶查詢與片段：簽章網址（`X-Amz-Signature` 之類的短效憑證）沒有理由出現在 stdout、agent 的對話與 `sources/index.jsonl` 的 `origin`
        let shownURL = snapshotURL ?? tabURL(ownTab)
        let u = FulltextFetch.plainURL(shownURL)
        out("handover: \(reason.rawValue) window \(window) tab \(ownTab) \(displaySafeInvisible(u, max: 1000))")
        err("✋ HANDED OVER TO YOU (\(reason.rawValue)) — window \(window), tab \(ownTab).")
        switch reason {
        case .pdfShown:
            err("  The tab reports that it shows a PDF (document.contentType — a page can claim that, so look at it before saving). Save it yourself (which Safari control is the standard one is being settled in safari-browser#210). If it shows a login, verification or block page instead, that is the abort clause.")
        case .htmlPage:
            err("  The page's own PDF link opened an HTML page — a reader, a login page, or an access shell. If it has a download button, press it yourself; if it says there is no access, report that.")
        case .unverifiable:
            err("  This command could not read the tab (Safari's PDF viewer may not run page scripts), so nothing on it was checked — it is unverified, not clean. Look at it: save the PDF if it shows one; a login, verification or block page is the abort clause.")
        case .tabUnchanged:
            err("  The tab did not leave the article page after following the PDF link — the link may have started a download (check Safari's downloads) or needs a click.")
        case .button:
            err("  The page's PDF download is a form button. Press it yourself; the site may download the file.")
        case .leftSite:
            err("  The tab left the article site for \(displaySafeInvisible(origin(shownURL), max: 300)); the page finished loading and matched none of the closed lists of verification, block or login markers — that does not mean it is not one. Look at it: if it shows the PDF, save it; a login, verification or block page is the abort clause. This item is handed to you; the rest of the batch can go on once you have looked at it.")
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
    private func currentTab() -> String { docs().first { $0.window == window && $0.isCurrent }.map { String($0.tabInWindow) } ?? "" }
    /// `scheme://主機[:埠號]`，不帶帳密（`URLSplit.siteOrigin`）：站的比對、訊息與帳本的站名都從這裡來。
    private func origin(_ url: String) -> String { URLSplit(url).siteOrigin }
    /// 分頁的網址是不是還在這個 origin（主機不分大小寫）。
    private func sameSite(_ url: String, _ site: String) -> Bool { origin(url).lowercased() == site.lowercased() }
    private var lock: [String] { ["--window", String(window), "--tab-in-window", ownTab] }

    /// 開一個分頁，用**位置**記住是哪一個，之後只關它。用位置而不是 URL：使用者已開著同一頁時，URL 鎖會對到兩個分頁、
    /// safari-browser 會 fail-closed（2026-09-23 觀察）。
    private func openOwnTab(_ url: String) throws {
        let r = browser.run(["open", "--new-tab", "--window", String(window), url])
        if r.status != 0 { throw fail("open: \(FulltextFetch.safariFailure(r.stderr))") }
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

    // MARK: 讀分頁：同一份快照（#613 R3 只用在別的主機上；b34 起文章站上也是，b33 X3 第 2、8 則）

    /// 一次讀頁面：（網址，標題）→ 頁面文字與狀態碼 → 再讀一次（網址，標題）。兩次不同＝讀的當中分頁換了頁，這一份不用（回 nil，
    /// `pageChanges` 加一）。`accept` 判第一次讀到的網址是不是這一步要判的那一頁。`page` 是 nil＝讀不到頁面文字。
    private struct PageSnapshot {
        let url: String
        let title: String
        let page: (status: Int?, text: String)?
    }
    private func readPage(accept: (String) -> Bool) -> PageSnapshot? {
        guard let first = tabSnapshot(), !first.url.isEmpty, accept(first.url) else { pageChanges += 1; return nil }
        let page = pageText()
        guard let second = tabSnapshot(), second.url == first.url, second.title == first.title else { pageChanges += 1; return nil }
        return PageSnapshot(url: first.url, title: first.title, page: page)
    }

    /// 讀的當中換了頁的次數（`readPage` 回 nil）。等到卡住時訊息照實說「頁面在讀的當中一直變」，不是只說沒落定（b33 X3 第 11、18 則：標題
    /// 每讀一次就變的倒數頁其實落定了，訊息卻叫人去找載入的問題）。每一段等待開始時歸零。
    private var pageChanges = 0
    private var pageChangesNote: String { pageChanges > 0 ? " — the page changed while it was being read (\(pageChanges) times); it may have settled" : "" }

    /// 文章站上一份快照的起疑判斷：命中 → 停法（等人驗證或整批暫停）；讀不到頁面文字 → 標題命中照訊號、否則整批暫停（無從檢查不等於
    /// 乾淨）；乾淨 → nil。
    private func onSiteSuspicion(_ snap: PageSnapshot, _ site: String) -> Stop? {
        guard let page = snap.page else {
            if let hit = BotSignals.classify(snap.title) { return stop(for: hit, site, at: snap.url) }
            return botStop("page-unreadable: could not check it for suspicion", site)
        }
        if let hit = BotSignals.classify(snap.title + "\n" + page.text, status: page.status) { return stop(for: hit, site, at: snap.url) }
        return nil
    }

    /// 我們的分頁（在文章站上）有沒有起疑訊號。等人驗證的訊號 → 結束碼 8；其他 → 6；讀不到頁面 → 6。回判斷的那一頁的網址。
    /// 同一份快照：讀的當中換了頁就先過 `siteGuard`（換到別的主機照 `leftSite` 判）再讀一次；連三次都在換頁＝無從檢查，整批暫停。三次（約
    /// 6–10 秒）是讀**同一頁**的次數，不是等頁面落定的時間：頁面在讀的當中一直變，使用者 2026-10-05 裁決維持整批暫停。
    ///
    /// `beforeNavigation`：導航到 PDF 連結**之前**的檢查（落地頁、讀連結之前、導航之前的接續）——每一份快照先判網址的**登入長相**，命中就整批暫停，
    /// 再判起疑訊號（#613 b37，b36 Y2 第 0 則：先前呼叫端只在呼叫之前看一次網址，讀的當中分頁轉到同站的 `/login`、那一頁寫著 CAPTCHA，就成了
    /// 等人驗證、印出以文章站為目標的 `resume:`——登入頁降成等人驗證，正是 R3 對落地頁修掉的形狀）。導航**之後**（`awaitShown`）傳 false：
    /// 那時同站的 HTML 頁是頁面自己的 PDF 連結的結果，與 `decideShown` 同一套只看文字訊號、交給人 `html-page`（b36 Y2 第 16 則）。
    @discardableResult
    private func botCheckPage(_ site: String, beforeNavigation: Bool) throws -> String {
        for _ in 1...3 {
            try siteGuard(site)
            guard let snap = readPage(accept: { self.sameSite($0, site) }) else { nap(2); continue }
            if beforeNavigation, BotSignals.urlGateLook(snap.url) == "login" {
                throw botStop("the page on the article site has the look of a login page → \(FulltextFetch.plainURL(snap.url)) (login page)", site)
            }
            if let stop = onSiteSuspicion(snap, site) { throw stop }
            return snap.url
        }
        throw botStop("the page kept changing while it was being read: could not check it for suspicion → \(FulltextFetch.plainURL(tabURL(ownTab)))", site)
    }

    /// 每個進一步動作之前：我們的分頁必須還顯示文章的站。分頁離開了文章站（使用者 2026-10-02），照 `leftSite` 判；分頁在等它落定的
    /// 時候回到文章站就照常往下走。
    private func siteGuard(_ site: String) throws {
        let u = tabURL(ownTab)
        if !u.isEmpty, sameSite(u, site) { return }
        guard !u.isEmpty else { throw botStop("site changed → <our tab is gone>", site) }
        if let stop = try leftSite(from: site) { throw stop }
    }

    /// 分頁離開了文章站。順序（#613 R2 verify 第 0、1、2、3、6、7、8、10 則；R3＝b31 W4 第 0、3、4、5、7、12 則）：
    /// 1. **先問 PDF**（`document.contentType`；頁面讀得到的值，頁面腳本改得了它——不是回應本身）→ 交給人（`pdf-shown`）。Safari 的 PDF
    ///    分頁標題通常就是文章標題，先前標題與網址的長相排在前面，`Research design in …` 這種標題讓 PDF 變成整批暫停。
    /// 2. 不是 PDF 的頁面**要等它落定**（readyState 是 complete／interactive；最多約 60 秒，以時鐘計、也不超過 30 次輪詢）：還在載入的頁面說不出
    ///    「沒有標記」。一直沒落定 → 卡住，整批暫停。等的時候分頁又換了網址就重新看（換到登入頁就判登入頁；回到文章站就照常往下走）。
    /// 3. 落定之後，**標題、網址、頁面文字與 HTTP 狀態一起**判起疑訊號（`classify`）：429 一律整批暫停，所以已知驗證服務上的 429 頁不會進
    ///    等人驗證；等人驗證只在已知的驗證服務上成立，其他主機一律整批暫停。這幾樣要是**同一頁的**（`readPage`）：讀完之後分頁的網址或
    ///    標題變了，那一份不用，回去等。
    /// 4. 登入／驗證頁的長相（`BotSignals.gateLook`：網址的主機與路徑、標題的整字片語）→ 整批暫停。
    /// 5. 其他（CDN 的檔案主機、跨主機的中繼頁）→ 這一筆交給人（`left-site`），批次繼續。沒命中封閉清單不代表不是登入頁，訊息照說。
    ///
    /// **讀不到**（頁面 JS 跑不起來；Safari 的 PDF 檢視器可能就是這樣）：同一個網址**連三次**讀不到、而且那個網址上**從沒讀到過一般網頁**的回答
    /// 才算（`UnreadableTally`），照 `judgeUnreadable` 判——文章站上同一套。讀到過「還在載入」的網址是一般網頁，不是 PDF 檢視器——讀不到就
    /// 繼續等，等不到是卡住。
    /// 回 nil＝分頁在等的時候回到了文章站。
    private func leftSite(from site: String) throws -> Stop? {
        let start = now()
        var tally = UnreadableTally()
        let outer = pageChanges   // 從文章站上的等待裡來：回到文章站時還給它
        pageChanges = 0
        for poll in 1...30 {
            if poll > 1, now().timeIntervalSince(start) >= FulltextFetch.settleSeconds { break }
            let before = tabURL(ownTab)
            let shown = browser.run(["js"] + lock + [FulltextFetch.shownJS])
            let url = tabURL(ownTab)
            if url.isEmpty { return botStop("site changed → <our tab is gone>", site) }
            if sameSite(url, site) { pageChanges = outer; return nil }
            if url == before {   // 看的這一下分頁沒有換頁：這個回答屬於這個網址
                if shown.status == 0, FulltextFetch.contentTypeIsPDF(shown.value) { return handover(.pdfShown, at: url) }
                if shown.status != 0 || FulltextFetch.isUnreadableShown(shown.value) {
                    if tally.unreadable(at: url), let stop = judgeUnreadable(url, site) { return stop }
                } else {
                    tally.answered(at: url)
                    if FulltextFetch.isSettled(shown.value), let stop = offSiteSettled(url, site) { return stop }
                }
            } else {
                tally.moved()   // 換頁中：讀不到的這一下不算到任何一個網址
            }
            nap(2)
        }
        return botStop("the tab left the article site and the page did not settle (stalled)\(pageChangesNote) → \(FulltextFetch.plainURL(tabURL(ownTab)))", site)
    }

    /// 讀不到的分頁要「同一個網址**連三次**、那個網址上從沒讀到過一般網頁的回答」才算（b31 W4 第 5 則；b34 起文章站上同一個規則，b33 X3
    /// 第 4 則：先前文章站上是累積計數，失敗、還在載入、失敗、失敗就交給人、批次繼續，別的主機上同一串回答是卡住）。
    private struct UnreadableTally {
        private var count = 0
        private var url = ""
        private var sawAPage: Set<String> = []
        /// 看的這一下分頁在換頁：不算到任何一個網址。
        mutating func moved() { count = 0 }
        /// 讀不到一次；回 true＝夠了（同一個網址連三次，那裡從沒讀到過一般網頁）。
        mutating func unreadable(at u: String) -> Bool {
            if u != url { count = 0; url = u }
            count += 1
            return count >= 3 && !sawAPage.contains(u)
        }
        /// 讀到了不是 PDF 的回答（還在載入、或落定）：那個網址是一般網頁。
        mutating func answered(at u: String) { count = 0; url = u; sawAPage.insert(u) }
    }

    /// 分頁此刻的（網址，標題）——同一次 `documents` 讀到的一對。
    private func tabSnapshot() -> (url: String, title: String)? { tab(ownTab).map { ($0.url, $0.title) } }

    /// 別的主機上的頁面落定了：標題、網址、頁面文字與狀態碼一起判訊號，再看登入／驗證頁的長相，都沒有就交給人。
    ///
    /// **同一份快照**（#613 R3，b31 W4 第 0 則；`readPage`）：讀完之後網址或標題變了＝讀的當中分頁換了頁（中繼頁轉到登入頁），這一份不用，回 nil
    /// 讓 `leftSite` 回去等。先前標題、頁面文字、交給人時印的網址各讀各的，舊中繼頁的網址與標題配上新登入頁的文字，三樣都沒命中就交給人。
    private func offSiteSettled(_ url: String, _ site: String) -> Stop? {
        guard let snap = readPage(accept: { $0 == url }) else { return nil }
        let moved = "→ \(FulltextFetch.plainURL(url))"
        guard let page = snap.page else {
            // 讀不到頁面文字：狀態碼也不知道，只剩標題與網址
            if let hit = BotSignals.classify(snap.title + "\n" + url) { return stop(for: hit, site, context: moved, at: url) }
            return botStop("page-unreadable \(moved): could not check it for suspicion", site)
        }
        if let hit = BotSignals.classify(snap.title + "\n" + url + "\n" + page.text, status: page.status) { return stop(for: hit, site, context: moved, at: url) }
        if let gate = BotSignals.gateLook(url: url, title: snap.title) { return botStop("site changed \(moved) (\(gate) page)", site) }
        return handover(.leftSite, at: url)
    }

    /// 讀不到的分頁（頁面 JS 跑不起來）：只剩標題與網址，而這樣的分頁可能就是 Safari 的 PDF 檢視器——PDF 分頁的標題常是文章標題、檔案的路徑
    /// 常有 `auth`、`validate` 之類的段。**文章站上與別的主機上同一套**（#613 b34，b33 X3 第 1、3、5、7 則：R3 只在別的主機上這樣判，文章站上
    /// 仍以標題與網址的一般字樣判——同站 PDF 的文章標題 `A Survey of CAPTCHA Design` 得 8、`Analysis of unusual traffic patterns` 得 6）。
    /// 一般的訊號字詞、路徑與標題的登入／驗證長相都**不看**（使用者 2026-10-02：PDF 交給人），只看三件封閉的事，依序：
    /// 1. 網址在已知的驗證服務上（`isKnownVerificationService`）：照訊號處理（等人驗證或整批暫停）；沒有訊號也整批暫停——那是驗證服務的頁面，
    ///    而它讀不到。
    /// 2. **主機**是登入主機的長相（`BotSignals.hostLoginLook`：最左邊的標籤、或 IdP 服務的名稱）→ 整批暫停（使用者 2026-10-02：登入頁維持
    ///    整批暫停；PDF 不從 IdP 主機出來）。只看主機，路徑與標題不看（`/auth/12345.pdf`、`Login behaviour in …`）。
    /// 3. 標題與網址帶著驗證服務自己的標記（`BotSignals.serviceMarker`，封閉的六個標籤）：照訊號處理（文章站上的人類檢查是等人驗證；
    ///    其他主機一律整批暫停）。
    /// 其他 → 交給人（`unverifiable`），訊息說讀不到、什麼都沒檢查。判斷用同一次 `documents` 的（網址，標題）；那一下網址不是 `url` 就回 nil，
    /// 回去等。
    private func judgeUnreadable(_ url: String, _ site: String) -> Stop? {
        guard let snap = tabSnapshot(), snap.url == url else { pageChanges += 1; return nil }
        let context = sameSite(url, site) ? "" : "→ \(FulltextFetch.plainURL(url))"
        if BotSignals.isKnownVerificationService(url: url) {
            if let hit = BotSignals.classify(snap.title + "\n" + url) { return stop(for: hit, site, context: context, at: url) }
            return botStop("page-unreadable on a known verification service \(context): could not check it", site)
        }
        if BotSignals.hostLoginLook(url) {
            return botStop("page-unreadable on a host with the look of a login page → \(FulltextFetch.plainURL(url)) (login page)", site)
        }
        if let hit = BotSignals.serviceMarker(snap.title + "\n" + url) { return stop(for: hit, site, context: context, at: url) }
        return handover(.unverifiable, at: url)
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
        }
        try openOwnTab(o.landing)
        let landed = try settleLanding()
        try checkTheArticlePage(url: landed.url, site: landed.site)
        try followThePagesOwnLink(site: landed.site, ledger: ledger)
    }

    /// 文章站的頁面（DOI 落地頁、導航之前的接續）：起疑訊號與網址的長相。只看網址：落地頁的標題是文章標題，標題片語在這裡只會誤判。
    ///
    /// 順序（#613 R3，b31 W4 第 2、13 則）：
    /// 1. **登入頁的長相先判**（EZproxy、SAML、IdP 把 DOI 帶在查詢字串裡的那一種）→ 整批暫停（使用者 2026-10-02：登入頁維持整批暫停）。
    ///    先前訊號排在前面：登入頁的文字提到 CAPTCHA 時得 8、印出以登入主機為「文章站」的 `resume:`——登入頁的網址是比頁面文字更強的證據，
    ///    而頁面文字是那個主機寫的。
    /// 2. 起疑訊號（`botCheckPage`）：文章站上的 CAPTCHA 是等人驗證。
    /// 3. **驗證頁的長相後判**：文章站自己的 CAPTCHA 頁常在 `/captcha/` 之類的路徑上（Optica 2026-09-28），它的訊號先得 8；沒有訊號而網址是
    ///    驗證頁的長相才整批暫停。
    ///
    /// 第 2、3 步看的是**判的那一頁**的網址（`botCheckPage` 的快照，#613 b34）：讀的當中分頁在文章站上換了頁，判的是新的那一頁——第 1 步
    /// 對那一頁同樣先判（`botCheckPage` 的 `beforeNavigation`，b37）：換到的若是同站的登入頁，頁面文字的 CAPTCHA 不把它降成等人驗證。
    private func checkTheArticlePage(url: String, site: String) throws {
        if BotSignals.urlGateLook(url) == "login" {
            throw botStop("the article page has the look of a login page → \(FulltextFetch.plainURL(url)) (login page)", site)
        }
        let judged = try botCheckPage(site, beforeNavigation: true)
        if let gate = BotSignals.urlGateLook(judged) {
            throw botStop("the article page has the look of a \(gate) page → \(FulltextFetch.plainURL(judged)) (\(gate) page)", site)
        }
    }

    /// 等頁面落定：越過 doi.org，DOM 越過 "loading"。插頁可以在文章頁取代它之前就回報 readyState=complete，所以真正的關卡是下一步
    /// （PDF 連結出現），不是這一步。60 秒沒落定算「卡住的回應」——中止條款，不是重試。回（文章站的 origin，落地頁的網址）。
    ///
    /// 「還在 doi.org」看的是**主機**（`isDOIResolver`），不是網址字串裡有沒有 `://doi.org/`（#613 R2 verify 第 9、20 則：把 DOI 帶在查詢
    /// 字串裡的登入頁、或任何網址裡提到 doi.org 的頁面，都被當成 doi.org）。
    private func settleLanding() throws -> (site: String, url: String) {
        var final = ""
        let start = now()
        for poll in 1...30 {
            if poll > 1, now().timeIntervalSince(start) >= FulltextFetch.settleSeconds { break }
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
    /// 接不回去（R2 verify 第 17 則）。登入／驗證頁的長相同樣整批暫停。還在載入是卡住（整批暫停）。停在 doi.org 卻看不到它自己的查無證據
    /// 整批暫停是使用者 2026-10-05 第 1 則的裁決（對 2026-10-01 裁決的收窄，以它為準）。
    ///
    /// 標題、頁面文字與交給人時印的網址是**同一份快照**（`readPage`，#613 b34）：讀的當中分頁離開了 doi.org 就不判——那一頁是誰的已經說不準，
    /// 整批暫停。
    private func stillOnTheDOIResolver(_ u: String) throws -> Never {
        let site = origin(u)
        let here = "→ \(FulltextFetch.plainURL(u))"
        let rs = browser.run(["js"] + lock + [FulltextFetch.readyStateJS]).value
        guard rs == "complete" || rs == "interactive" else { throw botStop("page did not settle in 60 s (stalled) \(here)", site) }
        guard let snap = readPage(accept: { FulltextFetch.isDOIResolver($0) }) else {
            throw botStop("the tab was still on doi.org after 60 s and changed page while it was being read \(here): could not check it", site)
        }
        guard let page = snap.page else {
            throw botStop("page-unreadable on doi.org \(here): could not check it for suspicion or for doi.org's own not-found page", site)
        }
        if let hit = BotSignals.classify(snap.title + "\n" + snap.url + "\n" + page.text, status: page.status) {
            throw botStop("\(hit.label) on doi.org \(here) — doi.org is not the article site, so this cannot be resumed", site)
        }
        if let gate = BotSignals.gateLook(url: snap.url, title: snap.title) { throw botStop("doi.org showed a page with the look of a \(gate) page \(here) (\(gate) page)", site) }
        guard FulltextFetch.isDOINotFound(title: snap.title, text: page.text, status: page.status) else {
            throw botStop("the tab stayed on doi.org for 60 s without doi.org's own not-found page (offline, or the resolver did not answer) \(here)", site)
        }
        throw handover(.doiNotResolved, at: snap.url)
    }

    /// 等人驗證之後，在同一個分頁接著走（使用者 2026-10-01：不重新載入文章頁；2026-10-02：接著走**同一步**）。
    ///
    /// - `article`（導航到 PDF 連結之前的驗證）：分頁必須還顯示文章站；接著讀頁面的連結、記一次嘗試、導過去。
    /// - `followed`（導航到 PDF 連結**之後**的驗證）：嘗試已經記過、已經導航過——**不讀連結、不導航、不記嘗試**，回到「分頁顯示什麼」
    ///   的判斷（PDF → 交給人；HTML 閱讀器 → 交給人）。分頁此刻可以在別的主機（PDF 放在另一個主機，驗證完瀏覽器把分頁帶過去），所以
    ///   這一步不要求分頁顯示文章站；它只讀分頁、不導航、不關分頁。但分頁要是這三種之一：文章站（`--resume-origin`）、已知的驗證服務、
    ///   或此刻顯示 PDF——其他分頁（使用者驗證時開關分頁，位置漂移到他自己的信箱或銀行）拒絕（結束碼 1）。判斷 PDF 只讀
    ///   `document.contentType`，不讀那個分頁的文字（#613 R2 verify 第 12、16、19、21 則：先前只要網址非空就對它跑讀頁文字的 JS）。
    /// - `article` 的順序（#613 b34，b33 X3 第 0、21 則）：主機是登入主機的長相 → 整批暫停，不送任何 JS；然後與導航之後同一套讀法
    ///   （`watchOnSite`）——分頁顯示 PDF → 交給人（舊的呼叫端沒帶 `--resume-stage`，驗證發生在導航之後；**PDF 先於路徑的登入長相**，
    ///   `/auth/12345.pdf` 不整批暫停）；讀不到 → `judgeUnreadable`；落定的網頁 → 判的是**分頁此刻的網址**（先前用接續開始時讀的舊網址）：
    ///   路徑的登入長相 → 整批暫停、起疑訊號 → 8 或 6、驗證頁的網址而沒有訊號 → 使用者說驗證完了而頁面還在轉址，**等它轉走**（只讀分頁網址、
    ///   不送 JS，與等落定同一個約 60 秒），轉走了照常往下走、沒轉走整批暫停。
    private func resume(tab position: Int, origin expected: String, stage resumeStage: ResumeStage, ledger: FulltextAttemptLedger) throws -> Never {
        guard let t = tab(String(position)) else {
            err("✗ window \(window) has no tab \(position) — the tab may have moved; find the one showing \(displaySafeInvisible(expected, max: 300)) with `safari-browser documents --json --profile <P>`")
            throw Stop(code: 1)
        }
        ownTab = String(position)
        stage = resumeStage
        switch resumeStage {
        case .followed:
            guard !t.url.isEmpty else {
                ownTab = ""   // 沒有人確認過那是我們的分頁（b31 W4 第 21 則：與下面兩個拒絕同樣不叫它「我們的分頁」）
                throw fail("window \(window) tab \(position) shows nothing — not resuming there.")
            }
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
            // 主機是登入主機的長相：不往那個分頁送任何 JS（PDF 不從 IdP 主機出來）
            if BotSignals.hostLoginLook(t.url) {
                throw botStop("the tab shows a page on a host with the look of a login page → \(FulltextFetch.plainURL(t.url)) (login page)", site)
            }
            try watchOnSite(site, stalled: "the tab did not settle after the check (stalled)") { url in
                if BotSignals.urlGateLook(url) == "login" {
                    return .stop(self.botStop("the tab shows a page with the look of a login page → \(FulltextFetch.plainURL(url)) (login page)", site))
                }
                let judged = try self.botCheckPage(site, beforeNavigation: true)   // 讀的當中換到登入頁 → 6；還在驗證頁 → 8；別的訊號 → 6
                switch BotSignals.urlGateLook(judged) {
                case "login":
                    return .stop(self.botStop("the tab shows a page with the look of a login page → \(FulltextFetch.plainURL(judged)) (login page)", site))
                case "verification":
                    return .waitForTheURLToChange(judged)
                default:
                    try self.followThePagesOwnLink(site: site, ledger: ledger)
                }
            }
        }
    }

    /// 讀頁面自己的 PDF 連結、記一次嘗試、把同一個分頁導過去、交給人。
    private func followThePagesOwnLink(site: String, ledger: FulltextAttemptLedger) throws -> Never {
        try siteGuard(site)
        _ = browser.run(["wait"] + lock + ["--js", FulltextFetch.hasLinkJS, "--timeout", "45000"])
        try siteGuard(site)
        try botCheckPage(site, beforeNavigation: true)   // 插頁在我們等的時候可以變成挑戰頁或登入頁
        try siteGuard(site)
        let linkRun = browser.run(["js"] + lock + [FulltextFetch.linkJS])
        if linkRun.status != 0 { throw fail("could not read the page's links: \(FulltextFetch.safariFailure(linkRun.stderr))") }
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
        // （不是網站起疑，是頁面給了一個不能照做的連結）：結束碼 1，分頁留著。站的比對看主機與埠號、不看帳密（與 `sameSite` 同一把，#613 b34，
        // b33 X3 第 6、23 則：先前連結的 origin 帶帳密而站的不帶，帶帳密的落地頁上同站的相對連結永遠被拒，訊息還把帳密印出來）。
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
        // 帳本的 landing 也不帶查詢與路徑參數（b33 X3 第 14 則；它不參與計數，只是記錄）
        do { reservation = try ledger.reserve(site: host, landing: FulltextFetch.plainURL(landing), at: at) } catch { throw fail("\(displaySafeErrorText(error))") }
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
        if navigation.status != 0 { throw fail("could not navigate the tab to the PDF link: \(FulltextFetch.safariFailure(navigation.stderr))") }
        try awaitShown(site: site, before: before)
    }

    /// 導航之後：等分頁離開文章頁（20 秒），再看它顯示什麼。分頁沒離開：檢查起疑訊號（同一份快照）——判的那一頁還是導航之前的那一頁才是
    /// `tab-unchanged`；檢查的當中換了頁就照「分頁顯示什麼」判（b33 X3 第 8 則的同一個形狀：先前交給人時才讀網址，印的是換過去的那一頁）。
    private func awaitShown(site: String, before: String) throws -> Never {
        var moved = false
        for _ in 1...10 {
            nap(2)
            let u = tabURL(ownTab)
            if u.isEmpty || u != before { moved = true; break }
        }
        try siteGuard(site)   // 分頁不見了 → 6；到了別的主機 → 照 `leftSite`（PDF／沒有標記的頁面交給人，訊號與登入頁停）
        if !moved {
            let judged = try botCheckPage(site, beforeNavigation: false)
            if judged == before { throw handover(.tabUnchanged, at: judged) }
        }
        try decideShown(site: site)
    }

    /// 分頁顯示什麼：PDF → 交給人；HTML 頁落定 → 查訊號（同一份快照）、交給人；讀不到 → `judgeUnreadable`。導航之後的判斷與等人驗證之後
    /// 接著走（`resume --resume-stage followed`）是同一段——驗證完不重新讀連結、不再導航。
    private func decideShown(site: String) throws -> Never {
        try watchOnSite(site, stalled: "the tab did not settle after following the PDF link (stalled)") { url in
            guard let snap = self.readPage(accept: { $0 == url }) else { return .retry }
            if let stop = self.onSiteSuspicion(snap, site) { return .stop(stop) }
            return .stop(self.handover(.htmlPage, at: snap.url))
        }
    }

    /// `watchOnSite` 對一個落定的網頁下的判斷。
    private enum OnSiteVerdict {
        case stop(Stop)
        /// 讀的當中換了頁：回去等
        case retry
        /// 分頁停在這個網址等它轉走：之後只讀分頁網址、不送 JS，網址變了才再看
        case waitForTheURLToChange(String)
    }

    /// 等分頁在文章站上給出一個屬於**同一個網址**的回答（#613 b34，b33 X3 第 2、4、8 則：R3 只在別的主機上這樣讀，文章站上一次讀分頁顯示什麼、
    /// 讀不到累積計數、判完再讀網址印出來）。導航之後（`decideShown`）與導航之前的接續（`resume` 的 `article`）同一套：
    /// - 每一次輪詢先過 `siteGuard`（分頁到了別的主機照 `leftSite` 判、不見了 → 6）；讀之前與之後的網址相同，這個回答才屬於那個網址。
    /// - PDF → 交給人（`pdf-shown`，印那個網址）。
    /// - 讀不到 → 同一個網址連三次、那裡從沒讀到過一般網頁才算（`UnreadableTally`），照 `judgeUnreadable` 判（與別的主機同一套）。
    /// - 落定的網頁 → `consider`。
    /// 約 60 秒（時鐘）沒有結果 → 卡住，整批暫停；停在等它轉走的網址上 → 整批暫停，訊息說是驗證頁的網址。
    private func watchOnSite(_ site: String, stalled: String, consider: (String) throws -> OnSiteVerdict) throws -> Never {
        let start = now()
        var tally = UnreadableTally()
        var holding: String?   // 等它轉走的網址
        pageChanges = 0
        for poll in 1...30 {
            if poll > 1, now().timeIntervalSince(start) >= FulltextFetch.settleSeconds { break }
            try siteGuard(site)
            if let h = holding {
                if tabURL(ownTab) == h { nap(2); continue }
                holding = nil
            }
            let before = tabURL(ownTab)
            let shown = browser.run(["js"] + lock + [FulltextFetch.shownJS])
            let url = tabURL(ownTab)
            if url.isEmpty || url != before || !sameSite(url, site) { tally.moved(); nap(2); continue }   // 換頁中：下一輪 `siteGuard` 再看
            if shown.status == 0, FulltextFetch.contentTypeIsPDF(shown.value) { throw handover(.pdfShown, at: url) }
            if shown.status != 0 || FulltextFetch.isUnreadableShown(shown.value) {
                // 空的或 `undefined` 的回答（對非 HTML 文件跑 `do JavaScript` 的可能結果）與失敗同樣算「讀不到」，不是「還在載入」
                if tally.unreadable(at: url), let stop = judgeUnreadable(url, site) { throw stop }
            } else {
                tally.answered(at: url)
                if FulltextFetch.isSettled(shown.value) {
                    switch try consider(url) {
                    case .stop(let stop): throw stop
                    case .retry: break
                    case .waitForTheURLToChange(let u): holding = u
                    }
                }
            }
            nap(2)
        }
        if let h = holding {
            throw botStop("the tab stayed on a page with the look of a verification page after the check → \(FulltextFetch.plainURL(h)) (verification page)", site)
        }
        throw botStop("\(stalled)\(pageChangesNote) → \(FulltextFetch.plainURL(tabURL(ownTab)))", site)
    }

    // MARK: 純函式（測試直接呼叫）

    /// 帳本用的站名：origin 的主機（加埠號），小寫，不帶帳密（b31 W4 第 16 則：先前是整個 netloc，帳密以小寫寫進帳本）。
    static func siteKey(_ origin: String) -> String { URLSplit(origin).hostPort.lowercased() }

    /// 網址去掉會帶憑證的部分，才印進 stdout、stderr 與 `origin`：查詢與片段（簽章網址的短效憑證、SSO 的票）、主機前的帳密（`user:pw@`，
    /// 含沒有 scheme 的 `//u:p@h/…`）、路徑上 `名=值` 形狀的路徑參數（`;jsessionid=…`、`;sid=…`、`;PHPSESSID=…`，以及百分比編碼的
    /// `%3Bjsessionid%3D…`）與 ASP.NET 無 cookie session 的整段（`/(S(…))/`、`/(A(…)F(…))/`、`/(S(…))(F(…))/`）
    /// （#613 R2 verify 第 11、15、18、22、33 則；R3＝b31 W4 第 17 則；b34＝b33 X3 第 12、13、24 則：百分比編碼、多個 ASP.NET 群組、沒有 scheme
    /// 的帳密）。以 Unicode scalar 找 `?`／`#`：`?` 後面接組合字元時，以 `Character` 找會找不到。
    ///
    /// **不剝**沒有 `=` 的 `;…`：SICI 式 DOI（`…3.0.CO;2-0`）的 `;2-0` 是文件身分的一部分。**也不剝一般的路徑段**：路徑裡的不透明字串
    /// （`/dl/<token>/file.pdf`、分享連結的 id）與 DOI、檔案 id 分不出來，原樣印出——那是這份形狀清單管不到的一半。
    ///
    /// **代價**：查詢字串本身就是文件身分的網址（`viewcontent.cgi?article=…`、`doiLanding?doi=…`）在 `origin` 裡也少了那一段——只剝
    /// 已知的憑證參數要一份會漏的清單，這裡選擇全剝（R2 verify 第 22 則，留給使用者裁決）；路徑參數同理，`;type=pdf` 也剝。
    ///
    /// **主機段與站的比對同一把**（#613 b37，b36 Y2 第 11、20、21 則）：scheme、authority 與路徑由 `URLSplit` 切，印出的主機是
    /// `URLSplit.hostPort`——在反斜線處結束、去掉最後一個 `@` 之前的帳密。先前這裡自己切：authority 只在 `/` 結束、`://` 在整串裡找，
    /// `https://evil.example\@pub.example/x` 印成 `pub.example` 而站的比對是 `evil.example`，`//u:p@h/a/https://z/q` 的帳密原樣印出。
    /// authority 裡反斜線之後到第一個 `/` 的那一段不印（它不是主機也不是路徑的一部分，`evil.example\@pub.example` 的 `pub.example` 印出來
    /// 只會讓人讀錯主機）。scheme 照 `URLSplit` 轉小寫。
    static func plainURL(_ url: String) -> String {
        var s = url
        if let cut = s.unicodeScalars.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            s = String(String.UnicodeScalarView(s.unicodeScalars[..<cut]))
        }
        let parts = URLSplit(s)
        guard parts.hasAuthority else { return withoutPathParameters(s) }
        let head = parts.scheme.isEmpty ? "//" : PyText.string(parts.scheme) + "://"
        return head + parts.hostPort + withoutPathParameters(parts.path)
    }

    /// 路徑的每一段去掉 `;名=值`（`;`、`=` 也可以是百分比編碼的 `%3B`、`%3D`），丟掉 ASP.NET 的 `(X(…))` 整段（一段裡可以有幾個群組、
    /// 也可以連著幾組）；一段因此變空（而它原本不是空的）就整段丟掉。
    private static func withoutPathParameters(_ path: String) -> String {
        let param = try! NSRegularExpression(pattern: #"(?:;|%3[Bb])(?:(?!%3[BbDd])[^;=/])+(?:=|%3[Dd])(?:(?!%3[Bb])[^;/])*"#)   // 編譯期常數
        let aspNetSession = try! NSRegularExpression(pattern: #"^(?:\((?:[A-Za-z]\([^()/]*\))+\))+$"#)
        var kept: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            let range = NSRange(segment.startIndex..., in: segment)
            if aspNetSession.firstMatch(in: segment, range: range) != nil { continue }
            let stripped = param.stringByReplacingMatches(in: segment, range: range, withTemplate: "")
            if stripped.isEmpty, !segment.isEmpty { continue }
            kept.append(stripped)
        }
        return kept.joined(separator: "/")
    }

    /// safari-browser 失敗時轉印它 stderr 的**第一行**（第一個非空行），裡面的網址過 `redactingURLs`；其餘的行不轉印，只說有幾行沒印
    /// （#613 b37，b36 Y2 第 1 則：`documentNotFound` 從第三行起列出**所有**視窗的目前分頁——含使用者其他 profile 的 session，這個命令沒帶
    /// `--profile`，那份清單不過濾；`targetTabChanged` 的第二行是那個位置此刻顯示的網址。網址去掉查詢字串之後，主機與路徑仍在）。
    /// safari-browser 每一種錯誤的第一行說的是**我們的目標**（`No Safari document matches "window 5 tab 2".`），所以診斷用的那一句還在；要看
    /// 完整訊息，人自己跑同一個 safari-browser 命令。`open:`、讀連結失敗、導航失敗三處都走這裡。行以 `Character.isNewline` 切（`\r\n` 是一個
    /// `Character`）。
    static func safariFailure(_ stderr: String) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return "(safari-browser printed no message)" }
        let rest = lines.count - 1
        guard rest > 0 else { return redactingURLs(first) }
        return redactingURLs(first) + " (\(rest) more line\(rest == 1 ? "" : "s") from safari-browser not shown: \(rest == 1 ? "it" : "they") can list other tabs and profiles)"
    }

    /// 文字裡的每一個網址先過 `plainURL`（b33 X3 第 12、24 則：`open:`、導航失敗、讀連結失敗三處先前原樣轉印 safari-browser 的 stderr，
    /// 回顯的簽章網址會帶著查詢字串出去）。b37 起只用在 `safariFailure` 取出的第一行。
    static func redactingURLs(_ text: String) -> String {
        let re = try! NSRegularExpression(pattern: #"(?i)(?<![A-Za-z0-9+.-])[a-z][a-z0-9+.-]*://[^\s"'<>]+"#)   // 編譯期常數
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += plainURL(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
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

    /// 頁面給的 PDF 連結的 origin（`https://主機[:埠號]`，小寫，**不帶帳密**）；不是「可以照字面比 origin 的絕對 https 網址」就回 nil＝拒絕。
    ///
    /// **只收 `linkJS` 在頁面裡解析好的絕對網址**（#629 R2 verify 第 0、9、12、20 則）：開頭必須是 `https://`；整串不得有反斜線、
    /// 空白或控制字元（WHATWG 序列化出來的網址不會有）；`://` 之後到第一個 `/?#` 的主機段不得是空的。埠號照字面比（與不帶的是不同的站）。
    /// **帳密不比也不印**（#613 b34，b33 X3 第 6、9、23 則）：站的 origin（`siteOrigin`）不帶帳密，連結的也不帶——帶帳密的落地頁上，相對連結
    /// 經 WHATWG 解析沿用 base 的帳密，先前兩邊永遠不等，同站的 PDF 連結被拒、訊息把帳密印出來。
    static func linkTargetOrigin(_ url: String) -> String? {
        guard url.lowercased().hasPrefix("https://"),
              !url.unicodeScalars.contains(where: { $0 == "\\" || $0.value < 0x21 || (0x7F...0x9F).contains($0.value) || $0.properties.isWhitespace })
        else { return nil }
        let hostPort = URLSplit(url).hostPort
        guard !hostPort.isEmpty else { return nil }
        return "https://\(hostPort)".lowercased()
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
