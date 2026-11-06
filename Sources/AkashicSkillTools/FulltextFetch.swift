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
///     9 這個站今天已經 10 次嘗試（Asia/Taipei）：停這個站，隔天再跑。沒有導航到 PDF。分頁留著。
///     6 **整批暫停**（SKILL.md〈中止條款〉）：其他起疑訊號——封鎖頁、HTTP 403／429、異常流量、PMC 的下載前驗證頁、ScienceDirect
///       的「Preparing your download」、其他主機上的驗證字樣、分頁跑到別的網站而那一頁是登入／驗證頁的長相、DOI 落地頁的網址是登入頁
///       的長相、讀不到的分頁停在登入主機的長相上（只看主機）、卡住（落地頁、導航之後、別的主機上的頁面約 60 秒沒落定）、停在 doi.org
///       卻看不到它自己的查無證據（使用者 2026-10-05 第 1 則）、落定的網頁讀不到頁面文字而無從檢查（導航之前的文章頁、導航之後文章站上
///       落定的 HTML 頁、別的主機上落定的頁面；連 `document.contentType` 都讀不到的分頁是 7 `unverifiable`）。分頁留著給使用者看。
///     3 頁面上找不到 PDF 連結。分頁留著：這個命令不關任何分頁（#768）
///     1 自動化失敗（見 stderr）；或頁面給的 PDF 連結不是同站的絕對 https 網址（`points off-site`）；或帳本讀不懂；或對不上我們的分頁
///       （`cannot find the tab just opened`、`went to another Safari window`、`the tabs in window <N> changed…`，#768：使用者正在動那個視窗）；
///       或判過之後頁面換了（`the page changed after it was checked`：PDF 連結不是從判過的那一頁讀來的，不導航）；
///       或有別的 profile 的視窗（或讀不出 profile 的視窗）開著（`a Safari window of another profile`；開頭、接續與 `ownTabNow` 的每一眼都判，
///       每一眼只看開頭沒有的視窗；safari-browser#352 以視窗 id 指定視窗之前不放寬）
///
/// **沒有結束碼 0**：這個命令的正常終點就是交給人。先前的 0（「取得並驗證」）、2（回應不是 PDF）、4（無權限的登入殼）、5（驗證不過）
/// 都跟著取位元組一起離開這個命令——2 與 5 在 `take`，4 由看分頁的人判斷。舊的呼叫端把 0 當成「檔案存好了」，新的碼不會被它讀錯。
///
/// # 鎖分頁（#768）
///
/// 分頁以落地網址上的一次性記號（`#akashic-` 加 16 個十六進位數字）認。記號在時以 `--profile <P> --url-endswith '#akashic-…'` 鎖——
/// `web-access-via-safari-browser.md` 的形狀，記號就是那個 suffix；**一定帶 `--profile`**：safari-browser 的 `open` 不把 `--url-endswith`
/// 當成指定了分頁，只帶它會在前景視窗開新分頁（safari-browser#233，第三輪 verify）。記號不在時（Elsevier 的轉址丟掉它、頁面用腳本轉走）
/// 退回 `--window N` 加位置（`--tab-in-window`，`ownTabNow` 剛確認過），規則檔〈例外〉形狀 (b)。`--resume-tab` 帶了 `--resume-mark` 時先以
/// 記號找分頁，找不到才照位置；另外要求那個分頁此刻顯示：導航之前的接續（`article`）是 `--resume-origin`；
/// 導航之後的接續（`followed`）是 `--resume-origin`、已知的驗證服務、或 PDF（只讀 `document.contentType` 判斷，不讀頁面文字）——
/// 使用者驗證時把視窗拉到前面，視窗編號會變；對不上就停（結束碼 1），不猜是哪一個分頁。**`--resume-origin` 是呼叫端給的**：接續時
/// 「文章站」就是它，主機的判斷信任這個參數。
///
/// **仍沒有的**：真的 Safari 只跑過兩次（2026-11-04：SAGE 找不到連結、Elsevier 接續之後導航到 PDF），記號還在時的導航沒有實跑；Safari 的
/// PDF 檢視器能不能執行頁面 JS、`document.contentType`
/// 在那裡回什麼、`PerformanceNavigationTiming.responseStatus` 在 Safari 有沒有值，都沒有實測——讀不到時照「無從檢查」處理（交給人或暫停），
/// 不當成乾淨。
///
/// # 契約版本
///
/// `contractVersion` 是這個命令（與 `take`）對 skill 的契約版本，`akashic fulltext contract` 印它；SKILL.md 第 0 步要求至少這個值（#613 R3，
/// b31 W4 第 1 則：先前以 `take` 的行為探測，分不出 R1、R2 的 CLI）。結束碼、交給人的原因、或哪些頁面整批暫停改變時就往上調，SKILL 第 0 步
/// 一起調（`SkillToolsCLITests` 比對兩邊相等）。
///
/// **印出的字改了要不要調，還沒有定**（b40 Z2 第 4、9、13、15 則）：b37 為了 safari-browser 的錯誤只轉印一行而從 5 調到 6；b39 與 b41 又改了
/// 同一類（轉印哪一行、對話框的文字不轉印、帳密的邊角），契約仍是 6。理由：`akashic` CLI 從來沒有發布過——release 只發 `akashic-mcp`
/// （`akashic-mcp-v0.12.1`，2026-09-24，早於 `fulltext` 子命令），CLI 要在本 repo `swift build`——所以「印 6 而行為是 b37 的」只會是維護者
/// 自己 b37～b39 之間的建置，沒有使用者面。第一次發布 CLI 時一起決定：升到 7，或把「印出的字改了不調」寫成這裡的政策（那時要說明 b37 為什麼例外）。
public final class FulltextFetch {
    /// 1＝#613 只導航、交給人；2＝R1 修正輪（2026-10-02）；3＝R2 修正輪（e5182cf1）；4＝R3（2026-10-04）；5＝b34（2026-10-05：文章站上
    /// 讀不到的分頁與別的主機同一套、讀不到的分頁在登入主機上整批暫停、文章站上同一份快照、使用者 2026-10-05 的主機標籤與路徑段裁決）；
    /// 6＝b37（2026-10-09：複合路徑段只認明確的登入字、讀的當中換到同站登入頁先判登入長相、safari-browser 的錯誤只轉印第一行、`plainURL`
    /// 與站的比對同一個主機；b39 起轉印 `Error:` 那一行、b41 起 stderr 有對話框的訊息時只轉印固定的一句——兩次都沒有調，理由見上面〈契約版本〉）。
    /// 7＝#768 第一到第四版（2026-11-03～04）：分頁的認法逐版在改（比對清單、記號）。調它是為了讓第 0 步擋下會讀、會關使用者分頁的舊 CLI；這幾版
    /// 本身也不可使用（第一版還會關分頁，第三版導航時會在前景視窗開出新分頁）。
    /// 8＝#768 第五版起（2026-11-04～05）：記號鎖帶 `--profile`、別的 profile 的視窗開著就停（開頭、接續、每一眼）、頁面文字這類讀取的鎖找不到分頁時
    /// 重跑一次、PDF 連結的答案綁在判過的那一頁上、接續可帶 `--resume-mark`。第五到第七版的開發建置也印 8 而行為不同（第五版有版本閘、第六版接續
    /// 不判別的 profile、讀連結會重跑），都沒有發布（CLI 沒有發布版），第 0 步分不出來：CLI 從合併之後的 commit 建置。
    /// 前三版的 CLI 沒有 `contract` 子命令——數字只是給歷史一個名字，第 0 步擋它們靠的是「沒有這個子命令」。
    public static let contractVersion = 8

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
        /// 停在等人驗證的那一次執行的記號（結束碼 8 的 `resume:` 一行有印才有）：接續時先找網址以它結尾的分頁，找不到才照位置（#768 第三輪 verify
        /// 第 7 則）。
        public var resumeMark: String?
        public init(window: Int, landing: String, ledger: String, expectProfile: String? = nil,
                    resumeTab: Int? = nil, resumeOrigin: String? = nil, resumeStage: ResumeStage = .article, resumeMark: String? = nil) {
            self.window = window; self.landing = landing; self.ledger = ledger; self.expectProfile = expectProfile
            self.resumeTab = resumeTab; self.resumeOrigin = resumeOrigin; self.resumeStage = resumeStage; self.resumeMark = resumeMark
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
    /// 這個視窗所有分頁的網址（依位置）：最後一次確認 `ownTab` 還是我們的分頁時看到的。下一眼拿來比（`ownTabNow`，#768）。
    private var lastTabs: [String] = []
    /// 我們的視窗（`documents --json` 的 `blocking_dialog.window_id`）。`--window` 的編號是前後順序，這個才是穩定的；每一眼都以它找回視窗的編號（#768）。
    private var ownWindowID: Int?
    /// 這次執行的記號（`akashic-` 加 16 個十六進位數字），開分頁時加在落地網址後、導航到 PDF 連結時也帶著（#768，使用者 2026-11-04 選定）。
    /// fragment 不送伺服器，HTTP 轉址會保留它，所以網址結尾是它的分頁就是我們的分頁（例外：記號不見之後以位置鎖導航回來的，要在我們的位置上才算，見 `ownTabNow`）。2026-11-04 在 Safari 量到：SAGE、Wiley、Springer、APA、
    /// Taylor & Francis 轉址後還在，Elsevier 在授權轉址（id.elsevier.com）時丟掉。頁面的腳本看得到它：這是接受了的代價。
    /// 接續（`--resume-mark`）時換成上一次執行的記號。
    private var mark: String
    private var markSuffix: String { "#" + mark }
    /// 上一眼有一個分頁帶著記號：指令改用 `--profile`＋`--url-endswith` 鎖分頁。`js`、`wait` 在同一段 AppleScript 裡重驗目標；`open` 不重驗：
    /// 它先解析記號、再以另一個 Apple event 導航那個分頁（safari-browser 的 `openURL`）。
    private var markSeen = false
    /// 這一站的嘗試已經記進帳本：之後停下要說已經算了。
    private var attemptCounted = false
    /// 開了新分頁、還沒認出是哪一個：失敗訊息要提醒有一個分頁可能留著。
    private var openedUnidentified = false
    private var landing = ""
    /// 目前走到哪一步；等人驗證時印進 `--resume-stage`（導航到 PDF 連結之後是 `followed`）。
    private var stage: ResumeStage = .article

    public init(browser: SafariBrowser, sleeper: @escaping (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
                now: @escaping () -> Date = Date.init,
                out: @escaping (String) -> Void, err: @escaping (String) -> Void, mark: String = FulltextFetch.newMark()) {
        self.browser = browser; self.sleeper = sleeper; self.now = now; self.out = out; self.err = err; self.mark = mark
    }

    /// 一個新的記號：`akashic-` 加 16 個十六進位數字。
    public static func newMark() -> String {
        var g = SystemRandomNumberGenerator()
        return "akashic-" + String(format: "%016llx", g.next() as UInt64)
    }

    /// `--resume-mark` 的值不是 `newMark()` 的形狀：回原因，是就回 nil。
    public static func markShapeProblem(_ value: String) -> String? {
        let hex = value.hasPrefix("akashic-") ? value.dropFirst("akashic-".count) : ""
        guard hex.count == 16, hex.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else {
            return "expected akashic- followed by 16 lowercase hexadecimal digits"
        }
        return nil
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
    /// `note`：另起一行的說明（`safariFailure` 的「其餘幾行沒轉印」）。不接在 `message` 後面：`message` 截在 600 字，接在後面的說明會在
    /// 第一行很長時被截掉（#613 b39，b38 Z2 第 5 則）。
    private func fail(_ message: String, note: String? = nil) -> Stop {
        err("✗ \(displaySafeInvisible(message, max: 600))")
        if let note { err("  \(displaySafeInvisible(note, max: 600))") }
        // SKILL 以這一行判斷算了沒（沒寫的沒算）：記進帳本之後的每一條失敗都要印（第三輪 verify 第 6、20 則：先前只有 `lostOwnTab` 印）
        if attemptCounted || stage == .followed { err("  This site's attempt for today is already counted.") }
        if !ownTab.isEmpty { err("  our tab (window \(window), tab \(ownTab)) is left open — look at it before retrying.") }
        if ownTab.isEmpty, openedUnidentified { err("  A new tab was opened and may be left open (its address ends with \(markSuffix)); ask the user to close it.") }
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
        // 記號還在：接續時以它找分頁（分頁移動了也找得到）。視窗編號是這一次最後看到的（執行當中可能變了，#768 第三輪 verify 第 21 則）
        let markFlag = markSeen ? " --resume-mark \(mark)" : ""
        err("  Nothing here solves or bypasses it. Continue only after the user says the check is done: the same command with --window \(window), plus --resume-tab \(ownTab) --resume-origin \(shownSite)\(stageFlag)\(markFlag), in the same tab.")
        err("  If the window came to the front its number may have changed: find the tab showing \(shownSite) with `safari-browser documents --json --profile <P>`.")
        out("resume: --resume-tab \(ownTab) --resume-origin \(shownSite)\(stageFlag) --window \(window)\(markFlag)")
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
        let url = snapshotURL ?? lastOwnURL
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
        let shownURL = snapshotURL ?? lastOwnURL
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
        var windowID: Int?
    }

    /// 讀不到清單就停，不回空的：空的清單會被讀成「分頁不見了」，而「不知道」不是「可以繼續」（#768）。
    private func docs() throws -> [Tab] {
        let r = browser.run(["documents", "--json"])
        guard r.status == 0, let root = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)), let items = root as? [[String: Any]] else {
            let f = FulltextFetch.safariFailure(r.stderr, command: "documents --json")
            throw fail("could not read Safari's tab list, so nothing more was read or navigated: \(f.line)", note: f.note)
        }
        let rows: [Tab] = items.compactMap { d in
            guard let w = FulltextFetch.int(d["window"]), let t = FulltextFetch.int(d["tab_in_window"]) else { return nil }
            return Tab(window: w, tabInWindow: t, url: (d["url"] as? String) ?? "", title: (d["title"] as? String) ?? "",
                       profile: d["profile"] as? String,
                       windowID: (d["blocking_dialog"] as? [String: Any]).flatMap { FulltextFetch.int($0["window_id"]) })
        }
        // safari-browser 把分頁標題不跳脫地接進以控制字元分隔的列舉（safari-browser#355），所以頁面可以用 `document.title` 寫出一列假的分頁，
        // 帶上它讀得到的記號：`ownTabNow` 認記號，導航就打到別的分頁（第八輪 verify 第 1 則）。假列刪不掉別的分頁的列，指向存在的分頁時通常
        // 與真的列同位置，所以同一個位置兩列就是這份清單不可信。視窗編號可以亂寫，safari-browser 以 id 解析分頁，所以兩種認法都比。
        // 比不到的形狀：我們的分頁是 current 時視窗名帶著標題，真列可能全都讀不到 id，一份帶對 id 的假列就不重複。擋住它的是頁面讀不到視窗 id（猜錯就
        // 走 `lostOwnTab`），不是這裡（第九輪 verify 第 9 則）。同一個視窗被讀兩次（列舉途中視窗被拉到前面）也是兩列，所以訊息兩種都說（第 1、7 則）。
        if FulltextFetch.hasDuplicatedPosition(rows.map { (window: $0.window, id: $0.windowID, tab: $0.tabInWindow) }) {
            throw fail("Safari's tab list has two entries for one tab position, so it cannot be trusted (a window raised while the list was read, or a page title forging an entry, safari-browser#355); nothing more was read or navigated.")
        }
        return rows
    }

    private static func int(_ any: Any?) -> Int? {
        if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        return nil
    }

    /// 同一個位置有兩列：以視窗編號認，或以視窗 id 認（id 讀不到的列只以編號認）。
    static func hasDuplicatedPosition(_ rows: [(window: Int, id: Int?, tab: Int)]) -> Bool {
        var byNumber = Set<[Int]>(), byID = Set<[Int]>()
        for row in rows {
            if !byNumber.insert([row.window, row.tab]).inserted { return true }
            if let id = row.id, !byID.insert([id, row.tab]).inserted { return true }
        }
        return false
    }

    /// 這個視窗的分頁，依位置排。
    private func tabsHere(_ all: [Tab]) -> [Tab] { all.filter { $0.window == window }.sorted { $0.tabInWindow < $1.tabInWindow } }

    /// 我們的分頁此刻的樣子，**先確認它還是我們的分頁**（#768）。
    ///
    /// 1. 有一個分頁的網址以記號結尾：那就是我們的分頁。它的位置與視窗編號跟著它走（左邊開關分頁、拖動、切換視窗都不必停）；兩個分頁帶著記號
    ///    （使用者複製了分頁）、或它在別的視窗，就停。例外：上一眼沒有記號，這一眼才帶著（以位置鎖導航帶回來的），那個分頁要在我們的位置上、位置
    ///    追蹤也要成立，否則是導航打到了使用者的分頁，記號在那個分頁上（第七輪 verify 第 2 則）。
    /// 2. 沒有分頁帶著記號：改用位置追蹤（`stillOurTab`），不論記號是轉址丟掉的（Elsevier）、頁面自己用腳本轉走時丟掉的、還是從沒出現過
    ///    （使用者 2026-11-04：記號不見時改用位置追蹤；第三輪曾在頁面落定之後改成停下，第三輪 verify 指出它把腳本轉到的登入、驗證頁從 6／8
    ///    變成 1，使用者裁決照原決定）。視窗一律以 id 找回編號。
    ///
    /// 對不上就停（`lostOwnTab`），不讀、不導航。**位置追蹤仍然不是證明**：確認與 JS 是兩個 Apple event，分頁剛好在兩者之間移動，那一段 JS
    /// 會打到別的分頁，只是答案不會被用；記號已經不在時（Elsevier），使用者在我們的分頁裡開別的網頁也分不出來。這就是這個命令不關分頁的原因。
    private func ownTabNow() throws -> Tab? {
        guard let position = Int(ownTab) else { return nil }
        let all = try docs()
        // 執行當中才開的別的 profile 的視窗：位置鎖可能打到它，停（第六輪 verify 第 8 則）。只看開頭沒有的視窗：開頭就在的視窗檢查過，它的 profile
        // 不會變，讀不出來只是載入中標題空白（第七輪 verify 第 4 則）
        if otherProfileWindowOpen(in: all.filter { $0.windowID.map { !windowsAtStart.contains($0) } ?? true }) {
            throw fail("a Safari window of another profile (or one whose profile cannot be read) was opened while this ran; a position-locked command could reach it, so nothing more was read or navigated. Ask the user: those windows have to be closed first, and only the user decides that.")
        }
        let mine = all.filter { $0.windowID == ownWindowID }.sorted { $0.tabInWindow < $1.tabInWindow }
        let marked = all.filter { $0.url.hasSuffix(markSuffix) }
        if !marked.isEmpty {
            guard marked.count == 1, let t = marked.first, t.windowID == ownWindowID else { throw lostOwnTab() }
            // 上一眼沒有記號：記號是我們以位置鎖導航帶回來的，所以它要在我們的位置上，而且位置追蹤要成立。否則導航打到了別的分頁（左邊開關分頁時
            // `--tab-in-window T` 指到使用者的分頁），記號在那個分頁上（第六輪 verify 第 6 則、第七輪 verify 第 2 則）
            if !markSeen {
                let index = position - 1
                guard t.tabInWindow == position, mine.indices.contains(index), mine[index].tabInWindow == position,
                      FulltextFetch.stillOurTab(last: lastTabs, position: position, now: mine.map(\.url)) else { throw lostOwnTab() }
            }
            window = t.window
            ownTab = String(t.tabInWindow)
            lastTabs = mine.map(\.url)
            lastOwnShown = t.url
            markSeen = true
            return t
        }
        let index = position - 1
        let urls = mine.map(\.url)
        guard let number = mine.first?.window, mine.indices.contains(index), mine[index].tabInWindow == position,
              FulltextFetch.stillOurTab(last: lastTabs, position: position, now: urls) else { throw lostOwnTab() }
        window = number
        lastTabs = urls
        lastOwnShown = mine[index].url
        markSeen = false
        return mine[index]
    }

    private func ownURL() throws -> String { try ownTabNow()?.url ?? "" }

    /// 最後一次確認時我們的分頁顯示的網址。不讀分頁：訊息與判斷用它，不會把別的分頁的網址印出來。記的是確認的那個分頁本身的網址，
    /// 不依位置從清單取（清單的位置有缺號時會取到旁邊的分頁，第三輪 verify 第 27 則）。
    private var lastOwnShown = ""
    private var lastOwnURL: String { ownTab.isEmpty ? "" : lastOwnShown }

    /// 位置上可能已經不是我們的分頁。這裡印的只有**我們自己的分頁**最後的網址，那個位置現在顯示什麼不印（那是使用者的分頁）。
    private func lostOwnTab() -> Stop {
        let shown = displaySafeInvisible(FulltextFetch.plainURL(lastOwnURL), max: 600)
        err("✗ the tabs in window \(window) changed while this ran: position \(ownTab) may no longer be the tab this command was working in (it last showed \(shown)). Nothing more was read or navigated.")
        if attemptCounted || stage == .followed { err("  This site's attempt for today is already counted.") }
        err("  No tab was closed. Ask the user to look at the window and close the leftover tab; run this again only when the tabs have stopped changing: another run loads the article page again.")
        ownTab = ""
        return Stop(code: 1)
    }

    /// `scheme://主機[:埠號]`，不帶帳密（`URLSplit.siteOrigin`）：站的比對、訊息與帳本的站名都從這裡來。
    private func origin(_ url: String) -> String { URLSplit(url).siteOrigin }
    /// 分頁的網址是不是還在這個 origin（主機不分大小寫）。
    private func sameSite(_ url: String, _ site: String) -> Bool { origin(url).lowercased() == site.lowercased() }
    /// 記號在：以它鎖分頁（safari-browser 在同一段 AppleScript 裡重驗）。不在：以視窗編號與位置鎖（`ownTabNow` 剛確認過）。
    /// 記號鎖一定帶 `--profile`：safari-browser 的 `open` 不把 `--url-endswith` 當成指定了分頁，只帶它會在前景視窗開新分頁（safari-browser#233，
    /// #768 第三輪 verify；使用者 2026-11-04 選定）。`--profile` 讓 `open` 解析記號、導航那個分頁。視窗的 profile 不只一個時改用位置鎖。
    ///
    /// 位置鎖是全域的 `--window N`（視窗的前後順序）。確認與命令之間使用者點了自己的另一個視窗，那一次會打到那個視窗；別的 profile 的視窗
    /// 開頭開著就不開始、執行當中才開的下一眼就停，但一眼與命令之間才開、又搶到同一個編號的視窗，那一次打得到。第五版曾改成「profile 內的第 k 個視窗」，第五輪 verify 指出那個 k 與
    /// safari-browser 自己的算法會對不上（沒有分頁的視窗、載入中標題空白時讀不出 profile），使用者 2026-11-04 選定改回並改做 safari-browser#352
    /// （以視窗 id 指定視窗）。
    private var lock: [String] {
        if markSeen, let p = ownProfile { return ["--profile", p, "--url-endswith", markSuffix] }
        return ["--window", String(window), "--tab-in-window", ownTab]
    }
    /// 我們的視窗所屬的 profile（開頭讀到恰好一個時）。
    private var ownProfile: String?
    /// 我們的視窗的分頁回報的 profile（開頭讀到的全部；通常只有一個）。
    private var ownProfiles: Set<String> = []
    /// 開頭檢查過的視窗（id）。每一眼的檢查只看這份清單以外的視窗。
    private var windowsAtStart: Set<Int> = []

    /// 清單裡有沒有不屬於我們視窗、而 profile 是別的或讀不出來的分頁。
    private func otherProfileWindowOpen(in all: [Tab]) -> Bool {
        all.contains { t in
            guard t.windowID != ownWindowID else { return false }
            let q = t.profile ?? ""
            return q.isEmpty || !ownProfiles.contains(q)
        }
    }
    /// 上一個鎖分頁的命令實際用的鎖（失敗訊息印它，不是重算一次；第四輪 verify 第 21 則）。
    private var usedLock: [String] = []
    private var lockText: String { (usedLock.isEmpty ? lock : usedLock).joined(separator: " ") }

    /// 鎖住我們的分頁跑一個 safari-browser 命令。**讀取**（`js`、`wait`）的記號鎖找不到分頁（記號剛好在確認與命令之間不見了：頁面用腳本換網址、
    /// `history.replaceState`；或 `--profile` 一時對不上）時，再確認一次分頁、照確認到的鎖重跑**一次**——記號不見就是位置鎖（第四輪 verify
    /// 第 8 則）。分頁對不上照常停（`ownTabNow` 丟出）。只重跑「沒有分頁符合」：別的失敗是命令本身的答案，不重跑。**導航（`open`）不重跑**：
    /// 重跑之前只確認了分頁是誰，沒有重新判那一頁（第五輪 verify 第 2 則：記號不見正是頁面剛換了網址的訊號，可能是驗證頁或登入頁），所以導航
    /// 找不到分頁就失敗（結束碼 1，已計次）。
    ///
    /// `retry: false`：答案會直接決定下一步、而呼叫端不再重判那一頁的讀取（讀 PDF 連結：重跑可能讀到剛換成同站登入或驗證頁的連結，接著就
    /// 導航過去；第六輪 verify 第 2 則）。
    private func locked(_ verb: String, _ rest: [String], retry: Bool = true) throws -> SafariRun {
        usedLock = lock
        let first = browser.run([verb] + usedLock + rest)
        guard retry, verb != "open", first.status != 0, usedLock.contains("--url-endswith"), FulltextFetch.noTabMatched(first.stderr) else { return first }
        _ = try ownTabNow()
        if markSeen { nap(1) }
        usedLock = lock
        return browser.run([verb] + usedLock + rest)
    }

    /// safari-browser 的錯誤是「沒有分頁符合這個目標」：`documentNotFound` 的 `Error: No Safari document matches "…"`（`Errors.swift`，
    /// v2.7.0 起）。只看 safari-browser 自己的那一行（`Error:` 開頭），不看頁面寫得進去的字（第五輪 verify 第 1、25 則：先前比對的是假瀏覽器
    /// 自己編的字，真的 safari-browser 一次也對不上）。
    /// 只看第一個非空行：頁面的 JavaScript 錯誤也以 `Error:` 開頭，訊息可以跨行寫出一行假的 `No Safari document matches`
    /// （第六輪 verify 第 17、21、31 則）。
    static func noTabMatched(_ stderr: String) -> Bool {
        stderr.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .hasPrefix("Error: No Safari document matches ") ?? false
    }


    /// 開一個分頁，網址帶著這次執行的記號，再找出網址以記號結尾的那一個分頁（#768）。先前取「目前的分頁」：使用者正在用 Safari 時那是他的分頁，
    /// 站名也取自那個分頁，頁面文字被讀，找不到連結時連分頁都關了；第二版比對開之前與之後的分頁清單，最後一個分頁同時換頁時會認錯。
    /// 記號在新分頁剛出現時一定還在（六家出版商都量到；Elsevier 約 2 秒後才丟掉），所以只看開完之後的頭幾眼。
    private func openOwnTab(_ url: String) throws {
        let r = browser.run(["open", "--new-tab", "--window", String(window), url + markSuffix])
        if r.status != 0 {
            let f = FulltextFetch.safariFailure(r.stderr, command: "open --new-tab --window \(window) <the landing URL>")
            throw fail("open: \(f.line)", note: f.note)
        }
        openedUnidentified = true
        for attempt in 1...FulltextFetch.markLooks {
            if attempt > 1 { nap(0.5) }
            let all = try docs()
            let marked = all.filter { $0.url.hasSuffix(markSuffix) }
            guard let t = marked.first else { continue }
            guard marked.count == 1 else {
                throw fail("more than one Safari tab shows this run's mark, so the tab just opened cannot be told apart. Nothing was read.")
            }
            guard t.windowID == ownWindowID else {
                openedUnidentified = false
                throw fail("the tab just opened went to another Safari window (window \(t.window)), not window \(window) (safari-browser#351). Nothing was read. Ask the user to close that tab (its address ends with \(markSuffix)); keeping a single Safari window open avoids this.")
            }
            openedUnidentified = false
            window = t.window
            ownTab = String(t.tabInWindow)
            lastTabs = all.filter { $0.windowID == ownWindowID }.sorted { $0.tabInWindow < $1.tabInWindow }.map(\.url)
            lastOwnShown = t.url
            markSeen = true
            return
        }
        throw fail("cannot find the tab just opened: no Safari tab showed this run's mark within about 3 s, so nothing was read.")
    }

    /// 我們分頁的（HTTP 狀態碼，標題與前 3000 字）。兩次嘗試；失敗回 nil，絕不當成「頁面乾淨」。狀態碼取自頁面自己的
    /// `PerformanceNavigationTiming.responseStatus`（已載入的資料，不發請求）；瀏覽器沒有這個值時是 nil。
    private func pageText() throws -> (status: Int?, text: String)? {
        for attempt in 1...2 {
            if attempt > 1 { _ = try ownTabNow() }   // 第一次之前呼叫端（`readPage`）剛確認過；等了之後要再確認
            let r = try locked("js", [FulltextFetch.pageTextJS])
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
    private func readPage(accept: (String) -> Bool) throws -> PageSnapshot? {
        guard let first = try tabSnapshot(), !first.url.isEmpty, accept(first.url) else { pageChanges += 1; return nil }
        let page = try pageText()
        guard let second = try tabSnapshot(), second.url == first.url, second.title == first.title else { pageChanges += 1; return nil }
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
            guard let snap = try readPage(accept: { self.sameSite($0, site) }) else { nap(2); continue }
            if beforeNavigation, BotSignals.urlGateLook(snap.url) == "login" {
                throw botStop("the page on the article site has the look of a login page → \(FulltextFetch.plainURL(snap.url)) (login page)", site)
            }
            if let stop = onSiteSuspicion(snap, site) { throw stop }
            return snap.url
        }
        throw botStop("the page kept changing while it was being read: could not check it for suspicion → \(FulltextFetch.plainURL(lastOwnURL))", site)
    }

    /// 每個進一步動作之前：我們的分頁必須還顯示文章的站。分頁離開了文章站（使用者 2026-10-02），照 `leftSite` 判；分頁在等它落定的
    /// 時候回到文章站就照常往下走。
    private func siteGuard(_ site: String) throws {
        let u = try ownURL()
        if !u.isEmpty, sameSite(u, site) { return }
        guard !u.isEmpty else { throw botStop("site changed → <our tab shows nothing>", site) }
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
            let before = try ownURL()
            let shown = try locked("js", [FulltextFetch.shownJS])
            let url = try ownURL()
            if url.isEmpty { return botStop("site changed → <our tab shows nothing>", site) }
            if sameSite(url, site) { pageChanges = outer; return nil }
            if url == before {   // 看的這一下分頁沒有換頁：這個回答屬於這個網址
                if shown.status == 0, FulltextFetch.contentTypeIsPDF(shown.value) { return handover(.pdfShown, at: url) }
                if shown.status != 0 || FulltextFetch.isUnreadableShown(shown.value) {
                    if tally.unreadable(at: url), let stop = try judgeUnreadable(url, site) { return stop }
                } else {
                    tally.answered(at: url)
                    if FulltextFetch.isSettled(shown.value), let stop = try offSiteSettled(url, site) { return stop }
                }
            } else {
                tally.moved()   // 換頁中：讀不到的這一下不算到任何一個網址
            }
            nap(2)
        }
        return botStop("the tab left the article site and the page did not settle (stalled)\(pageChangesNote) → \(FulltextFetch.plainURL(lastOwnURL))", site)
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
    private func tabSnapshot() throws -> (url: String, title: String)? { try ownTabNow().map { ($0.url, $0.title) } }

    /// 別的主機上的頁面落定了：標題、網址、頁面文字與狀態碼一起判訊號，再看登入／驗證頁的長相，都沒有就交給人。
    ///
    /// **同一份快照**（#613 R3，b31 W4 第 0 則；`readPage`）：讀完之後網址或標題變了＝讀的當中分頁換了頁（中繼頁轉到登入頁），這一份不用，回 nil
    /// 讓 `leftSite` 回去等。先前標題、頁面文字、交給人時印的網址各讀各的，舊中繼頁的網址與標題配上新登入頁的文字，三樣都沒命中就交給人。
    private func offSiteSettled(_ url: String, _ site: String) throws -> Stop? {
        guard let snap = try readPage(accept: { $0 == url }) else { return nil }
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
    private func judgeUnreadable(_ url: String, _ site: String) throws -> Stop? {
        guard let snap = try tabSnapshot(), snap.url == url else { pageChanges += 1; return nil }
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
        if let m = o.resumeMark {
            guard o.resumeTab != nil else { throw fail("--resume-mark goes with --resume-tab") }
            if let why = FulltextFetch.markShapeProblem(m) { throw fail("--resume-mark: \(why)") }
        }
        // 導航之後的接續：嘗試在上一次執行就記過了，從這裡起的每一條失敗都要說（第四輪 verify 第 4 則）
        if o.resumeTab != nil { stage = o.resumeStage }
        let ledger = FulltextAttemptLedger(path: o.ledger)
        do { _ = try ledger.load() } catch { throw fail("\(displaySafeErrorText(error))") }   // 數不出今天的次數，就不能保證沒超過上限

        // 視窗不存在，或它的分頁都沒有 profile 欄位：兩者對這支程式是同一件事——無從確認它屬於誰，不碰
        let everything = try docs()
        let tabsBefore = tabsHere(everything)
        let profiles = Set(tabsBefore.compactMap(\.profile).filter { !$0.isEmpty })
        ownProfiles = profiles
        let profile = profiles.sorted().joined(separator: ",")
        ownProfile = profiles.count == 1 ? profiles.first : nil
        guard !profile.isEmpty else { throw fail("Safari window \(window) not found") }
        out("window \(window) profile: \(displaySafeInvisible(profile, max: 200))")
        if let expected = o.expectProfile, !expected.isEmpty, profile != expected {
            throw fail("window \(window) belongs to profile '\(profile)', not '\(expected)' — refusing to touch it")   // `fail()` 跳脫整則訊息，這裡再跳脫就是兩次
        }

        // 視窗編號是前後順序，使用者一切換就指到別的視窗。認視窗要靠它的 id；拿不到就無從知道視窗換了沒（判不出來就不碰）
        let ids = Set(tabsBefore.map(\.windowID))
        guard ids.count == 1, let only = ids.first, let id = only else {
            throw fail("safari-browser did not report one window id for window \(window) (`blocking_dialog.window_id` in `documents --json`), so a change of window could not be noticed — update safari-browser")
        }
        ownWindowID = id

        // safari-browser#351：多個視窗時 `open --new-tab --window N` 可能開進別的視窗。那個視窗若屬於別的 profile（Safari 的 profile 可能屬於
        // 別人），落地頁就以那個 profile 的 cookie 與登入載入、記進它的瀏覽紀錄；位置鎖（全域的 `--window N`）在視窗順序變了時也會打到它。
        // 有別的 profile 的分頁開著就停（第三輪 verify 第 12 則）；認不出 profile 的別的視窗也算（第四輪 verify 第 6 則）。不印那個 profile 的名字。
        // 無條件：safari-browser 沒有穩定指定視窗的方式之前沒有安全的放寬（使用者 2026-11-04；以視窗 id 指定視窗是 safari-browser#352）。
        // **接續也一樣**，所以在 `resume` 之前判（第六輪 verify 第 1、4 則：先前放在 `resume` 之後，接續的 run 從不判）；之後每一眼也判（第 8 則）
        if otherProfileWindowOpen(in: everything) {
            throw fail("a Safari window of another profile (or one whose profile cannot be read) is open, and this safari-browser can put the new tab or a position-locked command in another window (safari-browser#352), which would load or read a page under that profile (possibly someone else's). Nothing was opened or read. Ask the user: those windows have to be closed first, and only the user decides that (they may belong to someone else).")
        }
        windowsAtStart = Set(everything.compactMap(\.windowID))
        if let resumeTab = o.resumeTab, let resumeOrigin = o.resumeOrigin {
            try resume(tab: resumeTab, origin: resumeOrigin, stage: o.resumeStage, mark: o.resumeMark, ledger: ledger)
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
        try judgedArticlePage(site)
    }

    /// `checkTheArticlePage` 的第 2、3 步：起疑訊號，再看判的那一頁的網址。回判的那一頁的網址。導航之前判頁面的地方，除了 `resume` 的 `.article`（那裡驗證頁的網址是等它變，不是停），都走這裡（第八輪 verify 第 5 則：
    /// 驗證頁的網址閘先前只在落地頁與接續，等連結時或讀完連結後到了同站的 `/captcha/`、頁面還沒寫出訊號，就成了結束碼 3 或 1，整批不暫停）。
    @discardableResult
    private func judgedArticlePage(_ site: String) throws -> String {
        let judged = try botCheckPage(site, beforeNavigation: true)
        // `botCheckPage(beforeNavigation: true)` 對 `judged` 已先判登入長相（命中就 throw），這裡的 `gate` 今天只會是 verification。
        // `login` 那一支是縱深防禦，不是死碼要刪：那個閘日後改成有條件時，由這裡接手、仍是整批暫停（b38 Z2 第 19、24 則）
        if let gate = BotSignals.urlGateLook(judged) {
            throw botStop("the article page has the look of a \(gate) page → \(FulltextFetch.plainURL(judged)) (\(gate) page)", site)
        }
        return judged
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
            let u = try ownURL()
            if u.isEmpty || FulltextFetch.isDOIResolver(u) { continue }
            let rs = try locked("js", [FulltextFetch.readyStateJS]).value
            if rs == "complete" || rs == "interactive" { final = u; break }
        }
        if final.isEmpty {
            let u = lastOwnURL   // 迴圈的最後一眼剛看過；組訊息時不再讀分頁（讀失敗會把整批暫停變成結束碼 1）
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
        let rs = try locked("js", [FulltextFetch.readyStateJS]).value
        guard rs == "complete" || rs == "interactive" else { throw botStop("page did not settle in 60 s (stalled) \(here)", site) }
        guard let snap = try readPage(accept: { FulltextFetch.isDOIResolver($0) }) else {
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
    private func resume(tab requested: Int, origin expected: String, stage resumeStage: ResumeStage, mark resumeMark: String?,
                        ledger: FulltextAttemptLedger) throws -> Never {
        let all = try docs()   // 別的 profile 的視窗已在 `execute` 呼叫這裡之前判過
        let here = tabsHere(all)
        var position = requested
        // 上一次執行的記號還在一個分頁上：那就是停下的那個分頁，不論它現在在哪個位置（分頁移動了也不會接到別的分頁）。它必須在這個視窗；
        // 兩個分頁帶著它、或它在別的視窗，就停。沒有分頁帶著它（Elsevier 的轉址丟掉了）才照位置（使用者 2026-11-04：記號不見時改用位置）
        if let m = resumeMark {
            mark = m
            let marked = all.filter { $0.url.hasSuffix(markSuffix) }
            if !marked.isEmpty {
                guard marked.count == 1, let found = marked.first, found.windowID == ownWindowID else {
                    throw fail("the tab ending with \(markSuffix) is not exactly one tab of window \(window) — not resuming. Find it with `safari-browser documents --json --profile <P>` and pass its window.")
                }
                position = found.tabInWindow
                markSeen = true
            }
        }
        guard here.allSatisfy({ $0.windowID == ownWindowID }), let t = here.first(where: { $0.tabInWindow == position }) else {
            throw fail("window \(window) has no tab \(position) — the tab may have moved; find the one showing \(expected) with `safari-browser documents --json --profile <P>`")
        }
        ownTab = String(position)
        lastTabs = here.map(\.url)   // 追蹤從這一眼開始
        lastOwnShown = t.url
        stage = resumeStage
        switch resumeStage {
        case .followed:
            guard !t.url.isEmpty else {
                ownTab = ""   // 沒有人確認過那是我們的分頁（b31 W4 第 21 則：與下面兩個拒絕同樣不叫它「我們的分頁」）
                throw fail("window \(window) tab \(position) shows nothing — not resuming there.")
            }
            if !sameSite(t.url, expected), !BotSignals.isKnownVerificationService(url: t.url) {
                // 維護者 2026-11-05 裁決接受：記號不在時（ScienceDirect 的 `pdfft` 之後）這裡只有位置，分頁又不在文章站，仍先問它顯示什麼，因為
                // Elsevier 的 PDF 在別的主機上，拒絕就接不上。代價：左邊的分頁關掉時，這段腳本會跑在使用者的分頁裡（只讀 `document.contentType` 與
                // `readyState`，不讀頁面文字）。回報 PDF 的分頁會被當成我們的。
                let shown = try locked("js", [FulltextFetch.shownJS])
                guard shown.status == 0, FulltextFetch.contentTypeIsPDF(shown.value) else {
                    ownTab = ""   // 那不是我們的分頁
                    throw fail("window \(window) tab \(position) shows another page — not \(expected), a known verification service, or a PDF; not resuming there. Find the tab you verified in with `safari-browser documents --json --profile <P>` and pass its window/tab; if it is that tab, look at it yourself.")
                }
            }
            out("resuming: window \(window) tab \(ownTab) \(displaySafeInvisible(FulltextFetch.plainURL(t.url), max: 600)) (after the PDF link was followed)")
            try decideShown(site: expected)
        case .article:
            guard !t.url.isEmpty, sameSite(t.url, expected) else {
                ownTab = ""   // 那不是我們的分頁
                throw fail("window \(window) tab \(position) shows \(t.url.isEmpty ? "nothing" : "another page"), not \(expected) — not resuming there. Find the tab showing \(expected) with `safari-browser documents --json --profile <P>` and pass its window/tab.")
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
                case "login":   // 今天到不了（`botCheckPage` 已先判、throw）；縱深防禦，同 `checkTheArticlePage`（b38 Z2 第 19、24 則）
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
        // 連結可能晚出現（最多約 45 秒）。`wait` 等的時候沒有人看分頁，所以切成小段，每段之前確認一次（#768）
        for _ in 1...FulltextFetch.linkWaitSlices {
            try siteGuard(site)
            if try locked("wait", ["--js", FulltextFetch.hasLinkJS, "--timeout", FulltextFetch.linkWaitSliceMilliseconds]).status == 0 { break }
        }
        try siteGuard(site)
        let judged = try judgedArticlePage(site)   // 插頁在我們等的時候可以變成挑戰頁或登入頁
        try siteGuard(site)
        let linkRun = try locked("js", [FulltextFetch.linkJS], retry: false)
        try siteGuard(site)   // 讀的當中分頁移動了：這個答案不用
        try requireTheJudgedPage(judged, shown: lastOwnURL, site: site)
        if linkRun.status != 0 {
            let f = FulltextFetch.safariFailure(linkRun.stderr, command: "js \(lockText) <the link script>")
            throw fail("could not read the page's links: \(f.line)", note: f.note)
        }
        let link = linkRun.value
        guard let space = link.firstIndex(of: " ") else {
            err("no PDF link on \(displaySafeInvisible(FulltextFetch.plainURL(lastOwnURL), max: 600)); our tab (window \(window), tab \(ownTab)) is left open")
            throw Stop(code: 3)
        }
        let method = String(link[..<space])
        let target = String(link[link.index(after: space)...])
        // 回答是頁面影響得到的字（頁面可以遮蔽 `linkJS` 用到的 API）：過 `redactingPageText`，不是只認一個網址的 `plainURL`（b41＝b40 Z2 第 8、28 則）
        guard method == "GET" || method == "POST" else { throw fail("unexpected answer from the link script: \(FulltextFetch.redactingPageText(link))") }
        // 頁面自己的連結來自 DOM（`citation_pdf_url`、`a[href]`、表單的 `action`）：只跟同一個站的絕對 https 網址走。拒絕不是中止條款
        // （不是網站起疑，是頁面給了一個不能照做的連結）：結束碼 1，分頁留著。站的比對看主機與埠號、不看帳密（與 `sameSite` 同一把，#613 b34，
        // b33 X3 第 6、23 則：先前連結的 origin 帶帳密而站的不帶，帶帳密的落地頁上同站的相對連結永遠被拒，訊息還把帳密印出來）。
        let linkOrigin = FulltextFetch.linkTargetOrigin(target)
        if linkOrigin != site.lowercased() {
            throw fail("the page's PDF link points off-site (\(linkOrigin ?? "not an absolute https URL"), page origin \(site)): \(FulltextFetch.redactingPageText(FulltextFetch.plainURL(target))) — not following a link the page chose to another site")
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
            err("  our tab (window \(window), tab \(ownTab)) is left open.")
            out("cap: \(displaySafeInvisible(host, max: 300)) \(used)/\(FulltextAttemptLedger.dailyCap) \(day)")
            throw Stop(code: Code.dailyCapReached)
        case .granted(let used):
            attemptCounted = true
            out("attempt: \(displaySafeInvisible(host, max: 300)) \(used)/\(FulltextAttemptLedger.dailyCap) \(day)")
        }

        if method == "POST" { throw handover(.button) }   // 表單按鈕交給人按，不代按、不代送

        out("pdf:  \(displaySafeInvisible(FulltextFetch.plainURL(target), max: 600))")
        let before = try ownURL()
        try requireTheJudgedPage(judged, shown: before, site: site)
        stage = .followed   // 從這裡起，等人驗證之後接著走的是「分頁顯示什麼」，不是再讀一次連結
        let navigation = try locked("open", [FulltextFetch.withMark(target, markSuffix)])
        if navigation.status != 0 {
            let f = FulltextFetch.safariFailure(navigation.stderr, command: "open \(lockText) <the PDF link>")
            throw fail("could not navigate the tab to the PDF link: \(f.line)", note: f.note)
        }
        try awaitShown(site: site, before: before)
    }

    /// 連結的答案屬於判過的那一頁（第七輪 verify 第 1、3 則）：`siteGuard` 只看主機，位置追蹤把同位置、同站的新網址當成我們的分頁在換頁，所以讀完
    /// 連結之後分頁到了同站的登入或驗證頁，先前照樣拿舊頁面的連結導航，把那一頁蓋掉（結束碼 6／8 不出現）。網址與判過的不同（我們的記號不算：
    /// 頁面用腳本拿掉 fragment 不是換頁）就**等新的那一頁落定、判它**，走 `watchOnSite`，與導航之前的接續同一套（第八輪 verify 第 5、10 則：先前只讀一次、
    /// 不看驗證頁的網址）：登入、驗證頁 6／8，一直不落定 6，PDF 交給人，讀不到的頁面交給人（7 `unverifiable`，落地頁同樣的頁面是 6，第九輪 verify 第 2、6 則），
    /// 其他都不導航（結束碼 1）：連結不是從判過的那一頁讀來的，而重讀一次又是同一個問題。別的 fragment 或 query
    /// 算換頁：`#/login` 這種路由也長這樣，看不出是不是同一頁，停的方向是安全的，訊息說明只有這部分變了（第八輪 verify 第 11、18 則）。
    /// 這是 Apple event 之間看得到的變化；網址不變而內容換了、或比對之後才換，看不到（導航收不回，SKILL 的限制 (b)）。
    private func requireTheJudgedPage(_ judged: String, shown: String, site: String) throws {
        let page = { (url: String) in url.hasSuffix(self.markSuffix) ? String(url.dropLast(self.markSuffix.count)) : url }
        if page(shown) == page(judged) { return }
        do {
            try watchOnSite(site, stalled: "the page changed after it was checked and did not settle (stalled)") { url in
                try self.judgedArticlePage(site)
                let was = FulltextFetch.plainURL(judged), now = FulltextFetch.plainURL(url)
                let change = was == now ? "now \(now), differing at most in a part of the address not printed here" : "\(was) → \(now)"
                return .stop(self.fail("the page changed after it was checked (\(change)), so the PDF link was not followed: nothing was navigated. Look at the tab; retry after it has settled."))
            }
        } catch let stop as Stop where stop.code == 6 || stop.code == Code.humanVerification {
            if attemptCounted { err("  This site's attempt for today is already counted.") }   // 6／8 的訊息不印這一行；SKILL 以它判斷算了沒
            throw stop
        }
    }

    /// 導航之後：等分頁離開文章頁（20 秒），再看它顯示什麼。分頁沒離開：檢查起疑訊號（同一份快照）——判的那一頁還是導航之前的那一頁才是
    /// `tab-unchanged`；檢查的當中換了頁就照「分頁顯示什麼」判（b33 X3 第 8 則的同一個形狀：先前交給人時才讀網址，印的是換過去的那一頁）。
    private func awaitShown(site: String, before: String) throws -> Never {
        var moved = false
        for _ in 1...10 {
            nap(2)
            let u = try ownURL()
            if u.isEmpty || u != before { moved = true; break }
        }
        try siteGuard(site)   // 分頁對不上 → 1（`lostOwnTab`）；到了別的主機 → 照 `leftSite`（PDF／沒有標記的頁面交給人，訊號與登入頁停）
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
            guard let snap = try self.readPage(accept: { $0 == url }) else { return .retry }
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
    /// - 每一次輪詢先過 `siteGuard`（分頁到了別的主機照 `leftSite` 判、對不上 → 1）；讀之前與之後的網址相同，這個回答才屬於那個網址。
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
                if try ownURL() == h { nap(2); continue }
                holding = nil
            }
            let before = try ownURL()
            let shown = try locked("js", [FulltextFetch.shownJS])
            let url = try ownURL()
            if url.isEmpty || url != before || !sameSite(url, site) { tally.moved(); nap(2); continue }   // 換頁中：下一輪 `siteGuard` 再看
            if shown.status == 0, FulltextFetch.contentTypeIsPDF(shown.value) { throw handover(.pdfShown, at: url) }
            if shown.status != 0 || FulltextFetch.isUnreadableShown(shown.value) {
                // 空的或 `undefined` 的回答（對非 HTML 文件跑 `do JavaScript` 的可能結果）與失敗同樣算「讀不到」，不是「還在載入」
                if tally.unreadable(at: url), let stop = try judgeUnreadable(url, site) { throw stop }
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
        throw botStop("\(stalled)\(pageChangesNote) → \(FulltextFetch.plainURL(lastOwnURL))", site)
    }

    // MARK: 純函式（測試直接呼叫）

    /// 等連結時切成幾段、一段多久：每段至少 3 秒，加上每段的分頁解析與確認；2026-11-04 實測一篇找不到連結的 SAGE 從開分頁到結束共 100 秒
    /// （先前一次等 45 秒）。每段之間有人看分頁。
    static let linkWaitSlices = 15
    static let linkWaitSliceMilliseconds = "3000"

    /// 開完分頁之後，找記號看幾眼（每眼間隔 0.5 秒）。
    static let markLooks = 6

    /// 網址接上記號。網址本身已有 fragment（頁面給的連結帶 `#…`）就原樣不動：導過去的要是驗過的那一串；記號不在之後靠位置追蹤。
    static func withMark(_ url: String, _ suffix: String) -> String {
        url.contains("#") ? url : url + suffix
    }

    /// 同一個視窗裡，上一眼與這一眼之間，`position` 上還是不是同一個分頁（1 起算；視窗換了由 `ownTabNow` 比 id）。只有位置與網址可看，所以這是
    /// 判斷，不是證明。
    ///
    /// - 分頁數變了：只有我們右邊開關分頁才不影響位置，所以左邊與我們自己都要沒變。
    /// - 分頁數沒變、這個位置的網址也沒變：同一個分頁；別的分頁換頁與我們無關（使用者照常工作，不能因此停）。
    /// - 分頁數沒變、這個位置的網址變了：可能是我們的分頁換頁，也可能是別的分頁移到這裡。以下任一成立就不是我們的分頁：
    ///   1. 這個新網址上一眼在別的位置，而那個位置現在不再顯示它（那個分頁移過來了）。使用者開著同一頁而我們轉址過去不算：他的分頁還在原位。
    ///   2. 我們上一眼的網址現在出現在別的位置（我們的分頁移走了）。
    ///   3. 其他分頁沒有一個還顯示原來的網址（整份清單換了，例如切換分頁群組）。兩個群組剛好有一個相同的分頁（都有空白起始頁）時擋不住；
    ///      空白分頁若不算，視窗裡只有一個空白分頁時，Elsevier 丟掉記號的那一刻就會誤停，那更常見。
    /// - 顯示過網址的位置變成空白：不是我們的分頁（⌘W 再 ⌘T 補上同一個位置）。
    ///
    /// **擋不住的**：(a) 使用者在我們的分頁裡開別的網頁（⌘L，或關掉它再開一個補上這個位置）：只有這個位置的網址變了，與換頁完全相同；
    /// (b) 顯示同一個網址的兩個分頁互換位置。所以這個判斷只拿來決定要不要繼續讀，不拿來決定關分頁。
    static func stillOurTab(last: [String], position: Int, now: [String]) -> Bool {
        let p = position - 1
        guard last.indices.contains(p), now.indices.contains(p) else { return false }
        let was = last[p], shows = now[p]
        if shows.isEmpty, !was.isEmpty { return false }   // 顯示過網址的分頁變成空白：多半是被關掉、補上了新分頁（⌘W 再 ⌘T）
        if now.count != last.count { return shows == was && now[..<p] == last[..<p] }
        if shows == was { return true }
        var anotherStayed = false
        for q in last.indices where q != p {
            if last[q] == shows, now[q] != shows { return false }
            if now[q] == was, last[q] != was { return false }
            if now[q] == last[q] { anotherStayed = true }
        }
        return anotherStayed || last.count == 1
    }

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
    /// `URLSplit.hostPort`——在反斜線處結束、去掉最後一個 `@` 之前的帳密（兩種讀法對帳密說法不同時例外，見下一段）。先前這裡自己切：authority 只在 `/` 結束、`://` 在整串裡找，
    /// `https://evil.example\@pub.example/x` 印成 `pub.example` 而站的比對是 `evil.example`，`//u:p@h/a/https://z/q` 的帳密原樣印出。
    /// authority 裡反斜線之後到第一個 `/` 的那一段不印。scheme 照 `URLSplit` 轉小寫。
    ///
    /// **兩種讀法對帳密說法不同的 authority 不印主機段**（#613 b39，b38 Z2 第 13 則）：authority 在反斜線之後還有 `@` 時
    /// （`user:SECRET\@pub.example`、`evil.example\@pub.example`），反斜線之前那一段在 WHATWG 的讀法裡是主機加埠號（站的比對用它，見
    /// `URLSplit.hostPort`），在 RFC 3986／Python 的讀法裡整段是帳密（帳密到最後一個 `@` 為止）。b37 印 `hostPort`，`user:SECRET\@pub.example`
    /// 因此印成 `https://user:SECRET/…`。印 `<ambiguous-host>`（`ambiguousHost`）：哪一種讀法的帳密都不印，也不印另一種讀法的主機（那只會
    /// 讓人讀錯主機）。站的比對不變（照 `hostPort`，這種網址與文章站永遠對不上）。Safari 回報的分頁網址不會是這個形狀（WHATWG 對 https 把
    /// `\` 當 `/`，這種網址解析失敗）、`--landing` 的形狀檢查不收反斜線，會到這裡的是頁面給的 PDF 連結（`linkJS` 的 `new URL()` 失敗時
    /// 原樣回 `citation_pdf_url`）。
    ///
    /// **網址不在字串開頭時**（#613 b39，b38 Z2 第 8、10、27 則）：從第一個 `://` 起當網址印——前面的字原樣（tab 與換行除外：`URLSplit` 切之前
    /// 也去掉它們，b41；路徑參數除外：前面若是另一個沒有 `//` 的網址，`;名=值` 在那一段，b45——只去那個網址本身，從它的起點到第一個空白、`"`、
    /// `<`、`>`，前後的字原樣，b47）、authority 照上面去帳密（`FOO https://u:p@h/x`、`view-source:https://u:p@h/x`、BOM 開頭的網址）。b37 改由 `URLSplit` 切
    /// 之後，這種字串沒有 authority、整串原樣回傳。之後再出現的 `://` 是路徑的一部分，與有 authority 的網址相同（上面「也不剝一般的路徑段」）。
    /// **不在保證裡的**（b47）：那個沒有 `//` 的網址的路徑參數，值、名字或 ASP.NET 群組跨過空白、`"`、`<`、`>` 時，界線之後的部分原樣（b43 整段
    /// 原樣；b45 去掉它，連同之後到 `://` 的說明文字與 scheme）。
    ///
    /// **這個函式只對一個網址負責**（b41＝b40 Z2 第 8、28 則）：字串裡的第二個網址、special scheme 沒有兩個斜線的寫法（`https:u:p@h`）它都看不到；
    /// tab 與換行在 scheme 之前時，`URLSplit` 把前面的字接進 scheme（`GET<LF>https://u:p@h/x` → `gethttps://h/x`：帳密去掉了，字變了）。
    /// 頁面給的字（`unexpected answer from the link script`、`points off-site` 那一行）改走 `redactingPageText`，b39 把整個回答交給這裡。
    static func plainURL(_ url: String) -> String {
        var s = url
        if let cut = s.unicodeScalars.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            s = String(String.UnicodeScalarView(s.unicodeScalars[..<cut]))
        }
        let parts = URLSplit(s)
        if parts.hasAuthority {
            let head = parts.scheme.isEmpty ? "//" : PyText.string(parts.scheme) + "://"
            return head + printedHostPort(parts) + withoutPathParameters(parts.path)
        }
        // tab 與換行先去掉——`URLSplit` 切之前也去掉它們；先前這一支在原樣的字上找 `://`，`GET https:/<tab>/u:p@h/x` 帳密原樣印出（b41＝b40 Z2 第 8 則）
        let scalars = Array(s.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" })
        guard let sep = scalars.indices.first(where: { PyText.hasPrefix(scalars, [":", "/", "/"], at: $0) }) else {
            return withoutPathParameters(s)
        }
        let inner = URLSplit("//" + PyText.string(Array(scalars[(sep + 3)...])))
        // `://` 之前那一段裡的網址也去路徑參數（b45，b44 第 3、16 則）：沒有 authority 的網址後面接著另一個 `scheme://` 時，`;jsessionid=…` 在
        // 這一段。**只去那個網址本身**（b47，b46 INFO 22）：從它的起點（`firstPageURLStart`）到第一個界線（`isPageURLBoundary`：空白、`"`、`<`、
        // `>`——`redactingURLs` 的網址、`pageURLBody` 的段同一組）；之前、之後的字原樣，與 b43 相同。b45 對 `://` 之前整段去：`Error: navigation
        // failed; code=5 for https://h/x` 的 `; code=5 for https` 被當成路徑參數、連 scheme 一起吃掉。
        let before = Scalars(scalars[..<sep])
        guard let urlStart = firstPageURLStart(before) else {
            return PyText.string(before) + "://" + printedHostPort(inner) + withoutPathParameters(inner.path)
        }
        let urlEnd = before[urlStart...].firstIndex(where: isPageURLBoundary) ?? before.count
        return PyText.string(Scalars(before[..<urlStart])) + withoutPathParameters(PyText.string(Scalars(before[urlStart..<urlEnd])))
            + PyText.string(Scalars(before[urlEnd...])) + "://" + printedHostPort(inner) + withoutPathParameters(inner.path)
    }

    /// 兩種讀法對帳密說法不同時印的主機段（見 `plainURL`）。
    static let ambiguousHost = "<ambiguous-host>"

    /// 印出的主機段：`hostPort`；authority 在反斜線之後還有 `@` 時是 `ambiguousHost`。
    private static func printedHostPort(_ parts: URLSplit) -> String {
        let n = parts.netloc
        if let backslash = n.firstIndex(of: "\\"), let at = n.lastIndex(of: "@"), backslash < at { return ambiguousHost }
        return parts.hostPort
    }

    /// `withoutPathParameters` 的兩條（編譯期常數）。只編一次（#613 b45，b44 LOW 13：先前每呼叫一次重編兩條，頁面的字有幾萬個網址時
    /// 每個網址多花幾十微秒；b45 的第 3 步逐段呼叫它，次數更多）。
    private static let pathParameterPattern = try! NSRegularExpression(pattern: #"(?:;|%3[Bb])(?:(?!%3[BbDd])[^;=/])+(?:=|%3[Dd])(?:(?!%3[Bb])[^;/])*"#)
    private static let aspNetSessionPattern = try! NSRegularExpression(pattern: #"^(?:\((?:[A-Za-z]\([^()/]*\))+\))+$"#)

    /// 路徑的每一段去掉 `;名=值`（`;`、`=` 也可以是百分比編碼的 `%3B`、`%3D`），丟掉 ASP.NET 的 `(X(…))` 整段（一段裡可以有幾個群組、
    /// 也可以連著幾組）；一段因此變空（而它原本不是空的）就整段丟掉。
    ///
    /// 一段裡以反斜線分開的部分整個是群組的，也丟掉（#613 b47，b46 INFO 16：WHATWG 對 special scheme 把 `\` 當 `/`，`https://h/(S(…))\x` 的
    /// 群組是一整段；先前只以 `/` 分段，群組原樣印出，b41、b43 同）。只丟、不改其餘的字：路徑參數的值照舊跨過 `\`（`[^;/]*`，與 b43 同）。
    private static func withoutPathParameters(_ path: String) -> String {
        func isGroup(_ s: String) -> Bool { aspNetSessionPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        var kept: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if isGroup(segment) { continue }
            let rest = segment.contains("\\")
                ? segment.split(separator: "\\", omittingEmptySubsequences: false).map(String.init).filter { !isGroup($0) }.joined(separator: "\\")
                : segment
            let stripped = pathParameterPattern.stringByReplacingMatches(in: rest, range: NSRange(rest.startIndex..., in: rest), withTemplate: "")
            if stripped.isEmpty, !segment.isEmpty { continue }
            kept.append(stripped)
        }
        return kept.joined(separator: "/")
    }

    /// safari-browser 失敗時轉印什麼（`safariFailure`）。
    struct SafariFailure: Equatable {
        /// 轉印的那一行（網址去憑證）。
        let line: String
        /// 其餘的行沒有轉印時的說明，另起一行印（`fail` 的 `note`）；safari-browser 只印了一行時是 nil。
        let note: String?
    }

    /// JavaScript 對話框的兩個記號——**封閉列舉，只有這兩個**：safari-browser 的錯誤 `javaScriptDialogBlocking`（`A JavaScript dialog is open and
    /// blocking this tab: "<對話框的文字>"`）與它在錯誤之前印的警告（`BlockingDialogWarning.firstLine`：`⚠ BLOCKING DIALOG in <視窗>: "<對話框的文字>"
    /// — buttons: …`）。對話框的文字就是頁面 `alert()`／`confirm()` 的引數。stderr 裡**任何地方**出現其中一個（去掉終端機控制序列之後，行與行接起來
    /// 比；`case` 寫明大小寫要不要相同），整段只轉印 `pageDialogLine`（#613 b41，b40 Z2 第 0、7、36 則）。不得依「看起來也帶頁面的字」類推第三個——
    /// 那一類見 `safariFailure` 的說明。
    ///
    /// `BLOCKING DIALOG` 大小寫要相同：safari-browser 在探測不到對話框時印的 `a blocking dialog would go unnoticed`（`BlockingDialogWarning` 的
    /// `unmappableLine`、`probeUnavailableLine`）是小寫，那不是有對話框。錯誤那一句不分大小寫，也不要求開頭的 `A`：包在別的前綴裡
    /// （`Error: Failed: …`、daemon 模式的 `daemon remote error [code]: …`）或改了大小寫，照樣是對話框。
    static let pageDialogMarkers: [(text: String, caseInsensitive: Bool)] = [
        ("JavaScript dialog is open and blocking this tab", true),
        ("BLOCKING DIALOG", false),
    ]
    /// 對話框擋住分頁時轉印的固定一句：不轉印頁面的字，留下唯一可行動的那一句。
    static let pageDialogLine = "A JavaScript dialog is open in the tab and blocks it (its text is the page's and is not relayed) — the user has to dismiss it in Safari; safari-browser does not, and neither does this command"

    /// safari-browser 失敗時轉印什麼（#613 b37；b39＝b38 Z2 第 5、9、11、18、29 則；b41＝b40 Z2 第 0、5、7、10、12、36 則）。`command` 是失敗的
    /// 那個命令（子命令與目標旗標，不含網址與 JS），寫進說明。
    ///
    /// - **對話框擋住分頁時只轉印 `pageDialogLine`**：stderr 裡任何地方有 `pageDialogMarkers` 的其中一個，就不挑任何一行（b41）。b39 先挑第一個
    ///   `Error:` 行再看它是不是對話框的那一行，兩個洞：對話框的文字若帶著沒逸出的換行，換行之後以 `Error:` 開頭的那一段（頁面寫的）會比真正的錯誤先被
    ///   挑到（b40 Z2 第 0 則；現行 safari-browser 的 `TerminalText.quotedDialogField` 把七種換行摺成空白，這個形狀到不了——縱深防禦，不依賴上游的
    ///   逸出）；警告之後是別的錯誤（`open` 逾時）時，挑到的是那一行，對話框這個診斷整個消失（第 7 則）。代價：有對話框時，真正的錯誤那一行也不轉印，
    ///   說明寫出它在沒轉印的行裡；頁面讓這兩句出現在別的地方（例如分頁標題）時，會誤報成有對話框——方向是少說，不是洩漏。
    /// - **其餘情形只轉印它的錯誤那一行**：第一個以 `Error:` 開頭的行——ArgumentParser 印錯誤時的前綴，safari-browser 的命令以它結束；沒有這樣的行
    ///   才退回第一個非空行（safari-browser 沒跑起來時是 `ToolRunner` 的錯誤）。b37 取第一個非空行，而 safari-browser 在錯誤之前會先印進度與警告
    ///   （`⏳ Waiting for System Events...`、`⚠️  System Events not responding, attempting restart...`、分頁在背景時的 `Warning: the resolved target
    ///   was in the background …`）：那時轉印的是那一行，真正的錯誤被藏起來。
    /// - **行先去掉終端機的控制序列**（`withoutTerminalEscapes`，b41＝第 36 則）：`ESC[1m` 開頭的錯誤行不以 `Error:` 開頭、`ESC[1;33m⚠ BLOCKING DIALOG`
    ///   的去前綴比法停在序列裡的 `m`——兩者先前都 fail-open。現行 safari-browser 不輸出控制序列。
    /// - **其餘的行一律不轉印**：`documentNotFound` 從第三行起、`ambiguousWindowMatch` 從第二行起列出所有視窗的分頁（含其他 profile 的
    ///   session，這個命令沒帶 `--profile`，清單不過濾）；`targetTabChanged` 的第二行是那個位置此刻顯示的網址。說明另起一行（`note`）：
    ///   有幾行沒印、為什麼、失敗的是哪個命令，以及使用者可以怎麼看——看那個分頁，或自己列出自己 profile 的分頁。**不說「重跑那個命令」**（b41＝第 5、
    ///   10 則）：印出的命令不含網址與 JS（`<the link script>` 使用者拿不到），導航的 `open` 重跑一次就是對網站多送一次請求（不經帳本、不計次）。
    ///   不接在那一行後面——`fail` 把訊息截在 600 字，第一行很長時說明會被截掉。
    /// - **那一行是錯誤的標題，不一定說的是我們的目標**：`AppleScript error: …`、`Process timed out after N seconds: <命令>` 帶的是底層訊息。
    ///   它**仍可能帶頁面寫的字**：`AppleScript error: JavaScript error: <訊息>` 的訊息可以由頁面決定（頁面改寫了我們注入的運算式用到的 API；
    ///   CSP 擋下時是瀏覽器的字，那是診斷要的）——一行、截在 600 字，是資料不是指令（SKILL 第 3 步）。
    /// - 那一行裡的網址過 `redactingURLs`。行以 `Character.isNewline` 切（`\r\n` 是一個 `Character`）。
    /// - 格式取自 safari-browser 的原始碼（`Errors.swift`、`SafariBridge.swift`、`BlockingDialogGate.swift`、`BackgroundTabDiagnostics.swift`、
    ///   `TerminalText.swift`），沒有對真的 binary 觸發。
    static func safariFailure(_ stderr: String, command: String) -> SafariFailure {
        let lines = stderr.split(whereSeparator: \.isNewline)
            .map { withoutTerminalEscapes(String($0)).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return SafariFailure(line: "(safari-browser printed no message)", note: nil) }
        let rest = lines.count - 1
        let more = "safari-browser `\(command)` printed \(rest) more line\(rest == 1 ? "" : "s"), not relayed"
        if mentionsPageDialog(lines.joined(separator: " ")) {
            let line = (lines.contains { $0.hasPrefix("Error:") } ? "Error: " : "") + pageDialogLine
            guard rest > 0 else { return SafariFailure(line: line, note: nil) }
            return SafariFailure(line: line, note: more + ": with a JavaScript dialog open they can carry the dialog's text (the page's), "
                + "and its own error line is among them. The user can see the dialog in Safari and dismiss it there.")
        }
        let line = redactingURLs(lines.first { $0.hasPrefix("Error:") } ?? lines[0])
        guard rest > 0 else { return SafariFailure(line: line, note: nil) }
        let note = more + ": its error output can list the tabs of other windows and profiles. The command is shown without its URL and script, "
            + "so it cannot be re-run as printed. To see what it was about, the user can look at the tab in Safari, or list their own tabs with "
            + "`safari-browser documents --profile \"<their profile>\"`."
        return SafariFailure(line: line, note: note)
    }

    /// stderr 裡有沒有 `pageDialogMarkers` 的其中一個。
    static func mentionsPageDialog(_ text: String) -> Bool {
        pageDialogMarkers.contains { m in
            m.caseInsensitive ? text.range(of: m.text, options: .caseInsensitive) != nil : text.contains(m.text)
        }
    }

    /// 去掉終端機的控制序列：ESC 開頭的 CSI（`ESC [` 參數、中間字元、結尾字元）、OSC（`ESC ]` 到 BEL 或 `ESC \`）、其餘的 `ESC` 加一個字元，
    /// 以及 C1 的 CSI（U+009B）。以 Unicode scalar 處理。沒有結尾的序列連同後面的字一起去掉（截斷的序列不留半個）。
    static func withoutTerminalEscapes(_ s: String) -> String {
        let a = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        func skipCSI(from start: Int) -> Int {   // 回傳結尾字元之後的位置
            var j = start
            while j < a.count, (0x20...0x3F).contains(a[j].value) { j += 1 }
            return j < a.count && (0x40...0x7E).contains(a[j].value) ? j + 1 : a.count
        }
        while i < a.count {
            let v = a[i].value
            if v == 0x1B, i + 1 < a.count {
                switch a[i + 1].value {
                case 0x5B: i = skipCSI(from: i + 2)
                case 0x5D:
                    var j = i + 2
                    while j < a.count, a[j].value != 0x07, !(a[j].value == 0x1B && j + 1 < a.count && a[j + 1].value == 0x5C) { j += 1 }
                    i = j >= a.count ? a.count : (a[j].value == 0x07 ? j + 1 : j + 2)
                default: i += 2
                }
            } else if v == 0x1B {
                i += 1
            } else if v == 0x9B {
                i = skipCSI(from: i + 1)
            } else {
                out.append(a[i]); i += 1
            }
        }
        return String(out)
    }

    /// 文字裡的每一個網址先過 `plainURL`（b33 X3 第 12、24 則：`open:`、導航失敗、讀連結失敗三處先前原樣轉印 safari-browser 的 stderr，
    /// 回顯的簽章網址會帶著查詢字串出去）。b37 起只用在 `safariFailure` 轉印的那一行；`redactingPageText` 以它收尾。
    ///
    /// 網址在空白、`"`、`<`、`>` 處結束（WHATWG 在路徑、查詢、片段裡都把它們百分比編碼）。**不在 `'` 處結束**（b41＝b40 Z2 第 12 則）：
    /// WHATWG 不把帳密與路徑裡的 `'` 編碼，`https://u:SEC'RET@h/x?sig=1` 先前只比到 `https://u:SEC`，`'RET@h/x?sig=1` 原樣留下。代價：網址後面
    /// 緊接的 `'`（`'https://h/x'` 的結尾）算進網址——它在查詢裡時跟著查詢一起去掉。
    static func redactingURLs(_ text: String) -> String {
        let re = try! NSRegularExpression(pattern: #"(?i)(?<![A-Za-z0-9+.-])[a-z][a-z0-9+.-]*://[^\s"<>]+"#)   // 編譯期常數
        return replacing(re, in: text) { plainURL($0) }
    }

    /// 頁面給的字印出之前去憑證：連結那一段 JS 的回答（`unexpected answer from the link script`）與頁面給的 PDF 連結（`points off-site`）
    /// （#613 b41，b40 Z2 第 8、28 則；b43，b42 第 0、4、5、7、12、13 則；b45，b44 第 2、3、5、6、10、11、16、19、20 則與 INFO 28；b47，b46 第 0、1、4 則
    /// 與 INFO 16、19）。`plainURL`
    /// 只對**一個**網址負責：字串裡第二個網址、tab 與換行夾在 `://` 中間、special scheme 沒有兩個斜線的寫法，它都看不到。這裡分三步讀頁面給的字：
    ///
    /// 1. 去掉 ASCII tab、LF、CR（WHATWG 讀網址時去掉它們，`URLSplit` 同）：`https:/<tab>/u:p@h` 是帶帳密的網址。**代價**：夾在字之間的換行跟著
    ///    消失，`GET<LF>https://…` 印成 `GEThttps://…`（第 3 步從 `https:` 起算網址）。
    /// 2. **authority 的帳密**（`withoutPageUserinfo`）。authority 從這三種地方開始——**封閉列舉**：(a) special scheme（`http`、`https`、`ws`、`wss`、
    ///    `ftp`、`file`）加冒號、後面接任意個斜線或反斜線（`https:u:p@h`、`https:/\u:p@h`、`https:///u:p@h`）；(b) 兩個以上斜線或反斜線（`//u:p@h`、
    ///    `\\u:p@h`）；(c) 前一個 authority 以 special scheme 加冒號結尾（`//cdn.example https:` 這種，帳密裡可以有空白，所以前一個 authority 吞得掉
    ///    後面的 `https:`）時，緊接的一個斜線或反斜線（b44 第 2、5、6 則：b43 跳過了它，`https://u:p@h https:/v:SECRET@x/y` 的第二組帳密原樣印出；
    ///    b41 的正規表示式有涵蓋）。authority **只在 `/`、`\`、`?`、`#` 或字尾結束**——空白、`"`、`<`、`>`、NBSP、VT 不結束它（WHATWG 在帳密裡把它們
    ///    百分比編碼；b42 第 0、12、13 則），最後一個 `@` 之前去掉。authority 在反斜線結束、而反斜線之後到下一個 `/`、`?`、`#` 之前還有 `@` 時，
    ///    兩種讀法對哪一段是帳密說法不同（`plainURL` 的 `<ambiguous-host>`）：從 authority 開頭到那個 `/`、`?`、`#` 整段印成 `<ambiguous-host>`（b44
    ///    第 10、20 則與 INFO 28：先前第二個反斜線串被當成 (b) 的起點、剝掉了 `@`，`https://user:SECRET\\@pub.example/x` 印成 `https://user:SECRET/x`）。
    ///    **不剝的**：不是這三種起點之後的 `@`——沒有斜線的非 special scheme（`ssh:u:p@h`）、一個斜線（`/u:p@h`）、沒有 scheme 的 `u:p@h`；它們在
    ///    WHATWG 與 RFC 3986 兩種讀法裡都不是 authority。不看前面是不是字的邊界（第 1 步可能把前面的字接上來），代價是 `profile:x@y`、
    ///    `https: 寫信給 a@b` 這種字也被剝——頁面的字，寧可多剝。
    /// 3. **第一個網址**（`firstPageURLStart`：special scheme 加冒號、前一個字不是 `[A-Za-z0-9+.:/\-]` 的兩個以上斜線或反斜線、或 `scheme://`）：
    ///    - **查詢與片段**：它的第一個 `?` 或 `#` 到字尾整段去掉（WHATWG：查詢在 `#`、片段在字尾結束，空白不結束它們——b41 的網址在空白處結束，
    ///      `?title=a b&sig=SECRET` 的 ` b&sig=SECRET` 原樣印出）。
    ///    - **它的開頭到那個 `?`／`#`**（`pageURLBody`），三遍：(i) **整段當一個網址**（`withoutWholeURLParameters`）——刪掉 b43 把整段交給
    ///      `plainURL` 時會刪的：路徑參數（值是 `[^;/]*`，跨過空白、`"`、`<`、`>` 到下一個 `;`、`/`、`%3B`）、整段是 ASP.NET 群組的路徑段、authority
    ///      裡反斜線之後到第一個 `/` 的那一段（b47，b46 第 0、1、4 則與 INFO 19：b45 只有 (ii)、(iii)，值跨過界線時界線之後的部分原樣印出）；
    ///      (ii) 逐個以空白、`"`、`<`、`>`（`isPageURLBoundary`）分開的段處理——第一段交給 `plainURL`，之後的段有網址起點的從那裡交給 `plainURL`、
    ///      其餘只去路徑參數（b45：第一個網址沒有 `//` 時 `plainURL` 從後面的 `://` 切，`://` 之前的那一段 (i) 不碰，由這一遍去；ASP.NET 群組後面接著
    ///      空白與字時不是一整段，也由這一遍去——b44 第 3、11、16、19 則）；(iii) 整段再去一次路徑參數（`;名 字=值` 這種名字裡夾著空白的、
    ///      `(S(… …))` 這種群組裡夾著空白的，(i) 沒有涵蓋到的位置）。
    ///    - 第一個網址之前的字原樣。最後每一個 `scheme://` 再過一次 `redactingURLs`。
    ///
    /// **保證的範圍就是上面三步**（b44 第 2、5 則：b43 的 changelog 與這裡寫「每一個帳密」，對 (c) 那個形狀不成立）。**對 b43 的保證**（b47）：b43
    /// 第 3 步刪掉的這裡都刪——(i) 照 b43 的 `plainURL` 的切法、只刪不改（b43 對沒有 `//` 而後面接著 `://` 的網址，`://` 之前那一段什麼都不刪）；
    /// (ii)、(iii) 只再多刪。`FulltextB47Tests` 以 b43（`6bc979f7`）的副本當 oracle 差分。**不在保證裡的**（封閉列舉）：
    ///    - 沒有網址起點的字整串原樣（`GET /download/x.pdf?sig=SECRET` 的查詢不剝）；第一個網址之後的路徑裡，不透明的 token 與 DOI 分不出來，
    ///      原樣（與 `plainURL` 同一個邊界）。
    ///    - 第一個網址沒有 `//`、後面又有 `scheme://` 時，`://` 之前那一段的路徑參數跨過空白、`"`、`<`、`>` 的部分（`https:h/x;k=SEC RET https://z`
    ///      的 ` RET`）原樣——b43 那一整段原樣，b45 同這裡；要去就得把值之後到 `://` 的說明文字一起吞掉（b43 不吞）。
    ///    - 第 2 步印成 `<ambiguous-host>` 的那一段吞掉了唯一的網址起點時（`GET\\ws:\\…@/;a=SECRET`：`\\` 前一個字是 scheme 字元，不是起點），
    ///      第 3 步沒有網址可處理，之後的路徑參數、查詢與片段都原樣（b46 INFO 16；b45 同，b43 不印；#767）。
    ///    - 名字夾著空白的 `;名 字=值`、群組夾著空白的 `(S(… …))` 在第一個網址之後再出現時，(iii) 對它們以 `/` 分段去——值在下一個 `/` 或 `;`
    ///      結束；它不是一個「網址」的處理，只是多去一次。
    ///
    /// **線性**（b42 第 4、5、7 則）：b41 的帳密那一條是沒有錨點的正規表示式，每一個斜線、每一個 `https:` 都是新的起點、各自掃到字尾才失敗——
    /// 20,000 個斜線要 25 秒以上，頁面寫一個全是斜線的 `citation_pdf_url` 就讓 CLI 卡住。這裡第 2 步一遍、第 3 步一遍加每段各一遍，每個字看常數次；
    /// 第 2 步判兩種讀法時要看到下一個 `/`、`?`、`#` 之前有沒有 `@`，事先從後往前一遍算好、查表（b45）。**不先截短**：`@` 在截斷點之外的帳密，
    /// 前半段會留在印出的那一段裡（第 7 則）；`fail` 的 600 字截斷在去憑證之後。
    static func redactingPageText(_ text: String) -> String {
        let stripped = Scalars(text.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" })
        let withoutUserinfo = withoutPageUserinfo(stripped)
        guard let start = firstPageURLStart(withoutUserinfo) else { return redactingURLs(PyText.string(withoutUserinfo)) }
        let queryStart = withoutUserinfo[start...].firstIndex(where: { $0 == "?" || $0 == "#" }) ?? withoutUserinfo.count
        return redactingURLs(PyText.string(Scalars(withoutUserinfo[..<start])) + pageURLBody(Scalars(withoutUserinfo[start..<queryStart])))
    }

    /// 網址的界線：Unicode 的空白、`"`、`<`、`>`（b41 的網址、`redactingURLs` 的 `[^\s"<>]`）。`pageURLBody` 的段、`plainURL` 無 authority 分支裡
    /// 「那個網址本身」都在這裡結束（b47：兩處同一組）。
    static func isPageURLBoundary(_ c: Unicode.Scalar) -> Bool { c.properties.isWhitespace || c == "\"" || c == "<" || c == ">" }

    /// `redactingPageText` 第 3 步：第一個網址從開頭到第一個 `?`／`#` 之前（三遍，見那裡）。段的界線是 `isPageURLBoundary`，界線原樣留著。
    static func pageURLBody(_ whole: Scalars) -> String {
        let body = withoutWholeURLParameters(whole)   // (i)
        var out = "", i = 0, first = true            // (ii)
        while i < body.count {
            var j = i
            while j < body.count, isPageURLBoundary(body[j]) { j += 1 }
            out += PyText.string(Scalars(body[i..<j]))
            guard j < body.count else { break }
            var k = j
            while k < body.count, !isPageURLBoundary(body[k]) { k += 1 }
            let piece = Scalars(body[j..<k])
            if first {
                out += plainURL(PyText.string(piece))   // 第一段從網址起點開始（`firstPageURLStart`）
                first = false
            } else if let s = firstPageURLStart(piece) {
                out += withoutPathParameters(PyText.string(Scalars(piece[..<s]))) + plainURL(PyText.string(Scalars(piece[s...])))
            } else {
                out += withoutPathParameters(PyText.string(piece))
            }
            i = k
        }
        return withoutPathParameters(out)   // (iii)
    }

    /// `pageURLBody` 的第一遍 (i)（b47，b46 第 0、1、4 則與 INFO 19）：把整段當**一個**網址、照 b43 的 `plainURL` 的切法（b43 的第 3 步就是把
    /// 整段交給它），刪掉它會刪的東西——路徑的路徑參數與 ASP.NET 群組（`withoutPathParameters`）、authority 裡反斜線之後到第一個 `/` 的那一段
    /// （`hostPort` 不印它）。只刪、不改寫其餘的字（scheme 的大小寫、主機段由之後的逐段處理照 `plainURL` 印）。
    ///
    /// 這一遍的意義在**跨過界線的值**：逐段處理在空白、`"`、`<`、`>` 處切段，`;jsessionid=SEC RET` 的第一段去掉 `;jsessionid=SEC` 之後，
    /// ` RET` 落在下一段、`;名=` 已經不在，補不回來（b45 印出 `RET`，b43 不印）；值以引號或角括號開頭時整個值落在下一段（`;k="SECRET"`）。
    /// 整段讀時值是 `[^;/]*`，跨過那些界線到下一個 `;`、`/`、`%3B` 為止，與 b43 相同——**代價也與 b43 相同**：值之後到下一個 `/` 或 `;` 之前的字
    /// 一起去掉（`https://h/x;k=v more` 印成 `https://h/x`）。
    ///
    /// **b43 的 `plainURL` 不刪的這裡也不刪**：沒有 `//` 的網址後面接著 `scheme://` 時，`://` 之前那一段 b43 原樣印出，這裡不碰——吞下去就會把值
    /// 之後到 `://` 的說明文字一起吞掉。那一段的路徑參數由之後的逐段處理去掉，跨過界線的部分照樣印出（`redactingPageText` 的「不在保證裡的」）。
    static func withoutWholeURLParameters(_ body: Scalars) -> Scalars {
        func isSchemeChar(_ c: Unicode.Scalar) -> Bool {
            c.isASCII && (c.properties.isAlphabetic || ("0"..."9").contains(c) || c == "+" || c == "-" || c == ".")
        }
        /// `s[from...]` 是 authority 開頭（`//` 之後）：authority 裡反斜線之後的那一段刪掉，路徑去路徑參數
        func authorityAndPath(_ s: Scalars, from: Int) -> Scalars {
            let end = s[from...].firstIndex(of: "/") ?? s.count
            let kept = s[from..<end].firstIndex(of: "\\") ?? end
            return Scalars(s[from..<kept]) + Scalars(withoutPathParameters(PyText.string(Scalars(s[end...]))).unicodeScalars)
        }
        // scheme 照 `URLSplit` 讀（`body` 從網址起點開始、沒有 tab 與換行，不必去前導的空白）
        var afterScheme = 0
        if let colon = body.firstIndex(of: ":"), colon > 0, body[0].isASCII, body[0].properties.isAlphabetic, body[..<colon].allSatisfy(isSchemeChar) {
            afterScheme = colon + 1
        }
        if PyText.hasPrefix(body, ["/", "/"], at: afterScheme) {
            return Scalars(body[..<(afterScheme + 2)]) + authorityAndPath(body, from: afterScheme + 2)
        }
        guard let sep = body.indices.first(where: { PyText.hasPrefix(body, [":", "/", "/"], at: $0) }) else {
            return Scalars(withoutPathParameters(PyText.string(body)).unicodeScalars)
        }
        return Scalars(body[..<(sep + 3)]) + authorityAndPath(body, from: sep + 3)
    }

    private static func isSlash(_ c: Unicode.Scalar) -> Bool { c == "/" || c == "\\" }

    /// special scheme 加冒號（小寫）。`https` 在 `http` 之前、`wss` 在 `ws` 之前：先比長的。
    private static let specialSchemes: [Scalars] = ["https:", "http:", "wss:", "ws:", "ftp:", "file:"].map { Scalars($0.unicodeScalars) }

    /// `s[i...]` 以 special scheme 加冒號開頭（大小寫不分）時，冒號之後的位置。
    private static func specialSchemeEnd(_ s: Scalars, at i: Int) -> Int? {
        switch s[i] {   // 每個位置都會問一次：先以第一個字擋掉
        case "h", "H", "w", "W", "f", "F": break
        default: return nil
        }
        for p in specialSchemes {
            guard i + p.count <= s.count else { continue }
            if (0..<p.count).allSatisfy({ k in
                let c = s[i + k]
                return c == p[k] || (c.isASCII && c.properties.isUppercase && Unicode.Scalar(c.value + 0x20) == p[k])
            }) { return i + p.count }
        }
        return nil
    }

    /// `redactingPageText` 的第 2 步：authority 的帳密去掉（三種起點與兩種讀法見那裡）。一遍掃完：authority 結束之前不會再有新的起點——它不含
    /// 斜線，裡面的 special scheme 後面若不是斜線，它的 authority 結束在同一個地方，而最後一個 `@` 已經去掉了；後面若是斜線，那個斜線就是
    /// 這個 authority 結束的地方，記下來、下一圈從那裡當起點 (c)。
    static func withoutPageUserinfo(_ s: Scalars) -> Scalars {
        // 每個位置之後第一個 `/`、`?`、`#`（RFC 3986／Python 讀 authority 的結束：不在 `\` 結束）與第一個 `@`——從後往前一遍算好，
        // 判兩種讀法時查表，不必每個 authority 再往後掃
        var rfcEnd = [Int](repeating: s.count, count: s.count + 1), nextAt = rfcEnd
        for j in stride(from: s.count - 1, through: 0, by: -1) {
            rfcEnd[j] = s[j] == "/" || s[j] == "?" || s[j] == "#" ? j : rfcEnd[j + 1]
            nextAt[j] = s[j] == "@" ? j : nextAt[j + 1]
        }
        let ambiguous = Scalars(ambiguousHost.unicodeScalars)
        var out = Scalars()
        out.reserveCapacity(s.count)
        var i = 0, schemeEndsHere = false   // 上一個 authority 以 special scheme 加冒號結尾、結束在 `i` 的斜線上：起點 (c)
        while i < s.count {
            var start: Int? = nil
            if let k = specialSchemeEnd(s, at: i) {
                var m = k
                while m < s.count, isSlash(s[m]) { m += 1 }
                start = m
            } else if isSlash(s[i]) {
                var m = i
                while m < s.count, isSlash(s[m]) { m += 1 }
                if m - i >= 2 || schemeEndsHere { start = m }
            }
            schemeEndsHere = false
            guard let from = start else { out.append(s[i]); i += 1; continue }
            out.append(contentsOf: s[i..<from])
            var end = from, lastAt: Int? = nil
            while end < s.count, !isSlash(s[end]), s[end] != "?", s[end] != "#" {
                if s[end] == "@" { lastAt = end }
                end += 1
            }
            if end < s.count, s[end] == "\\", nextAt[end] < rfcEnd[end] {   // 兩種讀法對帳密說法不同
                // 整段印成 `<ambiguous-host>`，直到下一個 `/`、`?`、`#`——但結尾的反斜線串留給下一圈：它接著那個 `/` 可能是下一個
                // authority 的開頭 (b)；這一段若以 special scheme 加冒號結尾，那個斜線是它的 authority 的開頭 (c)
                var q = rfcEnd[end]
                while q > end, s[q - 1] == "\\" { q -= 1 }
                out.append(contentsOf: ambiguous)
                schemeEndsHere = q < s.count && isSlash(s[q]) && specialSchemeEnds(s, at: q, notBefore: from)
                i = q
                continue
            }
            out.append(contentsOf: s[(lastAt.map { $0 + 1 } ?? from)..<end])
            schemeEndsHere = end < s.count && isSlash(s[end]) && specialSchemeEnds(s, at: end, notBefore: from)
            i = end
        }
        return out
    }

    /// `s[..<e]` 以 special scheme 加冒號結尾，而它從 `from` 或之後開始。
    private static func specialSchemeEnds(_ s: Scalars, at e: Int, notBefore from: Int) -> Bool {
        specialSchemes.contains { p in e - p.count >= from && specialSchemeEnd(s, at: e - p.count) == e }
    }

    /// `redactingPageText` 的第 3 步：第一個網址從哪裡開始（沒有網址回 nil）。三種起點與 b41 的三條正規表示式相同（special scheme 加冒號、
    /// 前一個字不是 `[A-Za-z0-9+.:/\-]` 的兩個以上斜線或反斜線、前一個字不是 `[A-Za-z0-9+.-]` 的 `scheme://`），只是不再在空白處結束。
    static func firstPageURLStart(_ s: Scalars) -> Int? {
        func isSchemeChar(_ c: Unicode.Scalar) -> Bool {
            c.isASCII && (c.properties.isAlphabetic || ("0"..."9").contains(c) || c == "+" || c == "." || c == "-")
        }
        var i = 0
        while i < s.count {
            if specialSchemeEnd(s, at: i) != nil { return i }
            let prev: Unicode.Scalar? = i > 0 ? s[i - 1] : nil
            if isSlash(s[i]), i + 1 < s.count, isSlash(s[i + 1]), !(prev.map { isSchemeChar($0) || $0 == ":" || isSlash($0) } ?? false) {
                return i
            }
            if s[i].isASCII, s[i].properties.isAlphabetic, !(prev.map(isSchemeChar) ?? false) {
                var k = i
                while k < s.count, isSchemeChar(s[k]) { k += 1 }
                if PyText.hasPrefix(s, [":", "/", "/"], at: k) { return i }
                // 這一段 scheme 字元之內的位置前一個字都是 scheme 字元，不是起點；跳過去（special scheme 已在每個位置上問過，見下）
                for j in (i + 1)..<k where specialSchemeEnd(s, at: j) != nil { return j }
                i = k
                continue
            }
            i += 1
        }
        return nil
    }

    /// `re` 的每一個比對換成 `transform` 的結果，其餘原樣。
    private static func replacing(_ re: NSRegularExpression, in text: String, _ transform: (String) -> String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += transform(ns.substring(with: m.range))
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
