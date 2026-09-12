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
    /// NFC → trim 前後空白 → 內部空白串收斂為單一 U+0020。**不做任何字元刪除**——被丟掉的
    /// 只有 `White_Space` scalar（#554 R5 verify 第 7 列：上一版在 **Character** 上切，而
    /// `Character.isWhitespace` 只看 cluster 的第一個 scalar，「空白＋combining mark」或「空白＋ZWJ」
    /// 整個 cluster 被當空白刪掉——`add-venue --names $'Jour ́nal'` 存成 `Jour nal`、零回報。
    /// D8 讓每個寫入者都走這裡，所以這條刪除路徑當時是新開的）。逐 scalar 走，判準是 Unicode 的
    /// `White_Space` 性質，與 `Character.isWhitespace` 對「首 scalar 是空白」的 cluster 判得一樣，
    /// 對後續 scalar 不再一起丟。
    public static func canonical(_ s: String) -> String {
        // Swift 的 `String ==` 本來就做 canonical equivalence，但這裡顯式取
        // `precomposedStringWithCanonicalMapping`——因為輸出會被當成**鍵**（用於
        // Set／字典），而 `Hashable` 的實作對 NFC/NFD 不保證同 hash。
        let nfc = s.precomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for u in nfc.unicodeScalars {
            if u.properties.isWhitespace {
                pendingSpace = !out.isEmpty   // 前導空白：out 還空，不記
                continue
            }
            if pendingSpace { out.append(" "); pendingSpace = false }
            out.append(u)
        }
        return String(out)                     // 尾隨空白：pendingSpace 掛著、沒人消費
    }

    /// 兩個名字在判定意義下是否同一。
    public static func same(_ a: String, _ b: String) -> Bool {
        canonical(a) == canonical(b)
    }

    /// **名字內容的不變式**（#554 R4 verify，使用者裁決 D8）：這個字串能不能作為一個名字
    /// 進 store。回 `nil`＝可以；否則回一句**對操作者**說的理由（修法是人改 YAML，訊息要說
    /// 改什麼，不得叫他呼叫一個 Swift 函式——R5 verify 第 17 列）。
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
    /// 2. **不含危險或不可見 scalar**——三份定義的聯集，每一份都是**性質**不是列舉：
    ///    輸出閘 `UnsafeToEmitScalar`（同一份）、generalCategory 的 Cc／Cf／Zl／Zp、以及 Unicode
    ///    自己的 `Default_Ignorable_Code_Point`（UAX #44；UTS #39 confusable 用的那個）。第三份是
    ///    R5 verify 第 2 列補的：VS16（U+FE0F，網頁貼上常見）、CGJ（U+034F）是 **Mn**、Hangul filler
    ///    （U+3164）是 **Lo**——四類 generalCategory 都放行，`心\u{FE0F}理學報`／`心\u{034F}理學報`／`心理學報`
    ///    存成三筆「不同」名字、`add-venue --names $'\u{3164}'` 建出一筆 displayName 空白的 venue。
    ///    R4 曾是 19 個例子的列舉（170 個 Cf 漏 149），R5 換成分類——換了一個更大的列舉。
    ///    **ZWJ／ZWNJ 例外**（兩者都是 DI）——波斯文與印度系文字合法用——但只在
    ///    `joinerIsLegal` 說合法的脈絡：前一個 scalar 是 virama（legacy Malayalam chillu＝
    ///    consonant＋virama＋ZWJ **詞尾**），或兩側都有非空白鄰居且任一側在使用 join control 的
    ///    書寫系統區塊（波斯文 `۱۴۰۰\u{200C}ها` 是**數字**＋ZWNJ）。R4／R5 的「兩側是字母」對拉丁
    ///    字母 fail-open（`Psycho\u{200C}metrika` 通過、可被 `--authorize` 升成 displayName，
    ///    五路命中）、對 chillu 與波斯數字 fail-closed——R5 verify 第 1 列，Claude 代裁 D9。
    /// 3. **至少一個字母或數字**——`×`／`—`／`…` 不是名字；純數字刊名（*1843*、*2600*）是。
    ///    R4 曾寫「至少一個字母」，被真反例打掉。
    /// 4. **非空**（1 的特例，訊息分開說）。
    ///
    /// 誠實邊界：1 的 NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A）——位元組層有損、
    /// Swift 層無損（Swift `==` 早已視為相等）。
    public static func wellFormednessIssue(_ name: String) -> String? {
        let canon = canonical(name)
        if canon.isEmpty { return "是空白——沒有名字，請刪掉這一筆" }
        if name != canon || Array(name.utf8) != Array(canon.utf8) {
            return "不是 canonical 形（前後／連續空白、tab 或未 NFC）——請在 YAML 裡把這一筆改成"
                 + "去掉前後空白、連續空白收成一個、NFC 的寫法"
        }
        let scalars = Array(name.unicodeScalars)
        for (i, u) in scalars.enumerated() {
            if u.value == 0x200C || u.value == 0x200D {
                guard joinerIsLegal(in: scalars, at: i) else {
                    return "接合字元（ZWJ／ZWNJ）不在使用它的文字裡（阿拉伯系／印度系等文字之間，或 virama 之後）"
                         + "——那不是名字的一部分，請刪掉它"
                }
                continue
            }
            if UnsafeToEmitScalar.contains(u) {
                return "含控制或方向控制字元 U+\(String(u.value, radix: 16, uppercase: true))——不是名字的一部分，請刪掉它"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            }
            if u.properties.isDefaultIgnorableCodePoint {
                return "含不可見字元 U+\(String(u.value, radix: 16, uppercase: true))（零寬、變體選擇子、填充字元一類）——不是名字的一部分，請刪掉它"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            }
            switch u.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                return "含格式或控制字元 U+\(String(u.value, radix: 16, uppercase: true))——不是名字的一部分，請刪掉它"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            default: break
            }
        }
        if !name.contains(where: { $0.isLetter || $0.isNumber }) {
            return "沒有任何字母或數字——不是名字，請刪掉這一筆（來自 work 的話改它的來源欄位）"
        }
        return nil
    }

    /// ZWJ／ZWNJ 在 `scalars[i]` 這個位置合不合法（第 2 條不變式的例外，D9）。兩個脈絡，**封閉**：
    ///
    /// - **前一個 scalar 是 virama**（ccc 9）：印度系文字的 conjunct 控制，含 legacy Malayalam
    ///   chillu 的詞尾 ZWJ（`ന്\u{200D}`）——所以這一支不要求右鄰居。
    /// - **兩側都有非空白鄰居，且任一側落在使用 join control 的書寫系統區塊**：Arabic 一族
    ///   （0600–06FF／0750–077F／0870–089F／08A0–08FF／FB50–FDFF／FE70–FEFF）、Syriac（0700–074F）、
    ///   NKo（07C0–07FF）、Indic（0900–0DFF，Devanagari 到 Sinhala）、Myanmar（1000–109F）、
    ///   Khmer（1780–17FF）、Mongolian（1800–18AF）。判準看**區塊**不看 generalCategory，所以
    ///   波斯數字（U+06F1…）與 Arabic 標記都算——`۱۴۰۰\u{200C}ها` 是真實刊名的形狀。
    ///
    /// 拉丁、西里爾、CJK 之間的 joiner 不在任一支——它們在那些文字裡沒有意義，只是
    /// 「看起來一樣、canonical 不相等」的通道。`zero-instance-guards` 第 25 列的 Python 對照
    /// 腳本鏡射這兩支；改一邊要同批改另一邊。
    static func joinerIsLegal(in scalars: [Unicode.Scalar], at i: Int) -> Bool {
        let prev: Unicode.Scalar? = i > 0 ? scalars[i - 1] : nil
        let next: Unicode.Scalar? = i + 1 < scalars.count ? scalars[i + 1] : nil
        if let p = prev, p.properties.canonicalCombiningClass == .virama { return true }
        guard let p = prev, let n = next,
              !p.properties.isWhitespace, !n.properties.isWhitespace else { return false }
        return usesJoinControl(p) || usesJoinControl(n)
    }

    /// 使用 join control（ZWJ／ZWNJ 有文字意義）的書寫系統區塊——封閉列舉，理由見 `joinerIsLegal`。
    static func usesJoinControl(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x0870...0x089F, 0x08A0...0x08FF,
             0xFB50...0xFDFF, 0xFE70...0xFEFF,                     // Arabic 一族
             0x0700...0x074F,                                      // Syriac
             0x07C0...0x07FF,                                      // NKo
             0x0900...0x0DFF,                                      // Indic：Devanagari…Sinhala
             0x1000...0x109F,                                      // Myanmar
             0x1780...0x17FF,                                      // Khmer
             0x1800...0x18AF:                                      // Mongolian
            return true
        default:
            return false
        }
    }
}
