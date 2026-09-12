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
    /// 2. **不含危險或不可見 scalar**——三份定義的聯集：輸出閘 `UnsafeToEmitScalar`（**同一份**，
    ///    它本身是 C0／C1／bidi 的列舉——#569 管它）、generalCategory 的 Cc／Cf／Zl／Zp（性質）、以及 Unicode
    ///    自己的 `Default_Ignorable_Code_Point`（性質；UAX #44，UTS #39 confusable 用的那個），再加一個
    ///    三者都沒收的 U+2800 BRAILLE PATTERN BLANK。第三份是
    ///    R5 verify 第 2 列補的：VS16（U+FE0F，網頁貼上常見）、CGJ（U+034F）是 **Mn**、Hangul filler
    ///    （U+3164）是 **Lo**——四類 generalCategory 都放行，`心\u{FE0F}理學報`／`心\u{034F}理學報`／`心理學報`
    ///    存成三筆「不同」名字、`add-venue --names $'\u{3164}'` 建出一筆 displayName 空白的 venue。
    ///    R4 曾是 19 個例子的列舉（170 個 Cf 漏 149），R5 換成分類——換了一個更大的列舉。
    ///    **ZWJ／ZWNJ 例外**（兩者都是 DI）——波斯文與印度系文字合法用——但只在
    ///    `joinerIsLegal` 說合法的脈絡：前一個 scalar 是掛在該類文字字母上的 virama（legacy Malayalam
    ///    chillu＝consonant＋virama＋ZWJ **詞尾**），或兩側都是使用 join control 的文字的字母／標記／
    ///    數字（波斯文 `۱۴۰۰\u{200C}ها` 是**數字**＋ZWNJ）。R4／R5 的「兩側是字母」對拉丁
    ///    字母 fail-open（`Psycho\u{200C}metrika` 通過、可被 `--authorize` 升成 displayName，
    ///    五路命中）、對 chillu 與波斯數字 fail-closed——R5 verify 第 1 列，Claude 代裁 D9；R6 verify
    ///    再收兩格（區塊裡的標點不算鄰居、連續 joiner 不算）。**代價要寫出來**（R6 verify 第 5／23／36 列）：
    ///    DI 一律拒等於拒掉幾類真實正字法用字——CJK IVS（U+E0100–E01EF）、蒙古文 FVS／MVS、希伯來文
    ///    CGJ、emoji ZWJ 序列、德文抑制連字的 ZWNJ——全部 fail-closed（訊息具名、零寫入），不是靜默損失；
    ///    書目資料裡機率極低，使用者回來後可翻 D9。**放行但不像名字的**：純 tatweel `\u{0640}`（Lm）、
    ///    開頭或空白後的 combining mark（第 7 列「不刪」的必然結果）、未指派碼位（Cn）——都零實例。
    /// 3. **至少一個字母或數字**——`×`／`—`／`…` 不是名字；純數字刊名（*1843*、*2600*）是。
    ///    R4 曾寫「至少一個字母」，被真反例打掉。
    /// 4. **非空**（1 的特例，訊息分開說）。
    ///
    /// 誠實邊界：1 的 NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A）——位元組層有損、
    /// Swift 層無損（Swift `==` 早已視為相等）。
    public static func wellFormednessIssue(_ name: String) -> String? {
        // 碼位印四位（R6 verify 第 32 列：`U+34F` 搜 `U+034F` 搜不到；displaySafe 自己就用 %04X）
        func hex(_ u: Unicode.Scalar) -> String {
            let h = String(u.value, radix: 16, uppercase: true)
            return String(repeating: "0", count: max(0, 4 - h.count)) + h
        }
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
                return "含控制或方向控制字元 U+\(hex(u))——不是名字的一部分，請刪掉它"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            }
            // Default_Ignorable 之外還有一個渲染成空白的碼位：U+2800 BRAILLE PATTERN BLANK（So）。
            // 不是 White_Space、不是四類、不是 DI、不在輸出閘——三份性質都沒收它，與 R5 verify 抓的
            // Hangul filler 同形（R6 verify 第 20 列），顯式列進來；同族的 U+FFFC 顯示為方框，不擋。
            if u.properties.isDefaultIgnorableCodePoint || u.value == 0x2800 {
                return "含不可見字元 U+\(hex(u))（零寬、變體選擇子、填充字元一類）——不是名字的一部分，請刪掉它"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            }
            switch u.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                return "含格式或控制字元 U+\(hex(u))——不是名字的一部分，請刪掉它"   // display-safe-exempt: 十六進位碼位（[0-9A-F]+），不是 store 字串
            default: break
            }
        }
        if !name.contains(where: { $0.isLetter || $0.isNumber }) {
            return "沒有任何字母或數字——不是名字，請刪掉這一筆"
        }
        return nil
    }

    /// ZWJ／ZWNJ 在 `scalars[i]` 這個位置合不合法（第 2 條不變式的例外，D9；R7 收緊）。兩個脈絡，**封閉**：
    ///
    /// - **前一個 scalar 是 virama**（ccc 9）**且 virama 掛在使用 join control 的文字的字母上**：
    ///   印度系文字的 conjunct 控制，含 legacy Malayalam chillu 的詞尾 ZWJ（`ന്\u{200D}`）——所以這一支
    ///   不要求右鄰居。「掛在字母上」是 R7 補的（R6 verify 第 19 列：`Psychometrika\u{094D}\u{200D}` 曾通過）。
    /// - **兩側都是「使用 join control 的文字」裡的字母／標記／數字**（`joiningScriptMember`）：Arabic 一族、
    ///   Syriac（含 Supplement）、Mandaic、NKo、Indic（0900–0DFF）、Myanmar、Khmer、Mongolian、Tifinagh、
    ///   Hanifi Rohingya、Sogdian／Old Uyghur、Manichaean、Adlam、Arabic Extended-C。**區塊成員資格不是
    ///   充分條件**（R6 verify 第 1 列，Codex）：區塊含標點，`A\u{200C}،B` 曾因逗號在 Arabic 區塊而通過；
    ///   R7 起鄰居還要是字母／標記／數字，且**兩側**都要——`ک\u{200C}A` 這種跨文字的 joiner 也沒有意義。
    ///   看區塊而不只看 generalCategory 是為了波斯數字（U+06F1…）：`۱۴۰۰\u{200C}ها` 是真實刊名的形狀。
    ///
    /// 兩個脈絡都不接受**鄰居是另一個 joiner**（R6 verify 第 19 列：連續 joiner 沒有正字法意義，字型
    /// 忽略重複，只是「看起來一樣、canonical 不相等」通道在合法脈絡裡的殘餘）——這不需要另寫一行：
    /// joiner 既不是任何文字的字母／標記／數字、也不是 virama，第二個 joiner 必然在兩支都失敗
    /// （負控實測：顯式加的那兩行是等價突變，拿掉測試照紅，所以不留）。
    ///
    /// 拉丁、西里爾、CJK 之間的 joiner 不在任一支。它們在那些文字裡**只有排版意義**（德文用 ZWNJ 抑制
    /// 跨複合詞的連字：Auf\u{200C}lage——R6 verify 第 48 列指出「沒有意義」這句是假的），對身分沒有意義，
    /// 而且正是 confusable 通道——所以拒（fail-closed，`matchingKey` 刪 Cf 所以 resolve-venues 仍配得到）。
    /// `zero-instance-guards` 第 25 列的 Python 對照腳本鏡射這兩支；改一邊要同批改另一邊。
    static func joinerIsLegal(in scalars: [Unicode.Scalar], at i: Int) -> Bool {
        let prev: Unicode.Scalar? = i > 0 ? scalars[i - 1] : nil
        let next: Unicode.Scalar? = i + 1 < scalars.count ? scalars[i + 1] : nil
        if let p = prev, p.properties.canonicalCombiningClass == .virama {
            return i >= 2 && joiningScriptMember(scalars[i - 2])
        }
        guard let p = prev, let n = next else { return false }
        return joiningScriptMember(p) && joiningScriptMember(n)
    }

    /// 「使用 join control 的文字」的字母／標記／數字：落在下列區塊**且**是 Alphabetic、Mn／Mc 或帶
    /// 數值——區塊裡的標點（Arabic comma U+060C、Devanagari danda U+0964…）不算。封閉列舉，理由見
    /// `joinerIsLegal`；R7 補進的區塊（Mandaic、Syriac Supplement、Adlam、Hanifi Rohingya、Tifinagh、
    /// Sogdian／Old Uyghur、Manichaean、Arabic Extended-C）是 R6 verify 第 14／22 列指出的疏漏——
    /// 同一個文字的補充區塊本來就該在。
    static func joiningScriptMember(_ u: Unicode.Scalar) -> Bool {
        guard usesJoinControl(u) else { return false }
        let props = u.properties
        if props.isAlphabetic || props.numericType != nil { return true }
        switch props.generalCategory {
        case .nonspacingMark, .spacingMark: return true
        default: return false
        }
    }

    /// 使用 join control（ZWJ／ZWNJ 有文字意義）的書寫系統區塊——封閉列舉，理由見 `joinerIsLegal`。
    static func usesJoinControl(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x0870...0x089F, 0x08A0...0x08FF,
             0xFB50...0xFDFF, 0xFE70...0xFEFF, 0x10EC0...0x10EFF,   // Arabic 一族（含 Extended-C）
             0x0700...0x074F, 0x0860...0x086F,                     // Syriac（含 Supplement）
             0x0840...0x085F,                                      // Mandaic
             0x07C0...0x07FF,                                      // NKo
             0x0900...0x0DFF,                                      // Indic：Devanagari…Sinhala
             0x1000...0x109F,                                      // Myanmar
             0x1780...0x17FF,                                      // Khmer
             0x1800...0x18AF,                                      // Mongolian
             0x2D30...0x2D7F,                                      // Tifinagh（連字 ZWJ）
             0x10D00...0x10D3F,                                    // Hanifi Rohingya
             0x10F30...0x10F6F, 0x10F70...0x10FAF,                 // Sogdian、Old Uyghur
             0x10AC0...0x10AFF,                                    // Manichaean
             0x1E900...0x1E95F:                                    // Adlam
            return true
        default:
            return false
        }
    }
}
