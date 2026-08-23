import Foundation
import AkashicCore

/// store 的**唯讀**健康事實，單一來源（#263）。
///
/// ## 為什麼需要它
///
/// `AkashicService.doctor()` 與 App 的健康總覽先前是**兩條獨立的實作路徑**——App
/// 完全不呼叫 `doctor()`（實測全樹唯一命中是一行註解），六個數字全由 `AppState`
/// 自行推導。
///
/// 差別很實：子集只會**少**，獨立路徑會**分岔**——App 可能顯示健康數字而 `doctor`
/// 對同一 store 報問題，而使用者**沒有任何線索**知道哪個對。
/// `entity-backlink-completeness` 執行細節 2 正禁止此事（「一個 entity kind 的讀取面
/// 只能有一條實作路徑」），只是該條當時只點名 CLI 與 MCP 兩面。
///
/// ## 為什麼不是「App 直接呼叫 doctor()」
///
/// **`doctor()` 不是唯讀的**——它會 `LibraryIndex(store:).rebuild()`。App 的健康總覽
/// 每次刷新（含 FileWatcher 觸發的外部 reload）都重建 index 是不可接受的副作用。
///
/// 所以本型別只持有**唯讀**的事實；`doctor()` 在它之上額外做 rebuild 與統計，App
/// 只讀它。兩者共用的部分因此只有一條路徑，而各自獨有的部分是各自的職責。
///
/// ## 新增一項檢查時
///
/// 加一個屬性到本型別，**兩個消費面就都拿得到**。
/// `StoreHealthSurfaceTests` 以反射釘住「每個屬性都被兩面消費」——漏掉一面會紅。
public struct StoreHealth {
    /// 跨記錄檢查（重複 citekey／person key 等）。
    public let crossRecordIssues: [ValidationIssue]
    /// 上面那些之中 severity == .error 的——它們會讓 index rebuild 撞 UNIQUE constraint。
    public let fatalCrossRecordIssues: [ValidationIssue]
    /// 佈局殘留（依 format／key 不該存在的檔案）。
    public let layoutResidue: [String]
    /// `sources/` 的 blob ↔ index 一致性。`nil` ＝ audit 本身失敗（見 `sourcesAuditError`）。
    public let sourcesAudit: LibraryStore.SourceIndexAudit?
    /// audit 自身失敗的描述。**audit 失敗不得吞掉整份報告**（#224 verify reg F1）。
    public let sourcesAuditError: String?
    /// 未決的同一性問題數。**0 也是資訊**，無條件持有（#76）。
    public let divergenceCount: Int
    /// 讀不進來的檔。
    public let quarantined: [QuarantinedFile]
    /// 含本 binary 不認得欄位的檔（tolerant-preserve 的可見性面，#23）。
    /// 與 `quarantined` 並列但**語意相反**：這些檔正常載入且完整保留。
    public let unknownFieldFiles: [String]
    /// 未歸戶的作者 literal 數（`literal-first-then-key` campaign 的進度量測）。
    public let unresolvedAuthorLiterals: Int
    /// 上游已消失（Zotero 端刪除）的 entry 的 citekey。
    public let orphanedCitekeys: [String]
    /// **每筆記錄自己的驗證問題**（`Entry.validate()` 一族），附它屬於誰（#416）。
    ///
    /// 先前這一族**只有 CLI 的 `validate` 看得到**——`Entry.validate()` 在全樹的
    /// 唯一呼叫點是 `Sources/akashic/Commands.swift`，`doctor()` 與 App 面各 0。
    /// 而 `mcp-cli-parity` 對 `validate` 是 CLI-only 的裁決，理由寫「讀取檢查由
    /// `akashic_doctor` 覆蓋（功能重疊）」；那句話被量測否掉：doctor 覆蓋的是
    /// **跨記錄**檢查，per-entry 一條都不做。落差裡有一條是 **error** 級
    /// （citekey 不符 pattern），而 MCP／App 的使用者拿不到它。
    ///
    /// 放這裡而不是各面自己算，是 #263 已建立的形狀：唯讀事實單一來源，
    /// 兩個消費面各自渲染。上面的反射守衛自動釘住新欄位。
    public let perRecordIssues: [OwnedIssue]

    /// 一則驗證問題 ＋ 它屬於哪筆記錄。
    ///
    /// **severity 與 owner 都要攜帶**：只給訊息的話消費端分不出 error 與 warning，
    /// 也指不出是哪一筆——CLI 面兩者都有，MCP 面就不能丟（#138 verify F3 的立場）。
    public struct OwnedIssue: Sendable {
        /// 這筆記錄的 key（entry 是 citekey、person 是 person key…）。
        public let owner: String
        /// 它屬於哪一族（`entry`／`person`／`library`）——渲染時要分辨得出來。
        public let kind: String
        public let issue: ValidationIssue
        public init(owner: String, kind: String, issue: ValidationIssue) {
            self.owner = owner
            self.kind = kind
            self.issue = issue
        }
    }

    /// 有沒有任何需要人看一眼的事。
    ///
    /// **`divergenceCount` 不計入**——未決的同一性問題是正常的工作狀態，不是腐爛。
    /// `unknownFieldFiles` 也不計入：那些檔完整保留，只是本 binary 讀不懂其中一部分，
    /// 提示升級而非提示修復。
    public var hasFindings: Bool {
        // **per-record 只有 error 計入**（#416）。warning 一族（title 為空、
        // 載體型別帶 editor…）是編目品質提示，不是腐爛——把它們計入會讓
        // `hasFindings` 對一份健康的 store 常態為真，於是這個布林失去訊號。
        // 這與 `unknownFieldFiles` 不計入是同一個判準。
        perRecordIssues.contains { $0.issue.severity == .error }
            || !crossRecordIssues.isEmpty
            || !layoutResidue.isEmpty
            || !quarantined.isEmpty
            || sourcesAuditError != nil
            || (sourcesAudit.map {
                !$0.orphanBlobs.isEmpty || !$0.danglingEntries.isEmpty
                    || !$0.malformedLines.isEmpty || !$0.unreadableShards.isEmpty
            } ?? false)
    }
}

public extension LibraryStore {
    /// 從一份已載入的快照算出唯讀健康事實（#263）。
    ///
    /// 收 `LibraryLoad` 而非自己 `load()`：呼叫端通常已經載過（`doctor()` 與
    /// `AppState.load()` 都是），再載一次會付兩倍 I/O 且兩份快照可能不一致。
    func health(from load: LibraryLoad) -> StoreHealth {
        let cross = load.crossRecordIssues()
        // `layoutResidue()` 與 `auditSourceIndex()` 各自可能擲錯，而**任一失敗都不得
        // 讓整份報告消失**——那正是 #224 verify reg F1 實測到的形狀（中途 throw 連
        // 已算好的 crossRecordIssues 都不見了）。
        let residue = (try? layoutResidue()) ?? []
        var audit: LibraryStore.SourceIndexAudit?
        var auditError: String?
        do {
            audit = try auditSourceIndex()
        } catch {
            auditError = displaySafe(String(describing: error), max: 300)
        }
        return StoreHealth(
            crossRecordIssues: cross,
            fatalCrossRecordIssues: cross.filter { $0.severity == .error },
            layoutResidue: residue,
            sourcesAudit: audit,
            sourcesAuditError: auditError,
            divergenceCount: load.divergences.count,
            quarantined: load.quarantined,
            unknownFieldFiles: load.unknownFieldFiles,
            unresolvedAuthorLiterals: load.entries.reduce(0) { n, entry in
                n + entry.authors.filter {
                    if case .literal = $0 { return true } else { return false }
                }.count
            },
            orphanedCitekeys: load.entries
                .filter { $0.provenance?.orphanedAt != nil }
                .map(\.citekey),
            // **五族逐一，順序與 CLI `validate` 相同**，好讓兩面的輸出逐行對照。
            // 族數是照 CLI 那五個迴圈數出來的（#416 第一版只寫了三族——漏掉
            // organizations 與 divergences，於是 MCP 面會少兩族而「看起來完整」）。
            perRecordIssues:
                load.entries.flatMap { e in
                    e.validate().map { StoreHealth.OwnedIssue(owner: e.citekey, kind: "entry", issue: $0) }
                }
                + load.people.flatMap { p in
                    p.validate().map { StoreHealth.OwnedIssue(owner: p.key, kind: "person", issue: $0) }
                }
                + load.libraries.flatMap { l in
                    l.validate().map { StoreHealth.OwnedIssue(owner: l.key, kind: "library", issue: $0) }
                }
                + load.organizations.flatMap { o in
                    o.validate().map { StoreHealth.OwnedIssue(owner: o.key, kind: "organization", issue: $0) }
                }
                + load.divergences.flatMap { d in
                    d.validate().map {
                        StoreHealth.OwnedIssue(owner: d.id.uuidString, kind: "divergence", issue: $0)
                    }
                })
    }
}
