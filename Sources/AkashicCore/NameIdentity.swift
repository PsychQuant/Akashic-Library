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
}
