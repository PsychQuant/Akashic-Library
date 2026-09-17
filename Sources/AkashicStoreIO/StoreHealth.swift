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
///
/// **第二種合法形狀**（#464）：掛進既有的 `perRecordIssues`（一個跨記錄檢查產出的 per-record
/// warning）。代價是反射守衛看不到它、消費端只能靠訊息前綴區辨——所以那個前綴要有單一定義
/// （`deadVerdictPrefix`，訊息**由它組出**）與一個計算屬性（`deadVerdicts`）；要區辨這一族的
/// 消費端（測試、日後的 App 面）從那裡取。CLI `validate` 與 MCP `doctor` 直接消費
/// `perRecordIssues`、不區辨——那是它們的既有形狀。
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
    ///
    /// **上升不一定是退步**：`split-author`（#443）把一個黏著的 literal 拆成 N 個作者位，
    /// 這個數會因此上升——那是一個合成的假人變成 N 個誠實的未歸戶名字，趨勢要與拆分次數
    /// 並讀（#451；store 不記得哪些位置是拆出來的，機械標註等 #450 的持久化）。
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

    /// 死 verdict（#464）的訊息前綴——**單一定義**：`deadVerdictIssues` 用它組訊息、`deadVerdicts` 用它篩，
    /// 測試與日後的 App 面也從這裡取。改這個常數，組與篩一起變。
    public static let deadVerdictPrefix = "死 verdict"
    /// 同一筆記錄對**同一個配對**同時持有 confirmed 與 rejected（#486）的訊息前綴——
    /// 與 `deadVerdictPrefix` 同形：訊息由它組出、`contradictoryVerdicts` 用它篩。
    public static let contradictoryVerdictPrefix = "矛盾 verdict"
    /// `perRecordIssues` 裡的死 verdict。是計算屬性不是儲存屬性：它是 `perRecordIssues` 的
    /// 子集（同一份事實的一個切面），存兩份會分岔（`entity-backlink-completeness` 的立場）。
    public var deadVerdicts: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.deadVerdictPrefix) }
    }
    /// `perRecordIssues` 裡的矛盾 verdict（#486）。計算屬性，與 `deadVerdicts` 同一個理由。
    public var contradictoryVerdicts: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.contradictoryVerdictPrefix) }
    }
    /// 同一筆記錄對同一配對持有**兩筆以上同 field 的判定記錄**（`verdictEqualityKey` 相同——#554 R23 D64）的訊息前綴——與
    /// `deadVerdictPrefix` 同形。這個狀態工具面的寫入不會製造（`appendIfAbsent` 以同一把鍵去重），但 rename 自 D62 起把它**原樣帶到新鍵**
    /// （只折整筆相等的重複，judgement 不同的兩筆都留），而下一次 person／venue 合併會以 #468 的血統層收成一筆——R22 verify security
    /// 第 14 列：「零資訊損失」只在 rename 那一步為真，而它之後沒有任何面看得見。
    public static let duplicateVerdictRecordPrefix = "重複的判定記錄"
    /// `perRecordIssues` 裡的重複判定記錄（D64）。計算屬性，與 `deadVerdicts` 同一個理由。
    public var duplicateVerdictRecords: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.duplicateVerdictRecordPrefix) }
    }
    /// 本機缺承重存檔（#453）的訊息前綴——**單一定義**：`danglingSourceIssues` 用它組訊息、
    /// `danglingSources` 用它篩，與 `deadVerdictPrefix` 同形。
    public static let danglingSourcePrefix = "本機缺承重存檔"
    /// `perRecordIssues` 裡的本機缺存檔。計算屬性，與 `deadVerdicts` 同一個理由：它是
    /// `perRecordIssues` 的一個視圖，不是第二份資料。
    public var danglingSources: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.danglingSourcePrefix) }
    }
    /// venue 的 verdict 數達 decode 預算一半（#499）的訊息前綴——單一定義，同上兩族。
    public static let venueVerdictBudgetPrefix = "venue 的 verdict 數逼近 decode 預算"
    /// `perRecordIssues` 裡的 venue verdict 預算 warning。計算屬性，同 `deadVerdicts`。
    public var venueVerdictBudgetWarnings: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.venueVerdictBudgetPrefix) }
    }

    /// #450：拆分後的孤兒 verdict——某 person／organization 持有的 resolution verdict，其 literal 已被
    /// 該 work 的拆分記錄退役（以 (citekey, literal) 為鍵）。計算屬性，同 `deadVerdicts`。
    public static let orphanedSplitVerdictPrefix = "拆分後的孤兒 verdict"
    public var orphanedSplitVerdicts: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.orphanedSplitVerdictPrefix) }
    }
    /// #450：拆分記錄的各段都已不在作者位——證據錨失效，記錄仍合法（供 un-split 參考）。
    public static let staleSplitRecordPrefix = "拆分記錄的各段都已不在作者位"
    public var staleSplitRecords: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.staleSplitRecordPrefix) }
    }
    /// #457：移除記錄說某個 literal 已退役，而它**現在又在作者位上**——store 同時斷言
    /// 兩件互相矛盾的事。可達路徑具名：移除之後 `authors` 是空的，而
    /// `enrich --include-absent-authors` 正好只在「完全為空」時補作者，於是同一個字串
    /// 可以被補回去。
    public static let contradictedRemovalPrefix = "移除記錄與作者位互相矛盾"
    public var contradictedRemovalRecords: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.contradictedRemovalPrefix) }
    }

    /// #554 配對唯一性的兩半（R11 D28、R14 D36／R15 D39）：per-record warning 住在 `Entry.validate()`／`Venue.validate()`，
    /// 前綴的**單一定義在 Core**（訊息在那裡組出），這裡只引用——同 `deadVerdictPrefix` 的形，家族才有計數
    /// （R14 verify regression 第 22 列：兩族沒有家族，doctor 截 20 則、App 預覽 5 則時可能完全看不到，
    /// `zero-instance-guards` 第 26／27 列宣稱的「掃得到」只對 CLI validate 成立）。
    /// **家族計數是下限**（R16；R15 verify 第 29 列）：每筆記錄至多 `Entry.perRecordWarningCap` 則進家族，其餘由一句概括
    /// （`Entry.perRecordCapSummaryPrefix`，**不在**任何家族裡）收尾——被截的記錄上，家族計數 ＝ min(受影響數, 上限)，
    /// 不是受影響數。**CLI `validate` 也拿不到被截的那幾則**（R24 D66；R23 verify Codex 第 2 列）：上限在本函式產生訊息時就生效，
    /// CLI 只是不再加一層面級的 20 則截斷——被截的記錄在三個面都只有概括句，要全部只能讀 YAML。**被截的記錄數自己是一族**（`cappedRecords`，R18 D54；R17 verify Codex 第 2 列：
    /// doctor 的描述與註解說「各族計數永遠完整」、與這一段互相矛盾，而 MCP 描述是呼叫端唯一看得到的契約）——三面都說得出「還有幾筆被截」。
    /// **以 (kind, owner) 計，不是概括句的行數**（R19 D56；R18 verify Codex 第 2 列：一筆 venue 可以同時出名字近重複與 confirmed-literal 兩句概括，
    /// R18 數行數就把「被截的記錄」多報一筆）——每筆記錄只留首見那一句，`count` 才真的是「幾筆記錄被截」。**留下的那一句是任意的**
    /// （由 `validate()` 內部 append 的順序決定、severity 也跟著它），消費端只得讀 `count`／`kind`／`owner`，不得依它的 message 或
    /// severity 分流（R19 verify logic 第 16 列）。
    public static let cappedRecordPrefix = Entry.perRecordCapSummaryPrefix
    public var cappedRecords: [OwnedIssue] {
        var seen = Set<String>()
        return perRecordIssues.filter { owned in
            guard owned.issue.message.hasPrefix(Self.cappedRecordPrefix) else { return false }
            return seen.insert("\(owned.kind)\u{1F}\(owned.owner)").inserted
        }
    }
    public static let duplicateVenueEdgePrefix = Entry.duplicateVenueEdgePrefix
    public var duplicateVenueEdges: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.duplicateVenueEdgePrefix) }
    }
    public static let confirmedLiteralAmbiguityPrefix = Venue.confirmedLiteralAmbiguityPrefix
    public var confirmedLiteralAmbiguities: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.confirmedLiteralAmbiguityPrefix) }
    }

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
        // **各族逐一，順序與 CLI `validate` 相同**，好讓兩面的輸出逐行對照。
        // 來源以本函式主體為準——寫死的族數在這裡漂過兩次（#416 第一版只寫了三族、
        // 漏掉 organizations 與 divergences；#394 補 venue 時「五族」沒跟著改）。
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
        // 結構上看不到。附加在各族之後：`errorsFirst` 是穩定分割，warning 內保持此序；MCP 面取
        // `prefix(20)`（`AkashicService.doctor()` 的既有截斷），per-record warning 若累積到 20 以上
        // （2026-09-03 實測 live store 2 條）這一族會被擠出 `first`——所以每一族都有專屬計數（R15 起含 #554 的兩族）。
        perRecord += deadVerdictIssues(in: load)
        perRecord += contradictoryVerdictIssues(in: load)   // #486
        perRecord += duplicateVerdictRecordIssues(in: load)   // #554 D64
        // #453：本機缺承重存檔——`missingSourceDigests` 先前零 production 呼叫端，doctor 只接
        // `auditSourceIndex()`（blob↔index 兩向比對），捏造或未同步的 digest 兩邊都不在、兩邊一致、
        // doctor 沉默（第 3 列「未涵蓋不得冒充通過」的形）。與死 verdict 同一形：per-record warning。
        perRecord += danglingSourceIssues(in: load)
        // #499：第 13 條邊在 venue 側是 O(catalog)——硬預算的一半處出聲、指名該 venue（裁決：候選 3）。
        perRecord += venueVerdictBudgetIssues(in: load)
        // #450：拆分後錨失效的兩種 warning——各段全不在的拆分記錄（owner 是 work）、literal 已被拆分
        // 退役的 verdict（owner 是持有者）。跨記錄（work 的拆分記錄 vs person 的 verdict），單筆 validate()
        // 看不到；同一形：per-record warning。
        perRecord += orphanedSplitVerdictIssues(in: load)
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
            // **各族逐一，順序與 CLI `validate` 相同**（來源見上方主體）。
            // **error 排在前面**（#416 R1 自審抓到）：MCP 面取 `prefix(20)`，而按族序
            // 排的話一個有 25 筆 warning 的 store 會把後面族別的 error **整個截掉**
            // ——`errors` 計數說「有一個」而 `first` 裡看不到它是哪一個。「知道有錯
            // 但看不到是哪個」與「不知道有錯」在可行動性上幾乎一樣糟，而它更難察覺，
            // 因為計數欄讓報告**看起來完整**（`lossless-intake` 執行細節 3 的形狀）。
            perRecordIssues: StoreHealth.errorsFirst(perRecord))
    }
}

public extension LibraryStore {
    /// **死 verdict 掃描**（#464）：resolution verdict 的 value 指向一個**目前沒有載入**的 holder。
    ///
    /// #232（rename）／#271（merge）／#460（venue 側）三次都是同一族的 stale——205 條靠人肉、
    /// 殘留 1 條靠 verify lens 全庫掃、清理完整性靠腳本——三個機制全是場外的、全在 #460 那一次
    /// （家族的三個結構缺口：#232 person rename／#271 person merge／#460 venue）。本掃描把它放進
    /// `StoreHealth`，CLI `validate` 與 MCP `doctor` 繼承（#416 的 perRecordIssues 形）。
    ///
    /// 判準是 set-difference：`work:` holder ∈ 已載入 citekey 集合、`person:` ∈ person key
    /// 集合、`org:` ∈ organization key 集合。**「不在集合」有兩種意思，訊息分開說**：holder 的
    /// 檔仍在磁碟但被 quarantine（先修那個檔）；或沒有任何檔宣稱它（掃描證得到的只有這件事——
    /// 最常見的成因是 holder 退役而 verdict 沒跟著遷移，即 #463 網格裡還沒補的格，但也可能是 key
    /// 打錯或壞的匯入；處置是確認後更新或刪掉這筆 verdict）。訊息只說掃描證得到的事實與處置，
    /// 成因與 issue 編號寫在這裡給維護者看。
    ///
    /// **severity 是 warning——三個理由，都不是「記錄仍合法」、也不是「rename 後常態為真」**
    /// （後者為假：寫下時 `renameEntry` 沒有 organizations 迴圈——#463 的格——所以只有 org 持有的那幾條
    /// verdict 的 holder 被 rename 時才會；verify DA 實測兩次 rename 產生 4 條。**#463 已於 2026-09-03
    /// 落地**（PR #493），合法 rename 不再產生死 verdict；第 3 個理由「沒有處置命令」仍成立，error 的
    /// 重開裁決等修復路徑出現）：
    /// 1. **升 error 會把 `zero-instance-guards` 第 8 列釘住的零翻掉**：那一列的依據是「per-record 的
    ///    error 級檢查全部是 key 合法性檢查、對載入後的記錄不可達」；死 verdict 若是 error，它會是第一個
    ///    既非 key 檢查又可達的 per-record error，`errorsFirst` 從裝飾品變成承重結構——而第 8 列明寫
    ///    那個轉變不得安靜發生。
    /// 2. #464 的 Expected 逐字寫「warning 級檢查」——使用者已裁的範圍不由實作端翻案。
    /// 3. 今天沒有處置命令：升 error 會讓那幾條的 holder 任一被 rename 後 `validate` 恆 exit 1 而修不掉
    ///    （只能手改 YAML）——必然失敗的紅燈會訓練人忽略紅燈。
    /// **三個理由都是「現在」**：#463 補完四格、且出現修復路徑之後，error 要重開裁決，第 8 列與第 13 列
    /// 一起改。
    ///
    /// 三面：CLI `validate` 逐則可見、不加面級截斷（exit 對 warning 仍為 0）；MCP `akashic_doctor` 進 `recordIssues`
    /// （截斷 20 則、`count` 送分母）；App 側欄「記錄」Section 渲染計數（#487，2026-09-04 落地）。per-record 的上限三面共有（R24 D66）。
    ///
    /// 解析不了的 value（`parse` 回 nil）不在此列——**對已載入的記錄它結構上不可達**：三族的
    /// YAML decode 在寫入閘與載入端都把 malformed verdict 整檔拒收（quarantine），
    /// `DeadVerdictScanTests.testMalformedVerdictValueIsUnreachableForLoadedRecords` 釘住這件事
    /// （`zero-instance-guards` 第 8 列的形狀：零的來源在別處，要釘住為什麼是零）。
    func deadVerdictIssues(in load: LibraryLoad) -> [StoreHealth.OwnedIssue] {
        let citekeys = Set(load.entries.map(\.citekey))
        let personKeys = Set(load.people.map(\.key))
        let orgKeys = Set(load.organizations.map(\.key))
        func loaded(_ p: ProvenanceReference.VerdictPairingValue) -> Bool {
            switch p.holderKind {
            case .work:   return citekeys.contains(p.holder)
            case .person: return personKeys.contains(p.holder)
            case .org:    return orgKeys.contains(p.holder)
            }
        }
        func quarantinedFile(_ p: ProvenanceReference.VerdictPairingValue) -> String? {
            switch p.holderKind {
            case .work:   return quarantinedFileClaiming(citekey: p.holder, in: load)
            case .person: return quarantinedFileClaiming(personKey: p.holder, in: load)
            case .org:    return quarantinedFileClaiming(orgKey: p.holder, in: load)
            }
        }
        func scan(_ refs: [ProvenanceReference], owner: String, kind: String) -> [StoreHealth.OwnedIssue] {
            refs.compactMap { r in
                guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                      let v = r.value,
                      let p = ProvenanceReference.VerdictPairingValue.parse(v),
                      !loaded(p) else { return nil }
                let target = "\(p.holderKind.rawValue):\(displaySafe(p.holder, max: 120))"
                let literal = displaySafe(p.literal, max: 120)
                let message: String
                if let file = quarantinedFile(p) {
                    message = "\(StoreHealth.deadVerdictPrefix)（暫定）：\(r.field) 的 holder \(target) 未載入——它的檔 "
                            + "\(displaySafe(file, max: 200)) 被 quarantine。先修那個檔，修好後這條會消失"
                            + "（literal「\(literal)」）"
                } else {
                    message = "\(StoreHealth.deadVerdictPrefix)：\(r.field) 的 holder \(target) 不在載入集合，且沒有任何檔宣稱它。"
                            + "處置：確認 holder 是否真的退役（最常見）或 key 打錯，然後在本記錄的 references "
                            + "更新或刪掉這筆 verdict（literal「\(literal)」）"
                }
                return StoreHealth.OwnedIssue(owner: owner, kind: kind,
                                              issue: ValidationIssue(severity: .warning, message: message))
            }
        }
        var out: [StoreHealth.OwnedIssue] = []
        for p in load.people { out += scan(p.references, owner: p.key, kind: "person") }
        for o in load.organizations { out += scan(o.references, owner: o.key, kind: "organization") }
        for v in load.venues { out += scan(v.references, owner: v.key, kind: "venue") }
        return out
    }
}

public extension LibraryStore {
    /// **同一筆記錄對同一個配對同時說「是」與「不是」**（#486）。
    ///
    /// `resolution-confirmed` 與 `resolution-rejected` 對同一個 (holderKind, holder, literal)
    /// 並存，代表判定史自相矛盾：提名層會同時把它算成「已判給這個人」與「已被否決」，而
    /// 兩條路徑對同一個配對給出相反的答案。這不是資料壞掉（兩條 verdict 各自合法、檔案載入
    /// 得了），是**判定**壞掉——所以出口是 warning 而不是 decode 拒收。
    ///
    /// **相等用 `verdictEqualityKey` 的那一半**（#470 剛裁決的單一定義）去掉 `field`：
    /// 本掃描問的正是「兩個 field 對同一個配對」，把 field 放進鍵會讓它永遠找不到東西
    /// ——#486 的 Expected 說「收攏鍵含 field」指的是 dedup 的那個鍵，不是這一個。
    /// 在 #470 之前這個掃描寫不出來：那時「同一配對」有兩個答案，先寫就是偷偷定案第三份。
    ///
    /// **2026-09-09 實測 live store：0 筆**（與 #464 verify 2026-09-03 的量測一致）。
    func contradictoryVerdictIssues(in load: LibraryLoad) -> [StoreHealth.OwnedIssue] {
        func pairingKey(_ p: ProvenanceReference.VerdictPairingValue) -> String {
            "\(p.holderKind.rawValue):\(p.holder)\u{0}" + NameNormalization.matchingKey(p.literal)
        }
        func scan(_ refs: [ProvenanceReference], owner: String, kind: String) -> [StoreHealth.OwnedIssue] {
            var byPairing: [String: (pairing: ProvenanceReference.VerdictPairingValue, fields: Set<String>)] = [:]
            for r in refs {
                guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                      let v = r.value,
                      let p = ProvenanceReference.VerdictPairingValue.parse(v) else { continue }
                let k = pairingKey(p)
                var e = byPairing[k] ?? (p, [])
                e.fields.insert(r.field)
                byPairing[k] = e
            }
            return byPairing.values.filter { $0.fields.count > 1 }
                // 走訪 Dictionary.values 的順序未定義——輸出要決定論，否則兩次跑同一個 store
                // 得到不同的行序，而逐字比對的負控會偶發假紅（`zero-instance-guards` 第 6 列）。
                .sorted { pairingKey($0.pairing) < pairingKey($1.pairing) }
                .map { e in
                    StoreHealth.OwnedIssue(
                        owner: owner, kind: kind,
                        issue: ValidationIssue(
                            severity: .warning,
                            message: "\(StoreHealth.contradictoryVerdictPrefix)："
                                   + "\(e.fields.sorted().joined(separator: " 與 ")) 對同一個配對並存"
                                   + "（\(e.pairing.holderKind.rawValue):"
                                   + "\(displaySafe(e.pairing.holder, max: 120))"
                                   + "，literal「\(displaySafe(e.pairing.literal, max: 120))」）。"
                                   + "處置：這是判定自相矛盾不是資料壞掉——決定哪一個才對，刪掉另一個"))
                }
        }
        var out: [StoreHealth.OwnedIssue] = []
        for p in load.people { out += scan(p.references, owner: p.key, kind: "person") }
        for o in load.organizations { out += scan(o.references, owner: o.key, kind: "organization") }
        for v in load.venues { out += scan(v.references, owner: v.key, kind: "venue") }
        return out
    }

    /// **重複的判定記錄**（#554 R23，D64）：同一筆記錄裡 ≥2 筆 verdict 的 `verdictEqualityKey`（field ＋ 正規化配對）相同。
    ///
    /// 這是 `appendIfAbsent`／`supersede`／merge 都當成「同一筆」的狀態，卻沒有任何面報它：`contradictoryVerdicts` 只比 confirmed×rejected、
    /// `confirmedLiteralAmbiguities` 以**位元組相異**分組（位元組相同的兩筆收成一組、計數 1）。而 rename 自 D62 起**刻意**保留它——只折整筆相等
    /// （含 judgement 與 rests-on）的重複，judgement 不同的兩筆都原樣帶到新鍵——於是「rename 零資訊損失」把一筆判定從「rename 當場刪、
    /// 有 `verdictsCollapsed` 回報」換成「留著、沒有面看得見、下一次合併以 #468 的血統層收成一筆」（R22 verify security 第 14 列）。
    /// 這一族讓中間那一格看得見。**severity 是 warning**：記錄合法可載入，兩筆各自都是一個人的判定；error 會讓一筆只能手改才修得好的
    /// 記錄擋住自己所有的寫入。處置寫在訊息裡：留一筆，或把其中一筆的 value 改成它實際描述的記錄。
    ///
    /// **2026-09-16 實測 live store：0 筆**（量法見 `zero-instance-guards` 第 28 列）。
    func duplicateVerdictRecordIssues(in load: LibraryLoad) -> [StoreHealth.OwnedIssue] {
        func scan(_ refs: [ProvenanceReference], owner: String, kind: String) -> [StoreHealth.OwnedIssue] {
            var byKey: [String: (first: ProvenanceReference, pairing: ProvenanceReference.VerdictPairingValue, count: Int,
                                 kinds: Set<[[UInt8]]>, spellings: Set<[UInt8]>)] = [:]   // kinds 以 byteExactKey 計（D65）：「全部完全相同」是位元組層的話
            var order: [String] = []
            for r in refs {
                guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                      let v = r.value,
                      let p = ProvenanceReference.VerdictPairingValue.parse(v) else { continue }
                let k = ProvenanceReference.verdictEqualityKey(field: r.field, value: v)
                if var e = byKey[k] { e.count += 1; e.kinds.insert(r.byteExactKey); e.spellings.insert(Array(p.literal.utf8)); byKey[k] = e }
                else { byKey[k] = (r, p, 1, [r.byteExactKey], [Array(p.literal.utf8)]); order.append(k) }
            }
            // 第 27 列的第二類（`Venue.validate()`：venue×work 的 confirmed、只差位元組）已經報的那一格**不重報**——同一件事出兩則是雜訊不是訊號；
            // 這一族報的是它認不得的：位元組相同的重複、rejected 的重複、person 配對的重複、person／organization 持有的重複。
            let issues = order.compactMap { k -> StoreHealth.OwnedIssue? in
                guard let e = byKey[k], e.count > 1 else { return nil }
                if kind == "venue", e.pairing.holderKind == .work, e.first.field == "resolution-confirmed", e.spellings.count > 1 { return nil }
                let sameness = e.kinds.count == 1 ? "全部完全相同" : "judgement 或 rests-on 彼此不同"
                return StoreHealth.OwnedIssue(
                    owner: owner, kind: kind,
                    issue: ValidationIssue(
                        severity: .warning,
                        message: "\(StoreHealth.duplicateVerdictRecordPrefix)：\(e.first.field) 對同一個配對有 \(e.count) 筆判定記錄"   // display-safe-exempt: 前綴是常量；field 是封閉對；Int
                               + "（\(e.pairing.holderKind.rawValue):\(displaySafe(e.pairing.holder, max: 120))"
                               + "，literal「\(displaySafe(e.pairing.literal, max: 120))」；\(sameness)）"   // display-safe-exempt: sameness 是兩句字面常量
                               + "——工具面的寫入以 verdictEqualityKey 去重、寫不出它：是手改、舊 binary 寫的，或由 rename 從舊鍵原樣帶過來（D62 不刪）；"
                               + "下一次 person／venue 合併會以 #468 的血統層收成一筆並在 verdictsCollapsed 回報。處置：留一筆，或把其中一筆的 value 改成它實際描述的記錄的鍵"))
            }
            // 每筆記錄至多 `Entry.perRecordWarningCap` 則、其餘一句概括（不帶家族前綴——與第 26／27 列同一條紀律；R23 首版無上限，
            // 一個 20 筆 work × 6 對的 venue 就出 120 則、把 doctor 的 `count` 從 20 推到 140）。
            let cap = Entry.perRecordWarningCap
            guard issues.count > cap else { return issues }
            return Array(issues.prefix(cap)) + [StoreHealth.OwnedIssue(
                owner: owner, kind: kind,
                issue: ValidationIssue(severity: .warning,
                                       message: "\(Entry.perRecordCapSummaryPrefix)：\(kind) '\(displaySafe(owner, max: 120))' 另有 \(issues.count - cap) 個配對未列出（同樣持有重複的判定記錄；每筆記錄最多列 \(cap) 個）"))]   // display-safe-exempt: 前綴是常量；Int
        }
        var out: [StoreHealth.OwnedIssue] = []
        for p in load.people { out += scan(p.references, owner: p.key, kind: "person") }
        for o in load.organizations { out += scan(o.references, owner: o.key, kind: "organization") }
        for v in load.venues { out += scan(v.references, owner: v.key, kind: "venue") }
        return out
    }
}

public extension LibraryStore {
    /// **本機缺承重存檔**（#453）：記錄的 provenance 指向一個本機 `sources/` 沒有的 digest。
    ///
    /// 兩層盲區：`missingSourceDigests` 不掃 venue（#406 起承重證據住在 venue 上）也不掃
    /// `Entry.references`（第 15 條邊）；而且它**零 production 呼叫端**——doctor／`StoreHealth` 接的是
    /// `auditSourceIndex()`，只比 blob↔index，捏造的 digest 兩邊都不在、兩邊一致、doctor 沉默
    /// （#251 形狀第三次）。修法是把逐 holder 的缺席以 warning 級 `OwnedIssue` 併入 `perRecordIssues`
    /// ——CLI `validate` 逐行、MCP `doctor` 進 `recordIssues`；App 側欄「記錄」Section 渲染計數（#487）。
    ///
    /// **用詞是「本機缺」不是「偽造」**：`sources/` 不進 git（`replace-endnote-and-zotero` 的承重閘），
    /// 本機分不出「從未存在」與「沒同步」——所以訊息說出這個邊界，處置寫成兩條。
    ///
    /// **severity 是 warning**：記錄合法可載入，缺的是位元組；error 會讓 `hasErrors` 翻紅、擋住
    /// export 類流程，而其他 clone 上「全部 dangling」是常態。
    ///
    /// 讀不到的 shard 不判缺席（#265 的既有語意，住在 `missingSourceDigests`）——那是
    /// `auditSourceIndex` 的 `unreadableShards` 在報的事。
    func danglingSourceIssues(in load: LibraryLoad) -> [StoreHealth.OwnedIssue] {
        missingSourceDigests(load).holders.map { h in
            let head = "\(StoreHealth.danglingSourcePrefix)：\(displaySafe(h.slot, max: 80)) 指向 "
                + "\(displaySafe(h.digest, max: 80))——"
            let message: String
            if h.wellFormed {
                message = head + "本機 sources/ 找不到這份存檔。sources/ 不進 git，其他 clone 上的數字會不同；"
                    + "處置：從持有它的機器同步 sources/，或確認這個 digest 是否從未存在過（本機分不出兩者）"
            } else {
                // 不是 `sha256:` 形——無從查找，同步也不會有。不能說「找不到」，那暗示同步就會有。
                message = head + "這不是合法的 digest（`sha256:` ＋ 64 個十六進位字元），無從在本機查找；"
                    + "處置：把來源存進 sources/（`store-source`）再把這個槽位改成它的 digest"
            }
            return StoreHealth.OwnedIssue(owner: h.owner, kind: h.kind,
                                          issue: ValidationIssue(severity: .warning, message: message))
        }
    }
}

public extension LibraryStore {
    /// **venue 的 verdict 數逼近 decode 預算**（#499，裁決：候選 3）。
    ///
    /// `resolve-venues` 的 confirmed verdict 落被判定的 venue（第 13 條邊）；目錄匯入讓一本刊一夜長出上千筆
    /// （`psychological-methods` 1,352 筆、268 KB），增長是 O(catalog)，而唯一的守衛是 decode 硬預算——撞上時
    /// 整檔 quarantine、venue 消失。裁決不改序列化位置（候選 1 會打回 #464／#463 的 per-holder 前提，候選 2 的
    /// blast radius 是那整套機制），改在**硬預算的一半**設 warning：`AliasEventBudget.venueVerdictWarningThreshold`
    /// ＝ `maxExpandedNodes / 2 / nodesPerVenueVerdict`（後者是量測值）。達門檻＝重開第 13 條邊的規模化裁決，
    /// 候選 2（sidecar ledger）是那時的形狀。
    ///
    /// 只數 resolution verdict（`resolutionVerdictFields`），不數其他 reference——增長來源就是它們。
    /// severity warning：記錄合法、只是在長；訊息說出數字、門檻與處置。
    func venueVerdictBudgetIssues(in load: LibraryLoad,
                                  threshold: Int = AliasEventBudget.venueVerdictWarningThreshold) -> [StoreHealth.OwnedIssue] {
        load.venues.compactMap { v in
            let n = v.references.filter { ProvenanceReference.resolutionVerdictFields.contains($0.field) }.count
            guard n >= threshold else { return nil }
            let message = "\(StoreHealth.venueVerdictBudgetPrefix)：\(n) 筆 resolution verdict（門檻 \(threshold)＝"
                + "decode 硬預算的一半）。這本刊的 verdict 是 O(catalog) 在長；處置：重開第 13 條邊的規模化裁決（#499，"
                + "候選 2 sidecar ledger），不要只放寬預算"
            return StoreHealth.OwnedIssue(owner: v.key, kind: "venue",
                                          issue: ValidationIssue(severity: .warning, message: message))
        }
    }
}

public extension LibraryStore {
    /// **拆分後錨失效的掃描**（#450）——兩種 warning，都是「拆分記錄 vs 作者位／verdict」的跨記錄一致性：
    ///
    /// 1. **各段全不在**（owner＝work）：一筆拆分記錄的 statement 各段沒有任何一段仍是本 work 的作者位。
    ///    「仍在」含已升格的 `.key`——升格不是消失，那一段的原 literal 記在 person 的 confirmed verdict
    ///    （`work:<citekey> :: <literal>`）裡。記錄仍合法、仍載入（decode 只驗形狀），只是證據錨失效。
    /// 2. **孤兒 verdict**（owner＝持有者）：person／organization 持有的 resolution verdict，其 value 指向
    ///    `work:<citekey> :: <literal>`，而該 work 有一筆拆分記錄的 value 就是那個 literal——verdict 判的
    ///    是一個已經不存在的作者位。**以 (citekey, literal) 為鍵**（design Risks）：同一個 literal 掛在
    ///    另一筆沒拆的 work 上不是孤兒。
    ///
    /// **severity 是 warning**：兩者記錄都合法可載入；error 會讓 `hasErrors` 翻紅擋住 export 類流程，
    /// 而處置（對拆出的各段重新消歧、更新或刪掉 verdict）是人的動作，不是修檔。`validate` exit 仍 0
    /// ——「掃得到」不「叫醒」（#464 的同一條界線）。零實例的來源是「記錄還沒開始寫」（4 筆已拆記錄
    /// 沒有拆分記錄，不回填），見 `zero-instance-guards` 第 17 列。
    func orphanedSplitVerdictIssues(in load: LibraryLoad) -> [StoreHealth.OwnedIssue] {
        // 已升格作者位的原 literal：person 的 confirmed verdict（holder 是 work）
        var confirmedByWork: [String: Set<String>] = [:]
        for p in load.people {
            for r in p.references where r.field == "resolution-confirmed" {
                guard let v = r.value, let pv = ProvenanceReference.VerdictPairingValue.parse(v),
                      pv.holderKind == .work else { continue }
                confirmedByWork[pv.holder, default: []].insert(pv.literal)
            }
        }
        var out: [StoreHealth.OwnedIssue] = []
        var retiredByWork: [String: Set<String>] = [:]
        // #457：移除記錄的一致性條件與拆分記錄**相反**——拆分要求「至少一段仍在作者位」，
        // 移除要求「那個字串**不在**作者位」。兩者都是 warning：記錄合法，失效的是證據錨。
        for e in load.entries where !e.authorRemovalRecords.isEmpty {
            let present = Set(e.authors.compactMap { a -> String? in
                if case .literal(let s) = a { return s } else { return nil }
            })
            for r in e.authorRemovalRecords where present.contains(r.removed) {
                let message = "\(StoreHealth.contradictedRemovalPrefix)：「\(displaySafe(r.removed, max: 120))」"
                            + "有一筆移除記錄（理由：\(displaySafe(r.record.reason, max: 120))），"
                            + "而它現在又是本 work 的作者位。處置：確認是不是被補值面重新加回來的"
                            + "（enrich --include-absent-authors 只在 authors 完全為空時補，而移除之後正好是空的）；"
                            + "要嘛再移除一次，要嘛刪掉那筆記錄——留著等於 store 同時說兩件相反的事"
                out.append(StoreHealth.OwnedIssue(owner: e.citekey, kind: "entry",
                                                  issue: ValidationIssue(severity: .warning, message: message)))
            }
        }
        for e in load.entries {
            let records = e.splitRecords
            guard !records.isEmpty else { continue }
            let present = Set(e.authors.compactMap { a -> String? in
                if case .literal(let s) = a { return s } else { return nil }
            }).union(confirmedByWork[e.citekey] ?? [])
            for s in records {
                retiredByWork[e.citekey, default: []].insert(s.retired)
                guard !s.record.parts.contains(where: { present.contains($0) }) else { continue }
                let parts = s.record.parts.map { "⟦\(displaySafe($0, max: 80))⟧" }.joined(separator: " ")
                let message = "\(StoreHealth.staleSplitRecordPrefix)：「\(displaySafe(s.retired, max: 120))」拆為 \(parts)，"
                            + "但沒有任何一段仍是本 work 的作者位（含已升格 .key 的 confirmed literal）。"
                            + "處置：確認作者位是否被改寫；記錄保留供 un-split 參考，不要刪"
                out.append(StoreHealth.OwnedIssue(owner: e.citekey, kind: "entry",
                                                  issue: ValidationIssue(severity: .warning, message: message)))
            }
        }
        guard !retiredByWork.isEmpty else { return out }
        func scan(_ refs: [ProvenanceReference], owner: String, kind: String) -> [StoreHealth.OwnedIssue] {
            refs.compactMap { r in
                guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                      let v = r.value,
                      let pv = ProvenanceReference.VerdictPairingValue.parse(v),
                      pv.holderKind == .work,
                      retiredByWork[pv.holder]?.contains(pv.literal) == true else { return nil }
                let message = "\(StoreHealth.orphanedSplitVerdictPrefix)：\(r.field) 指向 work:\(displaySafe(pv.holder, max: 120)) 的 "
                            + "literal「\(displaySafe(pv.literal, max: 120))」，而該 work 已把它拆分（拆分記錄在 work 側 references）"
                            + "——這條 verdict 判的作者位已退役。處置：對拆出的各段重新消歧，然後更新或刪掉這筆 verdict"
                return StoreHealth.OwnedIssue(owner: owner, kind: kind,
                                              issue: ValidationIssue(severity: .warning, message: message))
            }
        }
        for p in load.people { out += scan(p.references, owner: p.key, kind: "person") }
        for o in load.organizations { out += scan(o.references, owner: o.key, kind: "organization") }
        return out
    }
}
