import Foundation
import AkashicCore
import BiblatexAPA

/// `.bib` 是編譯產物——從 store 匯出、經 biblatex-apa-swift 序列化，
/// 永遠不是資料庫本體（spec ADR #10）。
public enum BibExport {
    /// Entry.fields（已是 biblatex 欄位名）之外的一級欄位對映。
    public static func bibEntry(for entry: Entry, people: [String: Person],
                                organizations: [String: Organization] = [:],
                                venues: [String: Venue]) -> BibEntry {
        // 每個值都過 `braceSafe`（#176）。**逐個作者、不是 join 之後**——一個壞名字
        // 不該把整串作者一起拖進逃脫（那會改掉同一筆裡其他機構名的 `{...}` 標記）。
        var fields = OrderedDict()
        fields["title"] = braceSafe(entry.title)
        if !entry.authors.isEmpty {
            fields["author"] = entry.authors
                .map { braceSafe(bibName(for: $0, people: people,
                                         organizations: organizations)) }
                .joined(separator: " and ")
        }
        if let date = entry.date, !entry.dateIsConfirmedAbsent {
            fields["date"] = braceSafe(date)
        }
        // `n.d.` sentinel **不寫進 .bib**（#350 第 2 類）。依賴自己的
        // `APACitationParser` 對 `n.d.` 的處理就是「無日期」並省略欄位，而 biblatex-apa
        // 對缺席的 date 印 `(n.d.)`——那正是 APA7 要的輸出。寫 `date = {n.d.}` 反而會
        // 讓 date parser 拿到一個不是日期的字串。
        //
        // 所以「確認無日期」在 store 裡是一個值、在 `.bib` 裡是欄位缺席。兩邊的表達方式
        // 不同是刻意的：store 要能區分「查過沒有」與「還沒查」，`.bib` 不需要（它只需要
        // 印對）。
        for key in entry.fields.keys.sorted() {
            fields[key] = entry.fields[key].map(braceSafe)
        }
        // 作品識別碼（#394 §7）。**在 `fields` 之後寫**——理由同下方學位論文欄位：
        // 遷移把 `doi` 從 `Entry.fields` 搬進結構化欄位之後，上面那個逐鍵迴圈就不再
        // 輸出它，而 `.bib` 少一個欄位**不會報錯**（LaTeX 照樣編得過，只是參考文獻
        // 少了 DOI）。這是 `apa7-is-the-work-floor` 記過的「語法正確性與書目正確性是
        // 兩件事」，而目前只有前者有守衛。
        //
        // **只在有結構化值時覆蓋。** 遷移前的記錄只有 `fields.doi`，那時必須照舊
        // 輸出殘留——否則光是升級 binary 就會讓全庫的 DOI 從 .bib 消失。
        //
        // 多值以逗號分隔：一筆 work 真的可以有多個 DOI（實測 37 組同題同年而 DOI
        // 不同），只留一個等於丟掉一次身分判定。寫出的是**正規形**——磁碟上可能是
        // 非正規形，但 .bib 是給下游排版用的。
        func emitIdentifiers<T: Identifier>(_ ids: [T], as key: String) {
            guard !ids.isEmpty else { return }
            fields[key] = braceSafe(ids.map(\.normalized).joined(separator: ", "))
        }
        emitIdentifiers(entry.doi, as: "doi")
        emitIdentifiers(entry.pmid, as: "pmid")
        emitIdentifiers(entry.isbn, as: "isbn")
        // **ISSN 來自 venue，不是 work**（#394 §8 遷移之後）。
        //
        // design.md 的 Risks 段預言了「export 靜默少欄位」，而 §7 的 mitigation 只涵蓋
        // `doi`／`pmid`／`isbn`——那三個仍在 work 上，`issn` **換了實體**，所以同一個
        // 形狀套不上去。遷移後實測 `.bib` 的 ISSN 欄位自 64 掉到 0：資料沒丟（在 venue
        // 上），但匯出看不到。驗收條件也沒抓到，因為它只列了那三個欄位。
        //
        // **只在 `fields` 沒有殘留時才寫**——遷移略過的那些仍在 `fields`，不得被覆蓋。
        // venue 未歸戶（`.literal`）時不生出任何東西：沒有 venue 記錄就沒有號。
        // **venue 優先於 work 的殘留**（#425 verify HIGH）。
        //
        // 先前的條件是 `if fields["issn"] == nil`——只在 work 沒有殘留時才拉 venue。
        // 而 `import-zotero`（pull）會把 `fields.issn` 寫回 work，於是那條拉取
        // **被遮蔽**，`.bib` 改印 Zotero 的原始字串而不是 venue 上正規化過的號。
        //
        // 方向該反過來：識別碼住在它所識別的實體上（spec），venue 的那個才是正典；
        // work 的殘留是**過渡態**（等 migrate-identifiers 搬走）。venue 沒有號時才
        // 退回殘留——那時它是唯一的來源。
        let venueISSNs = entry.venues.compactMap { ref -> Venue? in
            if case .key(let k) = ref { return venues[k] } else { return nil }
        }.flatMap(\.issn)
        if !venueISSNs.isEmpty {
            emitIdentifiers(venueISSNs, as: "issn")
        }
        // 學位論文事實（#335）。**在 `fields` 之後寫**，所以結構化欄位勝過自由字典裡
        // 同名的殘留值——遷移把 `fields.type` 搬進 `thesis.degree` 之後那個殘留不該
        // 存在，但若存在，結構化的那個才是正典（`no-compat-fallback`：不留兩條讀法）。
        if let th = entry.thesis {
            if let degree = th.degree {
                // token 由依賴指定（`APADataModel.suggestTypeUpgrade`），非自創慣例。
                fields["type"] = braceSafe(degree.biblatexToken)
            }
            if case .published(let repository, let url) = th.availability {
                // `eprint` ＝來源平台／典藏庫，沿用依賴自己的慣例（`classifyOnline`
                // 讀 `EPRINT` 判平台；ch10 fixture 的維基條目也用 `EPRINT = {Wikipedia}`）。
                //
                // **誠實邊界**：biblatex-apa 是否真的把它渲染成 §10.6 已出版形態的
                // source element，**未經 LaTeX 往返實測**——本專案沒有那種測試。依賴
                // 對「已出版 vs 未出版的學位論文」沒有任何機制（全樹搜尋只命中節名
                // 字串），所以 §10.6 兩形態的**渲染**是上游缺口。模型持有這個事實是
                // 下限要求（`apa7-is-the-work-floor`），渲染保真度是另一件事。
                if let repository { fields["eprint"] = braceSafe(repository) }
                if let url { fields["url"] = braceSafe(url) }
            }
        }
        // #355：`.review` 無條件帶 `RELATEDTYPE = reviewof`。
        //
        // **這不是為了讓分類器高興而編造欄位**——判準是「這個值對這個型別是不是定義上
        // 為真」。`.review` 的意思就是「這是一篇評論」，而「評論某物」是它的定義，
        // 不是某筆記錄碰巧具備的性質。對照 #355 否決掉的另外兩個：
        // `ENTRYSUBTYPE: Database record` 對非 PsycTESTS 的量表為假、
        // `EPRINT: Twitter` 對 Mastodon 貼文為假——那兩個是斷言記錄的**出處**，會錯。
        //
        // 既有值優先：若記錄自己帶了 `relatedtype`（例如來源就這麼寫），不覆寫。
        if entry.type == .review, fields["relatedtype"] == nil, fields["RELATEDTYPE"] == nil {
            fields["relatedtype"] = "reviewof"
        }
        // **依 fields 選型別**（#417）：`.conferenceSession` 帶 `booktitle` 時送
        // `INPROCEEDINGS`，否則 `PRESENTATION`。餵 `entry.fields` 而非上面組好的
        // `fields`——後者已經過 `braceSafe` 等處理，而判準只問「原始記錄有沒有這個欄位」。
        return BibEntry(entryType: entry.type.biblatexEntryType(fields: entry.fields),
                        key: entry.citekey,
                        fields: fields, rawText: "", lineNumber: 0)
    }

    // MARK: - APA7 完整性報告（#326）

    /// 一筆 APA7 必要／建議欄位的缺漏。
    ///
    /// 與 `AkashicCore.ValidationIssue` 同名不同物——那個管 store schema，這個管
    /// **書目正確性**。兩者刻意不合併：語法正確（大括號平衡、可被 LaTeX 讀）與書目
    /// 正確（參考文獻印得出來）是兩件事，先前只有前者有守衛。
    public struct APA7Issue: Equatable {
        public enum Severity: String, Equatable { case error, warning }
        public let citekey: String
        public let severity: Severity
        public let message: String
    }

    /// `apa7Report` 的結果。
    ///
    /// **`uncheckedCitekeys` 是這個型別存在的理由。** 必要欄位表不涵蓋所有 entry type，
    /// 而對未涵蓋的 type，檢查回空陣列——若只回 `issues`，「沒被檢查」與「檢查過且乾淨」
    /// 在輸出上**完全一樣**，而那正是本專案反覆記錄的靜默失敗形狀（`lossless-intake`
    /// 執行細節 3：「靜默是最糟的形式」）。
    ///
    /// type 值域的收斂已由 #325 完成（`Entry.type` 是封閉的 `WorkType`），對映的收窄由
    /// #352 修正，但**涵蓋缺口仍在**——收斂的是我們這一側，不是對方的必要欄位表。本型別
    /// 的責任只是**不假裝檢查過**。哪些節因此驗不出東西，由 `APA7GoldenTests` 逐節斷言
    /// （#327）。
    public struct APA7Report: Equatable {
        public let issues: [APA7Issue]
        public let uncheckedCitekeys: [String]

        /// 有沒有 error 級缺漏（warning 不算——它們是 recommended 欄位）。
        public var hasErrors: Bool { issues.contains { $0.severity == .error } }
    }

    /// 必要欄位表涵蓋的 entry type——**現算，不維護鏡像**（#353）。
    ///
    /// ## 為什麼是 `APADataModel` 而不是 `BibValidator`
    ///
    /// 依賴裡有**兩張**必要欄位表，而它們對同一個型別會給出不同答案：
    ///
    /// | | `BibValidator.requiredFields` | `APADataModel.requiredFields`（本函式用） |
    /// |---|---|---|
    /// | 涵蓋型別 | 7 | **15** |
    /// | 來源 | 手寫 | **`apa.dbx`**（biblatex-apa 的 LaTeX 資料模型）|
    /// | `ONLINE` | 不在表內 → 整批 unchecked | `[TITLE, DATE]`，**AUTHOR 不要求** |
    /// | `PRESENTATION` 的 `EVENTTITLE` | required | 只是 recommended |
    ///
    /// 選 `APADataModel` 的理由不是「它比較大」，是**它比較權威**：值域來自 `apa.dbx`，
    /// 而依賴自己較新的路徑（`APARuleEngine.fix` 的 Phase 7）也在用它。`BibValidator`
    /// 是較舊的那條。
    ///
    /// 那張表的 `ONLINE` **不要求 AUTHOR**（原始碼註解：`// AUTHOR or EDITOR recommended`）
    /// ——所以「網頁／社群貼文被報缺作者」那類假陽性（#350 第 3 類）是我們**挑錯表**
    /// 造成的，不是 APA7 的問題。（維基條目那 14 筆走 `INREFERENCE`，**兩張表都沒有它**
    /// ——那是 #354，本次未解。）
    ///
    /// ## 換表的一個代價，明寫在此（#359）
    ///
    /// 兩張表對 **`PRESENTATION` 的 `EVENTTITLE`** 給出相反的答案：`BibValidator` 說
    /// required，`APADataModel` 只列 recommended。實測 **25 筆**會議發表的
    /// `Missing EVENTTITLE` 因此從 error 降成 warning。
    ///
    /// 而依 §10.5，會議發表的 source element **就是**會議名稱——沒有它那筆參考文獻印不
    /// 出來，所以那 25 筆是**下限違反**，而 `hasErrors` 現在抓不到它們。資訊沒消失
    /// （`[WARNING]` 行照印），失去的是嚴重度分級的偵測力。
    ///
    /// **刻意不在這裡把 `EVENTTITLE` 加回 required**：那會製造第三張必要欄位表
    /// （`BibValidator` 的、`APADataModel` 的、我們自己的），而三張會各自分岔。且判準
    /// 問題沒解決——我們憑什麼說 `EVENTTITLE` 該是 required 而同樣缺 25 筆的 `VENUE`
    /// 不是？答案要來自 ch10。裁決見 #359。
    ///
    /// ## 為什麼不留手維護的鏡像
    ///
    /// 這裡原本有一份寫死的 7 個型別的 `Set`，doc 自己寫著「會隨 dependency 演進而過期」
    /// ——那句話是對的，而它就是那樣過期的。現算讓漂移在結構上不可能發生
    /// （`entity-backlink-completeness`：反向與衍生一律現算，存一份就是製造第二個會分岔
    /// 的來源）。
    private static func isCheckedByAPA7Table(_ entryType: String) -> Bool {
        requiredFields(for: entryType) != nil
    }

    /// **暫時的補充表**：依賴對這些 entry type **完全沒有意見**（兩張表都沒有它們），
    /// 而它們的必要欄位可以直接從 APA7 手冊讀出來（#354）。
    ///
    /// ## 這是 `no-compat-fallback` 明文允許的例外，三條都滿足
    ///
    /// 1. **不住 default 位置**——它是一張具名的補充表，`requiredFields(for:)` 明確地
    ///    先問依賴、再問這裡。`grep` 得出誰在走它。
    /// 2. **退場條件與量測**：當 `APADataModel.requiredFields["INREFERENCE"] != nil` 時
    ///    刪掉該列。`testSupplementOnlyCoversTypesTheDependencyLacks` 會在那一刻變紅。
    /// 3. **退場即刪**——不留著當保險。
    ///
    /// ## 為什麼是本地補充而不是改上游
    ///
    /// 先前傾向改上游（`repos/biblatex-apa-swift` 是同一個 owner 的 repo）。實地一看
    /// **那個 repo 完全沒有 Tests 目錄**——在一個沒有測試基礎設施的**共用** canonical
    /// library 裡加必要欄位語意，會讓多個 consumer 的行為改變而沒有任何守衛，比一個
    /// 自我刪除的本地補充更糟。
    ///
    /// 這也是本表與 #359 的分界：#359 要**反轉依賴刻意設定的值**（`EVENTTITLE`
    /// required ↔ recommended 是一個判斷），本表只**補上依賴沒有意見的型別**。
    /// 前者需要 ch10 的證據來裁決誰對，後者的值手冊直接寫著。
    ///
    /// ## `INREFERENCE` 的值從哪裡讀出來
    ///
    /// APA7 §10.3 的參考工具書條目（例 49 維基百科）：
    ///
    /// ```
    /// 條目名。(年, 月 日)。In 《工具書名》。URL
    /// ```
    ///
    /// **條目名佔作者位置**，所以 `AUTHOR` 不是必要的——這正是 #352 把 `wikipediaEntry`（#409 起 `referenceWorkEntry`）
    /// 從 `INCOLLECTION`（要求 `AUTHOR`）改對映到 `INREFERENCE` 的理由。但工具書名
    /// （`BOOKTITLE`）是必要的：沒有它，那筆參考文獻無法說出條目出自哪裡。
    ///
    /// 同節另有帶團體作者的例子（`American Psychological Association. (n.d.).
    /// Positive transference. In APA dictionary of psychology.`），所以 `AUTHOR` 是
    /// **recommended 而非禁止**。
    private static let supplementalRequiredFields: [String: [String]] = [
        "INREFERENCE": ["TITLE", "BOOKTITLE", "DATE"],
    ]

    /// 同上的 recommended 補充。
    private static let supplementalRecommendedFields: [String: [String]] = [
        "INREFERENCE": ["AUTHOR", "URL"],
    ]

    /// **作者位置的合法替代**（#350 第 1 類）。
    ///
    /// APA7 對編著作品把**編者放在作者位置**（`(Ed.)`／`(Eds.)`），所以一筆只有 `EDITOR`
    /// 的編著書**不是缺作者**——那是它的正確形式。必要欄位表只認 `AUTHOR`，於是把正確的
    /// 資料報成缺漏。
    ///
    /// 這條與 #359 的差別（同一條界線，第三次用到）：#359 要反轉依賴刻意設定的
    /// **required／recommended 判斷**；這裡不動任何欄位的必要性，只承認 APA7 允許
    /// **另一個欄位填同一個位置**。手冊的 template 直接寫著，不是判斷題。
    ///
    /// 值域刻意窄：只有 APA7 明確把編者放在作者位置的兩個型別。**不得依性質相似類推**
    /// ——`ARTICLE` 的編者不填作者位置（期刊文章的作者就是作者），`PRESENTATION` 同理。
    private static let authorPositionAlternatives: [String: [String]] = [
        "BOOK": ["EDITOR"],            // §10.2 編著書：Editor, E. E. (Ed.).
        "INCOLLECTION": ["EDITOR"],    // §10.3 整本編著作品被當條目引用時同形
    ]

    /// 這個必要欄位有沒有被滿足——**含 APA7 允許的替代形式**。
    ///
    /// 兩條替代規則，各自有手冊依據，且都**不是**放寬檢查：它們是修正檢查對「滿足」的
    /// 定義。缺真的缺的東西照樣報。
    private static func isSatisfied(_ field: String, in bib: BibEntry,
                                    entry: Entry, entryType: String) -> Bool {
        if bib.fields.caseInsensitiveValue(forKey: field) != nil { return true }
        // (1) 確認無日期：APA7 印 (n.d.)，那是合法形式而非缺漏。**注意這裡讀的是
        //     `entry.dateIsConfirmedAbsent` 而不是 `bib` 的欄位**——sentinel 刻意不寫進
        //     `.bib`（見 `bibEntry(for:)`），所以只有模型側知道「查過，沒有日期」。
        //     `date: nil`（還沒查）照樣報 error，這是兩者唯一被區分開的地方。
        if field.uppercased() == "DATE", entry.dateIsConfirmedAbsent { return true }
        // (2) 作者位置的合法替代（編者）。
        if let alternatives = authorPositionAlternatives[entryType],
           field.uppercased() == "AUTHOR" {
            return alternatives.contains { bib.fields.caseInsensitiveValue(forKey: $0) != nil }
        }
        return false
    }

    /// 必要欄位：**依賴優先**，補充表只在依賴沒有意見時生效。
    ///
    /// 順序是這張表的全部安全性所在——反過來就變成「用我們的意見覆寫依賴的」，
    /// 那是 #359 拒絕做的事。
    /// 一個 biblatex 型別的**完整欄位契約**（required ∪ recommended）。
    ///
    /// #414 方向 1 的可執行面：`booktitleCarrierTypes` 的成員資格判準（#324 的 §11，
    /// 「它決定了哪些欄位存在」）先前只存在於 doc comment。實測既有的兩張表
    /// **就能區辨**——`INCOLLECTION` 的 recommended 含 `EDITOR,PUBLISHER`，
    /// 兩個成員都不含——所以那個判準有程式層對應物，**不需要第三張表**
    /// （`apa7-is-the-work-floor` 記過的那個風險在這條路上不成立）。
    ///
    /// 實際的一致性由 `BooktitleCarrierDerivationTests` 逐型別驗，含一個具名的例外。
    public static func fieldContract(_ entryType: String) -> Set<String> {
        Set((requiredFields(for: entryType) ?? []) + recommendedFields(for: entryType))
    }

    static func requiredFields(for entryType: String) -> [String]? {
        APADataModel.requiredFields[entryType] ?? supplementalRequiredFields[entryType]
    }

    /// 同上，recommended 面。
    private static func recommendedFields(for entryType: String) -> [String] {
        if let fromDependency = APADataModel.recommendedFields[entryType] {
            return fromDependency
        }
        return supplementalRecommendedFields[entryType] ?? []
    }

    /// 對每筆 entry 跑 APA7 必要欄位檢查，回報缺漏與**未被涵蓋的 type**。
    ///
    /// 不改變 `.bib` 內容——本函式是純讀取的旁路檢查（warn-only，#326 裁決）。
    ///
    /// **`venues` 無預設值是刻意的**（#394 verify）：§8 讓 ISSN 住 venue 之後，漏傳
    /// 它的呼叫端會評到一份**沒有 ISSN 的** `BibEntry`，而編譯器不會出聲。這正是
    /// 下面那句 doc comment 禁止的分岔——它當時只防住 entry type，防不住欄位來源。
    public static func apa7Report(entries: [Entry], people: [Person],
                                  organizations: [Organization] = [],
                                  venues: [Venue]) -> APA7Report {
        let peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        let orgsByKey = Dictionary(uniqueKeysWithValues: organizations.map { ($0.key, $0) })
        let venuesByKey = Dictionary(venues.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var issues: [APA7Issue] = []
        var unchecked: [String] = []
        for entry in entries.sorted(by: { $0.citekey < $1.citekey }) {
            let bib = bibEntry(for: entry, people: peopleByKey, organizations: orgsByKey,
                               venues: venuesByKey)
            // 與 `bibEntry` 走**同一個**對映（#417）：兩邊分岔的話，報告會拿
            // `PRESENTATION` 的必要欄位去檢查一筆實際匯出成 `INPROCEEDINGS` 的記錄。
            let entryType = entry.type.biblatexEntryType(fields: entry.fields)
            guard isCheckedByAPA7Table(entryType) else {
                unchecked.append(entry.citekey)
                continue
            }
            // **直接讀 `APADataModel` 的表，不呼叫 `BibValidator.validate`。**
            //
            // 不是重造輪子——`APARuleEngine` 唯一使用那張表的入口是 `fix(entry:)`，而它是
            // **修改器不是驗證器**：同一次呼叫會改寫欄位（`HOWPUBLISHED` → `URL`、重排
            // 作者、格式化日期），且缺欄位是以 `kind: .warning` 的 `FixAction` 回報，沒有
            // error／warning 的嚴重度區分。本函式依 #326 的裁決是**純讀取的旁路檢查**，
            // 不能用一個會改資料的 API 實作。
            //
            // 所以這裡只借那張表，檢查迴圈自己寫（約十行）。表是唯一的知識來源，迴圈
            // 不是知識。
            for field in requiredFields(for: entryType) ?? [] {
                guard !isSatisfied(field, in: bib, entry: entry, entryType: entryType) else {
                    continue
                }
                // #457：**合法的無署名作品**。APA7 §9.12 對無作者的作品以標題起首——
                // 那是一個獨立的參考文獻形，不是缺陷。判準與 #406 的 `paginated` 完全同型：
                // 只在 store **明說過**「這一格不是作者、已移除」時抑制，也就是該 work 帶
                // 至少一筆移除記錄（`field: authors`、statement `移除：理由`）。
                //
                // **空的 `authors` 本身不足以抑制**——那是「還沒記」，正是本檢查要抓的東西。
                // 這裡與 `paginated` 的 `nil` 照報是同一條紀律：未判定不得折成預設值，
                // 否則所有沒查過的記錄都靜默通過下限檢查。
                if field.uppercased() == "AUTHOR", entry.authors.isEmpty,
                   !entry.authorRemovalRecords.isEmpty {
                    continue
                }
                issues.append(APA7Issue(citekey: entry.citekey, severity: .error,
                                        message: "Missing required field: \(field)"))
            }
            // recommended 是 warning。`PRESENTATION` 另有 context-aware 的一組
            // （依 `MAINTITLE` 在不在），由依賴自己的函式決定——不在這裡重寫那個判斷。
            let recommended: [String] = entryType == "PRESENTATION"
                ? APADataModel.presentationRecommendedFields(
                    hasMainTitle: bib.fields.caseInsensitiveValue(forKey: "MAINTITLE") != nil)
                : recommendedFields(for: entryType)
            for field in recommended {
                // #406：article-number 期刊的「缺 pages」是**正確狀態**不是缺陷。判準
                // 屬 venue 不屬 work——只在該 entry 第一個已歸戶 venue 被**判定**
                // `paginated == false` 時抑制。`nil`（未判定）與 `true` **照報**：
                // 欄位契約明文「未判定折成任何預設值，會讓所有未查的刊靜默通過
                // 下限檢查」。只限 ARTICLE——編著章節（INCOLLECTION）的頁碼與期刊
                // 分頁制無關。
                if field.uppercased() == "PAGES", entryType == "ARTICLE" {
                    let firstKeyedVenue = entry.venues.compactMap { ref -> String? in
                        if case .key(let k) = ref { return k }
                        return nil
                    }.first
                    if let vk = firstKeyedVenue, venuesByKey[vk]?.paginated == false {
                        continue
                    }
                }
                if bib.fields.caseInsensitiveValue(forKey: field) == nil {
                    issues.append(APA7Issue(citekey: entry.citekey, severity: .warning,
                                            message: "Missing recommended field: \(field)"))
                }
            }
        }
        return APA7Report(issues: issues, uncheckedCitekeys: unchecked)
    }

    public static func bibFile(entries: [Entry], people: [Person],
                               organizations: [Organization] = [],
                               venues: [Venue]) -> String {
        let peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        let orgsByKey = Dictionary(uniqueKeysWithValues: organizations.map { ($0.key, $0) })
        // #394 §8：ISSN 遷移到 venue 之後，work 的 .bib 要從這裡撈。
        let venuesByKey = Dictionary(uniqueKeysWithValues: venues.map { ($0.key, $0) })
        return entries
            .sorted { $0.citekey < $1.citekey }
            .map { BibWriter.serialize(bibEntry(for: $0, people: peopleByKey,
                                                organizations: orgsByKey,
                                                venues: venuesByKey)) }
            .joined(separator: "\n\n") + "\n"
    }

    /// 顯示名 → biblatex「Family, Given」。無空格（CJK 全名）整體視為 family。
    static func bibName(for author: AkashicCore.Author, people: [String: Person],
                        organizations: [String: Organization] = [:]) -> String {
        let display: String
        switch author {
        // #81：對外名字由 `authorized` 指定，不由 `names` 的位置決定。書目是**羅馬化
        // 脈絡**，所以請求 latn；沒有指定時解析退到 key，讓缺口在書目上看得見而不是
        // 靜默印出索引系統產生的引用形（實測 84.6% 的記錄目前會走到這一步）。
        case .key(let k): display = people[k]?.displayName(in: .latn) ?? k
        // #323：團體作者。**直接回傳雙大括號形，不走下方的 familyGiven 分支**——
        // APA7 §9.11／biblatex 的 `author = {{Group Name}}` 慣例讓 BibTeX 不把團體名
        // 拆成「姓, 名」。這條路徑先前靠 `CorporateName.isMarked` 偵測 `{...}` 標記
        // （#6），現在有**型別保證**：不是猜這串像不像機構，是這個槽已判定為機構。
        case .organization(let k):
            let name = organizations[k]?.displayName ?? k
            // 已帶標記就不重複包——`{{{X}}}` 會讓 biblatex 多一層 group。
            return CorporateName.isMarked(name) ? "{\(CorporateName.unmark(name))}"
                                                : "{\(name)}"
        case .literal(let s): display = s
        }
        // #6：機構名（`{...}` 標記）原樣輸出——biblatex 的大括號本來就是「別動它」，
        // 切成 Family, Given 會產生 "Organization, World Health" 這種錯誤輸出。
        if CorporateName.isMarked(display) { return display }
        guard let split = familyGiven(display) else { return display }
        // given 為空（例如來源只寫了姓、或尾隨逗號）時不要輸出「Chang, 」
        return split.given.isEmpty ? split.family : "\(split.family), \(split.given)"
    }

    /// 「Che Cheng」→ (family: Cheng, given: Che)；無空格回 nil（整體當 family）。
    ///
    /// ## 兩種輸入形，由**逗號**區分（#377）
    ///
    /// | 輸入 | 判定 | 輸出 |
    /// |---|---|---|
    /// | `Chang, Ya-Hsuan` | 已是 `Family, Given` | 原樣 `(Chang, Ya-Hsuan)` |
    /// | `Che Cheng` | `Given Family` | `(Cheng, Che)` |
    ///
    /// **逗號是顯式記號，不是啟發式。** biblatex 與 WoS 的 `Author Full Names`
    /// 共用「姓, 名」這個慣例，所以判準已經在資料裡——不需要猜「哪個 token 像姓」。
    ///
    /// ### 先前的缺陷（實測 730 筆）
    ///
    /// 原本一律取最後一個空格分隔 token 當姓。對 `Chang, Ya-Hsuan` 會得到
    /// family=`Ya-Hsuan`、given=`Chang,` —— **姓名顛倒且多一個逗號**，biblatex 印成
    /// 「Ya-Hsuan, C.」而非「Chang, Y.-H.」。`Reeves, Gillian K.` 更糟：`K., Reeves, Gillian`。
    ///
    /// 那 730 筆是 `import-wos` 依 `lossless-intake` 原樣收下的 WoS `Author Full Names`
    /// ——**入庫是對的，錯的是 export 端假設一律為「名 姓」**。
    ///
    /// 逗號形另有一個空格法做不到的好處：多 token 的姓（`van der Berg, Jan`）自動正確。
    static func familyGiven(_ display: String) -> (family: String, given: String)? {
        // 逗號形：第一個逗號之前是姓，之後是名。
        if let comma = display.firstIndex(of: ",") {
            let family = display[..<comma].trimmingCharacters(in: .whitespaces)
            let given = display[display.index(after: comma)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: .whitespaces)
            guard !family.isEmpty else { return nil }
            return (family: family, given: given)
        }
        let tokens = display.split(separator: " ").map(String.init)
        guard tokens.count >= 2, let family = tokens.last else { return nil }
        return (family: family, given: tokens.dropLast().joined(separator: " "))
    }

    // MARK: - 大括號注入（#176）

    /// 值裡的大括號若**不平衡**，換成平衡的 LaTeX 命令。
    ///
    /// ## 為什麼守在這裡而不是只靠 writer
    ///
    /// 欄位值寫成 `{value}`。值裡有不平衡的 `}` 就提早關掉欄位，之後的內容被當成
    /// bibtex 語法——一個 title 可以開出一整筆不存在的 entry，而下游（LaTeX build、
    /// 文獻管理器、讀這份輸出的 LLM）分不出真假。
    ///
    /// `biblatex-apa-swift` 的 `BibWriter` 也有一份同樣的防護，**兩份不衝突**：平衡的
    /// 值兩邊都原樣通過，所以這裡先做完之後那邊是 no-op。留兩份不是重複，是因為
    /// **不受信任的內容源自 store，邊界的擁有者是這裡**——`BibWriter` 是共用的
    /// canonical library，哪天換一個 writer、或它的規則改了，洞就回來。
    ///
    /// 上面 `bibName` 的 `#6` 又讓這件事非做不可：機構名的 `{...}` **刻意原樣輸出**。
    /// 這個模組已經決定了「大括號要穿透」，那它就得負責穿透的是安全的形狀。
    ///
    /// ## `\}` 不是逃脫——量過的
    ///
    /// btparse（biber 背後的 parser，BibTeX 本尊亦然）**數大括號時不看 backslash**，
    /// `\}` 照樣關掉欄位。真的 `biber --tool` 對同一個注入 payload：
    ///
    /// | 輸出成 | biber |
    /// |---|---|
    /// | 未處理 | 2 筆 entry，偽造的與真的無從分辨 |
    /// | `\}` | **syntax error**，整檔零輸出／整筆被 skip |
    /// | `\textbraceright{}` | 1 筆 entry，payload 留成文字，0 error |
    ///
    /// 所以判準是**輸出永遠平衡**（下面三個替換各自 `{`+`}` 成對），不是「有沒有加
    /// backslash」。這是輸出的結構性質，對任何做括號計數的 parser 都成立。
    ///
    /// 同理，深度計數**刻意不跳過** `\{` / `\}`：它模仿的正是 btparse 自己的計數方式，
    /// 把它們當成已逃脫會低估。
    ///
    /// **平衡的值原樣通過**：biblatex 用 `{DNA}` 保護大小寫、機構名用 `{...}` 標記，
    /// 都是合法且常見的，動它們會改掉每一筆這種記錄的排版輸出。
    static func braceSafe(_ value: String) -> String {
        var depth = 0
        for ch in value {
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth < 0 { break }   // 關得比開的多
            }
        }
        guard depth != 0 else { return value }

        // 單次掃描。三個接續的 replacingOccurrences 會把本函式自己產生的大括號
        // 再逃脫一次。
        var out = ""
        out.reserveCapacity(value.count + 32)
        for ch in value {
            switch ch {
            case "{":  out += "\\textbraceleft{}"
            case "}":  out += "\\textbraceright{}"
            case "\\": out += "\\textbackslash{}"
            default:   out.append(ch)
            }
        }
        return out
    }
}
