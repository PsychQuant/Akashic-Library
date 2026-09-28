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
/// 跳脫的集合是 `UnsafeToEmitScalar.escapesInDisplay`——與 `displaySafe` 同一份性質（#569），
/// 只少兩樣：反斜線（上面的理由），以及 TAB 與 LF（文件的結構）。先前這裡是一張手抄的列舉
/// （C0／C1／DEL、LS/PS、bidi、方向標記、BOM），#569 把輸出閘改成性質之後它沒有跟著改，
/// TAG 字元、ZWSP、SHY 經 `akashic_export`／`akashic_graph` 原樣進 LLM context（#569 R1 verify 三席同指）。
/// 這些字元與各格式自己的 metacharacter（`{}` `\` `%` `&`／`"` `\`／`<` `&`）是**兩組不相干的集合**，
/// 所以各 renderer 的 escape 不涵蓋它們，而本函式也不會踩到它們。
///
/// ZWJ／ZWNJ 保留：`.bib` 與圖是給人讀的文件，同人可讀輸出（使用者 2026-09-27 裁決）。CSL-JSON 是 JSON 出口，
/// 走 `documentSafeJSON`——它以 JSON 自己的 `\uXXXX` 逃脫，連同 ZWJ／ZWNJ，而且無損。
///
/// 標記寫成 `U+001B` 而非 `\u{001B}`：**不含反斜線、引號或角括號**，因此在
/// `.bib` 的大括號內、JSON 字串內、XML 文字節點內都是無害的字面文字。
///
/// ## 誠實邊界（兩條，第二條比第一條重要）
///
/// 1. 因為不跳脫反斜線，內容裡的字面文字 `U+202E` 與本函式的輸出不可區分。那在
///    錯誤訊息上是漏洞，在匯出文件上不是——沒有任何東西會對這個標記採取行動。
///
/// 2. **本函式保證「沒有裸控制字元」，不保證「內容沒有偽造結構」。** LF 是保留的
///    （文件的行結構），而 `BibWriter` 不跳脫 `}`——所以 title 塞
///    `ok},\n}\n@ARTICLE{forged2099,\n  TITLE = {I am fake` 會讓消毒後的 stdout
///    多出一整筆不存在的 entry（#171 複驗實測，`contains forged2099 == true`）。
///
///    **這不是本層造成的**（`displaySafeMultiline` 同樣保留 LF，根因在序列化層），
///    但讀者容易從「危險字元擋掉了」＋「文件仍合法」推出「顯示出來的 .bib 可信」
///    ——它不可信。修法屬 `BibWriter`（另案 #176）。
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
        // 留 TAB 與 LF（文件的結構）；CR 仍跳脫——與 LF 並存會造成歧義
        let escape = v != 0x09 && v != 0x0A && UnsafeToEmitScalar.escapesInDisplay(u)
        if escape {
            for c in String(format: "U+%04X", v).unicodeScalars { out.append(c) }
        } else {
            out.append(u)
        }
    }
    return String(out)
}

/// **JSON 文件出口的消毒**（CSL-JSON，#569 R1 verify）：字串字面值內的危險 scalar 改寫成 JSON 自己的 `\uXXXX`
/// （`UnsafeToEmitScalar.escapingUnsafeScalars(inSerializedJSON:)`）。與 `documentSafe` 的差別：
/// - 無損——`\u202E` 解回來就是原字元，`U+202E` 標記解不回來；
/// - 連 ZWJ／ZWNJ 一起逃（JSON 出口的裁決）；
/// - 字串外的結構空白不動，所以輸出仍是合法 JSON。
public func documentSafeJSON(_ json: String) -> String {
    UnsafeToEmitScalar.escapingUnsafeScalars(inSerializedJSON: json)
}
