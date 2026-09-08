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
    public static let personRule = "author-name-exact"

    /// organization 族的證據類別（「org name 完全命中且不歧義」）。與 person 族
    /// **分開命名**（verify REG-7）：兩條規則的校準歷史本來就該分開計。
    public static let orgRule = "org-name-exact"

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
    public static let venueRule = "venue-name-exact"

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
    public static let judgedRule = "author-judged-per-work"

    /// 判定種類——與 verdict 欄位對一一對應。
    public enum VerdictKind: String, CaseIterable {
        case confirmed = "resolution-confirmed"
        case rejected = "resolution-rejected"
    }

    /// 解析出的一筆判定（掛在哪個 record 上由呼叫端知道，故不含 judgedKey）。
    public struct Verdict: Equatable {
        public let kind: VerdictKind
        public let holderKind: ProvenanceReference.VerdictHolderKind
        public let holder: String
        public let literal: String
        public let rule: String
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

    /// 寫入邊界的冪等：同 (field, value) 的 verdict 已在 → 不重複附加（verify
    /// DA (d) 第 1 步——store 永遠不持有重複，計數就能誠實地數原始 refs）。
    /// 回傳是否真的附加了。
    @discardableResult
    public static func appendIfAbsent(_ ref: ProvenanceReference,
                                      to references: inout [ProvenanceReference]) -> Bool {
        // #470：相等取正規化（與 merge／rename 的寫入面、以及讀取面的 rejectedNorm 同一個
        // 定義）。在此之前這裡比位元組，於是一個只差空白的重複判定會被寫進去。
        let key = ProvenanceReference.verdictEqualityKey(field: ref.field, value: ref.value)
        guard !references.contains(where: {
            ProvenanceReference.verdictEqualityKey(field: $0.field, value: $0.value) == key
        }) else { return false }
        references.append(ref)
        return true
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
            guard case .judgement(let statement, _) = r.kind else {
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
                rule: ruleTail(of: statement) ?? familyDefault))
        }
        return (out, malformed)
    }

    /// statement 尾註 `[rule: <name>]` 的 tolerant 解析——缺席回 nil（呼叫端補預設）。
    private static func ruleTail(of statement: String) -> String? {
        guard statement.hasSuffix("]"),
              let open = statement.range(of: "[rule: ", options: .backwards) else { return nil }
        let inner = statement[open.upperBound..<statement.index(before: statement.endIndex)]
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
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
                out[ResolutionPairing(holderKind: v.holderKind, holder: v.holder,
                                      literal: v.literal, judgedKey: p.key)] = v.rule
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

    /// 三態計數（per rule；spec「Calibration counts SHALL be derived, never stored」）。
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
        -> [String: (confirmed: Int, rejected: Int, pending: Int)] {
        countsCore(judged: people.map { ($0.key, $0.references) },
                   candidates: candidates)
    }

    /// organization 族的三態計數——同一個 core，只換被判定的記錄集合與 pending 歸屬。
    public static func counts(organizations: [Organization],
                              candidatePairings: [ResolutionPairing])
        -> [String: (confirmed: Int, rejected: Int, pending: Int)] {
        countsCore(judged: organizations.map { ($0.key, $0.references) },
                   candidates: candidatePairings.map { ($0, orgRule) })
    }

    private static func countsCore(judged sets: [(key: String, references: [ProvenanceReference])],
                                   candidates: [(pairing: ResolutionPairing, rule: String)])
        -> [String: (confirmed: Int, rejected: Int, pending: Int)] {
        var result: [String: (confirmed: Int, rejected: Int, pending: Int)] = [:]
        var judged = Set<ResolutionPairing>()
        for s in sets {
            for v in verdicts(references: s.references).verdicts {
                var entry = result[v.rule] ?? (0, 0, 0)
                switch v.kind {
                case .confirmed: entry.confirmed += 1
                case .rejected: entry.rejected += 1
                }
                result[v.rule] = entry
                judged.insert(ResolutionPairing(holderKind: v.holderKind, holder: v.holder,
                                                literal: v.literal, judgedKey: s.key))
            }
        }
        for (c, rule) in candidates where !judged.contains(c) {
            var entry = result[rule] ?? (0, 0, 0)
            entry.pending += 1
            result[rule] = entry
        }
        return result
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
