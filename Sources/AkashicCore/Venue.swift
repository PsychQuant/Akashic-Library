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
/// `id / key / type / names / authorized / note / references / unknownFields`——**一個
/// 都裝不下**。它是 **work**，其容器關係是 work→work；它的 *publisher* 才是 venue。
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
    /// 載體種類（封閉三值）。
    public var type: VenueType
    /// 名稱變體與各自的效期（改名、縮寫、WoS 大寫形）。時間軸而非單值——
    /// **改名之後舊文章仍指向同一個 identity**（裁決五b 的刊名沿革）。
    public var names: TimelineOf<String>
    /// 對外可稱呼的名稱（#81 慣例；子集檢查在執行期，比對整條時間軸）。
    public var authorized: [String]
    public var note: String?
    /// 欄位層級 provenance（#66）；venue 消歧的 resolution verdict 也落這裡
    /// （封閉列舉第 13 條邊的 venue 面）。空清單不序列化。
    public var references: [ProvenanceReference]
    /// 較新版本寫入、本 binary 不認得的欄位（§5 tolerant-preserve）。
    public var unknownFields: [UnknownField]

    public init(key: String, type: VenueType,
                names: TimelineOf<String> = Timeline(),
                authorized: [String] = [],
                note: String? = nil, id: UUID? = nil,
                references: [ProvenanceReference] = [],
                unknownFields: [UnknownField] = []) {
        self.key = key
        self.type = type
        self.names = names
        self.authorized = authorized
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
    /// booktitle 視為會議載體的 entry type（proceedings 族，封閉列舉）——
    /// incollection 的 booktitle 是書名，不在此列。
    public static // #325 階段二：三個字串猜測（"inproceedings"／"proceedings"／"conference"）
        // 收斂成**一個列舉值**。實測舊值域只出現過 `inproceedings`（4 筆），另兩個
        // 從未被任何 importer 寫入——它們是防禦性猜測，而封閉列舉讓猜測不再必要。
        let proceedingsTypes: Set<WorkType> = [.conferenceSession]

    public static func literals(for entry: Entry) -> [VenueRef] {
        var out: [String] = []
        if let j = entry.fields["journaltitle"], !j.isEmpty { out.append(j) }
        if proceedingsTypes.contains(entry.type),
           let b = entry.fields["booktitle"], !b.isEmpty, !out.contains(b) {
            out.append(b)
        }
        if let p = entry.fields["publisher"], !p.isEmpty, !out.contains(p) {
            out.append(p)
        }
        return out.map { .literal($0) }
    }
}
