import Foundation

/// 網站是不是開始懷疑是自動化？是的話停下（#629 由 `bot_signals.py` 移植）。
///
/// 這是 skill 的中止條款（`akashic-fetch-fulltext/SKILL.md`〈中止條款〉）。使用者的標準是「任何網站起疑的跡象」——所以
/// **寧可多停**：誤停的代價是使用者看一眼，漏掉一個訊號的代價是出版商把使用者機構的 session 封掉。
///
/// # 命中之後分兩種（#613，使用者 2026-09-28、2026-10-01 裁決）
///
/// - **等人驗證**（`Response.humanVerification`）：只有 CAPTCHA、人類檢查、Cloudflare「Just a moment」、按住驗證這四種標籤
///   （`humanVerificationLabels`，封閉列舉）。暫停這一篇、請使用者在自己的 Safari 裡完成驗證；使用者說好了之後**在同一個分頁**
///   接著走（不重新載入、不換站、不代解）。
/// - **整批暫停**（`Response.pauseBatch`）：其他所有標籤與 HTTP 403／429——封鎖頁、異常流量、請求過多、PMC 的下載前驗證頁、
///   ScienceDirect 的「Preparing your download」中介頁。整批停下，交給使用者。
///
/// **同一頁同時命中兩種時，整批暫停優先**（`classify`）：PerimeterX 的封鎖頁同時寫著「Access to this page has been denied」與
/// 「Press & Hold」、DataDome 的挑戰頁網址含 `captcha`——拿不準就往停的那一邊倒。**HTTP 429 一律整批暫停**，不論頁面文字（只有 403
/// 的驗證頁文字可以優先於狀態碼）；等人驗證還要看**主機**：只有文章站本身或已知的驗證服務上才成立（使用者 2026-10-02）。
///
/// 下面的樣式是**下限**，不是定義。SKILL.md 要求 agent 在讀起來像起疑時照停，即使這裡一條都沒命中。
///
/// 已知且接受的誤判：落地頁檢查讀文章頁的前 3000 字，所以一篇**談** CAPTCHA、存取控制或流量限制的文章會讓 run 停下。這是
/// 刻意的——停下的回報會寫明訊號，由使用者決定那一篇要不要重跑。為了避免誤判而收窄樣式，是拿方便換漏掉挑戰頁，而那是貴的
/// 方向。
public enum BotSignals {
    /// Python `\w`（str 樣式）的補集當「不是字詞字元」：Python 的 `\b` 只把字母、數字與底線當字詞字元，組合標記與 ZWJ／ZWNJ
    /// **不是**；ICU 的 `\b` 相反（`\w` 含 `\p{M}` 與 U+200C／U+200D）。同一句 `rate limit` 後面接一個組合標記或 ZWJ，Python 命中、
    /// ICU 的 `\b` 不命中——中止條款的下限變弱（#629 R1 verify 第 25／43 則）。所以兩個 `\b` 都換成明寫字元類的前後查（測試對全部
    /// Unicode scalar 驗這個類與 `PyText.isWord` 一致——**用生產的編譯選項**）。
    ///
    /// 字元類包在 `(?-i:…)` 裡：ICU 在 `.caseInsensitive` 下會把字元類對大小寫折疊取閉包，U+0345（COMBINING GREEK YPOGEGRAMMENI，Mn）折成
    /// U+03B9（ι）而被拉進 `[\p{L}\p{N}_]`，於是 `access denied` 後面緊接 U+0345 時不命中；Python 不會（R2 verify 第 19 則）。字元類本身不需要
    /// 不分大小寫——字母不論大小寫都已在 `\p{L}` 裡。
    static let wordClass = #"(?-i:[\p{L}\p{N}_])"#
    static let wordStart = "(?<!" + wordClass + ")"
    static let wordEnd = "(?!" + wordClass + ")"

    /// 每一項是（標籤，樣式）。有觀察日期的是實際遇到的；其餘是常見挑戰頁的標準用語，留著是因為「停」是便宜的那一邊。
    static let signals: [(label: String, pattern: String)] = [
        // 先列廠商專屬的，讓停止報告點名廠商而不是泛稱（captcha-delivery.com 含 "captcha"）。這個 skill 的 run 還沒遇過；
        // 是標準封鎖頁用語。只收**整句**封鎖頁文字：單獨的 "press and hold"、"automation tools" 是 HCI 與軟體論文的
        // 一般用語（審查，2026-09-24），不像 "captcha" 那樣，即使出現在文章裡談的也是機器人偵測。
        ("akamai-block", #"pardon our interruption"#),
        // PerimeterX 的「按住驗證」是等人驗證；同一家的封鎖句是整批暫停（#613 把原本的一個標籤拆成兩個，使用者 2026-10-01 裁決）
        ("perimeterx-press-and-hold", #"press (&|and) hold to confirm|px-captcha"#),
        ("perimeterx-block", #"access to this page has been denied|believe you are using automation"#),
        ("datadome-block", #"datadome|captcha-delivery\.com"#),
        ("cloudflare-challenge", #"just a moment\.\.\.|cf-chl|challenge-platform|cf_chl_"#),   // OUP, 2026-09-23
        // ScienceDirect 點 View PDF 之後的中介頁（2026-09-28 觀察：「Preparing your download」、腳本 `cra_js_challenge`）；
        // 使用者 2026-10-01 裁決為起疑訊號、整批暫停。PMC 的是「preparing **to** download」，字樣不同，所以另列
        ("sciencedirect-download-challenge", #"preparing your download|cra_js_challenge"#),
        ("captcha", #"captcha|hcaptcha|recaptcha|turnstile"#),
        ("human-check", #"are you (a )?(robot|human)|verify (that )?you('| a)re (a )?human|prove you('| a)re human|i'?m not a robot"#),
        ("unusual-traffic", #"unusual (traffic|activity)|automated (access|requests|queries|traffic)|suspicious activity"#),
        ("rate-limit", #"too many requests|rate limit(ed)?\#(BotSignals.wordEnd)"#),
        ("access-denied", #"\#(BotSignals.wordStart)access denied\#(BotSignals.wordEnd)|request (was )?blocked|you have been blocked"#),
        ("pmc-pow-challenge", #"preparing to download|proof[- ]of[- ]work|checking your browser"#),   // PMC, 2026-09-23
    ]

    // 403 與 429 本身就是起疑（`classify`）：付費牆回 200 加登入頁（PsycNet，2026-09-23），不是 403。OUP 的 403 是 Cloudflare 頁。

    /// 生產的編譯選項（測試用同一份，R2 verify 第 19 則）。
    static let regexOptions: NSRegularExpression.Options = [.caseInsensitive]

    private static let compiled: [(label: String, regex: NSRegularExpression)] = signals.map {
        ($0.label, try! NSRegularExpression(pattern: $0.pattern, options: regexOptions))   // 樣式是編譯期常數
    }

    /// Python 的 `re.I` 把 U+0130（İ）與 U+0131（ı）當成 `i`（簡單大小寫對映）；ICU 的不分大小寫比對不會（土耳其文 i 的兩種寫法）。
    /// `innerText` 會套用 CSS `text-transform: uppercase`，`lang=tr` 的頁面把 `i` 變成 `İ`，所以這不是純理論。比對前先折成 `i`
    /// （其餘 `ſ`、Kelvin sign 兩邊本來就一致，測試釘住）。
    static func foldDotlessAndDottedI(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value == 0x130 || $0.value == 0x131 }) else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.map { $0.value == 0x130 || $0.value == 0x131 ? "i" : $0 }))
    }

    /// 命中之後的處置（#613）。`rawValue` 是 `bot-signals --kind` 印的字。
    public enum Response: String, Equatable {
        /// 等人驗證：暫停這一篇，使用者驗證完在同一個分頁接著走
        case humanVerification = "verify"
        /// 整批暫停，交給使用者
        case pauseBatch = "pause"
    }

    public struct Hit: Equatable {
        public let label: String
        public let response: Response
    }

    /// 等人驗證的標籤——**封閉列舉，只有這四個**（使用者 2026-10-01：captcha、人類檢查、Cloudflare「Just a moment」、按住驗證）。
    /// 不得依「看起來也是驗證頁」類推第五個：PMC 的下載前驗證頁與 ScienceDirect 的中介頁同樣是挑戰頁，使用者把它們裁在整批暫停。
    static let humanVerificationLabels: Set<String> = ["captcha", "human-check", "cloudflare-challenge", "perimeterx-press-and-hold"]

    /// 命中的訊號與處置；沒有則 nil。
    ///
    /// 優先順序（#613；2026-10-02 修正輪）：
    /// 1. 文字裡有**整批暫停**的標籤 → 整批暫停（同類之內照清單順序）。一頁同時帶著兩種文字訊號時往停的那一邊倒。
    ///    例外：`pmc-pow-challenge` 的通用字樣（`checking your browser`、`proof of work`）與 Cloudflare 自己的標記
    ///    （`just a moment...` 等，`cloudflare-challenge`）同頁、而頁面沒有 PMC 專屬的 `preparing to download` 時，那是 Cloudflare 的
    ///    經典挑戰頁（它也寫「Checking your browser before accessing…」），不是 PMC 的驗證頁，往下走成等人驗證。
    /// 2. **HTTP 429 → 整批暫停**（`http-429`），不看文字是什麼：請求過多是站方在限流，不是一個等人去點的驗證頁。先前文字優先於
    ///    403 與 429 兩者，429 的頁面只要帶一個 CAPTCHA 字樣就被降成等人驗證（使用者 2026-10-02 裁決改回整批暫停）。
    /// 3. 文字裡有**等人驗證**的標籤 → 等人驗證，**即使 `status` 是 403**：挑戰頁本身常以 403 回應（Cloudflare 的文件這樣寫，
    ///    本 repo 沒有實測）。狀態碼若優先，使用者列為等人驗證的 Cloudflare「Just a moment」與 2026-09-28 ScienceDirect 的 CAPTCHA 頁
    ///    在看得到狀態碼的時候就永遠走不到等人驗證。**這個例外只給 403，不給 429。**
    /// 4. 文字沒有訊號、`status` 是 403 → `http-403`，整批暫停。
    ///
    /// 這裡只決定標籤的**處置種類**；等人驗證能不能成立還要看**主機**（`FulltextFetch`：只有文章站本身或已知的驗證服務，
    /// `isKnownVerificationService`），其他主機上的驗證字樣一律整批暫停（使用者 2026-10-02）。
    public static func classify(_ text: String, status: Int? = nil) -> Hit? {
        let text = foldDotlessAndDottedI(text)
        let range = NSRange(text.startIndex..., in: text)
        let matched = compiled.filter { $0.regex.firstMatch(in: text, options: [], range: range) != nil }.map(\.label)
        let cloudflare = matched.contains("cloudflare-challenge")
        for label in matched where !humanVerificationLabels.contains(label) {
            if label == "pmc-pow-challenge", cloudflare, text.range(of: "preparing to download", options: .caseInsensitive) == nil { continue }
            return Hit(label: label, response: .pauseBatch)
        }
        if status == 429 { return Hit(label: "http-429", response: .pauseBatch) }
        if let label = matched.first(where: { humanVerificationLabels.contains($0) }) { return Hit(label: label, response: .humanVerification) }
        if status == 403 { return Hit(label: "http-403", response: .pauseBatch) }
        return nil
    }

    /// 命中的訊號標籤；沒有則 nil（`classify` 的標籤，同一套優先順序）。文字沒有訊號而 `status` 是 403／429 時回 `http-<status>`。
    public static func detect(_ text: String, status: Int? = nil) -> String? {
        classify(text, status: status)?.label
    }

    // MARK: 登入／驗證頁的長相（分頁離開文章站之後，沒有任何訊號標籤時的第二道檢查）

    /// 網址主機與路徑的字詞（不看查詢字串：簽章網址的查詢是一長串隨機字元）出現下列任何一個，或標題帶下列片語，就是「登入頁」／
    /// 「驗證頁」的長相。**封閉清單**，不是偵測訊號的下限：它只決定「分頁到了別的主機、沒有任何標籤命中」時是整批暫停還是交給人
    /// （使用者 2026-10-02：登入頁、驗證頁、封鎖頁維持整批暫停；其餘沒有標記的頁面交給人）。拿不準時往停的那一邊倒，但清單不得
    /// 依「看起來也像」擴張——一個被誤判成登入頁的 CDN 主機只是多停一次，漏掉一個登入頁則會把使用者導去輸入帳密。
    static let loginTokens: Set<String> = ["login", "logon", "signin", "sso", "auth", "authenticate", "shibboleth", "saml", "openathens", "wayf", "idp", "cas"]
    static let verificationTokens: Set<String> = ["verify", "verification", "challenge", "captcha", "validate", "turnstile"]
    static let loginTitlePhrases = ["sign in", "sign-in", "log in", "log-in", "login", "single sign-on", "authentication required"]
    static let verificationTitlePhrases = ["verify", "verification", "are you a human", "are you a robot"]

    /// `"login"`、`"verification"`，或 nil（沒有登入／驗證頁的長相）。
    public static func gateLook(url: String, title: String) -> String? {
        let parts = URLSplit(url)
        let hostAndPath = (PyText.string(parts.netloc) + " " + parts.path).lowercased()
        var tokens = Set(hostAndPath.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for compound in ["sign-in", "sign_in", "log-in", "log_in"] where hostAndPath.contains(compound) { tokens.insert("signin") }
        let lowerTitle = title.lowercased()
        if !tokens.isDisjoint(with: loginTokens) || loginTitlePhrases.contains(where: { lowerTitle.contains($0) }) { return "login" }
        if !tokens.isDisjoint(with: verificationTokens) || verificationTitlePhrases.contains(where: { lowerTitle.contains($0) }) { return "verification" }
        return nil
    }

    // MARK: 已知的驗證服務（等人驗證能成立的第二種主機）

    /// 等人驗證只在兩種主機上成立（使用者 2026-10-02）：文章站本身，或下面這份**封閉**的驗證服務清單（Cloudflare 挑戰、hCaptcha、
    /// reCAPTCHA）。其他主機上出現驗證字樣或網址標記，一律整批暫停——任何 DOI 註冊者都能讓落地頁落在自己的主機，而假的 CAPTCHA 頁
    /// （要使用者貼上指令到終端機那一類）正是利用「請完成這個驗證」的信任。不得依「看起來也是驗證服務」類推第四個。
    static let knownVerificationHosts: [String] = ["challenges.cloudflare.com", "hcaptcha.com", "recaptcha.net"]

    /// reCAPTCHA 也從 google.com 提供：只收 `/recaptcha/` 路徑，不收 google.com 的其他頁。
    static let knownVerificationPathPrefixes: [(host: String, prefix: String)] = [("www.google.com", "/recaptcha/"), ("google.com", "/recaptcha/")]

    /// 這個網址在不在已知的驗證服務上（主機等於清單裡的某個、或是它的子網域；https 才算）。
    public static func isKnownVerificationService(url: String) -> Bool {
        let parts = URLSplit(url)
        guard PyText.string(parts.scheme) == "https" else { return false }
        let host = PyText.string(parts.netloc).lowercased()
        if knownVerificationHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        return knownVerificationPathPrefixes.contains { host == $0.host && parts.path.hasPrefix($0.prefix) }
    }
}
