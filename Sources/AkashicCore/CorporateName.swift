import Foundation

/// 機構名（corporate / single-field name）的表示法（#6）。
///
/// ## 問題
///
/// `Author.literal` 只存顯示字串，export 端以「最後一個空白 token 當 family」切分——
/// `"World Health Organization"` 因此被輸出成 `"Organization, World Health"`。Zotero
/// 明明有 `fieldMode` 標記單欄姓名，卻在 import 時被丟掉。
///
/// ## 為什麼用大括號而不是新增欄位
///
/// `authors` 是 store 格式的 **strict 層**（未知 key 一律拒收，見 `docs/store-format.md`
/// §5）。在 author 元素裡新增 `corporate:` 之類的欄位會讓舊 binary 把整個檔 quarantine
/// ——那是 **non-additive** 變更，依 #24 得 bump store format，而 bump 會讓所有舊 binary
/// 拒絕開啟**整個 store**，代價遠大於這個問題。
///
/// 大括號是 BibTeX/biblatex 既有的保護慣例（`{World Health Organization}` 表示「別動它」），
/// 而在 store 裡它只是一個**普通字串**——strict 層完全不受影響，舊 binary 照常讀，
/// 只是它們的 export 仍會切錯（可用性退化，非資料毀損）。
///
/// ## 誠實邊界
///
/// 這是**表示法**不是**結構**。真正的結構化（family / given / corporate 三態各自成欄）
/// 屬於 #35 的 entity 模型統一——那時本來就要動 schema，一起做才划算。在此之前，
/// 大括號承載「這是機構名」這一個 bit，夠修掉 export 切錯，不夠做姓名排序等需要
/// 真結構的事。
public enum CorporateName {

    /// 顯示字串是否被標記為機構名。
    public static func isMarked(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, t.hasPrefix("{"), t.hasSuffix("}") else { return false }
        // 巢狀不平衡（`{a} b {c}`）不算——那是一般字串裡剛好有括號
        var depth = 0
        for (i, c) in t.enumerated() {
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 && i != t.count - 1 { return false }
            }
        }
        return depth == 0
    }

    /// 加上標記（已標記則不重複加）。
    public static func mark(_ s: String) -> String {
        isMarked(s) ? s : "{\(s)}"
    }

    /// 去掉最外層標記，得到人類可讀的名字。
    public static func unmark(_ s: String) -> String {
        guard isMarked(s) else { return s }
        let t = s.trimmingCharacters(in: .whitespaces)
        return String(t.dropFirst().dropLast())
    }
}
