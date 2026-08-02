import Foundation

/// compose 之前的 alias 展開預算（#36 / #27）。
///
/// ## 問題
///
/// 所有既有的資源守衛（200,000 節點預算、`depth > 512`）都跑在 `Yams.compose` **之後**。
/// alias 的展開發生在 compose **內部**——libyaml 的 `checkDuplicates(mappingKeys:)` 會遞迴
/// 雜湊鍵節點且不做 memoisation。630 bytes 的檔案就能讓 CLI / MCP / App 100% CPU 直到 timeout。
///
/// ## 為什麼這次的判準跟 R11 不同（那次兩個方向都錯）
///
/// #23 的 R11 加過一個守衛，問的是「**這個 alias 在什麼位置**」（block 隱式鍵？flow 顯式鍵？）
/// ——那是 **parse 層**的問題，用文字判必然出錯，實測三條繞道全未擋、又誤殺 emitter 自己的輸出。
///
/// 本機制問的是完全不同的問題：「**這個檔能不能指數展開**」。指數展開需要 **多個 anchor 且
/// 每個被多次引用**（billion-laughs 的結構）；單一 anchor 最多放大 2×，無害。所以只要**計數**，
/// 而且門檻留大量餘裕——**掃描器就算不完美，也需要好幾個巧合才會誤判**。正確性不再依賴掃描器
/// 的精巧度，這是與 R11 的根本差異。
///
/// ## 誠實邊界
///
/// 這**不是**完整的防線。真正的修法是 event-level 解析（libyaml 的 `yaml_parser_parse` 逐事件
/// 掃描不展開 alias，成本與輸入大小成正比），但 Yams 沒有把 `CYaml` 匯出成 product，拿不到。
/// 本機制擋的是「anchor/alias 構成的指數展開」這一類；**超大 scalar** 與 compose 階段的解析
/// 堆疊/記憶體仍未防護（見 `docs/store-format.md` §5 的「已知未防護」）。
public enum AliasBudget {

    /// 觸發拒絕需**同時**滿足。留大量餘裕：真實 corpus（536 檔）掃出 0 個 anchor/alias，
    /// 而 billion-laughs 的最小構造需要 ≥2 anchor、每個至少被引用 2 次。
    public static let maxAnchors = 2
    public static let maxAliases = 4

    /// 掃描結果。分開回傳讓錯誤訊息能說出實際數字，而不是只說「太多了」。
    public struct Count: Equatable {
        public let anchors: Int
        public let aliases: Int
        public var exceedsBudget: Bool {
            anchors >= AliasBudget.maxAnchors && aliases >= AliasBudget.maxAliases
        }
    }

    /// 逐字元掃描，跳過**引號內**、**註解**、**block scalar 內容**——這三處的 `&` / `*`
    /// 是資料不是語法。只計 **token 起始**位置的 `&name` / `*name`：`R&D` 的 `&` 在 token
    /// 中間，是純量的一部分，不是 anchor。
    public static func scan(_ text: String) -> Count {
        var anchors = 0, aliases = 0
        var inBlockScalar = false
        var blockScalarIndent = 0

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            // CRLF：split(on: "\n") 會在行尾留下 \r，它會被算進 token 判定。
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            let indent = line.prefix { $0 == " " }.count

            if inBlockScalar {
                // 空行不結束 block scalar；縮排回到標頭層以下才結束。
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if indent > blockScalarIndent { continue }
                inBlockScalar = false
            }

            var sq = false, dq = false      // ' 與 " 內
            var prevWasStructural = true    // token 起始判定：行首 / 空白 / 結構字元之後
            var i = line.startIndex
            var sawBlockIndicator = false

            while i < line.endIndex {
                let c = line[i]
                let next = line.index(after: i)

                if dq {
                    if c == "\\" { i = next < line.endIndex ? line.index(after: next) : line.endIndex; continue }
                    if c == "\"" { dq = false }
                    i = next; continue
                }
                if sq {
                    // YAML 單引號內的逸出是 '' —— 兩個連續單引號是字面的 '
                    if c == "'" {
                        if next < line.endIndex, line[next] == "'" { i = line.index(after: next); continue }
                        sq = false
                    }
                    i = next; continue
                }

                switch c {
                case "#":
                    // 註解只在 token 起始位置成立（`a#b` 的 # 是純量的一部分）
                    if prevWasStructural { i = line.endIndex; continue }
                case "\"": dq = true
                case "'":  sq = true
                case "|", ">":
                    // **不是每個 `>` 都是 block scalar 標頭**（reviewer probe 實測的繞道）：
                    // `k: x > y` 的 `>` 是純量內容。真標頭的 indicator 之後只允許
                    // chomping（`+`/`-`）、明確縮排（數字），然後就必須是行尾或註解。
                    // 誤判的後果很嚴重：掃描器會把**後面所有行**當成 block scalar 內容
                    // 而整段跳過，bomb 藏在那裡就完全掃不到。
                    if prevWasStructural, Self.isBlockScalarHeader(line, from: next) {
                        sawBlockIndicator = true
                    }
                case "&", "*":
                    // 只有 token 起始、且後面接非空白（`&name` / `*name`）才算
                    if prevWasStructural, next < line.endIndex,
                       line[next] != " ", line[next] != "\t" {
                        if c == "&" { anchors += 1 } else { aliases += 1 }
                    }
                default: break
                }

                prevWasStructural = (c == " " || c == "\t" || c == "-" || c == ":"
                                     || c == "[" || c == "]" || c == "{" || c == "}" || c == ",")
                i = next
            }

            if sawBlockIndicator {
                inBlockScalar = true
                blockScalarIndent = indent
            }
        }
        return Count(anchors: anchors, aliases: aliases)
    }

    /// `|` / `>` 之後是否構成合法的 block scalar 標頭。
    ///
    /// YAML 允許 `|`、`|-`、`|+`、`|2`、`>2-` 等組合，但 indicator 之後**必須**是
    /// 行尾或註解——一旦有其他內容（`x > y` 的 ` y`），那個 `>` 就是純量的一部分。
    private static func isBlockScalarHeader(_ line: String, from start: String.Index) -> Bool {
        var i = start
        // chomping 與明確縮排指示（順序不拘，各至多一次；此處寬鬆接受）
        while i < line.endIndex, line[i] == "+" || line[i] == "-" || line[i].isNumber {
            i = line.index(after: i)
        }
        // 其後只允許空白 + 註解
        while i < line.endIndex, line[i] == " " || line[i] == "\t" {
            i = line.index(after: i)
        }
        return i == line.endIndex || line[i] == "#"
    }

    /// compose **之前**的守衛。超過預算 → 擲錯，讓呼叫端 quarantine 該檔而非掛死。
    public static func check(_ text: String, context: String) throws {
        let c = scan(text)
        guard !c.exceedsBudget else {
            throw AliasBudgetError.exceeded(context: context,
                                            anchors: c.anchors, aliases: c.aliases)
        }
    }
}

public enum AliasBudgetError: Error, LocalizedError, Equatable {
    case exceeded(context: String, anchors: Int, aliases: Int)

    public var errorDescription: String? {
        switch self {
        case let .exceeded(context, anchors, aliases):
            // **單行**：quarantine reason 會過 displaySafe（因為它常含 Yams 展開的逐字
            // 檔案內容），真換行會被逸出成 \u{000A} 而變得難讀。與其發明「可信訊息」
            // 的例外（那個區分本身就是新的失誤面），不如訊息本身不含換行。
            return "\(context)：檔案含 \(anchors) 個 anchor 與 \(aliases) 個 alias，"
                + "超過展開預算（上限 \(AliasBudget.maxAnchors) / \(AliasBudget.maxAliases)）。"
                + "這是 alias 展開放大攻擊的形狀——展開發生在 YAML parser 內部，事後的預算來不及。"
                + "store 的寫入端從不產生 anchor/alias（實測 corpus 536 檔為 0），"
                + "正常檔案不會撞到這條線；若這是手寫的檔案，請把 alias 展開後再存。"
        }
    }
}
