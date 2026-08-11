import Foundation

/// 把外部來源的欄位名正規化成可安全落進 `Entry.fields` 的鍵（#206）。
///
/// ## 為什麼需要正規化——不是美觀，是 export 會壞
///
/// `Entry.fields` 的鍵**直接**成為匯出的 biblatex 欄位名（`BibExport.bibEntry`
/// 把 `fields` 攤平，`BibWriter.serialize` 再 `key.uppercased()` 印出去）。所以一個
/// 不合法的鍵不是「難看」，是**產出解析不了的 .bib**。
///
/// 真的 `biber --tool` 量過三種形狀：
///
/// | 欄位名 | biber |
/// |---|---|
/// | `RESEARCH_AREAS` | 0 error |
/// | `RESEARCH AREAS`（含空格） | **syntax error**：`found "AREAS", expected "="` |
/// | `29_CHARACTER_ABBREV`（數字開頭） | **syntax error** |
///
/// 第三種不是假想：WoS 匯出真的有一欄叫 `29 Character Source Abbreviation`。
///
/// 所以三條規則都是**必要**的，不是防禦性寫法：小寫、非英數轉 `_`、數字開頭補
/// 前綴。
///
/// ## 為什麼不丟掉這些欄位
///
/// 見 `.claude/rules/lossless-intake.md`。簡述：收了沒人用的成本是幾十 bytes；
/// 沒收的成本是那件事**永遠不可判定**，且沒有跡象顯示它曾經可判定。
public enum FieldKey {

    /// 數字開頭時補的前綴。用 `x` 而非 `f`／`_`：`_` 開頭在部分 BibTeX 實作同樣可疑，
    /// 而 `x` 是 biblatex 慣例上的 user-defined 前綴（`xdata` 等）。
    public static let digitPrefix = "x"

    /// 來源欄位名 → 合法的 biblatex 欄位鍵。
    ///
    /// - `"Research Areas"` → `"research_areas"`
    /// - `"29 Character Source Abbreviation"` → `"x29_character_source_abbreviation"`
    /// - `"WoS Categories "` → `"wos_categories"`（尾隨空白不留下尾底線）
    /// - `"  "` → `nil`（空鍵不可表達，呼叫端須跳過並回報）
    ///
    /// **回傳 optional 而非空字串**：空鍵是「這個欄位名無法表達」，與「正規化後是
    /// 某個值」是兩件事。壓成空字串會讓兩者在 `fields[""]` 裡合流。
    public static func normalized(_ raw: String) -> String? {
        var out = ""
        out.reserveCapacity(raw.count)
        for ch in raw.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if !out.hasSuffix("_") {
                out.append("_")          // 連續非英數收斂成一個底線
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        while out.hasPrefix("_") { out.removeFirst() }
        guard !out.isEmpty else { return nil }
        // **非 ASCII 數字也留在 `out` 裡**（`٣`／`Ⅷ`／`²` 的 `isNumber` 都是 true，
        // 所以上面的迴圈**保留**它們而非轉成 `_`）。前一版的註解宣稱「那些已在上面
        // 被轉成 `_`，這裡只可能是 ASCII 0-9」——**那是錯的**（#206 verify L1）。
        //
        // 行為本身沒問題：`٣ Chars` → `x٣_chars`，前綴照樣補上，實測 biber 收
        // `X٣_CHARS`／`XⅧ_VOLUME`／`X²ND` 皆 0 error。修的是那句會誤導下一個
        // 編輯者的理由——錯的理由比沒有理由更危險，它讓人以為某個分支不可達。
        if let first = out.first, first.isNumber { out = digitPrefix + out }
        return out
    }
}
