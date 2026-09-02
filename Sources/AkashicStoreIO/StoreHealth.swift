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
    /// **跨記錄**檢查，per-entry 一條都不做。
    ///
    /// **落差是 warning 一族，不是 error**（#416 R1 更正）。我原本寫「落差裡有一條是
    /// error 級（citekey 不符 pattern）」——實測那條到不了：load 對五族都做 key 合法性
    /// 檢查並 quarantine 整個檔，所以 `validate()` 的 error 分支對載入後的記錄結構上
    /// 不可達（`StoreHealthSurfaceTests.testNoPerRecordErrorIsReachableFromALoadedStore`
    /// 釘住這個事實）。quarantine 本來就在本型別裡、doctor 也渲染。
    ///
    /// 真正看不到的是「title 為空」「libraries 含重複 key」「載體型別帶 editor」
    /// 「未知欄位」那幾條 warning——它們是編目品質提示，少了它們 App 使用者不會知道
    /// 哪些記錄該補。
    ///
    /// 放這裡而不是各面自己算，是 #263 已建立的形狀：唯讀事實單一來源，
    /// 兩個消費面各自渲染。上面的反射守衛自動釘住新欄位。
    public let perRecordIssues: [OwnedIssue]

    /// 一則驗證問題 ＋ 它屬於哪筆記錄。
    ///
    /// **severity 與 owner 都要攜帶**：只給訊息的話消費端分不出 error 與 warning，
    /// 也指不出是哪一筆——CLI 面兩者都有，MCP 面就不能丟（#138 verify F3 的立場）。
    /// **不宣告 `Sendable`**：`ValidationIssue` 不是（`Models.swift:614`），而在
    /// 一個非 Sendable 的成員上宣告 Sendable 在 Swift 6 是 error（現在是 warning）。
    /// 讓 `ValidationIssue` 變 Sendable 是另一個變更的範圍——它是共用型別，動它會
    /// 波及五族的 `validate()`。本型別不跨並行邊界（`health(from:)` 同步算完就回），
    /// 所以不需要那個保證。
    public struct OwnedIssue {
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

extension StoreHealth {
    /// error 先於 warning，**同 severity 內保持原順序**（stable partition）。
    ///
    /// 不用 `sorted(by:)`：Swift 的排序不保證穩定，而族序（entry → person → …）
    /// 是刻意的——它讓 CLI 與 MCP 兩面的輸出可以逐行對照（#416）。
    static func errorsFirst(_ xs: [OwnedIssue]) -> [OwnedIssue] {
        xs.filter { $0.issue.severity == .error } + xs.filter { $0.issue.severity != .error }
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
        // **五族逐一，順序與 CLI `validate` 相同**，好讓兩面的輸出逐行對照。
        // 族數是照 CLI 那五個迴圈數出來的（#416 第一版只寫了三族——漏掉
        // organizations 與 divergences，於是 MCP 面會少兩族而「看起來完整」）。
        var perRecord: [StoreHealth.OwnedIssue] = []
        for e in load.entries {
            perRecord += e.validate().map { .init(owner: e.citekey, kind: "entry", issue: $0) }
        }
        for p in load.people {
            perRecord += p.validate().map { .init(owner: p.key, kind: "person", issue: $0) }
        }
        for l in load.libraries {
            perRecord += l.validate().map { .init(owner: l.key, kind: "library", issue: $0) }
        }
        for o in load.organizations {
            perRecord += o.validate().map { .init(owner: o.key, kind: "organization", issue: $0) }
        }
        // #394 task 4.3：**venue 是先前缺的第六族**。`Venue.validate()` 存在於
        // `Venue.swift` 卻在全樹零呼叫端——於是 venue 的 key 格式錯誤、authorized 與
        // names 不符、未知欄位警告全部看不見，而 #416 把這一族抽進 `StoreHealth` 時
        // 也沒把它補上（那一輪的封閉列舉是「五族」，venue 不在裡面）。
        // 這正是 `entity-backlink-completeness` 執行細節 2 記過的形狀：一個 entity kind
        // 在讀取面沒有路徑，而缺席不會有任何跡象。
        for v in load.venues {
            perRecord += v.validate().map { .init(owner: v.key, kind: "venue", issue: $0) }
        }
        for d in load.divergences {
            perRecord += d.validate().map {
                .init(owner: d.id.uuidString, kind: "divergence", issue: $0)
            }
        }
        // #464：死 verdict 掃描——跨記錄的一致性（holder 是否還在），單筆 `validate()`
        // 結構上看不到（它只有自己那一筆）。放這裡讓三個消費面自動繼承。
        perRecord += StoreHealth.deadVerdictIssues(in: load)
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
            // **error 排在前面**（#416 R1 自審抓到）：MCP 面取 `prefix(20)`，而按族序
            // 排的話一個有 25 筆 warning 的 store 會把後面族別的 error **整個截掉**
            // ——`errors` 計數說「有一個」而 `first` 裡看不到它是哪一個。「知道有錯
            // 但看不到是哪個」與「不知道有錯」在可行動性上幾乎一樣糟，而它更難察覺，
            // 因為計數欄讓報告**看起來完整**（`lossless-intake` 執行細節 3 的形狀）。
            perRecordIssues: StoreHealth.errorsFirst(perRecord))
    }
}

extension StoreHealth {
    /// **死 verdict 掃描**（#464）：resolution verdict 的 value 指向一個已不存在的 holder。
    ///
    /// #232（rename）／#271（merge）／#460（venue 側）三次都是同一族的 stale——205 條靠人肉、
    /// 殘留 1 條靠 verify lens 全庫掃、清理完整性靠腳本。三次全是場外機制；本掃描把它放進
    /// `StoreHealth`，CLI `validate` 與 App 兩面自動繼承（#416 的 perRecordIssues 形）。
    ///
    /// 判準是 set-difference 不變式（#460 fix round 已驗證可行）：`work:` holder ∈ citekey 集合、
    /// `person:` holder ∈ person key 集合、`org:` holder ∈ organization key 集合；不在集合內即 warning。
    /// 是 warning 不是 error：它是**過期**不是**矛盾**——記錄本身仍合法、仍可載入，只是它宣稱的
    /// 配對對象已經退役；把它升成 error 會讓 `hasFindings` 對一次 rename 之後的 store 常態為真。
    /// 解析不了的 value 不在此列（寫入閘與 `validate()` 的 malformed 檢查已管）。
    static func deadVerdictIssues(in load: LibraryLoad) -> [OwnedIssue] {
        let citekeys = Set(load.entries.map(\.citekey))
        let personKeys = Set(load.people.map(\.key))
        let orgKeys = Set(load.organizations.map(\.key))
        func alive(_ p: ProvenanceReference.VerdictPairingValue) -> Bool {
            switch p.holderKind {
            case .work:   return citekeys.contains(p.holder)
            case .person: return personKeys.contains(p.holder)
            case .org:    return orgKeys.contains(p.holder)
            }
        }
        func scan(_ refs: [ProvenanceReference], owner: String, kind: String) -> [OwnedIssue] {
            refs.compactMap { r in
                guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                      let v = r.value,
                      let p = ProvenanceReference.VerdictPairingValue.parse(v),
                      !alive(p) else { return nil }
                return OwnedIssue(owner: owner, kind: kind, issue: ValidationIssue(
                    severity: .warning,
                    message: "死 verdict：\(r.field) 指向已不存在的 \(p.holderKind.rawValue):"
                           + "\(displaySafe(p.holder, max: 120))（literal「\(displaySafe(p.literal, max: 120))」）"
                           + "——#232／#271／#460 家族的 stale；holder 退役時遷移漏了這一格，"
                           + "或退役走了沒有遷移的路徑"))
            }
        }
        var out: [OwnedIssue] = []
        for p in load.people { out += scan(p.references, owner: p.key, kind: "person") }
        for o in load.organizations { out += scan(o.references, owner: o.key, kind: "organization") }
        for v in load.venues { out += scan(v.references, owner: v.key, kind: "venue") }
        return out
    }
}
