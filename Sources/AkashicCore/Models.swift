import Foundation

/// 文獻條目——store 的基本單位（entries/<citekey>.yaml 的記憶體形）。
public struct Entry: Equatable {
    /// 不可變機器身分；citekey 改名不斷鏈。
    public var id: UUID
    /// 人類可讀、可改名的引用鍵。
    public var citekey: String
    /// biblatex entry type（article / book / incollection / …）。
    public var type: String
    public var title: String
    public var authors: [Author]
    public var date: String?
    /// 其餘 biblatex 欄位（journaltitle / volume / doi / …）。
    public var fields: [String: String]
    public var attachments: [AttachmentRef]
    /// Zotero namespace——pull 管理、pull 可覆寫。
    public var provenance: Provenance?
    /// Akashic 自有 namespace——pull 絕不觸碰。
    public var akashic: AkashicMeta
    /// 頂層未知欄位（tolerant-preserve，#23）。
    public var unknownFields: [UnknownField]

    public init(id: UUID, citekey: String, type: String, title: String,
                authors: [Author] = [], date: String? = nil,
                fields: [String: String] = [:], attachments: [AttachmentRef] = [],
                provenance: Provenance? = nil, akashic: AkashicMeta = AkashicMeta(),
                unknownFields: [UnknownField] = []) {
        self.id = id
        self.citekey = citekey
        self.type = type
        self.title = title
        self.authors = authors
        self.date = date
        self.fields = fields
        self.attachments = attachments
        self.provenance = provenance
        self.akashic = akashic
        self.unknownFields = unknownFields
    }
}

/// 作者二態：已解析（引用 people/ 的 person key）或未解析裸字串。
public enum Author: Equatable {
    case key(String)
    case literal(String)

    public var displayName: String {
        switch self {
        case .key(let k): return k
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

/// 人物實體（people/<person-key>.yaml）。
public struct Person: Equatable {
    /// 不變的身分（#35）。legacy `people/<key>.yaml` 沒有這個欄位——decode 時由
    /// `DeterministicUUID.forPerson(key:)` 推出，**每次都相同**，所以 index 的
    /// primary key 與 entry 的作者引用不會漂。
    public var id: UUID
    public var key: String
    /// 這個人的名字變體。**順序不帶語意**（#81）——「哪個名字對外」由 `authorized`
    /// 指定，不由陣列位置決定。
    public var names: [String]
    /// 對外可稱呼的名字（#81）：`names` 的子集，每個書寫系統至多一個。
    ///
    /// **`authorized` 是編目學的術語，不是權限**——RDA 的 *authorized access point*
    /// （規範檢索點，RDA 9.19 / MARC authority 1XX）。與它成對的是 *variant access
    /// point*（RDA 9.19.2 / MARC 4XX）。
    ///
    /// **注意對應關係**：`names` **不是** variant 那一側——本 repo 是**包含**而非
    /// 互斥（`docs/store-format.md` §3.1 不變式 1：`authorized` ⊆ `names`）。
    /// `names` 兼收兩者，**扣掉 `authorized` 的那些**才是 variant access point。
    /// RDA 裡兩者互斥，這裡不是；把類比推到底會要求刪掉那條不變式。
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
    /// 共用名字會誘發 `authorized = names.map(normalize)`。**不要。**
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
    /// 「還沒有人決定」與「已經決定了，而且就是這個」在資料上不再有分別。前者是有
    /// 意義的狀態（見本段最後：空集合讓缺口在輸出上看得見）。
    ///
    /// **禁令靠的是上面那段語意，不是靠 `validate`。** 那兩條不變式攔得下多數機械
    /// 嘗試，但**不是全部**——`testNormalizedFormsCanEvadeBothInvariants` 釘住一個
    /// `validate` 回傳 `[]` 的輸入。而且它們沒有 schema／decoder 層的表現，`writePerson`
    /// 的多數呼叫端也不驗（**#229**）。**不要因為這裡寫了禁令就以為寫入路徑會擋。**
    ///
    /// > 規範條文在 `openspec/specs/authorized-name/spec.md`。上面引 `AuthorizedNameMigration`
    /// > 是拿它當**一致性測試**（「repo 裡有沒有合法路徑違反這句話」），不是當規範依據
    /// > ——後者是 #222 v3 被打掉的範疇錯誤。這段論證的完整推導與五個被推翻的版本留在
    /// > #222 的討論串，不複製進原始碼。
    ///
    /// 空集合是合法的，意思是「還沒指定該怎麼稱呼他」——那時 `displayName` 退到 `key`，
    /// 讓缺口在輸出上看得見，而不是靜默印出索引系統產生的引用形。
    public var authorized: [String]
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

    /// `id` 省略時由 `key` 推出（確定性）——呼叫端不必為既有流程補一個 UUID。
    public init(key: String, names: [String] = [], authorized: [String] = [],
                orcid: String? = nil,
                openalex: String? = nil, died: String? = nil, note: String? = nil,
                id: UUID? = nil,
                profile: PersonProfile = PersonProfile(),
                references: [ProvenanceReference] = [],
                unknownFields: [UnknownField] = []) {
        self.profile = profile
        self.references = references
        self.id = id ?? DeterministicUUID.forPerson(key: key)
        self.key = key
        self.names = names
        self.authorized = authorized
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
                                 maxTotal: Int = 96_000) -> String {
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
        let safe = displaySafe(String(line), max: maxLineLength)
        total += safe.count + 1
        out.append(safe)
    }
    // 總量上限（#135 verify F3）：跳脫是 8 倍膨脹器——200 行 × 400 scalar 的
    // 最壞形狀曾放大到 ~640 KB（比未消毒的 main 多 6.3 倍）。cap 在 96 KB：
    // 訊息夠長、且刻意 > 64 KB pipe buffer（讓 harness 的 deadlock 修復可測）。
    return out.joined(separator: "\n")
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
public func displaySafe(_ s: String, max: Int = 200) -> String {
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
            || v == 0x5C                             // 反斜線自身——否則輸出可被偽造
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
        if type.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(severity: .error, message: "type 不可為空"))
        }
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
    /// 印出索引系統的引用形誠實。實測 868 筆記錄中 734 筆（84.6%）目前會走到這一步。
    public func displayName(in script: WritingSystem? = nil) -> String {
        if let script, let hit = authorized.first(where: { WritingSystem.of($0) == script }) {
            return hit
        }
        return authorized.first ?? key
    }

    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !StoreKey.isValid(key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "person key '\(displaySafe(key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
        // #81：對外名字的兩條不變式（子集、每書寫系統至多一個）。與 organization 共用
        // 同一份檢查——「哪個名字對外」是同一個問題，不該有兩套答案。
        issues += AuthorizedNames.validate(authorized: authorized, names: names, ownerKey: key)
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}
