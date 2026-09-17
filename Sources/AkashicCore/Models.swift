import Foundation

/// 文獻條目——store 的基本單位（entries/<citekey>.yaml 的記憶體形）。
/// 陣列索引的訊息形（#554 R12）：`venues`／`authors` 的 id 文法是 0-based（`citekey:venueIndex`），訊息裡用「index N」
/// 而不是「第 N 條」——中文序數詞讀起來是 1-based（R11 verify logic 第 27 列）。**列出的索引數有上限**：這些訊息跑在
/// 對未信任 store 內容的讀取路徑上（`StoreHealth` → doctor／App），join 無上限是 #562 那一族（R11 verify security 第 20 列）。
public enum IndexList {
    public static let cap = 10
    public static func render(_ idx: [Int]) -> String {
        let shown = idx.prefix(cap).map(String.init).joined(separator: "、")
        return idx.count > cap ? "index \(shown)…（共 \(idx.count) 條）" : "index \(shown)"
    }
}

public struct Entry: Equatable {
    /// 「同一 work 兩條 key 邊指同一 venue」warning 的家族前綴（#554 R11 D28；R15 起有前綴——`StoreHealth.duplicateVenueEdges`
    /// 用它篩、doctor 與 App 各一個計數）。**單一定義**：訊息由它組出、StoreHealth 只引用。
    public static let duplicateVenueEdgePrefix = "同一 venue 多條 key 邊"
    /// 一筆記錄上同一族 per-record warning 的則數上限（R15；`Venue.validate()` 的配對唯一性第二半共用同一個數）。
    public static let perRecordWarningCap = 20
    /// 上限觸發時那句「另有 N 筆未列出」的**自己的**前綴（R16；R15 verify 第 29 列：R15 讓概括句帶家族前綴，`StoreHealth` 的兩個家族計數把它
    /// 算成一則——被截的記錄少報 4、多報 1。家族計數要回答「幾筆受影響（至多上限）」，不是「印了幾行」）。凡是 per-record 上限的概括句
    /// （配對唯一性兩半、名字內容 error、近重複組）都用它，不進任何家族。
    public static let perRecordCapSummaryPrefix = "則數已達上限"
    /// 不可變機器身分；citekey 改名不斷鏈。
    public var id: UUID
    /// 人類可讀、可改名的引用鍵。
    public var citekey: String
    /// biblatex entry type（article / book / incollection / …）。
    /// 作品類型（#325 階段二：自由 `String` → 封閉列舉）。
    ///
    /// **decode 對未知值嚴格**——但那要求 #325 階段一的遷移**已經跑完**。
    /// 兩階段部署的理由見 `WorkType` 的 doc。（階段一的 `migrate-work-types` 命令與
    /// `WorkTypeMigration` 型別都已於階段二退場，所以這裡不再指向它們——#412。）
    public var type: WorkType
    public var title: String
    public var authors: [Author]
    /// 發表載體的二態指涉（#304，有序——主要載體在前）。作品側是正典側
    /// （#300 六理由同構）；反向（venue → 文章編年）一律現算。匯入端只產生
    /// `.literal`（`literal-first-then-key` 規則）；`fields` 內的 journaltitle
    /// 等字串照舊保留——ref 是升格不是取代（lossless-intake）。
    public var venues: [VenueRef]
    public var date: String?
    /// 其餘 biblatex 欄位（journaltitle / volume / doi / …）。
    public var fields: [String: String]
    public var attachments: [AttachmentRef]
    /// Zotero namespace——pull 管理、pull 可覆寫。
    public var provenance: Provenance?
    /// Akashic 自有 namespace——pull 絕不觸碰。
    public var akashic: AkashicMeta
    /// **確認無日期**的 sentinel（#350 第 2 類）。
    ///
    /// `date` 有三種狀態，而先前只能表達兩種：
    ///
    /// | `date` | 意思 |
    /// |---|---|
    /// | `"2020-04-01"` | 有日期 |
    /// | `Entry.noDateSentinel`（`"n.d."`） | **查過了，這筆作品確實沒有日期** |
    /// | `nil` | **還沒查** |
    ///
    /// 中間那一格先前不存在，於是「確實沒有」被折進 `nil`——而那正是 `lossless-intake`
    /// 執行細節 4 禁止的折疊（「還沒查」與「確實沒有」折成同一個觀察，事後完全無法區分）。
    ///
    /// 實測（2026-08-19）：store 有 **20 筆**確認無日期的記錄，而它們的 citekey 自己就寫著
    /// ——`anonndbbs`／`anonndbentry`／…／`mediandentry`（Zotero 快速入門指南）。citekey
    /// 產生器把 `nd` 編進鍵裡，但**模型讀不到那個資訊**。
    ///
    /// ## 為什麼是 sentinel 而不是另一個布林欄位
    ///
    /// `dateIsAbsent: Bool` 會讓「`date: 2020` ＋ `dateIsAbsent: true`」這個矛盾寫得出來。
    /// sentinel 佔用同一個格子，所以矛盾在文法上不存在——同 `ThesisFacts.Availability`
    /// 用關聯值的理由。
    ///
    /// ## 為什麼字面值是 `n.d.`
    ///
    /// 那是 APA7 自己的詞（手冊對無日期作品印 `(n.d.)`），也是依賴自己認的形式
    /// （`APACitationParser` 對 `dateStr == "n.d."` 的處理就是「無日期」）。用領域自己的
    /// 術語當 sentinel，讀 YAML 的人不需要查表。
    public static let noDateSentinel = "n.d."

    /// 這筆作品**確認沒有日期**（而不是還沒查）。
    public var dateIsConfirmedAbsent: Bool { date == Entry.noDateSentinel }

    /// 學位論文專屬事實（#335）。`nil` ＝ 這不是學位論文，或還沒查。
    ///
    /// **刻意不在型別層綁定 `type == .thesis`**——那需要把 `Entry` 變成 per-type 的
    /// 和類型，改動遠大於本題。「非學位論文帶 thesis 事實」由 `validate` 報診斷。
    public var thesis: ThesisFacts?
    /// 這筆作品的 DOI（#394）。**清單**——實測 37 組同題同年而 DOI 不同
    /// （JSTOR vs 出版商、preprint vs 正式版），一律純量會丟掉一個。
    ///
    /// 與 `fields["doi"]` **並存**：本階段不移除殘留，移除由遷移負責。兩者同時在場
    /// 時的正典是這個——讀取請走 `canonicalDOIs`，不要自己比較。
    public var doi: [DOI]
    /// PubMed ID（#394）。同一篇生醫論文同時有 DOI 與 PMID 是常態。
    public var pmid: [PMID]
    /// ISBN（#394）。不同版次／地區可以是不同的號。
    public var isbn: [ISBN]
    /// 欄位層級的 provenance（#394 §5）。**本輪新增的一條邊**——在此之前 work 的識別碼
    /// 無法攜帶來源，而 spec 明寫「不能攜帶 reference 的識別碼不算記錄的一等公民」。
    /// 值域：三個識別碼欄位 ＋ `authors`（拆分記錄——已退役的原 literal，#450；見 `validateReferenceAttachment`）。
    /// 空清單不序列化——既有記錄零 diff。
    public var references: [ProvenanceReference]
    /// 頂層未知欄位（tolerant-preserve，#23）。
    public var unknownFields: [UnknownField]

    public init(id: UUID, citekey: String, type: WorkType, title: String,
                authors: [Author] = [], venues: [VenueRef] = [], date: String? = nil,
                fields: [String: String] = [:], attachments: [AttachmentRef] = [],
                provenance: Provenance? = nil, akashic: AkashicMeta = AkashicMeta(),
                thesis: ThesisFacts? = nil,
                doi: [DOI] = [], pmid: [PMID] = [], isbn: [ISBN] = [],
                references: [ProvenanceReference] = [],
                unknownFields: [UnknownField] = []) {
        self.references = references
        self.doi = doi
        self.pmid = pmid
        self.isbn = isbn
        self.id = id
        self.citekey = citekey
        self.type = type
        self.title = title
        self.authors = authors
        self.venues = venues
        self.date = date
        self.fields = fields
        self.attachments = attachments
        self.provenance = provenance
        self.akashic = akashic
        self.thesis = thesis
        self.unknownFields = unknownFields
    }
}

// MARK: - 識別碼的正典讀法（#394）

public extension Entry {
    /// **優先序的唯一實作**：結構化識別碼勝過 `fields` 裡的同名殘留。
    ///
    /// 遷移之後殘留不該存在，但若存在，結構化的那個才是正典
    /// （`no-compat-fallback`：不留兩條讀法）。
    ///
    /// **為什麼是 accessor 而不是內聯在 export**：#335 的 `thesis.degree` 把同一個規則
    /// 內聯在 `BibExport`，那時只有一個欄位。識別碼有三種，內聯會變成三份會各自分岔的
    /// 比較——而「同一份規格的兩個副本必然分岔」是本 repo 反覆付過代價的形狀。
    ///
    /// 解析不出來的殘留回空清單，**不猜**：`fields` 是自由字典，裡面可能是
    /// `1467-8624(Electronic),0009-3920(Print)` 這種一欄兩號。
    private func canonicalIdentifiers<T: Identifier>(
        structured: [T], residueKey: String
    ) -> [T] {
        if !structured.isEmpty { return structured }
        return fields[residueKey].flatMap(T.init).map { [$0] } ?? []
    }

    /// 以欄位名取結構化識別碼的**個數**（跨種類的統一問法）。
    /// 回 `nil` ＝ 那個名字不是識別碼欄位。
    func identifierList(_ field: String) -> [String]? {
        switch field {
        case "doi":  return doi.map(\.normalized)
        case "pmid": return pmid.map(\.normalized)
        case "isbn": return isbn.map(\.normalized)
        default:     return nil
        }
    }

    var canonicalDOIs: [DOI] { canonicalIdentifiers(structured: doi, residueKey: "doi") }
    var canonicalPMIDs: [PMID] { canonicalIdentifiers(structured: pmid, residueKey: "pmid") }
    var canonicalISBNs: [ISBN] { canonicalIdentifiers(structured: isbn, residueKey: "isbn") }
}

/// 作者**三態**（#323）：已歸戶為人／已歸戶為團體／未歸戶。
///
/// ## 三態不是「人／團體／字串」
///
/// `.literal` 仍表示**未歸戶**——不論那個字串最終指的是人或團體。若把三態讀成「進庫時
/// 就分人與團體」，那是 `.claude/rules/literal-first-then-key.md` 第 1 段禁止的
/// 「進庫時猜」：寧漏勿誤，漏（literal 待消歧）可逆，誤（錯誤歸戶）不可逆。
///
/// ## 為什麼需要第三態
///
/// WoS 匯出的**團體作者**（consortium／study group）以大括號標記，例如
/// `{Taiwan Cancer Moonshot Program}`。二態下它們只能永久停在 `.literal`——因為
/// `.key` 的語意（doc comment 與 `entity-backlink-completeness` 封閉列舉第 1 條）
/// 是 person。於是 #303 的 literal 歸零 campaign 對這一類**結構上不可能達成終局**。
///
/// 而硬把 organization key 塞進 `.key` 會**通過型別檢查、通過 validate、通過所有
/// 守衛**——裸字串沒有 kind 標記——只是庫裡多出「作者是 person」的假斷言，且沒有任何
/// 機制會抓到。第三態讓那件事**寫不出來**，而不是靠紀律不去寫。
///
/// ## 與 APA7／biblatex 的對應
///
/// APA7 §9.11 Group Authors 的 biblatex 慣例是 `author = {{Group Name}}`（雙大括號，
/// 讓 BibTeX 不把團體名當人名拆解「姓, 名」）。WoS 的大括號標記與它是**同一個慣例**
/// ——那些 literal 不是髒資料，是模型先前接不住的正規表述。
public enum Author: Equatable {
    /// 已歸戶為 `entities/` 裡的 person。
    case key(String)
    /// 已歸戶為 `entities/` 裡的 organization（#323）。
    case organization(String)
    /// 未歸戶的裸字串（可能是人、可能是團體——**尚未判定**）。
    case literal(String)

    public var displayName: String {
        switch self {
        case .key(let k): return k
        case .organization(let k): return k
        case .literal(let s): return s
        }
    }
}

/// 未知欄位（store-format §5 v1.3 tolerant-preserve，#23 α）：較新版本寫入、
/// 本版不認識的欄位。保留載體是**原始檔案的逐字文字區塊**（含 key 行與其縮排
/// 子行）——decode 不 serialize、encode 逐字 append。key 型別（quoted/typed）、
/// tag、anchor/alias、註解、block scalar 保真，且結構上不存在展開放大。
/// 保真的兩個既知例外（見 docs/store-format.md §5）：column-0 stream 標記
/// （`---`/`...` 及變體、`%` directive）於擷取時剝除；寫回時縮排可能整塊
/// 等量平移。舊 binary 的 read-modify-write 不得剝掉新欄位（資料毀損防線）。
public struct UnknownField: Equatable {
    /// key 的字串內容（顯示 / validate 用；型別資訊在 raw 內保真）。
    public var key: String
    /// 原文區塊：含 key 行到下一個同層 entry 前的全部行（保留原縮排，以 \n
    /// 結尾；column-0 stream 標記行已剝除——見型別註解的保真例外）。
    public var raw: String

    public init(key: String, raw: String) {
        self.key = key
        self.raw = raw
    }
}

public struct AttachmentRef: Equatable {
    /// 鍵域是**封閉集合，且只剩一種**（#223）。可 ingest 的內容一律以 digest 引用
    /// （見 `AkashicMeta.sources`），不以檔案系統路徑引用——路徑會因搬移或改名斷鏈，
    /// 且無法偵測內容變更。
    ///
    /// 僅存的路徑型引用是指向**外部文獻管理器自有儲存**的過渡形式：它存在的理由是
    /// 那個管理器持有本 store 尚未 ingest 的位元組。這是**一的封閉列舉**——不得因
    /// 「形狀相似」而據以新增第二種路徑型引用。
    public enum Kind: String, Equatable {
        /// 相對 Zotero 資料目錄的 reference（storage/<KEY>/<file>）。
        case zotero
    }

    public var kind: Kind
    public var path: String

    public init(kind: Kind, path: String) {
        self.kind = kind
        self.path = path
    }
}

public struct Provenance: Equatable {
    public var zoteroKey: String
    public var zoteroVersion: Int
    /// Zotero libraryID（personal=1；缺欄位＝pre-Phase-2 舊檔，合法）。
    public var libraryID: Int?
    /// mapping 產出的 biblatex 面向 SHA-256——update 條件之一
    /// （version 較新 OR hash 不同），同時涵蓋本機未同步修改與 mapping 演進。
    public var zoteroHash: String?
    public var importedAt: Date?
    /// Zotero 端已刪除的標記時間；不自動刪 entry，人工裁決。
    public var orphanedAt: Date?

    public init(zoteroKey: String, zoteroVersion: Int,
                libraryID: Int? = nil, zoteroHash: String? = nil,
                importedAt: Date? = nil, orphanedAt: Date? = nil) {
        self.zoteroKey = zoteroKey
        self.zoteroVersion = zoteroVersion
        self.libraryID = libraryID
        self.zoteroHash = zoteroHash
        self.importedAt = importedAt
        self.orphanedAt = orphanedAt
    }
}

public struct AkashicMeta: Equatable {
    public var tags: [String]
    /// 所屬 library keys（#13 membership views）——store 是全集，library 只是成員集合；
    /// 空陣列＝只屬全集 view。元素須符合 StoreKey 格式（write 時驗證）。
    public var libraries: [String]
    public var status: String?
    public var relations: Relations
    /// Exact work UUID、ordered raw author snapshot 與封閉 provenance chain 的
    /// optional canonical 完備性證言。缺席保留 open-world 語意。
    public var authorListCompleteness: AuthorListCompletenessWitness?
    /// 宣告「這些已儲存內容是本記錄所描述之作品的副本」的 digest 清單（#223）。
    ///
    /// 與**欄位層級**的 `references` 是不同的關係項：`references` 說「這個欄位的值
    /// 以那份內容為據」（值 ← 證據），本欄位說「那些位元組是這篇作品的副本」
    /// （作品 ← 副本）。兩者不得合併，副本引用也不得寫成指涉整筆記錄的
    /// 欄位層級 reference。
    ///
    /// 連結存在**記錄側**、反向現算：內容先被取得、記錄後被建立，所以內容抵達
    /// 當下沒有 citekey 可填，而建立記錄時 digest 已存在——只有這一側能在對方
    /// 尚未存在時誠實記下。不另存內容側的反向索引（兩份會分岔）。
    ///
    /// 空陣列與缺席等價。digest 文法沿用 `ProvenanceReference.isValidDigest`。
    public var sources: [String]
    /// akashic namespace 內的未知欄位（tolerant-preserve，#23）——
    /// 歷史上 schema 演化就發生在這層（#13 的 `libraries` 即是）。
    public var unknownFields: [UnknownField]

    public init(tags: [String] = [], libraries: [String] = [],
                status: String? = nil, relations: Relations = Relations(),
                authorListCompleteness: AuthorListCompletenessWitness? = nil,
                sources: [String] = [],
                unknownFields: [UnknownField] = []) {
        self.tags = tags
        self.libraries = libraries
        self.status = status
        self.relations = relations
        self.authorListCompleteness = authorListCompleteness
        self.sources = sources
        self.unknownFields = unknownFields
    }

    /// unknownFields 參與 isEmpty，供 API 消費者正確判空（α 之後 encoder 以
    /// known 子欄位有無決定 akashic 段的 emit，nested raw 另行 append——
    /// isEmpty 不再是 encode 的丟段防線，但語意上「有未知欄位 ≠ 空」仍須成立）。
    public var isEmpty: Bool {
        tags.isEmpty && libraries.isEmpty && status == nil && relations.isEmpty
            && authorListCompleteness == nil
            && sources.isEmpty
            && unknownFields.isEmpty
    }
}

/// Library registry（#13）：具名成員集合視角的 metadata。
/// 成員關係存在各 entry 的 `akashic.libraries`，不在此檔（per-entry membership）。
public struct Library: Equatable {
    public var key: String
    public var name: String
    public var description: String?
    /// 頂層未知欄位（tolerant-preserve，#23）。
    public var unknownFields: [UnknownField]

    public init(key: String, name: String, description: String? = nil,
                unknownFields: [UnknownField] = []) {
        self.key = key
        self.name = name
        self.description = description
        self.unknownFields = unknownFields
    }
}

/// 需要「存」的關係；同作者/同期刊由 metadata 推導、不存。
public struct Relations: Equatable {
    public var cites: [String]
    public var related: [String]

    public init(cites: [String] = [], related: [String] = []) {
        self.cites = cites
        self.related = related
    }

    public var isEmpty: Bool { cites.isEmpty && related.isEmpty }
}

/// 一個人的名字，分成兩個**分割**（#227）：`authorized`（對外稱呼的指定）與
/// `variant`（其餘變體）。RDA 的術語本身就是階層的——*authorized* access point 與
/// *variant* access point 都是 access point 的一種；這個型別讓 `names.authorized`
/// 逐字讀作 "authorized names"。
///
/// **`all` 是 computed，不儲存。** 依 `OrgRef` doc 記下的原則：「兩個欄位可以互相
/// 矛盾，一個 sum type 不會」——存三個欄位就是三個可互相矛盾的真相。舊結構的
/// `authorized ⊆ names` 不變式在這裡是**恆真**：指定一個名字就是把它放進 authorized
/// 分割，不存在「authorized 含 names 沒有的字串」的可表達狀態。
///
/// **順序是隱性契約**：`all` 是 authorized 在前、variant 在後的串接。`displayName`
/// 的 fallback（取第一個 authorized，缺席時退到 key）依賴這個順序——改動串接順序
/// 會靜默改變對外顯示的名字。`authorized` 內部的順序有語意（fallback 取 first）；
/// `variant` 的順序不帶語意（#81 原意）。
public struct PersonNames: Equatable, ExpressibleByArrayLiteral {
    /// 對外可稱呼的名字。空集合合法：「還沒指定該怎麼稱呼他」——那時 `displayName`
    /// 退到 `key`，讓缺口在輸出上看得見，而不是靜默印出索引系統產生的引用形。
    /// 每書寫系統至多一個——那是**內容**約束，結構管不到，仍由寫入邊界的
    /// `AuthorizedNames.validate` 執行。
    ///
    /// **`authorized` 是編目學的術語，不是權限**——RDA 的 *authorized access point*
    /// （規範檢索點，RDA 9.19 / MARC authority 1XX）。與它成對的是 *variant access
    /// point*（RDA 9.19.2 / MARC 4XX）。巢狀化（#227）之後兩個分割與 RDA 的兩個
    /// 術語**逐一對應**——舊結構的 `names` 是聯集、沒有 variant 的位置，文件只能拿
    /// `names` 頂替（#222 修過的那個誤植正是這個結構缺口的症狀）。
    ///
    /// 本 package 的各 target 沒有任何 authz 概念，所以在這裡讀到「有權限的」是誤讀。
    /// （這是**現在式**的觀察，不是永久保證——真的引進權限概念時，衝突的是那個新東西
    /// 該換名字，不是這個欄位。）
    ///
    /// ## 不要改名叫 `normalized`
    ///
    /// 理由**不是**「那個字歸誰」——`NameNormalization` 裡根本沒有叫 `normalized` 的
    /// 符號（只有 `matchingKey`），而該識別字實際被 `CanonicalFormat.normalized(_:)`
    /// 佔著。理由是**兩層的 normal form 主詞不同**：
    ///
    /// | 層 | normal form 是什麼 | 誰產生 |
    /// |---|---|---|
    /// | 正規化（`matchingKey`）| 從字串**算出來**的比對鍵，**永不外洩成資料** | 機械 |
    /// | 本欄位 | 由人**指定**的對外形，**就是資料** | 權威 |
    ///
    /// 共用名字會誘發 `authorized = all.map(normalize)`。**不要。**
    ///
    /// 理由是**語意的**，不是機械的：這個欄位記錄的是一個**決定**，而決定只在
    /// **還有得選**的時候發生。判準是「**可容許候選集是不是單元素**」——不是
    /// 「有沒有經過計算」。
    ///
    /// 所以 `AuthorizedNameMigration` 的兩格自動填入**都不違反本禁令**，它們都
    /// 落在「沒得選」那一側：
    ///
    /// - `adopted`：某書寫系統只有一個候選 → 直接採用。
    /// - `nominated`：多個候選但只有一個非引用形 → 採用它。引用形（`姓, 名`）是
    ///   索引系統的產物、不是他的名字，**本來就不在候選集裡**；排除後又只剩一個。
    ///
    /// 被禁的是第三格：**排除非候選之後仍有多個，卻機械挑一個**。那支工具在這一格
    /// 的做法是**留空並報告**，而那正是對的——機械挑一個會把一個決定偽造出來，讓
    /// 「還沒有人決定」與「已經決定了，而且就是這個」在資料上不再有分別。
    ///
    /// **禁令靠的是上面那段語意，不是靠 `validate`。** person 側現存的執行期守衛
    /// 只有兩條**內容**約束：每書寫系統至多一個、兩分割互斥（#227 verify R1 補）——
    /// 舊的子集牆（不變式 1）已由結構承擔而不復存在。它們攔得下多數機械嘗試，但
    /// 不是全部，且**不要因為這裡寫了禁令就以為每條寫入路徑都會擋**（#229 之後
    /// 寫入邊界有閘，直接改欄位仍不經過它）。
    ///
    /// > 規範條文在 `openspec/specs/authorized-name/spec.md`。上面引 `AuthorizedNameMigration`
    /// > 是拿它當**一致性測試**（「repo 裡有沒有合法路徑違反這句話」），不是當規範依據
    /// > ——後者是 #222 v3 被打掉的範疇錯誤。這段論證的完整推導與五個被推翻的版本留在
    /// > #222 的討論串，不複製進原始碼。
    public var authorized: [String]
    /// 其餘名字變體（RDA variant access point）。順序不帶語意（#81）。
    public var variant: [String]
    /// 聯集：authorized 在前、variant 在後。**不得改為儲存屬性**（見型別 doc）。
    public var all: [String] { authorized + variant }

    public init(authorized: [String] = [], variant: [String] = []) {
        self.authorized = authorized
        self.variant = variant
    }

    /// 字面量的意義是「全部是 variant，沒有指定」。這是**型別轉換**，不是讀舊資料的
    /// compat fallback——no-compat-fallback 的封閉列舉是「為了讀舊資料而保留的路徑」
    /// 三類，array literal 不讀舊資料、不在其內（design D3）。反面界線由 decoder 守：
    /// 平坦陣列在序列化層 fail-closed，舊格式只能經遷移進來。
    public init(arrayLiteral elements: String...) {
        self.init(variant: elements)
    }
}

/// 人物實體（people/<person-key>.yaml）。
public struct Person: Equatable {
    /// 不變的身分（#35／#241）：建立時發放的 v4，隨檔攜帶（`id:` 是必要欄位，
    /// decode 對缺席 fail-closed）。不由任何屬性推導——身分是名字的函數時，
    /// 名字撞、被改、或因 import 順序拿到不同後綴，身分就跟著漂。
    public var id: UUID
    public var key: String
    /// 這個人的名字（#227 巢狀化）：`authorized` 與 `variant` 兩個分割，聯集為
    /// `names.all`。「哪個名字對外」由 authorized 分割的**成員資格**指定，不由
    /// 位置決定（#81）；「authorized ⊆ 全部名字」由結構保證，不再需要執行期驗證。
    /// 術語（RDA access point）與「不要改名叫 normalized」的禁令見 `PersonNames`
    /// 與其 `authorized` 屬性的 doc。
    public var names: PersonNames
    public var orcid: ORCID?
    public var openalex: String?
    /// 逝世日期（#67）。ISO 8601 前綴：`2004`、`2004-11`、`2004-11-18`——與
    /// `Organization.dissolved` 同慣例，精度就是來源說了什麼，**不補齊**。
    ///
    /// **缺席 ＝ 右設限，不是「在世」。** 死亡是必然事件，所以缺席永遠不是「不適用」，
    /// 只是尚未觀察到——它同時涵蓋「真的還活著」與「已故但未記錄」，而從資料的角度
    /// 那兩者本來就是同一件事。判斷「誰還在世」時據此讀，不要把缺席當成活著的斷言。
    ///
    /// 在場則是已觀察到的事件，精度即區間寬度（`2004` ＝ 落在該年某處）。唯一表達不了
    /// 的是「已知過世但區間無界」——那屬 #63。
    ///
    /// 來源在 #66 的 provenance 機制落地前建議寫進 `note`（緊鄰本欄位即為此）。那是
    /// 對填資料的人的慣例，**不是**格式要求——`died` 在場而 `note` 缺席是合法記錄。
    ///
    /// **空值在 `didSet` 收斂成缺席**，涵蓋每一條**建構後的寫入**路徑（直接賦值、
    /// key-path、`inout` 寫回、decode 的賦值）。**初始化不在其中**——Swift 的
    /// property observer 不在 initialization context 觸發，所以 `init` 必須自己呼叫
    /// `normalisedDied`；日後若為本型別加上 `Decodable`，`init(from:)` 同理要自己呼叫。
    ///
    /// 先前只在 init 與 decode 正規化，並宣稱「事後改成空字串會被 encode 的 canary
    /// 攔下」——那不夠：關聯匯出不經過 canary，而 canary 的行為是**拋錯**、不是規約
    /// 要求的正規化。守衛在某一條路徑上，不等於不變量成立。
    public var died: String? {
        didSet { died = Person.normalisedDied(died) }   // 在 didSet 內賦值不會遞迴
    }

    /// 空或全空白 → 缺席。`.whitespacesAndNewlines` 而非 `.whitespaces`——後者不含
    /// 換行，會讓一個純換行的值變成一筆「死於換行」的記錄。
    static func normalisedDied(_ v: String?) -> String? {
        v.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    public var note: String?
    /// 機構與身分維度（#20，valid-time temporal）。各屬性自帶時間軸。
    public var profile: PersonProfile
    /// 欄位層級的 provenance（#66）。空清單不序列化——既有記錄零 diff。
    public var references: [ProvenanceReference]
    /// 頂層未知欄位（tolerant-preserve，#23）。
    public var unknownFields: [UnknownField]

    /// `id` 省略時**發一個新的 v4**（#241）——身分只有一個產生事件：建立。
    ///
    /// 不再是 `v5(key)`：那讓身分成為名字的函數，而名字會撞、會被改、會因 import
    /// 順序拿到不同後綴；兩個不同 library 裡同 key 的**不同的人**會在合併時安靜
    /// 熔成一筆（不可逆）。legacy 補值（決定性推導）已退場——磁碟上全部記錄都帶
    /// `id:`，舊檔只能經 migrate-person-identity 進來（`.claude/rules/
    /// no-compat-fallback.md`：退場後刪掉，不留著當保險）。
    public init(key: String, names: PersonNames = [],
                orcid: ORCID? = nil,
                openalex: String? = nil, died: String? = nil, note: String? = nil,
                id: UUID? = nil,
                profile: PersonProfile = PersonProfile(),
                references: [ProvenanceReference] = [],
                unknownFields: [UnknownField] = []) {
        self.profile = profile
        self.references = references
        self.id = id ?? UUID()
        self.key = key
        self.names = names
        self.orcid = orcid
        self.openalex = openalex
        // #67：空值正規化成缺席——空字串永遠不是合法的 ISO 8601 前綴，而它的兩種可能
        // 意圖（「不知道死了沒」／「死了但不知何時」）都收斂到缺席。decode 端另有同樣
        // 的正規化（它繞過本 init 直接賦值）。兩個入口都擋住之後，`died` 在模型裡就
        // 不會是空字串；事後直接改成空字串仍會被 encode 的語意 canary 攔下。
        // init 不觸發 `didSet`，所以這裡要自己走一次同一個正規化。
        self.died = Person.normalisedDied(died)
        self.note = note
        self.unknownFields = unknownFields
    }
}

/// 多行版 displaySafe（#114）：`displaySafe` 會跳脫 LF 且截 200 字——把它直接套在
/// CLI 頂層錯誤輸出會毀掉合法的多行 usage/help。這裡按行分割、逐行消毒（行內
/// 控制字元照舊跳脫）、保留換行重組；行數與行長設寬鬆上限（擋 2 MB 攻擊行、
/// 不砍正常 usage）。
public func displaySafeMultiline(_ s: String, maxLineLength: Int = 400,
                                 maxLines: Int = 200,
                                 maxTotal: Int = 96_000,
                                 escapingBackslash: Bool = true) -> String {
    // **只有真 LF（含 CRLF 正規化）是分隔符**（#135 verify F2）：`isNewline` 會把
    // VT/FF/CR/NEL/LS/PS 全當換行「轉成」真 LF——displaySafe 的 R12 fix #2 特地
    // 跳脫 LS/PS（不得殘留真換行），wrapper 用 isNewline 等於把那道防線拆回來：
    // 困在單一 YAML scalar 裡的內容（結構上不可能含 LF）會獲得多行輸出注入。
    // 改為 CRLF→LF 正規化後只 split "\n"——其餘換行變體交給 displaySafe 逐行跳脫。
    let normalized = s.replacingOccurrences(of: "\r\n", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
    var out: [String] = []
    var total = 0
    for (i, line) in lines.enumerated() {
        if i >= maxLines || total > maxTotal {
            out.append("……（截斷：共 \(lines.count) 行）")
            break
        }
        let safe = displaySafe(String(line), max: maxLineLength,
                               escapingBackslash: escapingBackslash)
        total += safe.count + 1
        out.append(safe)
    }
    // 總量上限（#135 verify F3）：跳脫是 8 倍膨脹器——200 行 × 400 scalar 的
    // 最壞形狀曾放大到 ~640 KB（比未消毒的 main 多 6.3 倍）。cap 在 96 KB：
    // 訊息夠長、且刻意 > 64 KB pipe buffer（讓 harness 的 deadlock 修復可測）。
    return out.joined(separator: "\n")
}

/// **已組裝訊息**的最後一道終端安全網（#297 item 1）。
///
/// 與 `displaySafeMultiline` 的差別只有一項：**不跳脫反斜線自身**。
///
/// ## 為什麼頂層需要一個不同的變體
///
/// 片段層的 `displaySafe` 跳脫反斜線，是為了讓「值裡 literally 寫著 `\u{001B}`」
/// 無法冒充真的被跳脫的 ESC——那個反偽造性質在**消毒一個不受信任的值**時是必要的。
///
/// 但把同一套規則再對**已組裝好的訊息**跑一次，會同時弄壞兩類東西
/// （#227 cluster verify S6，兩者相鄰但不同）：
///
/// 1. **帶合法反斜線的常量**——`StoreKey.pattern`（`\A[a-z0-9][a-z0-9-]*\z`）
///    顯示成 `\u{005C}A[a-z0-9]…`。它從未經過片段層消毒（各 throw 站點都正確標了
///    `display-safe-exempt: pattern 是常量`），弄壞它的是**毯式單次**消毒。
/// 2. **已消毒片段的二次消毒**——`displaySafe(key)` 的產物 `\u{001B}` 再跑一次變成
///    `\u{005C}u{001B}`，並二次截斷。`displaySafe` 刻意不冪等，所以這是必然而非意外。
///
/// ## 安全性沒有降低
///
/// 真正保護終端的是**控制字元／C1／LS/PS／bidi／方向標記／BOM 的跳脫**，那些全部
/// 保留。去掉的只有反偽造性質，而它在片段層已經提供——那也是它該待的地方：
///
/// - 片段忘了消毒且含**真 ESC 位元組** → 本函式照樣跳脫它。終端安全 ✅
/// - 片段忘了消毒且含**字面文字** `\u{001B}` → 顯示成 `\u{001B}`。看起來像被跳脫的
///   ESC 但其實是普通文字——**外觀歧義，非終端危害**。
///
/// ## 使用邊界（唯一合法呼叫點）
///
/// **只在最終輸出前呼叫一次**，且該訊息的各片段已在自己的 throw 站點消毒過
/// （`DisplaySinkCoverageTests` 機械保證這件事）。**不得**用它取代片段層的
/// `displaySafe`——那會讓未消毒的值繞過反偽造性質。
public func displaySafeAssembled(_ s: String, maxLineLength: Int = 400,
                                 maxLines: Int = 200,
                                 maxTotal: Int = 96_000) -> String {
    displaySafeMultiline(s, maxLineLength: maxLineLength, maxLines: maxLines,
                         maxTotal: maxTotal, escapingBackslash: false)
}

/// **本函式的 doc 曾經孤兒化**（#170 的**第七例**，由 #114 的 `f357e90` 引入，
/// 就在 #170 量測的前一天）：下面這整段——含 R12 三條更正——曾經無空 `///` 行地
/// 接在 `displaySafeMultiline` 頭上，而本宣告零註解。
///
/// 被孤兒化的每一句對接收者都是假的：R12 第 1 條的「`max: 200` 下原樣通過」講的是
/// 本函式的 `max:` 參數（多行版收的是 `maxLineLength`／`maxLines`／`maxTotal`）；
/// 第 3 條的「反斜線自身要跳脫」講的是本函式的 escaping 實作。而多行版自己的 doc
/// 還明寫「`displaySafe` 會跳脫 LF 且截 200 字」——它把本函式當**別的東西**引用，
/// 卻頂著本函式的 doc。
///
/// 那段是 load-bearing 的 security doc：`DisplaySinkCoverageTests` 的機械守衛契約、
/// `// display-safe-exempt:` 的豁免規則、以及「三輪都憑記憶檢查 sink 清單、三輪都漏」
/// 的教訓——全部掛錯地方。
///
/// 顯示層消毒。store 檔案依 #23 的前提可能由別的 binary、別人、Dropbox 同步
/// 寫入，未知欄位 key、quarantine reason、以及**驗證失敗訊息裡被插值的原始 key**
/// 都是未信任內容。
///
/// **涵蓋範圍**：CLI stdout、MCP JSON、App（`QuarantinedFile.displayFile` /
/// `displayReason`、`ResolutionCandidate.display*` 三個投影）。**資料面也在內**
/// ——`title` / `name` / `description` 一律消毒，理由是 entries 來自 `import-zotero`，
/// 而 Zotero 的資料來自出版商與網頁：那不是使用者自撰內容，是第三方內容。
///
/// **這個範圍由機械守衛維持，不靠記憶**（#28）：`DisplaySinkCoverageTests` 掃描
/// CLI / MCP 原始碼，任何把 store 衍生字串插值進輸出而未經本函式的位置都會讓測試
/// 失敗；要例外必須在同一行寫 `// display-safe-exempt: <理由>`。**新增輸出路徑時
/// 不要回頭憑記憶檢查 sink 清單**——#23 的 R11→R12→R13 三輪都那樣做、三輪都漏，
/// 第三輪漏的還是最常用的 `akashic query`。
///
/// - **控制字元**：libyaml 擋輸入串流的裸 C0，但**不擋 double-quoted scalar 的
///   跳脫序列**——`"\e[2J…"` 解碼後就是真的 ESC。實測可清螢幕、上色，並在
///   `akashic validate` 的報告裡偽造統計行，而該報告正是人類判斷 store 健不健康
///   的依據（v1.2 由 `rejectUnknownKeys` 先擋，v1.3 把它移到 happy path）。
/// - **長度**：Yams 錯誤字串會展開成出錯那一行的逐字內容且不截斷；MCP 情境下
///   那是直接灌進 LLM context 的無上限字串。
///
/// **R12 三處更正**（R11 版本的實測缺陷）：
/// 1. **預算以 unicode scalar 計，不以 Character 計**。原版 `for ch in s` 逐
///    grapheme cluster 檢查預算，而一個 cluster 可含無上限的 combining mark——
///    實測 `"a" + 50,000 個 U+0301` 在 `max: 200` 下**原樣通過**。
/// 2. **補 LS/PS 與方向標記**。原版漏 U+2028/U+2029，而它們在 SwiftUI `Text`
///    與 JSON→JS/LLM context 都是換行——「不得殘留真換行」的不變式在那兩個
///    sink 上被繞過。另補 U+200E/200F/U+061C（Trojan-Source 家族較弱的一半）
///    與 U+FEFF。
/// 3. **反斜線自身要跳脫**，否則內容裡的字面 `\u{001B}` 與本函式的輸出無法區分
///    （消毒後的字串會變得可偽造）。
/// **哪些 scalar 不得原樣送進輸出**——`displaySafe`（終端機面）與 `bootstrap-people
/// --json`（JSON 面）**共用這一份**判準。
///
/// 分開寫兩份的失敗形狀已經發生過（#547 verify V2／V3）：JSON 面的守衛用
/// `byte < 0x20` 判斷，在 UTF-8 裡只可能看到 ASCII C0，於是 U+007F、U+009B（CSI，
/// ＝ `ESC [` 的單位元組等價形）、U+202E 全部進不了 filter——**它宣稱的紅燈條件
/// 不可達**，而終端機面同一時間早就擋著這三類。兩份規格不會一起改
/// （`no-compat-fallback` §「同一件事只能有一份描述」）。
///
/// **反斜線不在這裡**，那不是遺漏：它是各輸出面**自己的**逃脫語法的一部分——
/// `displaySafe` 要把它轉成 `\u{005C}` 免得輸出被偽造，而 JSON 面的 `\\` 由
/// `JSONSerialization` 自己處理，再包一次會壞掉。共用的只有「這個字元本身危險」，
/// 不含「這個輸出格式怎麼逃脫」。
public enum UnsafeToEmitScalar {
    public static func contains(_ v: UInt32) -> Bool {
        v < 0x20 || v == 0x7F                    // C0 + DEL（含 ESC / CR / LF / TAB）
            || (0x80...0x9F).contains(v)         // C1
            || v == 0x2028 || v == 0x2029        // LS / PS——SwiftUI 與 JS 視為換行
            || (0x202A...0x202E).contains(v)     // bidi override
            || (0x2066...0x2069).contains(v)     // bidi isolate
            || v == 0x200E || v == 0x200F || v == 0x061C  // 方向標記
            || v == 0xFEFF                       // ZWNBSP / BOM
    }

    public static func contains(_ u: Unicode.Scalar) -> Bool { contains(u.value) }

    /// 把一份**已序列化**的 JSON 文字裡、**字串字面值內**的危險 scalar 改寫成 `\uXXXX`。
    ///
    /// **為什麼在序列化之後做**：JSON 出口需要 literal **逐字**可取回（`bootstrap-people
    /// --json` 的名字要餵回 `add-person`，消毒過就會建出名字不對的 person）。而
    /// `\uXXXX` 是 JSON 自己的逃脫語法——`JSONSerialization`／`jq -r` 解回來與原字串
    /// 逐字相同。所以「消毒 vs 逐字」是假兩難：改寫的是**輸出的位元組**，不是值。
    ///
    /// **為什麼要追蹤字串字面值**：`.prettyPrinted` 在 token 之間送**裸的**換行
    /// （U+000A），而它落在本集合裡。不分內外一律改寫，會在結構位置產出 `\u000A`
    /// ——那不是合法 JSON。這裡逐 scalar 記住自己在不在字串內、且尊重反斜線逃脫，
    /// 所以不依賴「序列化器對字串內的控制字元會怎麼做」這個假設（而那個假設正是
    /// #547 V2 量錯的東西）。
    public static func escapingUnsafeScalars(inSerializedJSON json: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(json.unicodeScalars.count)
        var inString = false
        var afterBackslash = false
        for u in json.unicodeScalars {
            guard inString else {
                if u == "\"" { inString = true }
                out.append(u)
                continue
            }
            if afterBackslash {                      // 逃脫序列的第二個字元，原樣放行
                afterBackslash = false
                out.append(u)
            } else if u == "\\" {
                afterBackslash = true
                out.append(u)
            } else if u == "\"" {
                inString = false
                out.append(u)
            } else if contains(u) {
                for c in jsonEscape(u.value).unicodeScalars { out.append(c) }
            } else {
                out.append(u)
            }
        }
        return String(out)
    }

    /// 本集合目前全部落在 BMP，所以 `%04X` 恆為四位。**仍然處理 surrogate pair**——
    /// 日後有人往集合裡加一個非 BMP 的 scalar 時，五位的 `\uXXXXX` 會產出不合法的
    /// JSON 而**沒有任何跡象**（`zero-instance-guards` 第 1 列的形狀：不寫的話，
    /// 那個形狀第一次出現時不會有跡象）。
    private static func jsonEscape(_ v: UInt32) -> String {
        guard v > 0xFFFF else { return String(format: "\\u%04X", v) }
        let x = v - 0x10000
        return String(format: "\\u%04X\\u%04X", 0xD800 + (x >> 10), 0xDC00 + (x & 0x3FF))
    }
}

/// `displaySafe` 之後再以**性質**逃脫不可見 scalar（#554 R12／R13）：`displaySafe` 的列舉不含 TAG 字元、ZWSP、變體選擇子、
/// CGJ、Hangul filler，而名字不變式（§5.7 第 2 條）與 `verdictsRetired`（迴送 verdict 的 value／statement）都需要這一組——
/// 訊息在結構上保證帶著它剛拒掉的那個字元（R12 verify security 第 14 列）。類別：`Default_Ignorable_Code_Point`、Cc／Cf／Zl／Zp、
/// 非 U+0020 的 Zs（NBSP／NNBSP／U+3000——名字側被 canonical 折掉，verdict literal 側沒有，第 27 列）、私用區 Co、U+2800
/// BRAILLE PATTERN BLANK（名字不變式的顯式成員，第 22 列）。碼位補零到四位（與 `displaySafe` 的 `%04X` 一致，第 26 列）。
/// 套在 `displaySafe` 之後：原始反斜線已被逃成 `\u{005C}`，這裡新加的 `\u{…}` 不會被再逃一次、store 裡字面寫著 `\u{200B}`
/// 的字串也偽造不了本函式的輸出。它是 #569 的局部圍堵，不是它的裁決（`UnsafeToEmitScalar` 本身不動）。
public func displaySafeInvisible(_ s: String, max: Int = 200) -> String {
    escapingInvisibleScalars(displaySafe(s, max: max))
}

public func escapingInvisibleScalars(_ s: String) -> String {
    var out = String.UnicodeScalarView()
    for u in s.unicodeScalars {
        let cat = u.properties.generalCategory
        let invisible = u.properties.isDefaultIgnorableCodePoint
            || cat == .control || cat == .format || cat == .lineSeparator || cat == .paragraphSeparator
            || (cat == .spaceSeparator && u.value != 0x20) || cat == .privateUse || u.value == 0x2800
        if invisible {
            out.append(contentsOf: String(format: "\\u{%04X}", u.value).unicodeScalars)
        } else {
            out.append(u)
        }
    }
    return String(out)
}

public func displaySafe(_ s: String, max: Int = 200,
                        escapingBackslash: Bool = true) -> String {
    var out = String.UnicodeScalarView()
    // `s` 是 caller-controlled；不能為了 reserve 先完整走過可能極大的 scalar view。
    // `max` 才是本函式真正會接觸的上界，負值也收斂為空 budget。
    let boundedMaximum = Swift.max(0, max)
    out.reserveCapacity(Swift.min(boundedMaximum, 2_048))
    var emitted = 0
    var truncated = false

    func put(_ str: String) {
        for u in str.unicodeScalars { out.append(u) }
    }

    for u in s.unicodeScalars {
        if emitted >= boundedMaximum { truncated = true; break }
        let v = u.value
        let escape =
            UnsafeToEmitScalar.contains(v)
            || (escapingBackslash && v == 0x5C)      // 反斜線自身——否則輸出可被偽造。
                                                     // false 的呼叫端只有兩種：`displaySafeAssembled`（理由見該處）
                                                     // 與 `displaySafeClipOnly`（只截已消毒的訊息，R17）——
                                                     // 其他地方不得直接傳 false（R16 verify security 第 18 列）
        if escape {
            put(String(format: "\\u{%04X}", v))
        } else {
            out.append(u)
        }
        emitted += 1
    }
    var body = String(out)
    // 截點不得落在 `\u{…}` 中間（R28 D80；R27 verify DA 第 19 列）：只截不逃的呼叫端收的是**已含逃脫序列**的字串，而 `max` 數的是
    // 輸出 scalar——pad 對齊時輸出以裸反斜線或半截的 `\u{20` 結尾，「輸出不可偽造」的不變式被截斷本身打掉（`refusalLineMax` 的註解
    // 早就記過同一個形狀，R22 verify 第 23 列）。逃脫自己的呼叫端不會發生（每個 `\u{…}` 是整段 put）。退回到最後一個沒閉合的 `\u{` 之前。
    // 只截不逃的輸入裡，反斜線只以 `\u{…}` 的開頭出現（呼叫端契約：已消毒），所以「最後一個反斜線之後沒有 `}`」就是沒閉合的逃脫序列
    // ——包含只剩 `\`、`\u`、`\u{20` 三種殘端（第一版只找 `\u{`，pad 7 時殘端是裸 `\`、照樣漏）。
    if truncated, !escapingBackslash, let bs = body.lastIndex(of: "\\"), !body[bs...].contains("}") {
        body = String(body[..<bs])
    }
    return truncated ? body + "…（已截斷）" : body
}

/// **只截不逃**——給「訊息在生產端已逐項消毒、sink 只需要上限」的地方用（doctor 的 `recordIssues.first`、App 的預覽；#554 R16／R17）。
/// 具名的理由（R16 verify security 第 18 列）：`displaySafe(x, escapingBackslash: false)` 在語法上與消毒分不開，而 `displaySafe` 逃脫反斜線
/// 自身的不變式正是靠「呼叫端不得傳 false」撐著；把「只截」做成另一個名字，守衛與讀者才分得出這一格沒有消毒任何東西。
/// **不得**拿它接未消毒的 store 字串——那會把真反斜線原樣送出，與 `displaySafeInvisible` 產生的 `\u{…}` 不可區分。
public func displaySafeClipOnly(_ s: String, max: Int) -> String {
    displaySafe(s, max: max, escapingBackslash: false)
}

public struct ValidationIssue: Equatable {
    public enum Severity: Equatable { case error, warning }

    public var severity: Severity
    public var message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// 檔名安全的 key 格式（citekey 與 person key 共用）。
/// write-time 強制——不合格式的 key 絕不進 appendingPathComponent（path traversal 防護）。
public enum StoreKey {
    /// \A/\z 錨點：ICU 的 `$` 會在尾端換行前匹配，`\z` 才是嚴格字串結尾
    public static let pattern = "\\A[a-z0-9][a-z0-9-]*\\z"

    public static func isValid(_ key: String) -> Bool {
        key.range(of: pattern, options: .regularExpression) != nil
    }
}

extension Entry {
    private static let citekeyPattern = StoreKey.pattern

    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if citekey.range(of: Self.citekeyPattern, options: .regularExpression) == nil {
            issues.append(ValidationIssue(
                severity: .error,
                message: "citekey '\(displaySafeInvisible(citekey, max: 120))' 不符合 ^[a-z0-9][a-z0-9-]*$"))
        }
        // #325 階段二：`type` 是封閉列舉，「空 type」在型別層就寫不出來——
        // 原本的 `trimmingCharacters(...).isEmpty` 檢查隨自由字串一起退場。
        // 這是把驗證從執行期移到編譯期的直接收益：不是多一層檢查，是**一整類錯誤
        // 變得寫不出來**（同 `Author` 三態讓「org 冒充 person」寫不出來）。
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(severity: .warning, message: "title 為空"))
        }
        if Set(akashic.libraries).count != akashic.libraries.count {
            issues.append(ValidationIssue(severity: .warning,
                                          message: "akashic.libraries 含重複 key（load 已去重）"))
        }
        // `booktitleCarrierTypes` 的成員資格判準（#324 的 §11：「它決定了哪些欄位存在」）
        // 先前**只存在於 doc comment**——集合是人工列舉、只看 `type`，而那條「不得依性質
        // 相似類推第三個」的禁令沒有任何可機械執行的對應物（#414）。
        //
        // 這裡把 #324 排除編著的那個**結構性**理由變成對成員的可執行約束：`Venue` 沒有
        // 編者欄位，所以一個帶 `editor` 的型別若進了那張表，它的編者在 venue 側無處可放。
        //
        // **前件只有 `editor`，刻意不含 `publisher`**：實測（2026-08-23）`VenueType` 本身
        // 就有 `.publisher`，而 `VenueDerivation.literals` 無條件把 publisher 變成另一個
        // venue literal——出版社不是持不住，是**它自己就是一個 venue**。把它寫進前件會誤傷
        // 82 筆有正當路徑的記錄（`zero-instance-guards` 第 2 列：前件的寬度要先量過再定）。
        //
        // **必要條件不是充分條件**：不帶 editor 的新型別未必就該進表。
        if VenueDerivation.booktitleCarrierTypes.contains(type),
           let ed = fields["editor"], !ed.trimmingCharacters(in: .whitespaces).isEmpty {
            // **訊息分兩支，因為後果不同**（自審抓到，#414 R1）：一律說「venue 持不住
            // 編者」會對**沒有 `booktitle`** 的記錄斷言一個沒發生的推導。實測兩個成員
            // 剛好落在光譜兩端——37 筆 `conference-session` 零筆帶 booktitle，17 筆
            // `reference-work-entry` 全部帶。前件本身**不**收窄（§11 判準問的是型別，
            // 不是個別記錄），收窄的只有那句因果宣稱。
            let head = "type `\(type.rawValue)` 在 booktitle 載體列舉內卻帶 editor"
                     + "「\(displaySafeInvisible(ed, max: 80))」——"
            let tail = "請確認這筆的型別是否正確，或該型別是否真該在 booktitleCarrierTypes 內"
            issues.append(ValidationIssue(severity: .warning,
                message: head + (fields["booktitle"] != nil
                    ? "這筆的 booktitle 會被推導成 venue，而 venue 持不住編者"
                      + "（`Venue` 無此欄位）——#324 排除編著章節的理由正是這一條。"
                    : "這筆沒有 booktitle，所以那個推導這次沒有發生；"
                      + "但**型別**宣告了「我的 booktitle 是載體」，而載體型別不該帶編者"
                      + "（`Venue` 無此欄位，#324）。")
                    + tail))
        }
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafeInvisible(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        for f in akashic.unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "akashic 未知欄位「\(displaySafeInvisible(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        // **兩條 key 邊指同一 venue 要出聲**（#554 R11，D28；`zero-instance-guards` 第 26 列）：verdict 以 (work, literal) 為鍵、
        // 不帶 venue index，這種 work 在 repoint／demote 上都會被拒（D25），而工具面自 R11 起造不出它（apply／repoint 的閘）——
        // 只有手改或舊 binary 寫的，而 R10 verify 之前 `validate`／`doctor`／App 對它一律綠燈。warning：記錄合法，失效的是判定
        // 逆轉的前提；修法只有手改 YAML（移除面：#572）。literal 邊不算——那是尚未判定的誠實狀態。
        // 則數有上限（R15；R14 verify logic 第 16 列、security 第 18 列：本檢查在讀取路徑上對未信任的 store 內容跑，
        // 同一輪為近重複檢查加了上限、這裡卻逐筆無上限）；概括句用 `perRecordCapSummaryPrefix`、**不帶**家族前綴（R16；R15 verify
        // 第 29 列：帶了家族前綴，`StoreHealth.duplicateVenueEdges` 把它算成一則——家族計數因此是「至多上限」，不是「印了幾行」）。
        var keyed: [String: [Int]] = [:]
        for (i, ref) in venues.enumerated() { if case .key(let k) = ref { keyed[k, default: []].append(i) } }
        var listed = 0, unlisted = 0
        for (k, idx) in keyed.sorted(by: { $0.key < $1.key }) where idx.count > 1 {
            guard listed < Self.perRecordWarningCap else { unlisted += 1; continue }
            listed += 1
            issues.append(ValidationIssue(severity: .warning,
                // `venues[].key` 沒有 StoreKey 約束（decode 只做 scalarString），所以以性質逃脫（R16 verify security 第 17 列）
                message: "\(Self.duplicateVenueEdgePrefix)：venues 有 \(idx.count) 條邊指向同一 venue「\(displaySafeInvisible(k, max: 120))」（\(IndexList.render(idx))）"   // display-safe-exempt: 前綴是常量；Int 序列（IndexList 有上限）
                       + "——配對只能由一條邊實例化（verdict 不帶 index），resolve-venues 的 repoint／demote 對它會拒絕；"
                       + "請在 YAML 裡刪掉多餘的邊（移除面：#572）"))
        }
        if unlisted > 0 {
            issues.append(ValidationIssue(severity: .warning,
                // 正文刻意不引家族前綴的字面（guards 第 26 列的 grep 才真的不含概括句）
                message: "\(Self.perRecordCapSummaryPrefix)：另有 \(unlisted) 個 venue 未列出（同樣被多條 key 邊指向；每筆記錄最多列 \(Self.perRecordWarningCap) 個"   // display-safe-exempt: 前綴是常量；Int
                       + "——本檢查在讀取路徑上對未信任的 store 內容跑）"))
        }
        issues += Self.pagesShapeIssues(fields["pages"])
        // #394 task 4.3：非正規形的識別碼要出聲（值保留、但不靜默）。
        issues += IdentifierDiagnostics.nonNormal(doi, field: "doi")
        issues += IdentifierDiagnostics.nonNormal(pmid, field: "pmid")
        issues += IdentifierDiagnostics.nonNormal(isbn, field: "isbn")
        return issues
    }

    /// `pages` 欄位的形狀檢查（`kiki830621/storyline#7`）。
    ///
    /// **不是零實例守衛**——三個形狀各有實測，所以不進 `zero-instance-guards` 的裁決表：
    ///
    /// | citekey | 值 | 真值 | 形狀 |
    /// |---|---|---|---|
    /// | `clarkson2010impact` | `1948550610386628` | `231-238` | DOI 後綴誤入 |
    /// | `sun2011educational` | `0734282910394976` | `534-546` | DOI 後綴誤入 |
    /// | `lynn1986determination` | `382???386` | `382-386` | mojibake |
    ///
    /// **為什麼需要它**：三筆裡只有第一筆會在下游炸開（R 的 `yaml` 讀 16 位純數字時大整數
    /// 溢位落成 `NA`）。第二筆開頭的 `0` 讓 YAML 當字串讀，於是**一路安靜**到印出一個 16 位
    /// 數字當頁碼；第三筆同樣安靜。既有的偵測完全依賴下游剛好會壞，而安靜的那兩種才是多數。
    ///
    /// **判準不是「pages 是不是數字」**：article-number 期刊（PLoS ONE 的 `e12345`、
    /// Nature Communications 的 `1234`）的 `pages` 本來就是單一數字，那是合法的。位數門檻
    /// 取 10 是因為頁碼與 article number 都不到那個量級，而 DOI 後綴常是 16 位。
    ///
    /// 一律 `.warning`：SAGE 一族的線上優先文章確實會拿 DOI 後綴當 article ID，所以這裡報的
    /// 是「請編目看一眼」而非「這筆錯了」——與跨記錄那幾條同一個立場。
    static func pagesShapeIssues(_ pages: String?) -> [ValidationIssue] {
        guard let raw = pages?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return [] }
        let shown = displaySafeInvisible(raw, max: 120)

        if raw.range(of: "^[0-9]{10,}$", options: .regularExpression) != nil {
            return [ValidationIssue(severity: .warning,
                message: "pages「\(shown)」是 \(raw.count) 位純數字——頁碼與 article number 都不到這個量級，"
                       + "常見成因是 DOI 後綴被當成頁碼收進來；拿它反查 DOI 即可判定"
                       + "（查得到就是它，順便補回真的 volume／issue／pages）")]
        }
        if raw.hasPrefix("10.") || raw.contains("/") {
            return [ValidationIssue(severity: .warning,
                message: "pages「\(shown)」含 DOI 的形狀（`10.` 前綴或斜線）——整個 DOI 可能誤入了 pages 欄位")]
        }
        if raw.contains("?") || raw.contains("\u{FFFD}") {
            return [ValidationIssue(severity: .warning,
                message: "pages「\(shown)」含替換字元——常見成因是連字號（en-dash `U+2013`，UTF-8 為 "
                       + "`E2 80 93`）在某次轉碼中每個位元組各被換成一個 `?`；還原成 `-` 是解碼不是判斷，"
                       + "但末頁仍要另找獨立來源核對（上游索引本身也可能存著損毀值）")]
        }
        return []
    }
}

extension Library {
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !StoreKey.isValid(key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "library key '\(displaySafeInvisible(key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafeInvisible(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}

extension Person {
    /// 對外可稱呼的名字（#81）。
    ///
    /// 解析順序刻意**不含** `names` 的任一元素：
    ///
    /// 1. `authorized` 中書寫系統相符者
    /// 2. 任一 `authorized`（不變式保證同書寫系統至多一個，所以「任一」不含歧義）
    /// 3. `key`
    ///
    /// 第 3 步退到 `key`（`guan-yongtao`）而不是任一 name，是本 change 的核心判斷：
    /// 沒有指定就是「不知道該怎麼稱呼他」，用醜的 key 讓缺口在輸出上**看得見**，比靜默
    /// 印出索引系統的引用形誠實。
    ///
    /// **實測（2026-08-13，person 記錄 868 筆）**：734 筆（84.6%）會走到第 3 步。
    ///
    /// 時間戳是必要的，不是裝飾——person 記錄數會隨消歧合併而**減少**，所以
    /// 本檔的 868、`.claude/rules/no-compat-fallback.md` 的 869（2026-08-12）與
    /// 當下的 867（2026-08-19）**都是對的**，只是量在不同時點。#297 item 3 原本
    /// 把這組數字報成「三處不一致」，而真正缺的是這句話：**帶時間戳的引用不需要
    /// 對帳，沒帶的才需要**。要重新量就跑 `akashic validate`。
    public func displayName(in script: WritingSystem? = nil) -> String {
        if let script, let hit = names.authorized.first(where: { WritingSystem.of($0) == script }) {
            return hit
        }
        return names.authorized.first ?? key
    }

    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !StoreKey.isValid(key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "person key '\(displaySafeInvisible(key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
        issues += IdentifierDiagnostics.nonNormal(orcid, field: "person.orcid")
        // #81／#227：對外名字的內容不變式（每書寫系統至多一個）。與 organization 共用
        // 同一份檢查——「哪個名字對外」是同一個問題，不該有兩套答案。子集那條已由
        // `PersonNames` 的結構承擔，**刻意不呼叫** `validate(authorized:names:)`——
        // 留一條恆真檢查會讓下一個讀的人以為它還在防什麼（design D2）。
        issues += AuthorizedNames.validateWritingSystems(authorized: names.authorized,
                                                         ownerKey: key)
        // #227 verify R1：分割互斥——同一字串在兩個分割 = 序列化出現兩次（spec
        // 「occupy exactly one partition」）。經 writePerson 的 assertNoErrors
        // 落在所有寫入路徑的交會處。
        issues += AuthorizedNames.validateDisjointPartitions(authorized: names.authorized,
                                                             variant: names.variant,
                                                             ownerKey: key)
        // #296：近重複——配對判準視為同一、判定判準視為不同的兩個名字是**未決的問題**。
        // warning 級：不擋寫入（它們可能真的不同），但不得靜默。
        issues += AuthorizedNames.validateNearDuplicates(names: names.all, ownerKey: key)
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafeInvisible(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}
