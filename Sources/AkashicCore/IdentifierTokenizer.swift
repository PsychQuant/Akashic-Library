import Foundation

/// 一個自由字串裡的識別碼：切多值、配對括號註記、正規化＋去重（#394 §8 遷移寫的，
/// #458 搬進 Core）。
///
/// ## 為什麼住 Core 而不是 StoreIO
///
/// 它原本是 `IdentifierMigration` 的一部分，而該型別的 doc 明寫：「本型別是一次性遷移工具，
/// `no-compat-fallback` 要求遷移退場即刪。刪它之前必須先把這兩個函式搬到 `AkashicCore`
/// （識別碼解析不是遷移的職責）。追蹤：#427 的 follow-up。」#458 的 add-only core 住 Core
/// 且要對 `isbn` 重現同一個三態解析（全解／部分解／不解），是第一個非遷移的常設呼叫端，
/// 於是搬家在這裡發生。`IdentifierMigration` 的同名函式現在全部轉發到此——**一份 tokenizer**。
///
/// ## 括號只對 ISSN／ISBN 剝，對 DOI **絕不能剝**
///
/// `(Electronic)`／`(Print)`／`(Linking)`／`(softcover)` 是人給的註記，不是識別碼的一部分。
/// **但 DOI 的後綴合法含括號**：Elsevier／Wiley 大量使用，如 `10.1016/S0304-4076(98)00255-9`。
/// 實測真實 store 52 筆 DOI 含括號（#394 遷移乾跑）。第一版對所有種類一律剝括號，於是那
/// 52 筆被切成兩半、看起來像資料本身有問題——乾跑存在的理由正是讓這種 bug 在寫入前現形。
public enum IdentifierTokenizer {

    /// 這個欄位的多值該吸收，還是交給人？**按種類分，而分法是量出來的。**
    ///
    /// | 種類 | 一個欄位解出 >1 相異值 | 那些多值是什麼 | 裁決 |
    /// | --- | --- | --- | --- |
    /// | PMID | 0 筆 | — | 不吸收（無實例，且一篇一個 PMID） |
    /// | ISBN | 5 筆 | 精裝／電子版、ISBN-10 與 ISBN-13——**同一本書的兩個號** | 吸收 |
    /// | ISSN | 25 筆 | print 與 electronic——**同一份期刊的兩個號** | 吸收 |
    /// | DOI | **1 筆** | `10.1037/amp0000794` ＋ `….supp (Supplemental)`——**附錄的 DOI** | 不吸收 |
    ///
    /// DOI 那一筆是決定性的：吸收它等於讓該記錄宣稱自己是另一個物件，而識別碼**終結指涉**
    /// （`identity-is-judged-not-matched`）——那是一句假的身分宣稱，不是多一筆資料。
    /// 不吸收 ≠ 丟棄：那一筆會出現在報告裡、原值留在 `fields`，交人裁。
    public static func absorbsMultipleValues(field: String) -> Bool {
        field == "issn" || field == "isbn"
    }

    /// 逗號或空白切開，去空 token。**不剝括號**——剝不剝由呼叫端按種類決定。
    public static func splitTokens(_ stripped: String) -> [String] {
        stripped
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// 一個欄位值切成多個識別碼候選（不含括號註記）。
    public static func candidates(_ raw: String, field: String) -> [String] {
        candidatesWithAnnotations(raw, field: field).values
    }

    /// 同 `candidates`，但**一併回報被剝掉的括號註記**（#394 verify）。
    ///
    /// 剝括號是為了讓 `1860-0980 (Electronic) 0033-3123 (Linking)` 這種值解析得出來——但
    /// `Electronic`／`Print`／`Linking`／`softcover`／`alk. paper` **是有書目語意的 qualifier**，
    /// 不是雜訊。`lossless-intake` 執行細節 3：真的要丟就必須報出來。
    /// **這個函式不決定要不要丟，只保證丟了看得見。**
    public static func candidatesWithAnnotations(_ raw: String, field: String)
        -> (values: [String], annotations: [String]) {
        guard absorbsMultipleValues(field: field) else {
            return (splitTokens(raw), [])
        }
        var annotations: [String] = []
        if let re = try? NSRegularExpression(pattern: #"\(([^)]*)\)"#) {
            let ns = raw as NSString
            for m in re.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty { annotations.append(inner) }
            }
        }
        let stripped = raw.replacingOccurrences(of: #"\([^)]*\)"#, with: " ",
                                                options: .regularExpression)
        return (splitTokens(stripped), annotations)
    }

    /// 值 ＋ 緊跟在它後面的括號註記（#394 verify）。
    ///
    /// **配對而不是各自成堆**：`1939-1455(Electronic),0033-2909(Print)` 的資訊不是
    /// 「有兩個號、有兩個註記」，是「1939-1455 是電子版、0033-2909 是紙本」。
    /// 規則：一個 `(...)` 歸屬於**它前面最近的**值。前面沒有值的括號（罕見）被忽略，
    /// 但仍出現在 `candidatesWithAnnotations` 的回報裡——不猜它屬於誰。
    public static func qualifiedCandidates(_ raw: String, field: String)
        -> [(value: String, qualifier: String?)] {
        guard absorbsMultipleValues(field: field) else {
            return splitTokens(raw).map { ($0, nil) }
        }
        var out: [(value: String, qualifier: String?)] = []
        var token = ""
        var i = raw.startIndex
        func flush() {
            let s = token.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { out.append((s, nil)) }
            token = ""
        }
        while i < raw.endIndex {
            let c = raw[i]
            if c == "(" {
                flush()
                var inner = ""
                i = raw.index(after: i)
                while i < raw.endIndex, raw[i] != ")" { inner.append(raw[i]); i = raw.index(after: i) }
                if i < raw.endIndex { i = raw.index(after: i) }          // 跳過 ")"
                let q = inner.trimmingCharacters(in: .whitespaces)
                // 歸屬於前面最近的值。前面沒有值就丟掉——但 `candidatesWithAnnotations`
                // 仍會回報它，所以不是靜默。
                if !q.isEmpty, let last = out.indices.last { out[last].qualifier = q }
                continue
            }
            if c == "," || c.isWhitespace { flush() } else { token.append(c) }
            i = raw.index(after: i)
        }
        flush()
        return out
    }

    /// 把一個識別碼併進清單：相等時**有 qualifier 的勝過沒有的**（#425 verify HIGH）。
    ///
    /// 抽出來是因為這條規則先前只寫在 `normalizedUniqueQualified`（單一欄位內的多值），
    /// 而跨 work 累積到 venue 的那一步沒有套用它——`contains` 走 `Identifier.==`，它刻意
    /// 只比 `normalized`（dedup 的前提，不能改），所以先進來的勝出、不論有沒有 qualifier。
    /// 複製一份規則到第二處必然分岔，而分岔的方向就是「其中一處安靜地丟掉 qualifier」。
    public static func mergePreferringQualified<T: Identifier>(_ v: T, into out: inout [T]) {
        if let idx = out.firstIndex(of: v) {
            if out[idx].qualifier == nil, v.qualifier != nil { out[idx] = v }
        } else {
            out.append(v)
        }
    }

    /// 帶限定詞的正規化＋去重（#394 verify）。**相等仍只看正規形**；去重時**有 qualifier 的
    /// 勝過沒有的**，兩個都有而且不同時保留先出現的（一個 `String?` 裝不下兩個角色）。
    public static func normalizedUniqueQualified<T: Identifier>(
        _ pairs: [(value: String, qualifier: String?)], _ make: (String) -> T?
    ) -> (values: [T], unparseable: [String]) {
        var out: [T] = []
        var bad: [String] = []
        for (rawValue, q) in pairs {
            guard let v = make(rawValue) else { bad.append(rawValue); continue }
            mergePreferringQualified(v.withQualifier(q), into: &out)
        }
        return (out, bad)
    }

    /// 正規化 ＋ **去重**（先正規化再去重，去重後仍 >1 者才是真多號）。
    public static func normalizedUnique<T: Identifier>(_ raws: [String], _ make: (String) -> T?)
        -> (values: [T], unparseable: [String]) {
        var out: [T] = []
        var bad: [String] = []
        for r in raws {
            guard let v = make(r) else { bad.append(r); continue }
            if !out.contains(v) { out.append(v) }
        }
        return (out, bad)
    }

    /// 一個欄位的原字串 → 結構化識別碼的**三態**解析（#394 verify R5→R9 的裁決，
    /// 原本散在 `ZoteroMapping.followUpstream` 與 `ZoteroEnrichment.plan` 兩處）。
    ///
    /// | 結果 | `values` | `unparseable` | 意思 |
    /// |---|---|---|---|
    /// | 全解 | 非空 | 空 | 原字串可移出 `fields` |
    /// | 部分解 | 非空 | 非空 | 值進結構化欄位，**原字串保留在 `fields`**——殘留是解不了的值唯一的棲身處 |
    /// | 不解 | 空 | 非空 | 不猜；原字串留在 `fields`、報出來 |
    ///
    /// 吸不吸收多值按 `absorbsMultipleValues`：DOI／PMID 把整個字串當一個值解。
    public static func parse<T: Identifier>(_ raw: String, field: String, _ make: (String) -> T?)
        -> (values: [T], unparseable: [String]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], []) }
        if absorbsMultipleValues(field: field) {
            return normalizedUniqueQualified(qualifiedCandidates(trimmed, field: field), make)
        }
        return make(trimmed).map { ([$0], []) } ?? ([], [trimmed])
    }
}
