import Foundation

/// 名字的**判定用**等值判準（#296）。
///
/// **用於判定，零假陽性。** 這是 `NameNormalization.matchingKey` 的**對偶**——兩者
/// 語意相反，刻意放在不同檔案：
///
/// | | `matchingKey` | `NameIdentity` |
/// |---|---|---|
/// | 用途 | 配對（提名候選給人看）| 判定（斷言同一並丟棄）|
/// | 假陽性 | **容許**——後面有人審 | **不容許**——沒有下一關 |
/// | 收的變換 | NFKC、連字號家族、大小寫摺疊、空白 | 只有空白 |
///
/// 拿錯會出事，而且方向不同：拿 `matchingKey` 去判定會**丟掉真正不同的名字**且無
/// verdict 可回溯；拿本判準去配對會**漏掉該提名的候選**。
///
/// ## 收錄條件（#296 D1）
///
/// > 兩個字串只差這個變換，就**必然**是同一個名字。
///
/// 不是「幾乎總是」、不是「在我們的資料裡沒見過反例」。判定會丟棄資料且沒有下一關，
/// 所以條件是必然而非機率。
///
/// | 收 | 擋 |
/// |---|---|
/// | NFC（Swift `String ==` 已做）| NFKC |
/// | 前後空白 trim | 大小寫摺疊 |
/// | 內部空白**串**收斂 | 連字號家族統一 |
///
/// 空白三者的共同理由：**空白不是名字的一部分**。沒有兩個人的名字只差在前後或重複的
/// 空白——那是輸入時的雜訊，不是命名的內容。
///
/// ## 為什麼大小寫摺疊刻意不收（#296 D2）
///
/// `"Macdonald"` 與 `"MacDonald"` 幾乎總是同一個名字。但「幾乎總是」不滿足收錄條件。
///
/// 而它的代價**不對稱**：收了之後，判定會在**拉丁**書寫系統上多丟掉一批名字，卻在
/// CJK 上完全沒有效果（大小寫摺疊對 CJK 是 no-op）。也就是它用「拉丁側的假陽性風險」
/// 換「拉丁側的便利」，對本 store 的主要書寫系統毫無幫助。
///
/// 要收必須是一次**顯式裁決**（新開 issue、附實測），不是順手帶進來。
/// `NameIdentityTests.testCaseFoldingIsDeliberatelyExcluded` 釘住這條。
public enum NameIdentity {

    /// 判定用的正規形。**冪等**。
    ///
    /// NFC → trim 前後空白 → 內部空白串收斂為單一 U+0020。不做任何字元刪除。
    public static func canonical(_ s: String) -> String {
        // Swift 的 `String ==` 本來就做 canonical equivalence，但這裡顯式取
        // `precomposedStringWithCanonicalMapping`——因為輸出會被當成**鍵**（用於
        // Set／字典），而 `Hashable` 的實作對 NFC/NFD 不保證同 hash。
        let nfc = s.precomposedStringWithCanonicalMapping
        // `split(whereSeparator: \.isWhitespace)` 一次做完 trim 與串收斂：
        // 前後空白產生空片段（被 split 丟棄）、內部空白串產生一個分界。
        return nfc.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// 兩個名字在判定意義下是否同一。
    public static func same(_ a: String, _ b: String) -> Bool {
        canonical(a) == canonical(b)
    }

    /// **名字內容的不變式**（#554 R4 verify，使用者裁決 D8）：這個字串能不能作為一個名字
    /// 進 store。回 `nil`＝可以；否則回一句人看得懂的理由。
    ///
    /// 住在這裡而不是某個寫入面，是因為 R2→R4 三輪把閘裝在 `updateVenue` 的三個迴圈裡，
    /// 而同一個欄位還有 `addVenue` 與 `VenueBootstrap` 兩個寫入者——「守衛住在 validate →
    /// writeVenue 的交會處才擋得住所有路徑」（`Venue.swift` 自己的 doc）。`Venue.validate()`
    /// 對 names／authorized／variant 逐條呼叫；寫入面先 `canonical` 再呼叫，拿理由當錯誤訊息。
    ///
    /// 四條，各有量過的反例：
    ///
    /// 1. **是 canonical 形**（前後／連續空白、tab、NFD 都不是）——空白不是名字的一部分
    ///    （本型別的立場）；R3 把新條目存原樣，之後乾淨拼法永遠進不了 authorized。
    /// 2. **不含危險 scalar**——與輸出閘 `UnsafeToEmitScalar` **同一份**定義，再加上整個
    ///    Cf／Cc／Zl／Zp 類別（R4 曾是 19 個例子的列舉，170 個 Cf 漏 149：ALM、TAG 字元）。
    ///    ZWJ／ZWNJ 例外——波斯文與印度系文字合法用——但只在兩個字母（或標記）之間：
    ///    尾隨 ZWJ、拉丁字母間的 joiner 重開「看起來一樣、canonical 不相等」的通道。
    /// 3. **至少一個字母或數字**——`×`／`—`／`…` 不是名字；純數字刊名（*1843*、*2600*）是。
    ///    R4 曾寫「至少一個字母」，被真反例打掉。
    /// 4. **非空**（1 的特例，訊息分開說）。
    ///
    /// 誠實邊界：1 的 NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A）——位元組層有損、
    /// Swift 層無損（Swift `==` 早已視為相等）。
    public static func wellFormednessIssue(_ name: String) -> String? {
        let canon = canonical(name)
        if canon.isEmpty { return "是空白——沒有名字" }
        if name != canon || Array(name.utf8) != Array(canon.utf8) {
            return "不是 canonical 形（前後／連續空白、tab 或未 NFC）——寫入者要先 NameIdentity.canonical"
        }
        let scalars = Array(name.unicodeScalars)
        for (i, u) in scalars.enumerated() {
            if u.value == 0x200C || u.value == 0x200D {
                func joinable(_ s: Unicode.Scalar) -> Bool {
                    s.properties.isAlphabetic
                        || s.properties.generalCategory == .nonspacingMark
                        || s.properties.generalCategory == .spacingMark
                }
                guard i > 0, i + 1 < scalars.count, joinable(scalars[i - 1]), joinable(scalars[i + 1]) else {
                    return "接合字元（ZWJ／ZWNJ）不在兩個字母之間——那不是名字的一部分"
                }
                continue
            }
            if UnsafeToEmitScalar.contains(u) {
                return "含控制或方向控制字元 U+\(String(u.value, radix: 16, uppercase: true))——不是名字的一部分"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            }
            switch u.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                return "含格式或控制字元 U+\(String(u.value, radix: 16, uppercase: true))（零寬／不可見）——不是名字的一部分"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            default: break
            }
        }
        if !name.contains(where: { $0.isLetter || $0.isNumber }) {
            return "沒有任何字母或數字——不是名字"
        }
        return nil
    }
}
