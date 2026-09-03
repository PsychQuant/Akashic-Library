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
    /// `perRecordIssues` 裡的死 verdict。是計算屬性不是儲存屬性：它是 `perRecordIssues` 的
    /// 子集（同一份事實的一個切面），存兩份會分岔（`entity-backlink-completeness` 的立場）。
    public var deadVerdicts: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.deadVerdictPrefix) }
    }
    /// 本機缺承重存檔（#453）的訊息前綴——**單一定義**：`danglingSourceIssues` 用它組訊息、
    /// `danglingSources` 用它篩，與 `deadVerdictPrefix` 同形。
    public static let danglingSourcePrefix = "本機缺承重存檔"
    /// `perRecordIssues` 裡的本機缺存檔。計算屬性，與 `deadVerdicts` 同一個理由：它是
    /// `perRecordIssues` 的一個視圖，不是第二份資料。
    public var danglingSources: [OwnedIssue] {
        perRecordIssues.filter { $0.issue.message.hasPrefix(Self.danglingSourcePrefix) }
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
        // （2026-09-03 實測 live store 2 條）這一族會被擠出 `first`——那時要重排或給專屬計數，這裡先記下。
        perRecord += deadVerdictIssues(in: load)
        // #453：本機缺承重存檔——`missingSourceDigests` 先前零 production 呼叫端，doctor 只接
        // `auditSourceIndex()`（blob↔index 兩向比對），捏造或未同步的 digest 兩邊都不在、兩邊一致、
        // doctor 沉默（第 3 列「未涵蓋不得冒充通過」的形）。與死 verdict 同一形：per-record warning。
        perRecord += danglingSourceIssues(in: load)
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
    /// 三面：CLI `validate` 逐行可見（exit 對 warning 仍為 0）；MCP `akashic_doctor` 進 `recordIssues`
    /// （截斷 20 則、`count` 送分母）；**App 面未渲染 `perRecordIssues`**（#416 起的既有缺口，#487）。
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
    /// **本機缺承重存檔**（#453）：記錄的 provenance 指向一個本機 `sources/` 沒有的 digest。
    ///
    /// 兩層盲區：`missingSourceDigests` 不掃 venue（#406 起承重證據住在 venue 上）也不掃
    /// `Entry.references`（第 15 條邊）；而且它**零 production 呼叫端**——doctor／`StoreHealth` 接的是
    /// `auditSourceIndex()`，只比 blob↔index，捏造的 digest 兩邊都不在、兩邊一致、doctor 沉默
    /// （#251 形狀第三次）。修法是把逐 holder 的缺席以 warning 級 `OwnedIssue` 併入 `perRecordIssues`
    /// ——CLI `validate` 逐行、MCP `doctor` 進 `recordIssues`；App 面未渲染 per-record（#416 起，#487）。
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
