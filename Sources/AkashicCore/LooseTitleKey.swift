import Foundation

/// 刊名／機構名的寬鬆比對鍵（#548）。與 `LooseNameKey`（人名）並列住 core——
/// venue 與 organization 的 bootstrap 共用**單一定義**。
///
/// ## 為什麼不是 `LooseNameKey`——這是裁決，不是省略
///
/// `LooseNameKey` 的兩個 tier 對刊名／機構名都不適用，各有理由：
///
/// | tier | 對人名 | 對刊名／機構名 |
/// |---|---|---|
/// | `reorderKey`（token 集合相等） | `Hsu, Yung-Fong` ↔ `Yung-Fong Hsu`——索引系統**真的會**重排人名 | **誤判來源**。刊名不會被重排，而 token 集合相等會把不同的刊當成同一本 |
/// | `initialsKeys`（姓＋首字母） | `Chen, Y.-H.` ↔ `Chen, Yi-Hau` | 刊名沒有姓，取首字母無對應物 |
///
/// ## 實際的變異形狀是標點與冠詞（實測，不是猜的）
///
/// 2026-09-11 量 live store 的 406 筆 venue：`NameNormalization.matchingKey`
/// （NFKC ＋ 連字號家族 ＋ Cf ＋ 小寫 ＋ 空白收斂）**不摺標點**，於是同一本刊
/// 只差 `:` ／ `(` ／ `-` 就成了不同記錄——
///
/// ```
/// journal-of-the-royal-statistical-society     …Series B: Statistical Methodology
/// journal-of-the-royal-statistical-society-2   …Series B (Statistical Methodology)
/// journal-of-the-royal-statistical-society-3   …SERIES B-STATISTICAL METHODOLOGY
/// ```
///
/// `-2`／`-3` 是 `bootstrap-venues` 自己撞號時加的後綴——**缺口不是零實例，它已經
///發生過 5 組／11 筆**（另有 American Statistician、American Journal of Psychology、
/// BJMSP 的 `&` vs `and`）。
///
/// ## 判準取窄的那一個
///
/// 量過兩版：本版（只剝前導冠詞）與「連 of／and／for／in／on 等停用詞一起丟」的寬版。
/// **兩者在真實資料上結果完全相同**（同樣 5 組重複、同樣 404 個鍵、候選側同樣命中 1 筆），
/// 所以取窄的——寬版多丟的那些詞今天沒有換到任何東西，只擴大未來的誤判面。
///
/// **鍵只用於配對，永不用於判定、永不外洩成資料**——同 `LooseNameKey` 檔頭的鐵律。
/// 同鍵只代表「值得提名給人看」。
public enum LooseTitleKey {

    /// 前導冠詞。**只剝開頭**——`Journal of the Royal Statistical Society` 中間那個
    /// `the` 留著（剝掉就進了上面說的寬版，而寬版沒有換到東西）。
    private static let leadingArticles: Set<String> = ["the", "a", "an"]

    /// 寬鬆鍵：`matchingKey` 之上再摺 `&`／標點，並剝掉前導冠詞。
    ///
    /// 空字串（純標點的名字）回空字串——呼叫端要自己排除，同 `LooseNameKey` 對
    /// 產不出鍵的處置：**不生鍵，不是生一個空鍵**。
    public static func key(_ s: String) -> String {
        // `&` 先展開成 `and`：BJMSP 在店裡兩種寫法都有，而標點摺疊會把 `&` 變成
        // 空白、於是兩者的 token 數不同。順序不能反過來。
        let expanded = NameNormalization.matchingKey(s)
            .replacingOccurrences(of: "&", with: " and ")
        // 標點一律轉空白（`matchingKey` 已把連字號家族統一成 `-`，這裡連它一起摺）。
        let spaced = String(expanded.map { c in
            c.isLetter || c.isNumber || c.isWhitespace ? c : " "
        })
        var tokens = spaced.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = tokens.first, leadingArticles.contains(first) {
            tokens.removeFirst()
        }
        return tokens.joined(separator: " ")
    }

    /// 兩個名字是否寬鬆共鍵。空鍵**不算共鍵**——否則兩個純標點的名字會配成一對。
    public static func matches(_ a: String, _ b: String) -> Bool {
        let ka = key(a)
        return !ka.isEmpty && ka == key(b)
    }
}
