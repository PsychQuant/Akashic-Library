import Foundation

/// **文件邊界的消毒**——與 `displaySafe`（訊息邊界）是兩個不同的契約。
///
/// ## 為什麼不能共用 `displaySafe`
///
/// `displaySafe` 跳脫反斜線（`0x5C`），理由是**反偽造**：錯誤訊息裡的字面
/// `\u{001B}` 必須能與「本函式跳脫出來的 ESC」區分，否則消毒後的輸出可被內容
/// 偽造。那個理由在**錯誤訊息**上成立。
///
/// 在 `.bib` 與 CSL-JSON 上它是致命的——反斜線在那裡**是內容語法**。實測
/// （#171 verify 171-2，`akashic export-bib` 走 stdout）：
///
///     TITLE = {Emphasis \u{005C}textit{word}, caf\u{005C}'{e}}    ← biblatex 壞掉
///     "title" : "A \u{005C}"quoted\u{005C}" title"                ← 不是合法 JSON
///
/// 同一份匯出走 `--output` 是好的、走 stdout 是壞的。而 stdout 是**預設**——
/// `export-bib > refs.bib`、`| pbcopy`、`| bibtool` 都走它。
///
/// ## 判準：只擋危險字元，不碰語法
///
/// 跳脫的集合與 `displaySafe` **完全相同，只少了反斜線**：C0／C1／DEL、
/// LS/PS、bidi override 與 isolate、方向標記、BOM。這些與各格式自己的
/// metacharacter（`{}` `\` `%` `&`／`"` `\`／`<` `&`）是**兩組不相干的集合**，
/// 所以各 renderer 的 escape 不涵蓋它們，而本函式也不會踩到它們。
///
/// 標記寫成 `U+001B` 而非 `\u{001B}`：**不含反斜線、引號或角括號**，因此在
/// `.bib` 的大括號內、JSON 字串內、XML 文字節點內都是無害的字面文字。
///
/// **誠實邊界**：因為不跳脫反斜線，內容裡的字面文字 `U+202E` 與本函式的輸出
/// 不可區分。那在錯誤訊息上是漏洞，在匯出文件上不是——沒有任何東西會對這個
/// 標記採取行動，真正的不變式（**沒有裸控制字元抵達 sink**）仍然成立。
///
/// ## 不截斷
///
/// **文件沒有行長上限。** `displaySafeMultiline` 的 `maxLineLength` 對訊息是對的，
/// 對文件是致命的：`BibWriter.serialize` 把每個欄位放**單一行**，而 abstract 是
/// 常態欄位——5000 字元的 abstract 在 4000 上限下會被截成大括號不閉合的無效
/// `.bib`，而且**沒有任何警告**（171-3）。
///
/// 「截斷一份文件」永遠產生一份壞掉的文件。所以尺寸的處置只有兩種：不設限
/// （CLI stdout——使用者自己要的），或**拒絕**（MCP——見 `AkashicService.export`）。
/// 不存在「截一半還能用」的中間選項。
public func documentSafe(_ s: String) -> String {
    var out = String.UnicodeScalarView()
    out.reserveCapacity(s.unicodeScalars.count + 16)
    for u in s.unicodeScalars {
        let v = u.value
        let escape =
            (v < 0x20 && v != 0x09 && v != 0x0A)     // C0，但留 TAB 與 LF（文件的結構）
            || v == 0x0D                             // CR 仍跳脫——與 LF 並存會造成歧義
            || v == 0x7F                             // DEL
            || (0x80...0x9F).contains(v)             // C1
            || v == 0x2028 || v == 0x2029            // LS / PS
            || (0x202A...0x202E).contains(v)         // bidi override
            || (0x2066...0x2069).contains(v)         // bidi isolate
            || v == 0x200E || v == 0x200F || v == 0x061C  // 方向標記
            || v == 0xFEFF                           // ZWNBSP / BOM
        if escape {
            for c in String(format: "U+%04X", v).unicodeScalars { out.append(c) }
        } else {
            out.append(u)
        }
    }
    return String(out)
}
