import Foundation

/// **只補不存在的鍵**的補值——一份政策，所有補值面都委派到這裡（#458）。
///
/// ## 為什麼只有一份
///
/// `enrich-from-zotero`（#340）把 add-only 紀律做進了 `ZoteroEnrichment.plan`，但它只吃
/// Zotero item。#423／#455 之後 store 裡有以 DOI 為鍵的摘要存檔與其他非 Zotero 來源
/// （Crossref／OpenAlex／人工查證），要補進 work 的 `fields` 沒有任何面收得下——唯一的路
/// 是手改 YAML，而那正是 `replace-endnote-and-zotero` 第 4 條要防的安靜失敗。兩份政策就是
/// 兩條會分岔的路徑（`entity-backlink-completeness` 執行細節 2），所以欄位政策**逐字**自
/// `ZoteroEnrichment.plan` 搬入、Zotero 版降為 adapter：
///
/// - **只加原本不存在的鍵**。既有值一個都不動——人工修改過的值不得被洗掉。
/// - **`issn` 一律拒**：ISSN 識別的是期刊不是文章（spec entity-identifier 明文的 misplacement）。
/// - **`doi`／`pmid`／`isbn` 走結構化欄位**，三態解析（`IdentifierTokenizer.parse`）：全解 → 不留
///   殘留；部分解 → 值進結構化欄位**且**原字串保留在 `fields` 供人裁；不解 → 拒、不猜。
/// - **`date` 空才補；`authors` 完全為空且旗標開才補 `.literal`**（`literal-first-then-key`：
///   進庫不猜 key）。非空一律不動——已歸戶的 `.key` 更不可能被碰到。
/// - **不動 `type`／`title`／`venues`／`attachments`**。它們各自有自己的裁決路徑。
///
/// ## 定位：citekey 或 DOI，恰一個
///
/// DOI 相等是 `identity-is-judged-not-matched` 明列的識別碼例外，所以「DOI → citekey」可以由
/// 程式做（`two-kinds-of-edits`：程式編輯）。但 store 實測 37 組同題同年不同 DOI 的攣生、且一筆
/// work 可有多個 DOI（#394）——反向命中 ≥2 筆時**拒絕並具名全部命中的 citekey**（`ambiguous`），
/// 零寫入；哪一筆才對是 divergence 管線的事（#459），本型別不判定。比對走 `Entry.canonicalDOIs`
/// （`Models.swift` 的既有立場：「讀取請走 `canonicalDOIs`，不要自己比較」）。
///
/// ## 雙摘要分鍵，本型別不猜鍵名
///
/// 一篇文章有兩個摘要時：第一個用 `abstract`，第二個由呼叫端具名——知道語言用 `abstract-<lang>`、
/// 不知道用 `abstract-2`；經 `FieldKey.normalized` 落地為 `abstract_es`／`abstract_2`。這是
/// `lossless-intake`（來源給兩個就收兩個）與 add-only（既有值一個都不動）唯一同時成立的形：
/// 接在同一個鍵裡結構不可還原；只收第一個是有損。不拼接、不自動編號、不猜語言。
///
/// ## 失敗語意分兩類（#386 的形）
///
/// - **輸入語法錯 → 整批拒絕零寫入**，錯誤指名第 N 筆：兩鍵同給、兩鍵皆無、`fields` 空且無
///   `date`／`authors`、`FieldKey.normalized` 回 nil 或正規化後撞鍵。
/// - **狀態不符 → 該筆略過並具名**，其餘照常：`ambiguous`／`notFound`／`rejected`。
///
/// 沉默的只有一種：`skipped`（全部鍵已存在）——它在報告裡有分類，不是靜默。
///
/// ## 誠實邊界
///
/// `Proposal.sourceDigest` **只進報告不進 store**：`Entry.references` 的值域只收識別碼
/// （#394 §5，`Entry.validateReferenceAttachment`）；要讓 work 的欄位攜帶來源是第 15 條邊的
/// 值域裁決（#450），本型別不擴。
public enum AddOnlyEnrichment {

    // MARK: - 輸入

    /// 一筆補值提案。`citekey` 與 `doi` **恰給一個**。
    public struct Proposal: Equatable, Codable {
        public var citekey: String?
        public var doi: String?
        /// 要補的 biblatex 欄位（原始鍵名；落地前經 `FieldKey.normalized`）。
        /// 識別碼鍵 `doi`／`pmid`／`isbn` 走結構化欄位；`issn` 一律拒。
        public var fields: [String: String]
        public var date: String?
        /// literal 作者名（只在 entry 的 `authors` 完全為空且 `includeAbsentAuthors` 時補）。
        public var authors: [String]
        /// 來源存檔的 digest（`sha256:…`）——**只回顯進報告，不寫進 store**。
        public var sourceDigest: String?

        public init(citekey: String? = nil, doi: String? = nil, fields: [String: String] = [:],
                    date: String? = nil, authors: [String] = [], sourceDigest: String? = nil) {
            self.citekey = citekey; self.doi = doi; self.fields = fields
            self.date = date; self.authors = authors; self.sourceDigest = sourceDigest
        }

        /// JSON 形：`{ "citekey" | "doi", "fields": {…}, "date", "authors": […], "sourceDigest" }`。
        /// `source_digest` 也收（MCP 面其餘參數是 snake_case）。**未知的頂層鍵拒絕**——
        /// 把 `abstract` 寫在頂層而不是 `fields` 裡是最容易犯的錯，靜默略過會讓那筆看起來
        /// 「補了」而其實什麼都沒補。
        private struct AnyKey: CodingKey {
            var stringValue: String; var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        private static let knownKeys: Set<String> = [
            "citekey", "doi", "fields", "date", "authors", "sourceDigest", "source_digest",
        ]

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            let unknown = c.allKeys.map(\.stringValue).filter { !Self.knownKeys.contains($0) }.sorted()
            guard unknown.isEmpty else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: c.codingPath,
                    debugDescription: "未知的鍵 \(unknown.map { "「\($0)」" }.joined(separator: "、"))"
                        + "——要補的欄位要放在 fields 裡；可用的頂層鍵：citekey、doi、fields、date、authors、sourceDigest"))
            }
            func key(_ s: String) -> AnyKey { AnyKey(stringValue: s)! }
            citekey = try c.decodeIfPresent(String.self, forKey: key("citekey"))
            doi = try c.decodeIfPresent(String.self, forKey: key("doi"))
            fields = try c.decodeIfPresent([String: String].self, forKey: key("fields")) ?? [:]
            date = try c.decodeIfPresent(String.self, forKey: key("date"))
            authors = try c.decodeIfPresent([String].self, forKey: key("authors")) ?? []
            sourceDigest = try c.decodeIfPresent(String.self, forKey: key("sourceDigest"))
                ?? c.decodeIfPresent(String.self, forKey: key("source_digest"))
        }

        private enum CodingKeys: String, CodingKey {
            case citekey, doi, fields, date, authors, sourceDigest
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(citekey, forKey: .citekey)
            try c.encodeIfPresent(doi, forKey: .doi)
            try c.encode(fields, forKey: .fields)
            try c.encodeIfPresent(date, forKey: .date)
            try c.encode(authors, forKey: .authors)
            try c.encodeIfPresent(sourceDigest, forKey: .sourceDigest)
        }
    }

    /// 輸入語法錯——**整批拒絕、零寫入**，指名第 N 筆（1 起算，給人讀）。
    public enum InputError: Error, LocalizedError, Equatable, CustomStringConvertible {
        case invalidProposal(index: Int, reason: String)
        /// 提案 JSON 本身解不開（形狀錯、頂層未知鍵、型別不符）。
        case malformedJSON(String)
        public var errorDescription: String? { description }
        /// 字串內插（`"\(error)"`）也要拿到人讀得懂的那句，不是 enum 的預設印法。
        ///
        /// **消毒在消費端**：`reason`／`why` 含呼叫端給的欄位名（未信任字串），而本型別住 Core、
        /// 不是輸出面——三個消費端（`AkashicService.enrich`、`EnrichCmd`、MCP handler）各自在
        /// throw 站點 `displaySafe(e.description)`。在這裡先消毒會讓那三處二次消毒
        /// （`displaySafe` 不冪等——它跳脫反斜線自身）。
        public var description: String {
            switch self {
            case .invalidProposal(let i, let reason):
                return "第 \(i) 筆：\(reason)——整批拒絕，零寫入"   // display-safe-exempt: i 是 Int；reason 由消費端（service／CLI／MCP）在 throw 站點消毒，見上方註解
            case .malformedJSON(let why):
                return "提案 JSON 解析失敗：\(why)——整批拒絕，零寫入"   // display-safe-exempt: why 由消費端在 throw 站點消毒，見上方註解
            }
        }
    }

    /// 兩面共用的 JSON 解析（CLI `--from` 讀檔、MCP `proposals` 陣列）——**一個解析器、一種錯誤訊息**，
    /// 兩面對「什麼是合法的提案」不會分岔。`DecodingError` 的預設 `localizedDescription` 是
    /// 「The data couldn't be read」，對呼叫端等於沒說；`Proposal.init(from:)` 把理由放在 `debugDescription`。
    public static func decodeProposals(from data: Data) throws -> [Proposal] {
        do {
            return try JSONDecoder().decode([Proposal].self, from: data)
        } catch let e as DecodingError {
            let why: String
            switch e {
            case .dataCorrupted(let ctx): why = ctx.debugDescription
            case .keyNotFound(let k, let ctx): why = "缺鍵「\(k.stringValue)」：\(ctx.debugDescription)"
            case .typeMismatch(_, let ctx): why = "型別不符：\(ctx.debugDescription)"
            case .valueNotFound(_, let ctx): why = "值缺席：\(ctx.debugDescription)"
            @unknown default: why = String(describing: e)
            }
            throw InputError.malformedJSON(why)
        }
    }

    // MARK: - 輸出

    /// 逐筆的封閉分類。**每一筆提案恰落一類。**
    public enum Category: String, Equatable, CaseIterable {
        /// 有東西可補（可能同時帶 `refused`／`partial`）。
        case added
        /// 找到了記錄，但提案的每個鍵都已存在（或只有旗標未開的 authors）。
        case skipped
        /// DOI 反向命中 ≥2 筆——`matches` 列全部 citekey，零寫入。
        case ambiguous
        /// citekey 不在 store／DOI 沒有記錄帶／DOI 不是合法形狀。
        case notFound
        /// 提案只含被拒絕的東西（`issn`、解析不出的識別碼），沒有任何可補值。
        case rejected
    }

    /// 一個會補進去的東西——給報告用（`valueSummary` 是原值，呈現面自己 `displaySafe`）。
    public struct Addition: Equatable {
        public enum Kind: String, Equatable, CaseIterable {
            /// `fields` 的一個鍵。
            case field
            /// `doi`／`pmid`／`isbn` 走結構化欄位。
            case identifier
            case date
            case authors
        }
        public let key: String
        public let valueSummary: String
        public let kind: Kind
        public init(key: String, valueSummary: String, kind: Kind) {
            self.key = key; self.valueSummary = valueSummary; self.kind = kind
        }
    }

    /// 一筆記錄的**寫入計畫**——`applied(_:to:)` 消費的東西。與 `ZoteroEnrichment.Addition`
    /// 的欄位一一對應（那個型別現在是這個的 adapter 形）。
    public struct Outcome: Equatable {
        /// 只含**原本不存在**的鍵（含部分解析識別碼的殘留原字串）。
        public var addedFields: [String: String]
        public var addedDate: String?
        /// 一律 `.literal`；空陣列＝沒有補。
        public var addedAuthors: [Author]
        public var addedDOIs: [DOI]
        public var addedPMIDs: [PMID]
        public var addedISBNs: [ISBN]
        /// 給了識別碼但**刻意不採用**的理由（逐條具名）。`lossless-intake` 執行細節 3：丟棄必須可見。
        public var refused: [String]
        /// **部分成功**：一部分 token 解得出並已採用，其餘形狀不認得（#394 verify R9）。
        /// 刻意不併進 `refused`——那個欄位的契約是「刻意不採用」，而部分成功既不是刻意也不是不採用。
        public var partial: [String]

        public init(addedFields: [String: String] = [:], addedDate: String? = nil,
                    addedAuthors: [Author] = [], addedDOIs: [DOI] = [], addedPMIDs: [PMID] = [],
                    addedISBNs: [ISBN] = [], refused: [String] = [], partial: [String] = []) {
            self.addedFields = addedFields; self.addedDate = addedDate; self.addedAuthors = addedAuthors
            self.addedDOIs = addedDOIs; self.addedPMIDs = addedPMIDs; self.addedISBNs = addedISBNs
            self.refused = refused; self.partial = partial
        }

        public var nothingToAdd: Bool {
            addedFields.isEmpty && addedDate == nil && addedAuthors.isEmpty
                && addedDOIs.isEmpty && addedPMIDs.isEmpty && addedISBNs.isEmpty
        }
    }

    public struct Item: Equatable {
        /// 提案在輸入陣列裡的位置（0 起算）。
        public let proposalIndex: Int
        /// 定位到的 citekey；`ambiguous`／`notFound` 時為 nil。
        public let citekey: String?
        public let category: Category
        public let outcome: Outcome
        public let additions: [Addition]
        /// 提案給了、而記錄已經有值的鍵（含 `doi`／`pmid`／`isbn`／`date`／`authors`）。
        public let alreadyPresent: [String]
        public let reason: String?
        /// `ambiguous` 時全部命中的 citekey（排序）；其餘為空。
        public let matches: [String]
        /// 逐筆回顯 `Proposal.sourceDigest`——**不進 store**。
        public let sourceDigest: String?
    }

    public struct Result: Equatable {
        public var items: [Item]
        public init(items: [Item] = []) { self.items = items }
    }

    // MARK: - plan

    /// 算出補值計畫。**純函式、不寫檔**——套用由呼叫端做，dry-run 與 apply 讀的是同一份計畫。
    ///
    /// 同一批裡多筆提案指向同一筆記錄時**依序**計算：後面的提案看得到前面那筆會補的鍵
    /// （否則兩筆都報「added」而 apply 只寫得進一筆的內容）。
    public static func plan(entries: [Entry], proposals: [Proposal],
                            includeAbsentAuthors: Bool = false) throws -> Result {
        // 1. 整批驗證，零寫入——任一筆語法錯就不產生任何 item。
        let validated = try proposals.enumerated().map { try validate($1, index: $0 + 1) }

        var working: [String: Entry] = [:]
        for e in entries { working[e.citekey] = e }

        var result = Result()
        for (i, p) in validated.enumerated() {
            let digest = p.raw.sourceDigest
            // 2. 定位
            let citekey: String
            if let ck = p.citekey {
                guard working[ck] != nil else {
                    result.items.append(Item(proposalIndex: i, citekey: nil, category: .notFound,
                                             outcome: Outcome(), additions: [], alreadyPresent: [],
                                             reason: "citekey「\(ck)」不在 store 裡",
                                             matches: [], sourceDigest: digest))
                    continue
                }
                citekey = ck
            } else {
                let rawDOI = p.doi ?? ""
                guard let target = DOI(rawDOI) else {
                    result.items.append(Item(proposalIndex: i, citekey: nil, category: .notFound,
                                             outcome: Outcome(), additions: [], alreadyPresent: [],
                                             reason: "「\(rawDOI)」不是合法的 DOI 形狀（\(DOI.shapeDescription)）",
                                             matches: [], sourceDigest: digest))
                    continue
                }
                let matches = working.values.filter { $0.canonicalDOIs.contains(target) }
                    .map(\.citekey).sorted()
                if matches.isEmpty {
                    result.items.append(Item(proposalIndex: i, citekey: nil, category: .notFound,
                                             outcome: Outcome(), additions: [], alreadyPresent: [],
                                             reason: "沒有記錄帶 DOI「\(target.normalized)」",
                                             matches: [], sourceDigest: digest))
                    continue
                }
                if matches.count >= 2 {
                    result.items.append(Item(proposalIndex: i, citekey: nil, category: .ambiguous,
                                             outcome: Outcome(), additions: [], alreadyPresent: [],
                                             reason: "DOI「\(target.normalized)」命中 \(matches.count) 筆——不判定哪一筆才對（#459），零寫入",
                                             matches: matches, sourceDigest: digest))
                    continue
                }
                citekey = matches[0]
            }
            // 3. 政策（逐字自 ZoteroEnrichment.plan）
            let entry = working[citekey]!
            let (outcome, alreadyPresent, note) = policy(entry: entry, proposal: p,
                                                         includeAbsentAuthors: includeAbsentAuthors)
            let category: Category
            if outcome.nothingToAdd {
                category = outcome.refused.isEmpty ? .skipped : .rejected
            } else {
                category = .added
                working[citekey] = applied(outcome, to: entry)
            }
            result.items.append(Item(proposalIndex: i, citekey: citekey, category: category,
                                     outcome: outcome, additions: additions(of: outcome),
                                     alreadyPresent: alreadyPresent, reason: note,
                                     matches: [], sourceDigest: digest))
        }
        return result
    }

    /// 把一筆計畫套進 entry，回傳**新的** entry（不 mutate 傳入者）。
    ///
    /// 只碰 `fields` 的缺鍵、空的結構化識別碼、空的 `date`、空的 `authors`。斷言式防呆：
    /// 若計畫含一個 entry 已經有值的鍵，這裡**跳過它**而不是覆寫——計畫與套用之間若有落差
    /// （例如 plan 之後 store 被改過），保守側是不動既有值。
    public static func applied(_ outcome: Outcome, to entry: Entry) -> Entry {
        var out = entry
        for (k, v) in outcome.addedFields where out.fields[k] == nil {
            out.fields[k] = v
        }
        // 結構化識別碼：同一條保守側紀律——**只在仍為空時**補，不覆寫。
        if out.doi.isEmpty, !outcome.addedDOIs.isEmpty { out.doi = outcome.addedDOIs }
        if out.pmid.isEmpty, !outcome.addedPMIDs.isEmpty { out.pmid = outcome.addedPMIDs }
        if out.isbn.isEmpty, !outcome.addedISBNs.isEmpty { out.isbn = outcome.addedISBNs }
        if (out.date ?? "").isEmpty, let d = outcome.addedDate { out.date = d }
        // 同一條保守側紀律：計畫之後 store 若已長出作者，一律不動。
        if out.authors.isEmpty, !outcome.addedAuthors.isEmpty {
            out.authors = outcome.addedAuthors
        }
        return out
    }

    // MARK: - Internals

    /// 驗證後的提案：鍵已正規化、兩鍵恰一。
    private struct Validated {
        let raw: Proposal
        let citekey: String?
        let doi: String?
        /// 正規化鍵 → 值（含空值——空值在政策層略過並具名）。
        let fields: [String: String]
    }

    private static func validate(_ p: Proposal, index: Int) throws -> Validated {
        func present(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        let ck = present(p.citekey), doi = present(p.doi)
        switch (ck, doi) {
        case (.some, .some):
            throw InputError.invalidProposal(index: index, reason: "citekey 與 doi 只能給一個")
        case (.none, .none):
            throw InputError.invalidProposal(index: index, reason: "citekey 與 doi 必須給一個")
        default: break
        }
        // **鍵在這一層正規化**（#206 verify C1 的同一條理由：`Entry.fields` 的鍵直接成為匯出的
        // biblatex 欄位名，一個壞鍵讓整份 library 的 .bib 解析不了）。排序 → 撞鍵時的勝者是決定性的。
        var fields: [String: String] = [:]
        for key in p.fields.keys.sorted() {
            guard let k = FieldKey.normalized(key) else {
                throw InputError.invalidProposal(
                    index: index, reason: "欄位名「\(key)」無法表達成合法的 biblatex 欄位鍵")
            }
            guard fields[k] == nil else {
                throw InputError.invalidProposal(
                    index: index, reason: "欄位名「\(key)」正規化後（\(k)）與另一個欄位相撞")
            }
            fields[k] = p.fields[key]
        }
        let hasDate = present(p.date) != nil
        let hasAuthors = p.authors.contains { present($0) != nil }
        guard !fields.isEmpty || hasDate || hasAuthors else {
            throw InputError.invalidProposal(
                index: index, reason: "沒有任何可補的東西（fields 空、無 date、無 authors）")
        }
        return Validated(raw: p, citekey: ck, doi: doi, fields: fields)
    }

    /// 欄位政策本體——**逐字**自 `ZoteroEnrichment.plan` 搬入（#340／#394 verify R7–R9）。
    private static func policy(entry: Entry, proposal p: Validated, includeAbsentAuthors: Bool)
        -> (Outcome, alreadyPresent: [String], note: String?) {
        var added: [String: String] = [:]
        var addedDOIs: [DOI] = [], addedPMIDs: [PMID] = [], addedISBNs: [ISBN] = []
        var refused: [String] = []
        var partial: [String] = []
        var alreadyPresent: [String] = []
        var notes: [String] = []

        for k in p.fields.keys.sorted() {
            let v = p.fields[k]!
            guard !v.isEmpty else { notes.append("\(k) 的值為空，略過"); continue }
            switch k {
            case "issn":
                // **work 一律不收 ISSN。** spec（entity-identifier）逐字：「WHEN a work record
                // carries an ISSN THEN the store SHALL treat that as a misplacement, because ISSN
                // identifies the serial and not the article」。補回去等於製造 spec 明文指為錯置的東西。
                refused.append("issn「\(v)」——ISSN 識別的是期刊不是文章，"
                               + "work 不收；要補請補到它的 venue")
            case "doi", "pmid", "isbn":
                // 三態（#394 verify R8／R9）：解析不出 → 拒；全解 → 進結構化欄位、不留殘留；
                // 部分解 → 值進結構化欄位**且**原字串保留在 `fields`（殘留是解不了的值唯一的棲身處）。
                // 判準問「這一輪有沒有解析出任何東西」，不問「欄位空不空」。
                let parsedCount: Int
                let unparseable: [String]
                let hasStructured: Bool
                switch k {
                case "doi":
                    let r = IdentifierTokenizer.parse(v, field: k, DOI.init)
                    parsedCount = r.values.count; unparseable = r.unparseable
                    hasStructured = !entry.canonicalDOIs.isEmpty
                    if parsedCount > 0, !hasStructured { addedDOIs = r.values }
                case "pmid":
                    let r = IdentifierTokenizer.parse(v, field: k, PMID.init)
                    parsedCount = r.values.count; unparseable = r.unparseable
                    hasStructured = !entry.canonicalPMIDs.isEmpty
                    if parsedCount > 0, !hasStructured { addedPMIDs = r.values }
                default:
                    let r = IdentifierTokenizer.parse(v, field: k, ISBN.init)
                    parsedCount = r.values.count; unparseable = r.unparseable
                    hasStructured = !entry.canonicalISBNs.isEmpty
                    if parsedCount > 0, !hasStructured { addedISBNs = r.values }
                }
                if parsedCount == 0 {
                    refused.append("\(k)「\(v)」——解析不出 \(k.uppercased()) 的形狀，不猜")
                } else {
                    if hasStructured { alreadyPresent.append(k) }
                    if !unparseable.isEmpty {
                        // **部分成功：真的保留原字串**（#394 verify R9）——add-only 的保守側
                        // 同樣適用，只在該鍵原本不存在時加。
                        let kept = entry.fields[k] == nil
                        if kept { added[k] = v }
                        partial.append("\(k)「\(v)」——只解析出 \(parsedCount) 個，"
                                       + "其餘 token 的形狀不認得；"
                                       + (kept ? "原字串已一併加進 fields 供人裁"
                                               : "fields 已有該鍵，原字串未動"))
                    }
                }
            default:
                if entry.fields[k] == nil { added[k] = v } else { alreadyPresent.append(k) }
            }
        }

        var addedDate: String?
        if let d = p.raw.date?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            if (entry.date ?? "").isEmpty { addedDate = d } else { alreadyPresent.append("date") }
        }
        // #340：只在 `authors` **完全為空**時補，且一律 `.literal`（`literal-first-then-key`）。
        var addedAuthors: [Author] = []
        let names = p.raw.authors
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !names.isEmpty {
            if !entry.authors.isEmpty {
                alreadyPresent.append("authors")
            } else if includeAbsentAuthors {
                addedAuthors = names.map { Author.literal($0) }
            } else {
                notes.append("authors 未補：entry 的 authors 為空，但未開 includeAbsentAuthors")
            }
        }

        let outcome = Outcome(addedFields: added, addedDate: addedDate, addedAuthors: addedAuthors,
                              addedDOIs: addedDOIs, addedPMIDs: addedPMIDs, addedISBNs: addedISBNs,
                              refused: refused, partial: partial)
        return (outcome, alreadyPresent, notes.isEmpty ? nil : notes.joined(separator: "；"))
    }

    private static func additions(of o: Outcome) -> [Addition] {
        var out: [Addition] = []
        for k in o.addedFields.keys.sorted() {
            out.append(Addition(key: k, valueSummary: o.addedFields[k]!, kind: .field))
        }
        if !o.addedDOIs.isEmpty {
            out.append(Addition(key: "doi", valueSummary: o.addedDOIs.map(\.normalized).joined(separator: ", "),
                                kind: .identifier))
        }
        if !o.addedPMIDs.isEmpty {
            out.append(Addition(key: "pmid", valueSummary: o.addedPMIDs.map(\.normalized).joined(separator: ", "),
                                kind: .identifier))
        }
        if !o.addedISBNs.isEmpty {
            out.append(Addition(key: "isbn", valueSummary: o.addedISBNs.map(\.normalized).joined(separator: ", "),
                                kind: .identifier))
        }
        if let d = o.addedDate { out.append(Addition(key: "date", valueSummary: d, kind: .date)) }
        if !o.addedAuthors.isEmpty {
            let names = o.addedAuthors.map { a -> String in
                if case .literal(let n) = a { return n }
                return "?"
            }
            out.append(Addition(key: "authors", valueSummary: names.joined(separator: "、"), kind: .authors))
        }
        return out
    }
}
