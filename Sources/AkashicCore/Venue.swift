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

/// 發表載體的種類。**封閉列舉三值**（#304 裁決三：期刊＋會議＋出版社一次到位）；
/// 擴充第四類（series 等）＝修 spec 的顯式動作，decode 對未知值整檔拒讀、不猜。
public enum VenueType: String, CaseIterable, Equatable {
    case journal
    case conference
    case publisher
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
    public static let proceedingsTypes: Set<String> = ["inproceedings", "proceedings", "conference"]

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
