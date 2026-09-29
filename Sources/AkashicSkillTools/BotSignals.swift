import Foundation

/// 網站是不是開始懷疑是自動化？是的話，整個 run 停下（#629 由 `bot_signals.py` 移植）。
///
/// 這是 skill 的中止條款（`akashic-fetch-fulltext/SKILL.md`〈中止條款〉）。使用者的標準是「任何網站起疑的跡象」——所以
/// **寧可多停**：誤停的代價是使用者看一眼，漏掉一個訊號的代價是出版商把使用者機構的 session 封掉。
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
        ("perimeterx-block", #"press (&|and) hold to confirm|px-captcha|access to this page has been denied|believe you are using automation"#),
        ("datadome-block", #"datadome|captcha-delivery\.com"#),
        ("cloudflare-challenge", #"just a moment\.\.\.|cf-chl|challenge-platform|cf_chl_"#),   // OUP, 2026-09-23
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

    /// 命中的訊號標籤；沒有則 nil。`status` 是 403／429 時直接回 `http-<status>`。
    public static func detect(_ text: String, status: Int? = nil) -> String? {
        if let status, suspiciousStatus.contains(status) { return "http-\(status)" }
        let text = foldDotlessAndDottedI(text)
        let range = NSRange(text.startIndex..., in: text)
        for (label, regex) in compiled where regex.firstMatch(in: text, options: [], range: range) != nil {
            return label
        }
        return nil
    }
}
