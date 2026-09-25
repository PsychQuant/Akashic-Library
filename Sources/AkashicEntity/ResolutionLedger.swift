import Foundation
import AkashicCore

/// #232：消解判定的**唯一**讀寫封裝點（design D4）。
///
/// verdict 以既有 `ProvenanceReference` 承載（無新序列化形狀）：
/// - `field`：封閉對 `resolution-confirmed`／`resolution-rejected`
///   （單一來源在 `ProvenanceReference.resolutionVerdictFields`）
/// - `value`：配對定位 `<kind>:<key> :: <literal>`（design D2 + verify DA——kind
///   token 必填且兩族統一；文法解析器住 `ProvenanceReference.VerdictPairingValue`，
///   store 閘與本 ledger 共用同一個）
/// - `statement`：人話 + 尾註 `[rule: <name>]`（design D3——typed slot 被 #247
///   擋住的 v1 妥協；tolerant parse、缺席依 holderKind 計入該族的預設 rule）
///
/// encode 與 decode 只住這裡——慣例改動不外溢（deletion test：沒有它 = 重複提名
/// 回歸 + 計數無來源 + 慣例散落三處）。
public enum ResolutionLedger {

    /// person 族的證據類別（resolver 的「alias 完全命中且不歧義」規則）。
    public static let personRule = ProvenanceReference.RuleName.personExact   // #468：字面住 AkashicCore

    /// organization 族的證據類別（「org name 完全命中且不歧義」）。與 person 族
    /// **分開命名**（verify REG-7）：兩條規則的校準歷史本來就該分開計。
    public static let orgRule = ProvenanceReference.RuleName.orgExact

    /// tier → person 族校準規則名（#303 R1-fix B2）。**封閉映射**——寬鬆 tier 的
    /// 判定與 exact 的校準史分開計（REG-7 的同一條理由換到 tier 軸）；verdict 寫入
    /// 前由候選的 tier 導出，寫入面不得再寫死 `personRule`。exact 沿用既有字面，
    /// 讓 #232 以來的歷史不需遷移；legacy 無尾註 verdict 依 `ruleTail` 的族預設
    /// 落回 `personRule`——它們全是 exact 時代寫的，語意正確。
    public static func personRule(for tier: ResolutionTier) -> String {
        switch tier {
        case .exact: return personRule
        case .confirmedElsewhere: return "author-name-confirmed-elsewhere"
        case .reorder: return "author-name-reorder"
        case .initials: return "author-name-initials"
        }
    }

    /// venue 族的證據類別（「venue name 完全命中且不歧義」，#304）。同上，
    /// 分開命名讓各族規則的校準歷史分開計。
    public static let venueRule = ProvenanceReference.RuleName.venueExact

    /// 逐篇判定的證據類別（change `per-work-judged-authorship`）。
    ///
    /// **刻意不用 `author-name-` 前綴**：那個前綴的意思是「靠作者名字比對出來的」，
    /// 而判定依 `.claude/rules/identity-is-judged-not-matched.md` **不是**靠名字——
    /// 它由名字以外的證據（論文登記的機構、共同作者、庫內出處）支撐。沿用該前綴會讓
    /// 校準統計把兩種完全不同的證據混在一起。
    ///
    /// **不進 `personRule(for tier:)`**：那是 tier → rule 的封閉映射，而判定無 tier。
    ///
    /// 字面須通過提名理由的弱血統揭露檢查（`^[a-z][a-z-]{0,60}$`），否則會被顯示成
    /// 「非標準rule」而讓判定的來歷不可見——`ResolutionLedgerTests` 釘住這件事。
    public static let judgedRule = ProvenanceReference.RuleName.judgedPerWork

    /// 判定種類——與 verdict 欄位對一一對應。
    public enum VerdictKind: String, CaseIterable {
        case confirmed = "resolution-confirmed"
        case rejected = "resolution-rejected"
        /// 查過、判不出來（change `resolution-verdict-states`，#619）。**不是判定**：不抑制提名、不構成矛盾、
        /// 配對被判定之後仍保留為查證歷史（不退役）。
        case undecided = "resolution-undecided"

        /// 翻轉判定時要退役的另一方（D20）。未決沒有「相反」——寫未決不退役任何東西。
        public var opposite: VerdictKind? {
            switch self {
            case .confirmed: return .rejected
            case .rejected: return .confirmed
            case .undecided: return nil
            }
        }
    }

    /// 未決記錄的尾註 rule（#619）。字面住 AkashicCore。
    public static let undecidedRule = ProvenanceReference.RuleName.undecided

    /// 配對的狀態（spec「A pairing's state SHALL be derived as decided, undecided, or pending」）——現算，不存。
    public enum PairingState: String, Sendable {
        /// 有任一層級的 confirmed 或 rejected
        case decided
        /// 沒有判定，但有 ≥1 筆未決記錄
        case undecided
        /// 沒有任何 verdict
        case pending
    }

    /// 解析出的一筆判定（掛在哪個 record 上由呼叫端知道，故不含 judgedKey）。
    public struct Verdict: Equatable {
        public let kind: VerdictKind
        public let holderKind: ProvenanceReference.VerdictHolderKind
        public let holder: String
        public let literal: String
        public let rule: String
        /// statement 原文（含尾註）與 rests-on——檢視面逐筆印未決記錄時要用（#619）。
        public let statement: String
        public let restsOn: [String]
    }

    // MARK: - 寫端（唯一產生器）

    /// 產生一筆 verdict reference。statement 收人話，尾註由本函式補——
    /// 呼叫端不自行拼 `[rule:]`（慣例單一來源）。
    public static func record(_ kind: VerdictKind,
                              holderKind: ProvenanceReference.VerdictHolderKind,
                              holder: String, literal: String,
                              rule: String, statement: String) -> ProvenanceReference {
        ProvenanceReference(
            field: kind.rawValue,
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: holderKind, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "\(statement) [rule: \(rule)]", restsOn: []))
    }

    /// 一筆**判定**的 verdict（change `per-work-judged-authorship`）。
    ///
    /// 與提名路徑的差別只有兩處，而兩處都是刻意的：
    /// - `statement` 是**操作者／agent 給的原文**，不是罐頭字串
    /// - `rule` 是 `judgedRule`，不由 tier 導出（判定無 tier）
    ///
    /// **住這裡而不由呼叫端各拼一次**：本檔頭的既有立場是「慣例單一來源——呼叫端不自行
    /// 拼 `[rule:]`」。CLI 與 MCP 兩面若各組一次，就是兩份會分岔的規格。
    ///
    /// `restsOn` 依 `record` 既有行為留空——#280 裁決 verdict 刻意不攜證據指標，
    /// 判定所依據的承重內容寫進被判 person 的 `references`。
    public static func record(judged pairing: JudgedPairing,
                              kind: VerdictKind = .confirmed) -> ProvenanceReference {
        record(kind, holderKind: .work,
               holder: pairing.citekey, literal: pairing.literal,
               rule: judgedRule, statement: pairing.judgement)
    }

    /// 一筆**未決**記錄（change `resolution-verdict-states`，#619）：查過、判不出來。
    ///
    /// statement 是操作者／agent 寫的「查了什麼、為何判不出來」，尾註由本函式補 `[rule: checked-undecided]`（慣例單一來源）。
    /// **rests-on 可帶**：查過未決的配對沒有被判實體能承認那份證據，唯一的落點是這筆記錄本身（#280 注記的改寫）。
    /// digest 形狀由呼叫端先以 `ProvenanceReference` 的平面 init 驗（單一驗證入口）。
    public static func record(undecided holderKind: ProvenanceReference.VerdictHolderKind,
                              holder: String, literal: String,
                              statement: String, restsOn: [String]) -> ProvenanceReference {
        ProvenanceReference(
            field: VerdictKind.undecided.rawValue,
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: holderKind, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "\(statement) [rule: \(undecidedRule)]", restsOn: restsOn))
    }

    /// 寫入邊界的冪等：同 (field, value) 的 verdict 已在 → 不重複附加（verify
    /// DA (d) 第 1 步——**這個寫入面**不製造重複，計數就能誠實地數原始 refs）。store 仍可能持有同鍵的重複：手改、舊 binary，
    /// 或 rename 自 D62 起原樣帶過來的（它只折整筆相等的）——那個狀態由 `StoreHealth.duplicateVerdictRecords` 報（#554 R23，D64）。
    /// 回傳是否真的附加了。
    ///
    /// **`allowCoexistence`**（change `resolution-verdict-states`，R1 verify regression）：false 時，同一配對同一 field 已有
    /// **另一個判定層級**的記錄就不寫（回 false）——那是 format 18 的既有語意（舊鍵把兩層級當同一筆）。寫入面在
    /// store format < 19 時傳 false：否則 apply／reject／accept／attribute-org 會在 entry 已寫入之後才被
    /// `assertVerdictShapesWritable` 擋下，留下一個已歸戶卻沒有 verdict 的作者位。
    @discardableResult
    public static func appendIfAbsent(_ ref: ProvenanceReference,
                                      to references: inout [ProvenanceReference],
                                      allowCoexistence: Bool = true) -> Bool {
        if !allowCoexistence, let cls = ref.verdictClass {
            let k = ProvenanceReference.verdictEqualityKey(field: ref.field, value: ref.value)
            if references.contains(where: {
                $0.verdictClass.map { $0 != cls } == true
                    && ProvenanceReference.verdictEqualityKey(field: $0.field, value: $0.value) == k
            }) { return false }
        }
        // #470：相等取正規化（與 merge／rename 的寫入面、以及讀取面的 rejectedNorm 同一個
        // 定義）。在此之前這裡比位元組，於是一個只差空白的重複判定會被寫進去。
        // change `resolution-verdict-states`：去重用**記錄鍵**——confirmed／rejected 帶判定層級（nominated 與 judged 並存，
        // #636），未決比整筆位元組（同一配對的多次查證都留，#619）。同層級內仍是 #470 的正規化相等。
        let key = ref.verdictRecordKey
        guard !references.contains(where: { $0.verdictRecordKey == key }) else { return false }
        references.append(ref)
        return true
    }

    /// **寫入一筆判定，並退役同一份 references 裡對同一配對的相反判定**（#554 R8 verify 第 9／12 列，D20）。
    ///
    /// `repoint`／`demote` 寫 rejected 時，那個配對的 confirmed 還留在同一個 holder 上——兩條各自合法，
    /// 合起來是 #486 的「矛盾 verdict」warning，而它的唯一處置「刪掉另一個」沒有工具面。verdict 沒有時間戳，
    /// 讀端判不出哪條是後來的；只有寫入面知道自己是新的，所以退役在這裡做。相等用 `verdictEqualityKey`
    /// 把 field 換成相反那個——與 `appendIfAbsent`、#486 的掃描同一個正規化（#470）。回傳附加了沒有、退役了幾筆。
    /// 歷史留在 git（同 un-split 刪拆分記錄的既有取捨）。**只對 verdict 欄位對有意義**——非 verdict 的 reference
    /// 沒有「相反」，走 `appendIfAbsent` 就好；這裡對它們等價於 `appendIfAbsent`（退役 0 筆）。
    ///
    /// **退役的每一筆逐字回傳**（R9 verify security 第 4 列、DA 第 29 列）：被刪的是人的判斷記錄——#553 合併會把被併
    /// venue 的顯式 `--reject` 以位元組相等搬進 keeper，日後一次 repoint 就會退役它，而被併檔已不在，唯一副本只剩 git；
    /// 只回一個整數會讓「從未判定」與「判過、被這次刪了」在輸出上不可區分（`lossless-intake` 執行細節 3）。
    ///
    /// **前提：這個配對只由一條邊實例化**（D25，R9 verify 六路命中）：verdict 不帶 venue index，同一 work 兩條邊指同一
    /// venue 時只有一筆 confirmed——退役它會讓另一條邊在任何工具面上都救不回來，而且 #486 的矛盾 warning 也一起消失。
    /// 本函式不查 entry，呼叫端（`repointVenues`／`demoteVenues`）在呼叫前用 `assertPairingHasOneEdge` 擋。
    @discardableResult
    public static func supersede(_ ref: ProvenanceReference,
                                 in references: inout [ProvenanceReference]) -> (appended: Bool, retired: [ProvenanceReference]) {
        var retired: [ProvenanceReference] = []
        // 相反判定的兩個層級一起退役（`verdictEqualityKey` 不含層級）；未決沒有相反、也不被退役（它是查證歷史）。
        if let kind = VerdictKind(rawValue: ref.field), let opposite = kind.opposite {
            let oppositeKey = ProvenanceReference.verdictEqualityKey(field: opposite.rawValue, value: ref.value)
            retired = references.filter {
                ProvenanceReference.verdictEqualityKey(field: $0.field, value: $0.value) == oppositeKey
            }
            references.removeAll {
                ProvenanceReference.verdictEqualityKey(field: $0.field, value: $0.value) == oppositeKey
            }
        }
        return (appendIfAbsent(ref, to: &references), retired)
    }

    // MARK: - 讀端（唯一解析器）

    /// 從一份 references 解析 verdict。非 verdict 欄位完全忽略（不算 malformed）；
    /// verdict 欄位但 value 解析不了 → **loud** 進 `malformed`，不靜默丟
    /// （lossless-intake 的「丟棄必須可見」在讀端的對應）。store 閘已在寫入邊界
    /// 拒收 malformed，這裡是縱深防禦（手改檔、他庫匯入）。
    public static func verdicts(references: [ProvenanceReference])
        -> (verdicts: [Verdict], malformed: [String]) {
        var out: [Verdict] = []
        var malformed: [String] = []
        for r in references {
            guard let kind = VerdictKind(rawValue: r.field) else { continue }
            guard let value = r.value,
                  let pairing = ProvenanceReference.VerdictPairingValue.parse(value) else {
                malformed.append(
                    "verdict reference（field: \(r.field)）的 value 無法定位配對"
                    + "（需「<kind>:<key> :: <literal>」）：「\(r.value ?? "<nil>")」")
                continue
            }
            guard case .judgement(let statement, let restsOn) = r.kind else {
                malformed.append("verdict reference（field: \(r.field)）不是 judgement 型")
                continue
            }
            // 尾註缺席時依 holderKind 計入該族的預設 rule——族別在 value 裡，
            // 不靠「掛在哪種記錄上」的脈絡推斷
            let familyDefault = pairing.holderKind == .work ? personRule : orgRule
            out.append(Verdict(
                kind: kind,
                holderKind: pairing.holderKind,
                holder: pairing.holder,
                literal: pairing.literal,
                rule: ruleTail(of: statement) ?? familyDefault,
                statement: statement,
                restsOn: restsOn))
        }
        return (out, malformed)
    }

    /// statement 尾註 `[rule: <name>]` 的 tolerant 解析——缺席回 nil（呼叫端補預設）。
    private static func ruleTail(of statement: String) -> String? {
        ProvenanceReference.ruleTail(ofStatement: statement)   // #468：解析住 AkashicCore，兩個 module 共用
    }

    // MARK: - 衍生（derived, never stored）

    /// 已否決配對的集合——resolver 的跳過輸入（design D5：恰跳同配對）。
    public static func rejectedPairings(people: [Person]) -> Set<ResolutionPairing> {
        var set = Set<ResolutionPairing>()
        for p in people {
            for v in verdicts(references: p.references).verdicts where v.kind == .rejected {
                set.insert(ResolutionPairing(holderKind: v.holderKind, holder: v.holder,
                                             literal: v.literal, judgedKey: p.key))
            }
        }
        return set
    }

    /// 已確認配對的集合（#303 design D3，`rejectedPairings` 的鏡像）——
    /// resolver 的 `confirmedElsewhere` tier 資料源：同 literal 已在他處判給某人，
    /// 別的 entry 的同字串值得以該知識提名。**只提名不 apply**，且不寫 alias——
    /// verdict 的 value 文法本身就記著配對，比 variant alias 多了 provenance。
    /// 回傳「配對 → 來源 rule」（R2-fix R3-7）：confirmed verdict 餵提名層時，
    /// 弱血統（initials／reorder 判定寫下的 confirmed）要在提名 reason 可見——
    /// 照餵（人確認過的配對就是確認）但不隱藏出身。同配對重複 verdict 在寫入
    /// 邊界已被 `appendIfAbsent` 擋掉，實務上 rule 唯一；極端情形取後者。
    public static func confirmedPairings(people: [Person]) -> [ResolutionPairing: String] {
        var out: [ResolutionPairing: String] = [:]
        for p in people {
            for v in verdicts(references: p.references).verdicts where v.kind == .confirmed {
                let key = ResolutionPairing(holderKind: v.holderKind, holder: v.holder,
                                            literal: v.literal, judgedKey: p.key)
                // #636 起同一配對可並存兩筆（nominated 與 judged）。取哪一筆的 rule 餵提名理由：exact 優先
                // （PersonResolver 對 exact 不加血統註記——它本來就是最強的名字證據），其次 judged（有理由的逐篇判定），
                // 最後才是其餘的弱血統。與序列化順序無關（R1 verify logic／regression：先前 judged 優先，一筆 exact 的
                // apply 加上後來的 judge 反而讓提名理由多出一個弱血統註記）。
                if let seen = out[key], lineageRank(seen) <= lineageRank(v.rule) { continue }
                out[key] = v.rule
            }
        }
        return out
    }

    /// organization 族的已否決配對（task 3.2——family 一次涵蓋）。
    public static func rejectedPairings(organizations: [Organization]) -> Set<ResolutionPairing> {
        var set = Set<ResolutionPairing>()
        for o in organizations {
            for v in verdicts(references: o.references).verdicts where v.kind == .rejected {
                set.insert(ResolutionPairing(holderKind: v.holderKind, holder: v.holder,
                                             literal: v.literal, judgedKey: o.key))
            }
        }
        return set
    }

    /// venue 族的已否決配對（#304——family 第三員，同構）。
    public static func rejectedPairings(venues: [Venue]) -> Set<ResolutionPairing> {
        var set = Set<ResolutionPairing>()
        for v in venues {
            for verdict in verdicts(references: v.references).verdicts where verdict.kind == .rejected {
                set.insert(ResolutionPairing(holderKind: verdict.holderKind, holder: verdict.holder,
                                             literal: verdict.literal, judgedKey: v.key))
            }
        }
        return set
    }

    /// 全庫 malformed verdict 的彙整（呈現面消費——lossless-intake：丟棄必須可見）。
    public static func malformedVerdicts(people: [Person],
                                         organizations: [Organization] = []) -> [String] {
        var out: [String] = []
        for p in people {
            for m in verdicts(references: p.references).malformed {
                out.append("person \(p.key)：\(m)")
            }
        }
        for o in organizations {
            for m in verdicts(references: o.references).malformed {
                out.append("organization \(o.key)：\(m)")
            }
        }
        return out
    }

    /// 四態計數（per rule；spec「Calibration counts SHALL be derived, never stored」；change `resolution-verdict-states` 起多 undecided）。
    ///
    /// - confirmed／rejected：**數原始 refs**（歷史全量）。寫入邊界已冪等
    ///   （`appendIfAbsent` + service 端 rowID 去重），所以殘存的重複是**症狀**，
    ///   讓它顯形而不是在計數層抹平（verify DA (d)：unique-counting 會把懸空
    ///   外鍵的雙重計數一起藏掉）。
    /// - pending：`candidatePairings` 中**無任何 verdict** 者——「還沒查」與
    ///   「查過了不是他」由 verdict 存在與否區分（spec「Rejection SHALL be
    ///   distinct from absence」），pending 歸入該族的預設 rule。
    /// pending 依**每個候選自己的 rule** 分桶（#303 R1-fix B2）——四 tier 的
    /// 待判量各自可見，不混進 exact 的校準史。
    public static func counts(people: [Person],
                              candidates: [(pairing: ResolutionPairing, rule: String)])
        -> [String: Counts] {
        countsCore(judged: people.map { ($0.key, $0.references) },
                   candidates: candidates)
    }

    /// organization 族的四態計數——同一個 core，只換被判定的記錄集合與 pending 歸屬。
    public static func counts(organizations: [Organization],
                              candidatePairings: [ResolutionPairing])
        -> [String: Counts] {
        countsCore(judged: organizations.map { ($0.key, $0.references) },
                   candidates: candidatePairings.map { ($0, orgRule) })
    }

    /// 四態計數（change `resolution-verdict-states`）。confirmed／rejected 數原始 refs、依 rule 分桶；undecided 與 pending
    /// 以**候選配對**為單位、依候選自己的 rule 分桶——查過未決的配對不再算進 pending（#619：讀進度的人會高估未處理量）。
    public typealias Counts = (confirmed: Int, rejected: Int, undecided: Int, pending: Int)

    private static func countsCore(judged sets: [(key: String, references: [ProvenanceReference])],
                                   candidates: [(pairing: ResolutionPairing, rule: String)])
        -> [String: Counts] {
        var result: [String: Counts] = [:]
        var decided = Set<ResolutionPairing>()
        var checked = Set<ResolutionPairing>()
        for s in sets {
            for v in verdicts(references: s.references).verdicts {
                // 狀態推導用正規化配對（`statePairing`，R1 verify）
                let pairing = statePairing(ResolutionPairing(holderKind: v.holderKind, holder: v.holder,
                                                             literal: v.literal, judgedKey: s.key))
                var entry = result[v.rule] ?? (0, 0, 0, 0)
                switch v.kind {
                case .confirmed: entry.confirmed += 1
                case .rejected: entry.rejected += 1
                case .undecided:
                    // 未決不是判定：不開 rule 桶（它的 rule 是尾註，不是證據類別），只標記配對被查過
                    checked.insert(pairing)
                    continue
                }
                result[v.rule] = entry
                decided.insert(pairing)
            }
        }
        // undecided／pending 以**配對**為單位（spec「count candidate pairings」）：同一筆 work 兩個作者位同一 literal
        // 同一人時是兩列候選、一個配對——先前逐列數，一筆未決記錄會計兩次（R1 verify Codex）。一個配對出現在多個 rule
        // 下時，計入第一個出現的 rule（候選依信心降冪排序，所以是最強的那一層）。
        var counted = Set<ResolutionPairing>()
        for (raw, rule) in candidates {
            let c = statePairing(raw)
            guard !decided.contains(c), counted.insert(c).inserted else { continue }
            var entry = result[rule] ?? (0, 0, 0, 0)
            if checked.contains(c) { entry.undecided += 1 } else { entry.pending += 1 }
            result[rule] = entry
        }
        return result
    }

    /// 配對狀態（spec「A pairing's state SHALL be derived as decided, undecided, or pending」）與它的未決記錄數。
    /// 只回有 verdict 的配對；不在表裡的就是 `pending`。
    ///
    /// **鍵是正規化的配對**（`statePairing`，literal 取 `matchingKey`）——與 spec 的配對鍵、與寫入端 `pairingIsDecided`
    /// 用的 `verdictPairingKey` 同一把正規化（R1 verify logic／requirements：先前讀取端比位元組、寫入端比正規化，
    /// 只差空白的兩筆在兩端答案不同）。查詢用 `undecidedChecks(in:holderKind:holder:literal:judgedKey:)`。
    public static func pairingStates(references: [ProvenanceReference], judgedKey: String)
        -> [ResolutionPairing: (state: PairingState, undecidedChecks: Int)] {
        var out: [ResolutionPairing: (state: PairingState, undecidedChecks: Int)] = [:]
        for v in verdicts(references: references).verdicts {
            let p = statePairing(ResolutionPairing(holderKind: v.holderKind, holder: v.holder,
                                                   literal: v.literal, judgedKey: judgedKey))
            var cur = out[p] ?? (.undecided, 0)
            if v.kind == .undecided { cur.undecidedChecks += 1 } else { cur.state = .decided }
            out[p] = cur
        }
        return out
    }

    /// 仍是 `undecided` 狀態的配對 → 未決記錄數（提名列表的「查過未決 N 次」）。
    public static func undecidedChecks(holders: [(key: String, references: [ProvenanceReference])])
        -> [ResolutionPairing: Int] {
        var out: [ResolutionPairing: Int] = [:]
        for h in holders {
            for (p, s) in pairingStates(references: h.references, judgedKey: h.key) where s.state == .undecided {
                out[p] = s.undecidedChecks
            }
        }
        return out
    }

    /// 狀態推導用的配對：literal 換成 `NameNormalization.matchingKey`（與 `verdictPairingKey` 同一把正規化）。
    public static func statePairing(_ p: ResolutionPairing) -> ResolutionPairing {
        ResolutionPairing(holderKind: p.holderKind, holder: p.holder,
                          literal: NameNormalization.matchingKey(p.literal), judgedKey: p.judgedKey)
    }

    /// `undecidedChecks(holders:)` 的查詢：以正規化配對查，缺席＝0。
    public static func undecidedChecks(in map: [ResolutionPairing: Int],
                                       holderKind: ProvenanceReference.VerdictHolderKind = .work,
                                       holder: String, literal: String, judgedKey: String) -> Int {
        map[statePairing(ResolutionPairing(holderKind: holderKind, holder: holder,
                                           literal: literal, judgedKey: judgedKey))] ?? 0
    }

    /// 提名理由的血統排序：exact（0）＜ judged（1）＜ 其餘（2）。數字小者勝。
    static func lineageRank(_ rule: String) -> Int {
        if ProvenanceReference.RuleName.exact.contains(rule) { return 0 }
        return ProvenanceReference.verdictClass(rule: rule) == .judged ? 1 : 2
    }

    // MARK: - 沉底列（design D7「order without hiding」的唯一來源）

    /// person 族沉底列：仍在觀測中的已否決配對。**同 literal 的每個作者位置各一列**
    /// （verify C-4：配對鍵不含位置——同 entry 同 literal 的多個位置是同一個命題，
    /// 一筆否決同時抑制它們，呈現就得把每個被抑制的位置都列出來）。literal 已從
    /// entry 移除的 stale 否決不列——不是候選就無處沉；ledger 仍記得，計數照算。
    public struct ObservedRejection: Equatable {
        public let citekey: String
        public let authorIndex: Int
        public let literal: String
        public let judgedKey: String
        public let rule: String
    }

    public static func observedRejections(people: [Person],
                                          entries: [Entry]) -> [ObservedRejection] {
        let byCitekey = Dictionary(entries.map { ($0.citekey, $0) },
                                   uniquingKeysWith: { a, _ in a })
        var out: [ObservedRejection] = []
        for p in people {
            for v in verdicts(references: p.references).verdicts
            where v.kind == .rejected && v.holderKind == .work {
                guard let e = byCitekey[v.holder] else { continue }
                for (i, author) in e.authors.enumerated()
                where author == .literal(v.literal) {
                    out.append(ObservedRejection(citekey: v.holder, authorIndex: i,
                                                 literal: v.literal, judgedKey: p.key,
                                                 rule: v.rule))
                }
            }
        }
        return out.sorted {
            ($0.citekey, $0.literal, $0.judgedKey, $0.authorIndex)
                < ($1.citekey, $1.literal, $1.judgedKey, $1.authorIndex)
        }
    }

    /// organization 族沉底列。holder 的 kind 來自 value 的 kind token（verify C-3
    /// ——不再「先猜 person」：同名 person／org 各自的配對各自呈現）。
    public struct ObservedOrgRejection: Equatable {
        public let holderKind: ProvenanceReference.VerdictHolderKind
        public let holder: String
        public let literal: String
        public let judgedKey: String
        public let rule: String
    }

    public static func observedRejections(organizations: [Organization],
                                          people: [Person]) -> [ObservedOrgRejection] {
        let pByKey = Dictionary(people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let oByKey = Dictionary(organizations.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func holdsLiteral(_ segs: [TemporalValue<OrgRef>], _ literal: String) -> Bool {
            segs.contains { if case .literal(let l) = $0.value { return l == literal }
                            return false }
        }
        var out: [ObservedOrgRejection] = []
        for o in organizations {
            for v in verdicts(references: o.references).verdicts where v.kind == .rejected {
                let observed: Bool
                switch v.holderKind {
                case .person:
                    observed = pByKey[v.holder].map {
                        holdsLiteral($0.profile.affiliations.entries, v.literal) } ?? false
                case .org:
                    observed = oByKey[v.holder].map {
                        holdsLiteral($0.parents.entries, v.literal) } ?? false
                case .work:
                    observed = false   // work-holder verdict 不屬 org 族——不呈現
                }
                guard observed else { continue }
                out.append(ObservedOrgRejection(holderKind: v.holderKind, holder: v.holder,
                                                literal: v.literal, judgedKey: o.key,
                                                rule: v.rule))
            }
        }
        return out.sorted {
            ($0.holderKind.rawValue, $0.holder, $0.literal, $0.judgedKey)
                < ($1.holderKind.rawValue, $1.holder, $1.literal, $1.judgedKey)
        }
    }
}

/// 一個被判定（或待判定）的配對——(holder 的 kind, literal 所在記錄, literal,
/// 被判定的 record key)。kind 屬於配對身分：person 與 org 的 key 可合法同名（#166）。
public struct ResolutionPairing: Hashable {
    public let holderKind: ProvenanceReference.VerdictHolderKind
    public let holder: String
    public let literal: String
    public let judgedKey: String

    public init(holderKind: ProvenanceReference.VerdictHolderKind,
                holder: String, literal: String, judgedKey: String) {
        self.holderKind = holderKind
        self.holder = holder
        self.literal = literal
        self.judgedKey = judgedKey
    }
}
