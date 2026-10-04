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

    // MARK: 驗證服務自己的標記（讀不到的分頁只看這些）

    /// 驗證或封鎖**服務**自己的標記——**封閉列舉，只有這六個標籤**（#613 R3，b31 W4 第 3、4 則）。不得依「看起來也是服務的字樣」類推第七個。
    ///
    /// 用在讀不到頁面的分頁上（Safari 的 PDF 檢視器可能不跑頁面 JS）：那裡只剩標題與網址，而 PDF 分頁的標題常常就是文章標題。一般字詞
    /// （`captcha`、`verify you are human`、`unusual traffic`、`access denied`、`rate limit`）在文章標題裡是常見的研究主題，所以不在這份清單；
    /// 這六個標籤的樣式寫的是廠商或服務自己的頁面用語與網址（`Just a moment...`、`captcha-delivery.com`、`cra_js_challenge`…）。
    /// `pmc-pow-challenge` 刻意不收：它的樣式含 `proof of work`、`checking your browser` 這類一般字詞，而 PMC 的驗證頁在文章站本身，
    /// 是讀得到的 HTML 頁。
    static let serviceMarkerLabels: Set<String> = ["akamai-block", "perimeterx-press-and-hold", "perimeterx-block", "datadome-block",
                                                   "cloudflare-challenge", "sciencedirect-download-challenge"]

    /// 文字裡驗證服務自己的標記（`serviceMarkerLabels`）；沒有則 nil。整批暫停的標籤優先，與 `classify` 同一個方向。
    public static func serviceMarker(_ text: String) -> Hit? {
        let text = foldDotlessAndDottedI(text)
        let range = NSRange(text.startIndex..., in: text)
        let matched = compiled.filter { serviceMarkerLabels.contains($0.label) && $0.regex.firstMatch(in: text, options: [], range: range) != nil }.map(\.label)
        if let label = matched.first(where: { !humanVerificationLabels.contains($0) }) { return Hit(label: label, response: .pauseBatch) }
        if let label = matched.first { return Hit(label: label, response: .humanVerification) }
        return nil
    }

    // MARK: 登入／驗證頁的長相（分頁離開文章站之後，沒有任何訊號標籤時的第二道檢查）

    /// 網址的主機與路徑（不看查詢字串與片段：簽章網址的查詢是一長串隨機字元）出現下列任何一個字詞，或標題帶下列片語，就是「登入頁」／
    /// 「驗證頁」的長相。**封閉清單**，不是偵測訊號的下限：它只決定「分頁到了別的主機、沒有任何標籤命中」時是整批暫停還是交給人
    /// （使用者 2026-10-02：登入頁、驗證頁、封鎖頁維持整批暫停；其餘沒有標記的頁面交給人）。拿不準時往停的那一邊倒，但清單不得
    /// 依「看起來也像」擴張——一個被誤判成登入頁的 CDN 主機只是多停一次，漏掉一個登入頁則會把使用者導去輸入帳密。
    ///
    /// **怎麼比**（#613 R2 verify 第 1、2、6、8 則：先前三個面都是子字串，`Research design in …` 因為 `design in` 含 `sign in` 被判成登入頁、
    /// `/10.1111/cas.12345.pdf` 因為 DOI 片段 `cas` 被判成登入頁）：
    /// - **主機**：以非字母數字切開的每個字詞（`sso.uni.example`、`idp-prod.uni.example`），另加去掉連字號的整個標籤（`sign-in.example`）。
    /// - **路徑**：**整段**比（`/login`、`/cas/login`）。一段可以帶一個網頁副檔名（`pageExtensions`：`/login.php`），可以有 `;` 之後的路徑參數
    ///   （`/login;jsessionid=…`），連字號與底線可省（`/sign-in`、`/log_in`）。不從一段裡切出片段——DOI 與檔名的一部分不是登入頁。
    /// - **標題**：片語是**整個字詞**的連續序列（`Please log in to continue` 是，`Analog input` 不是；`Sign-In` 與 `sign in` 同一個片語）。
    static let loginTokens: Set<String> = ["login", "logon", "signin", "sso", "auth", "authenticate", "shibboleth", "saml", "openathens", "wayf", "idp", "cas"]
    static let verificationTokens: Set<String> = ["verify", "verification", "challenge", "captcha", "validate", "turnstile"]
    static let loginTitlePhrases = ["sign in", "sign-in", "log in", "log-in", "login", "single sign-on", "authentication required"]
    static let verificationTitlePhrases = ["verify", "verification", "are you a human", "are you a robot"]
    /// 路徑的一段可以帶的網頁副檔名（**封閉清單**）。`cas.12345`、`cas.12345.pdf` 的「副檔名」不在這裡，所以那一段不是 `cas`。
    static let pageExtensions: Set<String> = ["php", "asp", "aspx", "jsp", "do", "action", "cgi", "htm", "html", "pl"]

    /// `"login"`、`"verification"`，或 nil（沒有登入／驗證頁的長相）。網址與標題任一邊有登入頁的長相就是 `login`，否則看驗證頁。
    public static func gateLook(url: String, title: String) -> String? {
        let looks = [urlGateLook(url), titleGateLook(title)]
        if looks.contains("login") { return "login" }
        if looks.contains("verification") { return "verification" }
        return nil
    }

    /// 只看網址（主機與路徑）的那一半。DOI 落地頁用它：落地頁的標題是文章標題，標題片語在那裡只會誤判。
    public static func urlGateLook(_ url: String) -> String? {
        let parts = URLSplit(url)
        let host = PyText.string(parts.netloc).lowercased()
        var words = Set(host.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for label in host.split(separator: ".") { words.insert(label.replacingOccurrences(of: "-", with: "")) }
        for segment in parts.path.split(separator: "/") { words.formUnion(pathSegmentWords(String(segment))) }
        if !words.isDisjoint(with: loginTokens) { return "login" }
        if !words.isDisjoint(with: verificationTokens) { return "verification" }
        return nil
    }

    /// 路徑的一段 → 拿來比的字（整段；去掉 `;` 之後的路徑參數與一個網頁副檔名；另一個去掉連字號與底線的寫法）。
    static func pathSegmentWords(_ raw: String) -> Set<String> {
        var segment = (raw.removingPercentEncoding ?? raw).lowercased()
        if let semicolon = segment.firstIndex(of: ";") { segment = String(segment[..<semicolon]) }
        if let dot = segment.lastIndex(of: "."), pageExtensions.contains(String(segment[segment.index(after: dot)...])) {
            segment = String(segment[..<dot])
        }
        return [segment, segment.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")]
    }

    /// 只看標題的那一半：片語是整個字詞的連續序列。
    public static func titleGateLook(_ title: String) -> String? {
        let words = titleWords(title)
        let has: (String) -> Bool = { phrase in
            let p = titleWords(phrase)
            guard !p.isEmpty, p.count <= words.count else { return false }
            return (0...(words.count - p.count)).contains { Array(words[$0..<($0 + p.count)]) == p }
        }
        if loginTitlePhrases.contains(where: has) { return "login" }
        if verificationTitlePhrases.contains(where: has) { return "verification" }
        return nil
    }

    /// 標題切成字詞：字母與數字以外的一律是分隔（`Sign-In` → `sign`、`in`）。
    static func titleWords(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    // MARK: 已知的驗證服務（等人驗證能成立的第二種主機）

    /// 等人驗證只在兩種主機上成立（使用者 2026-10-02）：文章站本身，或下面這份**封閉**的驗證服務清單（Cloudflare 挑戰、hCaptcha、
    /// reCAPTCHA）。其他主機上出現驗證字樣或網址標記，一律整批暫停。不得依「看起來也是驗證服務」類推第四個。
    ///
    /// **這條規則擋得住什麼、擋不住什麼**（#613 R2 verify 第 5、28、29 則）：它擋的是**之後的轉址**——文章站把分頁送到另一個主機，
    /// 那個主機要人驗證。它**擋不住文章站本身**：文章站就是 doi.org 解析到的主機，而那是 DOI 註冊者決定的，所以註冊者自己架的假 CAPTCHA 頁
    /// （要使用者貼上指令到終端機那一類）落在文章站上仍是等人驗證（結束碼 8）——使用者的裁決是文章站算，行為照裁決。那一格唯一的防線是
    /// **使用者自己看頁面**：程式與 agent 都看不到頁面，所以結束碼 8 的訊息要 agent 請使用者看、頁面要求貼上或執行任何東西就整批停、
    /// 只在使用者說完成之後接著走。
    static let knownVerificationHosts: [String] = ["challenges.cloudflare.com", "hcaptcha.com", "recaptcha.net"]

    /// reCAPTCHA 也從 google.com 提供：只收 `/recaptcha/` 路徑，不收 google.com 的其他頁。
    static let knownVerificationPathPrefixes: [(host: String, prefix: String)] = [("www.google.com", "/recaptcha/"), ("google.com", "/recaptcha/")]

    /// 這個網址在不在已知的驗證服務上（主機等於清單裡的某個、或是它的子網域；https 才算）。主機要是一個乾淨的 DNS 名稱——每個標籤只有
    /// ASCII 字母、數字與連字號：主機段夾著反斜線、分號、百分比編碼、空白、帳密（`@`）或埠號（`:`）時不算（R2 verify 第 31 則：先前對原樣的
    /// 主機段比字尾，`evil.example\.hcaptcha.com` 也算已知）。
    public static func isKnownVerificationService(url: String) -> Bool {
        let parts = URLSplit(url)
        guard PyText.string(parts.scheme) == "https" else { return false }
        let host = PyText.string(parts.netloc).lowercased()
        guard isPlainDNSName(host) else { return false }
        if knownVerificationHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        return knownVerificationPathPrefixes.contains { host == $0.host && parts.path.hasPrefix($0.prefix) }
    }

    /// 每個標籤非空、只有 ASCII 字母、數字與連字號。
    static func isPlainDNSName(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "-") }
        }
    }
}
