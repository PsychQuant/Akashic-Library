import Foundation

/// 文獻條目——store 的基本單位（entries/<citekey>.yaml 的記憶體形）。
public struct Entry: Equatable {
    /// 不可變機器身分；citekey 改名不斷鏈。
    public var id: UUID
    /// 人類可讀、可改名的引用鍵。
    public var citekey: String
    /// biblatex entry type（article / book / incollection / …）。
    /// 作品類型（#325 階段二：自由 `String` → 封閉列舉）。
    ///
    /// **decode 對未知值嚴格**——但那要求 `migrate-work-types`（階段一）**已經跑完**。
    /// 兩階段部署的理由見 `WorkType` 的 doc 與 `WorkTypeMigration`。
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
    /// 頂層未知欄位（tolerant-preserve，#23）。
    public var unknownFields: [UnknownField]

    public init(id: UUID, citekey: String, type: WorkType, title: String,
                authors: [Author] = [], venues: [VenueRef] = [], date: String? = nil,
                fields: [String: String] = [:], attachments: [AttachmentRef] = [],
                provenance: Provenance? = nil, akashic: AkashicMeta = AkashicMeta(),
                thesis: ThesisFacts? = nil,
                unknownFields: [UnknownField] = []) {
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
    public var orcid: String?
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
                orcid: String? = nil,
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
            v < 0x20 || v == 0x7F                    // C0 + DEL（含 ESC / CR / LF / TAB）
            || (0x80...0x9F).contains(v)             // C1
            || v == 0x2028 || v == 0x2029            // LS / PS——SwiftUI 與 JS 視為換行
            || (0x202A...0x202E).contains(v)         // bidi override
            || (0x2066...0x2069).contains(v)         // bidi isolate
            || v == 0x200E || v == 0x200F || v == 0x061C  // 方向標記
            || v == 0xFEFF                           // ZWNBSP / BOM
            || (escapingBackslash && v == 0x5C)      // 反斜線自身——否則輸出可被偽造。
                                                     // 唯一的 false 呼叫端是
                                                     // `displaySafeAssembled`，理由見該處
        if escape {
            put(String(format: "\\u{%04X}", v))
        } else {
            out.append(u)
        }
        emitted += 1
    }
    let body = String(out)
    return truncated ? body + "…（已截斷）" : body
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
                message: "citekey '\(displaySafe(citekey, max: 120))' 不符合 ^[a-z0-9][a-z0-9-]*$"))
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
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        for f in akashic.unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "akashic 未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}

extension Library {
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !StoreKey.isValid(key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "library key '\(displaySafe(key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
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
                message: "person key '\(displaySafe(key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
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
                message: "未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}
