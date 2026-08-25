import Foundation

/// 對某個發表載體的指涉，或一段尚未歸戶的字面文字。
///
/// 形狀與 `Author`／`OrgRef` 相同（`.key` / `.literal`）——同型問題的第三次實例。
/// **刻意不與 OrgRef 共用型別**：venue 與 organization 是不同的 predicate 定義域
/// （發表載體 vs 機構），共用型別就是把兩個定義域攤平（§7；同 OrgRef 不與人的
/// 隸屬共用的理由）。
///
/// 進庫紀律見 `.claude/rules/literal-first-then-key.md`：匯入端只產生 `.literal`，
/// 升格為 `.key` 是顯式消歧動作。
public enum VenueRef: Equatable, Comparable {
    /// 指向一筆 venue 記錄的 key。
    case key(String)
    /// 尚未歸戶的載體名稱原文（WoS 全大寫形等）。**這是合法狀態**，不是髒資料。
    case literal(String)

    public var displayName: String {
        switch self {
        case .key(let k): return k
        case .literal(let s): return s
        }
    }

    public static func < (a: VenueRef, b: VenueRef) -> Bool {
        switch (a, b) {
        case (.key(let x), .key(let y)):         return x < y
        case (.literal(let x), .literal(let y)): return x < y
        case (.key, .literal):                   return true
        case (.literal, .key):                   return false
        }
    }
}

/// 發表載體的種類。**封閉列舉六值**，值域**細分** APA7 §9.23–9.33 的 source 類型學
/// （#324）；decode 對未知值整檔拒讀、不猜。
///
/// ## 判準（為什麼是這六個）
///
/// APA7 的分類不是按「載體長什麼樣」，而是按**這個載體要向參考文獻貢獻哪一組欄位**
/// ——§9.24：「The source element has **one or two parts, depending on the reference
/// category**」。這與本檔 `Venue` 的 §11 判準（「它決定了哪些欄位存在」）同源，所以
/// 兩者可以疊起來用。
///
/// | APA7 § | 值 | 索取的欄位組 |
/// |---|---|---|
/// | 9.25–9.27 | `periodical` | title, volume, issue, pages／article number |
/// | 9.29 | `publisher` | publisher 名（**明文不含地點**）|
/// | 9.30 | `database` | database／archive 名 |
/// | 9.31 | `conference` | 會議名＋地點資訊 |
/// | 9.32 | `socialMedia` | site 名 |
/// | 9.33 | `website` | site 名 |
///
/// ## 為什麼 `journal` 更名為 `periodical`
///
/// APA7 的 periodical 涵蓋 journal／magazine／newspaper／newsletter／blog——它們
/// **索取同一組欄位**，是同一類。叫 `journal` 會讓下一個人以為報紙要另立一格，那正是
/// 判準缺席造成的爭議（#304 的原始三值以「一次到位」收錄，不是判準）。
///
/// ## 為什麼**沒有** APA7 的第七類（§9.28 edited book / reference work）
///
/// 一本編著**有編者、書名、版次、出版社**，而 `Venue` 的全部欄位是
/// `id / key / type / names / authorized / issn / note / references / unknownFields`——**一個
/// 都裝不下**。（這份列舉是欄位表的第二份副本，因此有守衛：
/// `IdentifierPlacementTests.testVenueDocFieldEnumerationMatchesTheActualFields`
/// 會在它與實際欄位分岔時變紅。守衛查的是**一致性**不是**論證仍成立**——加一個
/// 裝得下編者的欄位不會被它擋下，那一步永遠是人工裁決。）它是 **work**，其容器關係是 work→work；它的 *publisher* 才是 venue。
/// store 早就這樣存了：`incollection` 的 `venues:` 放出版社、書名放 `fields.booktitle`
/// （正是 §9.28 描述的兩部分 source）。硬把它塞進本列舉會製造一個結構上無法持有 APA7
/// 要求欄位的 venue——把「模型接不住」搬個位置而不是修掉。
///
/// ## 細分關係，不是相等
///
/// 依 `.claude/rules/apa7-is-the-work-floor.md`：專案的值域**可以更細、不能更粗**。
/// 本列舉目前與 APA7 的六類一一對應，但將來若要把 `periodical` 再拆（例如
/// `newspaper` 另立），只要它仍對映回 §9.25 即合法。
public enum VenueType: String, CaseIterable, Equatable {
    case periodical
    case conference
    case publisher
    case database
    case socialMedia
    case website

    /// 給錯誤訊息用的值域字串。**從 `allCases` 生成，不得寫死**——#324 改值域時
    /// 發現三處錯誤訊息各自寫死「journal / conference / publisher」，值域改了而訊息
    /// 還在報舊值，會直接誤導使用者去試一個不存在的值。
    public static var domainDescription: String {
        allCases.map(\.rawValue).joined(separator: " / ")
    }
}

/// 發表載體（`entities/<uuid>.yaml`，形狀標籤 `venue:`）。
///
/// ## 為什麼它是第五種形狀
///
/// 它通過 §11 的必要條件：它決定了哪些欄位存在。venue 沒有 citekey、沒有作者、
/// 沒有隸屬；它有載體種類、刊名沿革。載入器為它分岔到不同的 decoder。
///
/// ## 與 organization 的關係
///
/// 期刊不是機構（出版載體 vs 法人單位）——#304 診斷否決了「塞進 organization」。
/// 但兩者共享同一套**機制**：names 是 `TimelineOf<String>`（改名史免費獲得，
/// 裁決五b）、authorized 子集在執行期驗證（#227 的不對稱：巢狀化是 person 專屬）。
public struct Venue: Equatable {
    /// 不變的機器身分。**v4 隨機**（#241 doctrine：單一來源事件發放、永不由
    /// 名字重算——venue 從第一天就沒有 v5 遺產，不需要 legacy 補值入口）。
    public var id: UUID
    /// 人類可讀鍵（`StoreKey` 規則）。
    public var key: String
    /// 載體種類（封閉列舉；值域見 `VenueType`）。
    ///
    /// **出貨面的值域字串由 `VenueType.domainDescription` 現算**——`akashic-mcp` 的
    /// `add_venue`／`update_venue`（tool 說明與 per-parameter 描述）與 CLI 對應命令的
    /// abstract 與 `--type` 說明，共六處。實測 `Sources/` 內已無寫死的值域清單。
    /// 刻意**不**寫成「錯誤訊息一律用它生成」那種全稱保證：那句話沒有守衛支撐，
    /// 而它涵蓋的是本 diff 沒有逐一查過的每一個未來錯誤訊息（#407 R5 finding 28）。
    public var type: VenueType
    /// 名稱變體與各自的效期（改名、縮寫、WoS 大寫形）。時間軸而非單值——
    /// **改名之後舊文章仍指向同一個 identity**（裁決五b 的刊名沿革）。
    public var names: TimelineOf<String>
    /// 對外可稱呼的名稱（#81 慣例；子集檢查在執行期，比對整條時間軸）。
    public var authorized: [String]
    /// 這個期刊的 ISSN（#394）。**清單而非純量**——print 與 electronic 是兩個**真的**
    /// 號（實測 Behavior Research Methods 的 `1554-351X` 與 `1554-3528`），一律純量會
    /// 丟掉一個。基數不是風格選擇：它決定 `ProvenanceReference` 走哪條驗證分支
    /// （清單型比照 `names` 必須帶 `value`，純量型比照 `orcid` 拒收 `value`）。
    ///
    /// ISSN 識別的是**期刊**，不是文章——它先前住在 work 的 `fields` 裡（實測 64 筆），
    /// 只因為 venue 沒有地方放它。空清單不序列化（既有記錄零 diff）。
    public var issn: [ISSN]
    public var note: String?
    /// 欄位層級 provenance（#66）；venue 消歧的 resolution verdict 也落這裡
    /// （封閉列舉第 13 條邊的 venue 面）。空清單不序列化。
    public var references: [ProvenanceReference]
    /// 較新版本寫入、本 binary 不認得的欄位（§5 tolerant-preserve）。
    public var unknownFields: [UnknownField]

    public init(key: String, type: VenueType,
                names: TimelineOf<String> = Timeline(),
                authorized: [String] = [],
                issn: [ISSN] = [],
                note: String? = nil, id: UUID? = nil,
                references: [ProvenanceReference] = [],
                unknownFields: [UnknownField] = []) {
        self.key = key
        self.type = type
        self.names = names
        self.authorized = authorized
        self.issn = issn
        self.note = note
        // v4 直接產生——不經任何名字推導（對照 Organization 的 legacy 補值，
        // venue 無遺產故無該入口；`no-compat-fallback` 規則的順向案例）。
        self.id = id ?? UUID()
        self.references = references
        self.unknownFields = unknownFields
    }

    /// Schema 驗證（與 organization 對齊：key 格式＋authorized 子集＋未知欄位警告）。
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !StoreKey.isValid(key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "venue key '\(displaySafe(key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
        issues += AuthorizedNames.validate(authorized: authorized,
                                           names: names.entries.map(\.value), ownerKey: key)
        issues += IdentifierDiagnostics.nonNormal(issn, field: "venue.issn")
        // 認不出的 ISSN 角色**保留原值並報出來**（#394 verify）——不猜、也不靜默丟。
        // 形狀與上一行的非正規形診斷同構：讀取面寬容、`validate` 出聲。
        for i in issn where i.qualifierRaw != nil && i.medium == nil {
            issues.append(ValidationIssue(
                severity: .warning,
                message: "venue.issn「\(displaySafe(i.normalized, max: 40))」的 qualifier"
                       + "「\(displaySafe(i.qualifierRaw ?? "", max: 60))」不是 ISSN 標準的"
                       + "三個角色（print／electronic／linking）——原值已保留，"
                       + "但 medium 未判定；改成標準寫法即可（例：Online → electronic）"))
        }
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }

    /// 對外可稱呼的名稱：authorized 書寫系統相符者 → 任一 authorized →
    /// 當前有效名稱（`names.current`）→ key（同 Organization 四階）。
    public var displayName: String { displayName(in: nil) }

    public func displayName(in script: WritingSystem?) -> String {
        if let script, let hit = authorized.first(where: { WritingSystem.of($0) == script }) {
            return hit
        }
        return authorized.first ?? names.current?.value ?? key
    }
}

/// 從書目字串欄位推導 venue literal ref 的**唯一**對映（design D4）。
///
/// migration 回填與兩個 importer 共用本函式——兩份對映清單會分岔
/// （`lossless-intake` 的 consumedColumns 教訓同型），所以只有這一份。
/// 只產生 `.literal`（`literal-first-then-key`：進庫不猜 key）；順序帶語意
/// （主要載體在前）；type 推定不寫進 ref，歸戶時人裁。
public enum VenueDerivation {
    /// `booktitle` 是**載體**而非書名的 entry type（封閉列舉，現有 2 個）。
    ///
    /// 判準是 #324 的 §11 那一條：**它決定了哪些欄位存在**。
    ///
    /// | 型別 | `booktitle` 是什麼 | 收不收 | 理由 |
    /// |---|---|---|---|
    /// | `.conferenceSession` | 會議名／論文集名 | ✅ | 論文集論文的 booktitle 是載體（`VenueMigrationTests.testProceedingsBooktitleAndPublisher` 釘住：會議與出版社**各自**成為一個 venue）。**#417 R1 曾據「`INPROCEEDINGS` 含 `PUBLISHER`」把它移除，被那條測試抓到並還原**——出版社不是 venue 持不住的東西，它自己就是一個 venue |
    /// | `.referenceWorkEntry` | 參考工具書名 | ✅ | 持續出版的線上參考工具，沒有逐卷編者（#339，2026-08-23 裁決） |
    /// | `.bookChapter` | **書名** | ❌ | 編著索取 `BOOKTITLE + EDITOR + PUBLISHER`（APA7 §9.28），venue 結構上持不住——#324 明文關掉這條路 |
    ///
    /// **不得依性質相似類推第三個**：`.referenceWorkEntry` 之所以進來，不是因為它「看起來
    /// 像 proceedings」，是因為對它做了與 #324 同一個判準的獨立評估，而答案不同。
    /// #324 關掉的是**編著**那條路，不是「凡是 booktitle」。
    ///
    /// ## 這條禁令能執行到什麼程度（#414，2026-08-23 量測後改寫）
    ///
    /// 跨模型審查指出：上面那句禁令**沒有可機械執行的判準程序**——下一個線上百科／
    /// 辭典型別仍只能靠人判斷「像不像」。那是對的，而先前這段散文沒有承認它。
    ///
    /// 現在有一個**部分**的對應物：`Entry.validate()` 對「本表成員卻帶 `editor`」出聲。
    /// 它把 #324 排除編著的那個結構性理由（`Venue` 沒有編者欄位，持不住）變成對成員的
    /// 可執行約束。實測 54 筆成員記錄（37 conference-session ＋ 17 reference-work-entry）
    /// 零筆觸發，全 corpus 帶 `editor` 的只有 2 筆、全是 `.bookChapter`——正是被排除的
    /// 那一個。
    ///
    /// **兩個成員在「booktitle 是否在場」上落在光譜兩端**（#414 R1 自審量測）：
    /// 37 筆 `conference-session` **零筆**帶 booktitle（它們用 `eventtitle`／`venue`），
    /// 17 筆 `reference-work-entry` **全部**帶。所以守衛的訊息分兩支——一律說
    /// 「venue 持不住編者」會對前者斷言一個沒發生的推導。**前件不因此收窄**：
    /// §11 判準問的是型別，不是個別記錄。
    ///
    /// **它是必要條件不是充分條件**（同 `apa7-is-the-work-floor` 對 113 例的立場）：
    /// 一個新型別即使不帶 `editor` 也未必該進表，那一步仍是人工裁決。所以這段不再說
    /// 禁令「有程序」——它擋掉的是**已知會錯**的那一類，不保證通過的都對。
    ///
    /// **上表原本還有一個理由被量測否掉**：`.referenceWorkEntry` 那列曾寫「沒有逐卷編者
    /// 與**同義的出版社**」。後半是假的——`VenueType` 本身就有 `.publisher`，而下面的
    /// `literals(for:)` 第三個分支無條件把 publisher 變成另一個 venue literal。出版社不是
    /// 持不住，是它自己就是一個 venue（全 corpus 82 筆帶它）。該半句已刪。
    ///
    /// **#414 方向 1 已做，而它不需要新表**（2026-08-24 量測推翻了原本的判斷）。
    /// 原本的顧慮是「讓成員資格由欄位契約推導要新增第三張必要欄位表」，而
    /// `apa7-is-the-work-floor` 記過三張表會各自分岔。實測既有的
    /// `requiredFields(for:)` ＋ `recommendedFields(for:)` **就能區辨**——
    /// `INCOLLECTION` 的 recommended 含 `EDITOR,PUBLISHER`，本表兩個成員都不含。
    ///
    /// 判準因此有了程式層對應物：`BooktitleCarrierDerivationTests` 逐型別比對
    /// 「契約含 `BOOKTITLE` 且不含 `EDITOR`」與本表，**16/17 相符**。
    ///
    /// **判準只排除 `EDITOR`**。曾經多一個 `¬PUBLISHER`，而那與本檔下方
    /// `literals(for:)` 的第三個分支矛盾——它無條件把 publisher 變成另一個 venue
    /// literal。#417 R1 依那個錯誤子句改了表，被 `VenueMigrationTests` 抓到（見上表）。
    ///
    /// 守衛住在測試而非產品程式，因為 `VenueDerivation` 在 `AkashicCore` 而欄位契約在
    /// `AkashicExport`——讓 core 讀 export 會把依賴方向倒過來。集合維持人工維護，
    /// 但**判準可檢查**，這正是 #414 要的：不是集合被自動生成。
    ///
    /// **唯一的不合是具名例外，而它是「契約不完整」而非「表錯了」**：`.conferenceSession` 的契約
    /// （`PRESENTATION`）**完全沒有 `BOOKTITLE`**——它的容器是 `EVENTTITLE`。與資料層
    /// 互相印證：37 筆 conference-session 零筆帶 booktitle。也就是說它在本表的成員資格
    /// **目前對任何一筆記錄都不生效**；留著是為了「論文集中的論文」那種形狀，而
    /// APA7 §10.5 把它與「會議發表」併在同一節，`WorkType` 也只給了一個格子。
    /// **例外的退場條件是可執行的**：`INPROCEEDINGS` 的契約含 `BOOKTITLE` 而**不含**
    /// `EDITOR`，所以正向哪天改送它（#417 的方向 2），現行判準會自動接受，
    /// `namedException` 即可清空。那條斷言在測試裡。
    ///
    /// 「該不該拆 `.conferenceSession` 這個型別」仍是建模裁決（#417），本表不預判。
    ///
    /// **那個已知缺口已於 2026-08-23 由 #409 關閉。** 它原本寫著：3 筆 SEP 條目的型別是
    /// `.bookChapter`，與這些維基條目是同一種東西，但把 `.bookChapter` 加進本表會把 14 筆
    /// 真正的編著章節一起掃進來——所以要修的是**它們的型別**（當時的 `.wikipediaEntry`
    /// 這個名字對 SEP 過窄）。
    ///
    /// #409 就是去修那個型別的：`.wikipediaEntry` → `.referenceWorkEntry`。那 3 筆一併改
    /// 型別後即走進本表，歸戶到 `stanford-encyclopedia-of-philosophy`。
    ///
    /// **這段保留而不刪**：#324 為什麼排除 `.bookChapter`、以及「同一種東西卻因型別標籤
    /// 而分流」曾經是個真問題——那是本表判準的實例，刪掉會讓下一個人重新踩一次。
    public static // #325 階段二：三個字串猜測（"inproceedings"／"proceedings"／"conference"）
        // 收斂成**一個列舉值**。實測舊值域只出現過 `inproceedings`（4 筆），另兩個
        // 從未被任何 importer 寫入——它們是防禦性猜測，而封閉列舉讓猜測不再必要。
        let booktitleCarrierTypes: Set<WorkType> = [.conferenceSession, .referenceWorkEntry]

    public static func literals(for entry: Entry) -> [VenueRef] {
        var out: [String] = []
        if let j = entry.fields["journaltitle"], !j.isEmpty { out.append(j) }
        if booktitleCarrierTypes.contains(entry.type),
           let b = entry.fields["booktitle"], !b.isEmpty, !out.contains(b) {
            out.append(b)
        }
        if let p = entry.fields["publisher"], !p.isEmpty, !out.contains(p) {
            out.append(p)
        }
        return out.map { .literal($0) }
    }
}
