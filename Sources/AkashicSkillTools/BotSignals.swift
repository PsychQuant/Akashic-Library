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
/// 「Press & Hold」、DataDome 的挑戰頁網址含 `captcha`——拿不準就往停的那一邊倒。
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

    /// 403 與 429 本身就是起疑：付費牆回 200 加登入頁（PsycNet，2026-09-23），不是 403。OUP 的 403 是 Cloudflare 頁。
    static let suspiciousStatus: Set<Int> = [403, 429]

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
    /// 優先順序（#613）：
    /// 1. 文字裡有**整批暫停**的標籤 → 整批暫停（同類之內照清單順序）。一頁同時帶著兩種文字訊號時往停的那一邊倒。
    /// 2. 文字裡有**等人驗證**的標籤 → 等人驗證，**即使 `status` 是 403／429**：挑戰頁本身常以 403 回應（Cloudflare 的文件這樣寫，
    ///    本 repo 沒有實測）。狀態碼若優先，使用者列為等人驗證的 Cloudflare「Just a moment」與 2026-09-28 ScienceDirect 的 CAPTCHA 頁
    ///    在看得到狀態碼的時候就永遠走不到等人驗證。
    /// 3. 文字沒有訊號、`status` 是 403／429 → `http-<status>`，整批暫停。
    public static func classify(_ text: String, status: Int? = nil) -> Hit? {
        let text = foldDotlessAndDottedI(text)
        let range = NSRange(text.startIndex..., in: text)
        var firstVerification: String?
        for (label, regex) in compiled where regex.firstMatch(in: text, options: [], range: range) != nil {
            if humanVerificationLabels.contains(label) {
                if firstVerification == nil { firstVerification = label }
            } else {
                return Hit(label: label, response: .pauseBatch)
            }
        }
        if let label = firstVerification { return Hit(label: label, response: .humanVerification) }
        if let status, suspiciousStatus.contains(status) { return Hit(label: "http-\(status)", response: .pauseBatch) }
        return nil
    }

    /// 命中的訊號標籤；沒有則 nil（`classify` 的標籤，同一套優先順序）。文字沒有訊號而 `status` 是 403／429 時回 `http-<status>`。
    public static func detect(_ text: String, status: Int? = nil) -> String? {
        classify(text, status: status)?.label
    }
}
