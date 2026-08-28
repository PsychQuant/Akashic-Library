import Foundation
import AkashicCore

/// `Entry.fields` 裡的識別碼殘留 → 結構化欄位；work 的 `issn` → 它的 venue（#394 §8）。
///
/// ## 為什麼要遷移，而不是讓兩邊並存
///
/// §3 讓結構化欄位與 `fields` 殘留並存是**過渡**：`canonicalDOIs` 一族在兩者都在場時
/// 取結構化值，所以並存期間讀取面是對的。但並存久了會出現第二個真相來源——有人改了
/// `fields.doi` 而結構化欄位沒動，兩邊分岔且**沒有任何跡象**。`no-compat-fallback`
/// 記過這個形狀：留著的相容路徑不會保護任何東西，它只是在等一個新的呼叫端誤入。
///
/// ## 三件事，一次寫入
///
/// 1. `doi`／`pmid`／`isbn` 自 `fields` 升格為結構化欄位，並移除殘留。
/// 2. `issn` **移位到 venue**——ISSN 識別的是期刊不是文章（spec 的 requirement
///    「An identifier SHALL live on the entity it identifies」）。實測 64 筆帶 `issn`
///    的 work **全部**已歸戶 venue，所以全部搬得動。
/// 3. 指向被改寫值的 provenance `value` 同一次原子改寫。
///
/// ## 誠實邊界：第 3 件事目前是零實例
///
/// `Entry.references` 是 §5 才新增的、全庫為空；venue 的 `issn` reference 也還不存在
/// （寫入面要 format 13，而 store 仍是 12）。所以改寫 provenance 的那條路徑**現在一定
/// 走不到**。它仍然實作並測試，理由是：遷移是一次性的破壞性寫入，等到真的有 reference
/// 指向識別碼時再補，那時已經來不及——而它的成本是一個迴圈。
///
/// **不自動 bump format。** 遷移必須跑在舊解碼器上（design 的部署順序），bump 是人工的
/// 最後一步。
public enum IdentifierMigration {

    /// 一筆記錄的處置。
    public struct Plan: Equatable {
        public var citekey: String
        /// `<欄位>: <原值> → <正規形>`，逐個識別碼一行。
        public var changes: [String]
        /// 這筆的 `issn` 要搬到哪個 venue（`nil` ＝ 沒有 issn）。
        public var issnToVenue: String?
    }

    /// 無法解析而**略過**的——不猜、不丟棄，原值留在 `fields` 裡。
    public struct Skipped: Equatable {
        public var citekey: String
        public var field: String
        public var value: String
        public var reason: String
    }

    /// venue 側的 ISSN 落點。`merged` 與 `keptMultiple` **分開列**（task 8.2）——
    /// 前者是異寫法收斂，後者是 print／electronic 兩個真的號，人要分辨得出來。
    public struct VenuePlan: Equatable {
        public var venueKey: String
        /// **帶 medium 的完整值**（#394 verify）。先前是 `[String]`，於是 apply 走
        /// `plan.values.compactMap(ISSN.init)` 從字串重建——`ISSN.init` 把 medium 設 nil，
        /// 兩層損失：本輪剛從括號註記解出的 medium 蒸發，而 `merged` 的種子是 venue
        /// **既有的** issn，所以連已經在磁碟上的 medium 也一起被壓掉。
        public var issn: [ISSN]
        /// 顯示用——**由 `issn` 現算，不另存**（兩份會分岔）。
        public var values: [String] { issn.map(\.normalized) }
        public var mergedFrom: [String]
        public var keptMultiple: Bool
    }

    /// 一筆被剝掉的括號註記——連同它原本黏在哪個值上。
    public struct DiscardedAnnotation: Equatable {
        public let citekey: String
        public let field: String
        public let raw: String
        public let annotations: [String]
    }

    public struct Report: Equatable {
        public var plans: [Plan] = []
        public var venuePlans: [VenuePlan] = []
        public var skipped: [Skipped] = []
        public var provenanceRewrites: [String] = []
        /// 被剝掉的括號註記（#394 verify）。`lossless-intake` 執行細節 3：真的要丟就
        /// 必須報出來——先前這些在報告的任何一處都不出現，而它們是有書目語意的
        /// qualifier（Electronic／Print／Linking／softcover／alk. paper），不是雜訊。
        public var discardedAnnotations: [DiscardedAnnotation] = []
        /// **寫入開始之前**就判定成立的阻擋前提（#394 verify）。
        ///
        /// 取代原本的 `failed`——那個名字對應的是「寫到一半失敗」，而那正是本命令
        /// 不該有的狀態：它**跨記錄搬動資料**（work 的 issn → venue），寫到一半
        /// 等於兩邊都不對。現在所有前提在任何寫入之前裁決完畢，於是乾跑與 apply
        /// 得到同一組結果，乾跑才真的能預告 apply。
        public var blockers: [String] = []
        /// format 12 → 13 的形狀前置升級碰過的檔（`issn`／`isbn` 的裸純量 → mapping）。
        public var shapeUpgraded: [String] = []
        public var applied: Int = 0

        /// 會被改動的識別碼總數——dry-run 的頭條數字。
        public var identifierCount: Int { plans.reduce(0) { $0 + $1.changes.count } }
    }

    /// `fields` 裡承載識別碼的鍵。**封閉列舉**——`url` 不在其中（它是位置不是身分，
    /// `identity-is-judged-not-matched` 的例外節具名排除過）。
    static let workIdentifierKeys = ["doi", "pmid", "isbn", "issn"]

    /// 一個欄位值切成多個識別碼候選。**是否剝括號按種類決定。**
    ///
    /// 實測的多值寫法：空白分隔（`0022-3506 1467-6494`）、逗號分隔、帶括號標註
    /// （`1860-0980 (Electronic) 0033-3123 (Linking)`）。
    ///
    /// ## 括號只對 ISSN／ISBN 剝，對 DOI **絕不能剝**
    ///
    /// `(Electronic)`／`(Print)`／`(Linking)`／`(softcover)` 是人給的註記，不是識別碼的
    /// 一部分，而我們沒有欄位存它——留著會讓值解析失敗、整筆被略過。
    ///
    /// **但 DOI 的後綴合法含括號**：Elsevier／Wiley 大量使用，如
    /// `10.1016/S0304-4076(98)00255-9`、`10.1002/1097-0258(20001115)19:21<3020::AID-SIM596>3.0.CO;2-A`。
    /// 實測真實 store **52 筆** DOI 含括號。
    ///
    /// 第一版對所有種類一律剝括號，於是那 52 筆被切成兩半——乾跑報告裡出現
    /// `00255-9`、`90012-h`、`19:21<3020::aid-sim596>3.0.co;2-a` 這種殘骸，
    /// **而它們會被當成「解析不了」而略過，看起來像是資料本身有問題**。
    /// 這是乾跑存在的理由：它讓一個會靜默毀資料的 bug 在寫入前現形。
    static func candidates(_ raw: String, field: String) -> [String] {
        candidatesWithAnnotations(raw, field: field).values
    }

    /// 同 `candidates`，但**一併回報被剝掉的括號註記**（#394 verify）。
    ///
    /// 剝括號是為了讓 `1860-0980 (Electronic) 0033-3123 (Linking)` 這種值解析得出來
    /// ——但 `Electronic`／`Print`／`Linking`／`softcover`／`alk. paper` **是有書目語意的
    /// qualifier**，不是雜訊。`lossless-intake` 執行細節 3：真的要丟就必須報出來，
    /// 「靜默是最糟的形式」。
    ///
    /// **這個函式不決定要不要丟，只保證丟了看得見。** 那些註記在現行模型裡確實沒有
    /// 棲身處——`Identifier` 的 `raw` 不進磁碟（`IdentifierYAML.listNode` 只寫
    /// `normalized`），而給 ISSN 加 medium 欄位是 schema 改動。裁決留在 #394。
    static func candidatesWithAnnotations(_ raw: String, field: String)
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
    /// 先前 `candidatesWithAnnotations` 把兩者拆成兩個平坦清單——那保住了「有丟東西」
    /// 這個事實，卻保不住那個事實的內容。
    ///
    /// 規則：一個 `(...)` 歸屬於**它前面最近的**值。前面沒有值的括號（罕見）被忽略，
    /// 但仍出現在 `candidatesWithAnnotations` 的回報裡——不猜它屬於誰。
    /// **常設路徑也在用**（#394 verify R5 ①）：`import-zotero` 的跟隨語意需要同一個
    /// 切法——Zotero 把多個號塞在一個字串裡,而那正是本函式為之而寫的形狀。
    ///
    /// ⚠️ **耦合**:本型別是一次性遷移工具,而 `no-compat-fallback` 要求遷移「退場即刪」。
    /// 刪它之前必須先把這兩個函式搬到 `AkashicCore`（識別碼解析不是遷移的職責）。
    /// 追蹤:#427 的 follow-up。
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

    /// format 12 → 13 的行級轉換。**純函式，可單獨測**（#394 verify R4）。
    ///
    /// ## 判準是「它是不是真的裸識別碼」，不是「它長得像不像 mapping」
    ///
    /// R3 的病是 `hasPrefix("value:")`——猜一種寫法。R3 的修法換成「有沒有 YAML 鍵結構」
    /// ——**那仍是白名單**，只是把邊界挪了一格。R4 實測四種合法的 format-13 元素落在
    /// 新邊界外面（`- value : X`、`-  value: X`、`- {value: X}`、`- "value": X`），
    /// 而前兩者改寫後產生 `- value: value : X`：**整檔 YAML 語法錯誤**，比原缺陷嚴重
    /// ——原缺陷只是 decode 失敗。
    ///
    /// 當時的註解**寫出了正確的性質**（「ISSN 與 ISBN 的值不含冒號」）卻實作了它的
    /// 近似補集。這一版直接問那個性質：**`ISSN(v) != nil`**。
    ///
    /// 於是它只在「確定是裸識別碼」時改寫——mapping、垃圾、解析不出的值一律不動。
    /// 不確定就不碰，剩下的交給 quarantine 具名，那比猜一個包裝誠實。
    ///
    /// 序列的結束條件同樣改掉白名單：**下一個頂層鍵**才是邊界（第 0 欄的 `<鍵>:`），
    /// 空行與 `#` 註解不再讓其後的元素漏掉（R4 ⑤）。
    static func upgradedLines(_ lines: [String]) -> [String] {
        var out = lines
        var listKey: String?
        for i in lines.indices {
            let line = lines[i]
            if line == "issn:" || line == "isbn:" {
                listKey = String(line.dropLast()); continue
            }
            guard let key = listKey else { continue }
            if line.hasPrefix("- ") {
                let v = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if isBareIdentifier(v, field: key) { out[i] = "- value: \(v)" }
                continue
            }
            // **序列的邊界是下一個頂層鍵**，不是「這一行長得像不像續行」。
            // 空行、`#` 註解、縮排的續行都仍在序列內。
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("#"),
               line.first?.isWhitespace != true {
                listKey = nil
            }
        }
        return out
    }

    /// 這個字串是不是該欄位的**裸識別碼**——由型別自己的建構器回答，不由形狀猜。
    static func isBareIdentifier(_ v: String, field: String) -> Bool {
        switch field {
        case "issn": return ISSN(v) != nil
        case "isbn": return ISBN(v) != nil
        default:     return false
        }
    }

    private static func splitTokens(_ stripped: String) -> [String] {
        stripped
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// 帶限定詞的正規化＋去重（#394 verify）。
    ///
    /// **相等仍只看正規形**（`Identifier` 的既有立場——否則 `0003-066x` 與 `0003-066X`
    /// 會被當成兩個號）。所以去重時要決定保留哪一個的限定詞：**有的勝過沒有的**。
    ///
    /// 兩個都有而且不同時（實測案例：`0022-3514 (Print) 0022-3514 (Linking)`——同一個
    /// 號同時是紙本 ISSN 與 ISSN-L）**保留先出現的**，第二個由
    /// `candidatesWithAnnotations` 的回報留下痕跡。一個 `String?` 裝不下兩個角色，
    /// 而為此把欄位變成清單，是為一個實測 1 筆的情形付結構成本。
    /// 把一個識別碼併進清單：相等時**有 qualifier 的勝過沒有的**（#425 verify HIGH）。
    ///
    /// 抽出來是因為這條規則先前只寫在 `normalizedUniqueQualified`（單一欄位內的多值），
    /// 而**跨 work 累積到 venue 的那一步沒有套用它**——`merged.contains(v)` 走
    /// `Identifier.==`，而它刻意只比 `normalized`（dedup 的前提，不能改），
    /// 所以先進來的勝出、不論有沒有 qualifier。
    ///
    /// 那是真實資料的形狀：同一份期刊被多篇引用，只有其中一篇帶括號註記，
    /// 而那一篇的 citekey 不一定排在前面。複製一份規則到第二處必然分岔，
    /// 而分岔的方向就是「其中一處安靜地丟掉 qualifier」。
    static func mergePreferringQualified<T: Identifier>(_ v: T, into out: inout [T]) {
        if let idx = out.firstIndex(of: v) {
            if out[idx].qualifier == nil, v.qualifier != nil { out[idx] = v }
        } else {
            out.append(v)
        }
    }

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

    /// 正規化 ＋ **去重**（task 8.2：先正規化再去重，去重後仍 >1 者才是真多號）。
    static func normalizedUnique<T: Identifier>(_ raws: [String], _ make: (String) -> T?)
        -> (values: [T], unparseable: [String]) {
        var out: [T] = []
        var bad: [String] = []
        for r in raws {
            guard let v = make(r) else { bad.append(r); continue }
            if !out.contains(v) { out.append(v) }
        }
        return (out, bad)
    }

    /// 這個欄位的多值該吸收，還是交給人？**按種類分，而分法是量出來的。**
    ///
    /// | 種類 | 一個欄位解出 >1 相異值 | 那些多值是什麼 | 裁決 |
    /// | --- | --- | --- | --- |
    /// | PMID | 0 筆 | — | 不吸收（無實例，且一篇一個 PMID） |
    /// | ISBN | 5 筆 | 精裝／電子版、ISBN-10 與 ISBN-13——**同一本書的兩個號** | 吸收 |
    /// | ISSN | 25 筆 | print 與 electronic——**同一份期刊的兩個號** | 吸收 |
    /// | DOI | **1 筆** | `10.1037/amp0000794` ＋ `….supp (Supplemental)`——**附錄的 DOI** | 不吸收 |
    ///
    /// DOI 那一筆是決定性的：吸收它等於讓該記錄宣稱自己是另一個物件，而識別碼**終結
    /// 指涉**（`identity-is-judged-not-matched`）——那是一句假的身分宣稱，不是多一筆資料。
    ///
    /// **spec 給 DOI 是清單的證據不支持吸收**：它寫「37 組 work 記錄同題同年而 DOI 不同」
    /// ——那是**跨記錄**的重複，不是一筆記錄需要兩個 DOI。型別仍然是清單（真的多 DOI 存在
    /// 且遷移之後可以人工加），但遷移不從一個自由字串裡**發明**多值。
    ///
    /// 不吸收 ≠ 丟棄：那一筆會出現在報告的 `skipped` 裡、原值留在 `fields`，交人裁。
    public static func absorbsMultipleValues(field: String) -> Bool {
        field == "issn" || field == "isbn"
    }

    /// **format 12 → 13 的形狀前置升級**（#394 verify）：`issn:`／`isbn:` 序列的
    /// 裸純量元素改寫成 `- value: …`。
    ///
    /// ## 為什麼這條相容路徑可以存在
    ///
    /// `no-compat-fallback` 允許「一次改不完」時保留相容路徑，但要求三件事，本函式逐條滿足：
    ///
    /// 1. **不住 default 位置**：解碼器（`decodeQualifiedList`）維持嚴格、對裸純量整檔拒讀。
    ///    這條路徑**只有遷移命令呼叫**，`grep -n 'upgradingIdentifierShape' Sources/` 一眼看完。
    /// 2. **退場量測**（可直接貼進終端機）：
    ///    ```bash
    ///    awk 'FNR==1{s=0} /^(issn|isbn):$/{s=1;next} s&&/^- /{if($0!~/^- value:/)n++;next} \
    ///         s&&!/^[ -]/{s=0} END{print n+0}' ~/.akashic/entities/*.yaml
    ///    ```
    ///    回 0 ＝ 全庫已無裸純量形狀，本函式可刪。
    ///
    ///    **上一版的量測是壞的**（#394 verify R5 ⑤）：`grep -A5` 的 context 行用 `-` 當
    ///    分隔（`檔名-<行>`），而編碼器把 `references:` 排在 `isbn:`／`issn:` 之後，於是
    ///    每個帶 reference 的記錄都貢獻一個 `- field: resolution-confirmed` 假陽性。
    ///    在**乾淨的** store 上它回 **35** 而非 0——也就是它**永遠到不了退場條件**，
    ///    而維護者會據此判定「還有 35 筆舊形狀」並把這條路徑永久留著。
    ///
    ///    新版逐檔重置狀態、只認 `issn:`／`isbn:` 序列自己的元素。實測（2026-08-26，
    ///    真實 store）：**序列元素 88 個、裸純量 0 個** → 回 0。負控:注入一個裸純量回 1。
    ///
    ///    **所以退場條件此刻已經成立**——本函式與呼叫點可刪。刻意不在同一個變更裡刪:
    ///    它是 #394 的 apply 路徑正在用的東西,而那條路徑還沒 merge。追蹤:#394 close 前。
    /// 3. **退場即刪**：條件成立後移除本函式與它的呼叫點，不留著當保險。
    ///
    /// ## 為什麼是文字層而不是寬容解碼器
    ///
    /// 寬容解碼器要嘛住 default 位置（違反第 1 條），要嘛要把旗標穿過整條 decode 鏈。
    /// 而這是**一次性的形狀轉換**，文字層足夠且不污染型別層——同 `migrate-venues`
    /// 一族的既有形狀。
    ///
    /// 只改**確實是舊形狀**的行：`issn:`／`isbn:` 之下、以 `- ` 開頭、且**不是**
    /// `- value:` 的那些。其餘一律不動。
    @discardableResult
    static func upgradingIdentifierShape(store: LibraryStore, apply: Bool,
                                         tracked: Set<Data>)
        throws -> (touched: [String], upgraded: [String: String]) {
        let fm = FileManager.default
        let dir = store.root.appendingPathComponent("entities")
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return ([], [:]) }
        var touched: [String] = []
        var upgraded: [String: String] = [:]
        for name in names.sorted() where name.hasSuffix(".yaml") {
            let url = dir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n")
            let newLines = Self.upgradedLines(lines)
            let changed = newLines != lines
            guard changed else { continue }
            let rel = "entities/\(name)"
            // **同一條 trackedness 紀律**：未被 git 追蹤的檔改寫沒有回復路徑。
            // 前置升級也是改寫——它先前繞過了這道閘。
            guard tracked.contains(Data(rel.utf8)) else { continue }
            touched.append(rel)
            let newText = newLines.joined(separator: "\n")
            if apply {
                try newText.write(to: url, atomically: true, encoding: .utf8)
            } else {
                // **乾跑不寫檔，但要讓 load 看到升級後的樣子**——否則那些檔會被
                // quarantine，於是乾跑拒跑而 apply 成功（#425 verify）。
                upgraded[url.path] = newText
            }
        }
        return (touched, upgraded)
    }

    /// 掃全庫、產出處置計畫；`apply` 才寫入。
    ///
    /// **不自動 bump format**（design 的部署順序）——遷移必須跑得動在舊解碼器上，
    /// bump 是人工的最後一步。
    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        var report = Report()
        // trackedness 先算——前置升級也要受它管（它同樣是改寫）。
        var tracked: Set<Data> = []
        var trackednessKnown = true
        if let out0 = LibraryStore.git(["ls-files", "-z", "--", "entities"], in: store.root),
           out0.status == 0 {
            tracked = Set(out0.out.split(separator: "\0").map { Data($0.utf8) })
        } else if apply {
            throw PersonIdentityMigration.MigrationError.noRecoveryPath(
                detail: "git ls-files 無法執行——無從確認追蹤狀態")
        } else {
            trackednessKnown = false
        }
        // **形狀前置升級必須在 load 之前**——裸純量的 issn/isbn 會讓那些檔整檔
        // quarantine，於是 load 之後它們根本不在 `load.venues`／`load.entries` 裡。
        // **一律模擬，寫入延到守衛之後**（#394 verify R4）。
        //
        // 先前的順序是「升級寫檔 → load → 守衛」，於是守衛擋下時**檔案已經被改過**，
        // 而 `report`（含 `shapeUpgraded`）隨例外被丟棄——使用者沒有任何線索知道
        // 有寫入發生過。R3 的註解已經為 venue 寫入具名了這個形狀，而形狀升級這一格
        // 當時沒有跟著改。
        //
        // 現在乾跑與 apply 走**同一條**模擬路徑，差別只剩最後那一步寫不寫。
        let shape = try upgradingIdentifierShape(store: store, apply: false, tracked: tracked)
        report.shapeUpgraded = shape.touched
        // 乾跑：把升級後的文字餵給接下來的 load，磁碟不動（#425 verify 的裁決）。
        store.textOverrides = shape.upgraded
        defer { store.textOverrides = [:] }
        let load = try store.load()
        // **quarantine 守衛**（#394 verify CRITICAL）。對照組就在隔壁：
        // `AuthorizedNameMigration.run` 對非空 quarantined 直接拒跑，理由是「本工具
        // **看不見**它們」。這裡先前沒有，而後果更尖銳：形狀前置升級只認**一種**
        // YAML 寫法（頂格 `issn:` ＋ 頂格 `- `），縮排序列／flow 序列／CRLF／混合形狀
        // 一律漏掉，然後**在同一次 run 的下一行**被 `decodeQualifiedList` 拒讀而整檔
        // quarantine——於是那個 venue 從 `load.venues` 消失，報告卻說一切正常，
        // 甚至可能印出誤導的「venue「X」不存在——ISSN 無處可放」。
        //
        // fail-fast 兩種模式都擋：乾跑的報告對看不見的記錄同樣不完整。
        guard load.quarantined.isEmpty else {
            throw StoreIOError.invalidInput(
                what: "migrate-identifiers",
                why: "store 有 \(load.quarantined.count) 個檔 quarantined——本工具"
                      + "**看不見**它們（load 已排除），"
                      + (apply ? "apply 會改寫其餘記錄並回報成功，而那些檔的識別碼"
                               + "一個都沒被搬，後續 format bump 會把它們鎖在門外"
                               : "報告會漏掉它們（誤導性的不完整）")
                      + "。先跑 `akashic doctor` 看 quarantine 的原因。"
                      + "**若是 `issn`／`isbn` 的裸純量序列**，那是本命令的形狀前置升級"
                      + "沒有處理到的形狀——它只認頂格的 `issn:`／`isbn:` ＋ 頂格的 "
                      + "`- <識別碼>`，且該檔必須已被 git 追蹤。已知會漏的："
                      + "CRLF 行尾、縮排序列、未追蹤的檔。人工改成 `- value: …` 後重跑。")
        }

        // per-file trackedness：apply 時查一次（同 VenueMigration／PersonIdentityMigration）。
        // 未被 git 追蹤的檔改寫沒有回復路徑。


        // venue key → 要加上去的 ISSN（跨 work 累積後一次寫）。
        var issnByVenue: [String: [ISSN]] = [:]
        var issnSources: [String: [String]] = [:]
        var updatedEntries: [Entry] = []
        // 每筆 work 自己的值改寫（citekey → 對照），供 provenance 同步改寫（task 8.3）。
        var rewritesByCitekey: [String: [IdentifierRewrite]] = [:]
        // ISSN 的改寫跟著號搬到 venue——venue 上指向該號舊字面的 reference 要一起改。
        var rewritesByVenue: [String: [IdentifierRewrite]] = [:]

        for entry in load.entries.sorted(by: { $0.citekey < $1.citekey }) {
            var updated = entry
            var changes: [String] = []
            var issnTarget: String?

            for key in workIdentifierKeys {
                guard let raw = entry.fields[key] else { continue }
                let annotations = candidatesWithAnnotations(raw, field: key).annotations
                let qualifiedToks = qualifiedCandidates(raw, field: key)
                if !annotations.isEmpty {
                    report.discardedAnnotations.append(DiscardedAnnotation(
                        citekey: entry.citekey, field: key, raw: raw, annotations: annotations))
                }

                // **有解不了的 token 時，殘留要留著；但可解的那個仍要升格**（#424 裁決 A）。
                //
                // 這兩件事先前綁在同一個 `return`（`bad.isEmpty ? values : nil`），
                // 而那一行的註解只寫了前半——於是「保護解不了的 token」被實作成
                // 「連可解的一起放棄」。實測 2 筆記錄因此永遠沒有一等公民 DOI，
                // 而它們在報告上長得像「這個值解析不了」。
                var residueMustStay = false
                func take<T: Identifier>(_ make: (String) -> T?) -> [T]? {
                    let (values, bad) = normalizedUniqueQualified(qualifiedToks, make)
                    for b in bad {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: b,
                            reason: "解析不了——不猜、不丟棄，原值留在 fields"))
                    }
                    // **正規形與原字面不同者即是一次改寫**——指向舊字面的
                    // provenance reference 要在同一次寫入裡跟著改（task 8.3）。
                    for v in values where v.raw != v.normalized {
                        let rw = IdentifierRewrite(field: key, old: v.raw, new: v.normalized)
                        rewritesByCitekey[entry.citekey, default: []].append(rw)
                    }
                    guard !values.isEmpty else { return nil }
                    guard values.count == 1 || absorbsMultipleValues(field: key) else {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: raw,
                            reason: "一個欄位解出 \(values.count) 個相異值，而 \(key) 不吸收多值"
                                + "——實測唯一的多 DOI 是附錄的 DOI，吸收它是一句假的身分宣稱；交人裁"))
                        return nil
                    }
                    // 有任何一個 bad → **殘留留著**（它是那些解不了的值唯一的棲身處），
                    // 但可解的那些照樣升格。呼叫端讀 `residueMustStay` 決定要不要
                    // `removeValue`——那是本函式與呼叫端刻意分開的兩個決定。
                    residueMustStay = !bad.isEmpty
                    return values
                }

                switch key {
                case "doi":
                    // **不覆寫已在場的結構化值**（#394 verify）。§3 讓結構化欄位與
                    // `fields` 殘留並存是設計中的過渡態，而 `canonicalDOIs` 的既有
                    // 立場是「兩者同時在場時的正典是結構化那個」。無條件賦值會讓
                    // 遷移把正典換成殘留——方向正好相反，且不可逆。
                    guard updated.doi.isEmpty else {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: raw,
                            reason: "已有結構化 doi「"
                                + updated.doi.map(\.normalized).joined(separator: "、")
                                + "」——殘留與正典並存時正典勝，不覆寫；兩者不一致交人裁"))
                        continue
                    }
                    if let v: [DOI] = take(DOI.init) {
                        updated.doi = v; if !residueMustStay { updated.fields.removeValue(forKey: key) }
                        changes.append("doi: \(raw) → \(v.map(\.normalized).joined(separator: "、"))")
                    }
                case "pmid":
                    // **不覆寫已在場的結構化值**（#394 verify）。§3 讓結構化欄位與
                    // `fields` 殘留並存是設計中的過渡態，而 `canonicalPMIDs` 的既有
                    // 立場是「兩者同時在場時的正典是結構化那個」。無條件賦值會讓
                    // 遷移把正典換成殘留——方向正好相反，且不可逆。
                    guard updated.pmid.isEmpty else {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: raw,
                            reason: "已有結構化 pmid「"
                                + updated.pmid.map(\.normalized).joined(separator: "、")
                                + "」——殘留與正典並存時正典勝，不覆寫；兩者不一致交人裁"))
                        continue
                    }
                    if let v: [PMID] = take(PMID.init) {
                        updated.pmid = v; if !residueMustStay { updated.fields.removeValue(forKey: key) }
                        changes.append("pmid: \(raw) → \(v.map(\.normalized).joined(separator: "、"))")
                    }
                case "isbn":
                    // **不覆寫已在場的結構化值**（#394 verify）。§3 讓結構化欄位與
                    // `fields` 殘留並存是設計中的過渡態，而 `canonicalISBNs` 的既有
                    // 立場是「兩者同時在場時的正典是結構化那個」。無條件賦值會讓
                    // 遷移把正典換成殘留——方向正好相反，且不可逆。
                    guard updated.isbn.isEmpty else {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: raw,
                            reason: "已有結構化 isbn「"
                                + updated.isbn.map(\.normalized).joined(separator: "、")
                                + "」——殘留與正典並存時正典勝，不覆寫；兩者不一致交人裁"))
                        continue
                    }
                    if let v: [ISBN] = take(ISBN.init) {
                        updated.isbn = v; if !residueMustStay { updated.fields.removeValue(forKey: key) }
                        changes.append("isbn: \(raw) → \(v.map(\.normalized).joined(separator: "、"))")
                    }
                case "issn":
                    // **ISSN 不留在 work 上**——它識別的是期刊不是文章
                    // （spec：An identifier SHALL live on the entity it identifies）。
                    guard let vkey = entry.venues.compactMap({ ref -> String? in
                        if case .key(let k) = ref { return k } else { return nil }
                    }).first else {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: raw,
                            reason: "venue 邊尚未歸戶（仍是 literal 或不存在）——ISSN 無處可放"))
                        continue
                    }
                    if let v: [ISSN] = take(ISSN.init) {
                        if !residueMustStay { updated.fields.removeValue(forKey: key) }
                        issnByVenue[vkey, default: []].append(contentsOf: v)
                        for one in v where one.raw != one.normalized {
                            rewritesByVenue[vkey, default: []].append(
                                IdentifierRewrite(field: "issn", old: one.raw,
                                                  new: one.normalized))
                        }
                        issnSources[vkey, default: []].append(raw)
                        issnTarget = vkey
                        changes.append("issn: \(raw) → venue「\(vkey)」")
                    }
                default: break
                }
            }

            guard !changes.isEmpty else { continue }
            report.plans.append(Plan(citekey: entry.citekey, changes: changes,
                                     issnToVenue: issnTarget))
            updatedEntries.append(updated)
        }

        // venue 側：跨 work 累積之後**再去重一次**——同一份期刊被多篇引用時，
        // 各篇給的寫法可能不同（`0003-066x` 與 `0003-066X 1935-990X` 即實測案例）。
        let existingVenues = Dictionary(uniqueKeysWithValues: load.venues.map { ($0.key, $0) })
        for (vkey, raws) in issnByVenue.sorted(by: { $0.key < $1.key }) {
            var merged: [ISSN] = existingVenues[vkey]?.issn ?? []
            var mergedFrom: [String] = []
            // **同一條偏好規則**（#425 verify）——先前這裡是 `!merged.contains(v)`，
            // 於是先進來的勝出而不論有無 qualifier。
            for v in raws { Self.mergePreferringQualified(v, into: &merged) }
            for src in issnSources[vkey] ?? [] where !mergedFrom.contains(src) {
                mergedFrom.append(src)
            }
            report.venuePlans.append(VenuePlan(
                venueKey: vkey, issn: merged,
                mergedFrom: mergedFrom, keptMultiple: merged.count > 1))
        }

        // 守衛過了——現在才把形狀升級落到磁碟。
        if apply {
            for (path, text) in shape.upgraded.sorted(by: { $0.key < $1.key }) {
                try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            }
        }

        // ---- Pre-flight：**任何寫入之前**判定每個 venue 落點寫不寫得成 ----
        //
        // 這是 `mcp-cli-parity` 為本命令寫下的那句話的守衛：「它會**跨記錄搬動資料**
        // （work 的 issn 移位到它的 venue），所以一次失敗的部分寫入會讓兩邊都不對」。
        // 規則指名了風險，實作原本沒有對應的守衛——work 先寫（`fields.issn` 已刪）、
        // venue 後寫，venue 那格失敗時 ISSN **從兩邊都消失**，且工具內不可逆。
        //
        // 判定只依賴 pre-flight 拿得到的事實（venue 是否存在、檔案是否被追蹤），
        // 所以乾跑與 apply 得到**同一組** blockers——乾跑因此真的能預告 apply 的結果。
        // 寫入閘要用的 format——讀一次，pre-flight 與實際寫入看到同一個值。
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        var blockedVenues: Set<String> = []
        for plan in report.venuePlans {
            guard let v = existingVenues[plan.venueKey] else {
                report.blockers.append("venue「\(plan.venueKey)」不存在——ISSN 無處可放")
                blockedVenues.insert(plan.venueKey)
                continue
            }
            let rel = "entities/\(v.id.uuidString).yaml"
            if trackednessKnown && !tracked.contains(Data(rel.utf8)) {
                report.blockers.append("venue「\(plan.venueKey)」：\(rel) 未被 git 追蹤")
                blockedVenues.insert(plan.venueKey)
                continue
            }
            // **模擬實際的寫入閘**（#394 verify）。先前 pre-flight 只查「venue 存在」
            // 與「檔案受追蹤」，而 `writeVenue` 另有四道會 throw 的閘
            //（key 合法性、format >= 11、venue type 的 format 閘、識別碼 reference 的
            // format 13 閘、`assertNoErrors(validate())`）。任何一道在寫入當下 throw，
            // 例外就穿出 run()——work 的 `fields.issn` 已被移除而 venue 從未收到那個號，
            // **ISSN 從兩邊同時消失**，且 report 在印任何東西之前就被丟棄。
            //
            // 走 `LibraryStore.assertVenueWritable` 的**同一份**閘門清單，不複製。
            var candidate = v
            candidate.issn = plan.issn
            do {
                try LibraryStore.assertVenueWritable(candidate, format: storeFormat)
            } catch {
                report.blockers.append("venue「\(plan.venueKey)」寫入前提不成立：\(error)")
                blockedVenues.insert(plan.venueKey)
            }
        }
        // 落點被擋的 work **整筆不動**——不是「照寫但少一個欄位」。它的 `fields.issn`
        // 是那個號在此刻唯一的棲身處，刪掉它而 venue 沒收到，就是純粹的資料消失。
        let issnTargetByCitekey = Dictionary(
            report.plans.compactMap { p in p.issnToVenue.map { (p.citekey, $0) } },
            uniquingKeysWith: { a, _ in a })
        var blockedEntries: Set<String> = []
        for (ck, vkey) in issnTargetByCitekey where blockedVenues.contains(vkey) {
            report.blockers.append("\(ck)：ISSN 的落點 venue「\(vkey)」寫不進去——本筆整筆略過")
            blockedEntries.insert(ck)
        }
        if trackednessKnown {
            for updated in updatedEntries
            where !tracked.contains(Data("entities/\(updated.id.uuidString).yaml".utf8)) {
                report.blockers.append(
                    "\(updated.citekey)：entities/\(updated.id.uuidString).yaml 未被 git 追蹤"
                    + "——改寫無回復路徑，先 commit 再跑")
                blockedEntries.insert(updated.citekey)
            }
        }

        guard apply else { return report }

        // ---- 寫入（此後不再有新的失敗判定；所有前提已在上方裁決）----
        for updated in updatedEntries where !blockedEntries.contains(updated.citekey) {
            _ = try store.writeEntry(rewritingProvenance(
                updated, rewrites: rewritesByCitekey[updated.citekey] ?? [], report: &report))
            report.applied += 1
        }
        for plan in report.venuePlans where !blockedVenues.contains(plan.venueKey) {
            guard var v = existingVenues[plan.venueKey] else { continue }
            // **直接用 plan 帶的 ISSN 物件**——經字串往返會把 medium 丟掉。
            v.issn = plan.issn
            _ = try store.writeVenue(rewritingProvenance(
                v, rewrites: rewritesByVenue[plan.venueKey] ?? [], report: &report))
            report.applied += 1
        }
        return report
    }

    /// 一次識別碼值的改寫：某個欄位裡的舊字面 → 新的正規形。
    public struct IdentifierRewrite: Equatable {
        public let field: String
        public let old: String
        public let new: String
    }

    /// 指向被改寫值的 provenance `value` 同一次原子改寫（task 8.3）。
    ///
    /// **這個函式曾經是恆等空殼**（`report.provenanceRewrites.append(contentsOf: [])`
    /// ＋ `return record`），而 tasks.md 8.3 打勾宣稱「測試斷言改寫後無任何 reference
    /// 指向不存在的值」——那個測試不存在，16 支遷移測試零觸及 provenance。
    ///
    /// 空殼有一個**真實的**理由：舊簽章只收記錄，拿不到「舊值是什麼」，所以它結構上
    /// 做不到自己宣稱的事。修法是改簽章，不是補迴圈。
    ///
    /// **零實例的理由即將過期。** doc 原本寫「venue 的 issn reference 還不存在（寫入面
    /// 要 format 13，而 store 仍是 12）」——而 store 正要 bump 到 13，那道閘就開了。
    /// 遷移是一次性的破壞性寫入：等真的有 reference 指向識別碼時再補就來不及
    /// （`zero-instance-guards` 第 8 列的「不可回頭」）。
    static func rewritingProvenance<T: ProvenanceCarrying>(
        _ record: T, rewrites: [IdentifierRewrite], report: inout Report
    ) -> T {
        guard !rewrites.isEmpty, !record.references.isEmpty else { return record }
        var out = record
        for i in out.references.indices {
            let ref = out.references[i]
            guard let v = ref.value,
                  let hit = rewrites.first(where: { $0.field == ref.field && $0.old == v })
            else { continue }
            out.references[i].value = hit.new
            report.provenanceRewrites.append("\(ref.field)「\(v)」→「\(hit.new)」")
        }
        return out
    }
}
