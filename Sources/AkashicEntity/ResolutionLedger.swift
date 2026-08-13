import Foundation
import AkashicCore

/// #232：消解判定的**唯一**讀寫封裝點（design D4）。
///
/// verdict 以既有 `ProvenanceReference` 承載（零 format bump）：
/// - `field`：封閉對 `resolution-confirmed`／`resolution-rejected`
///   （單一來源在 `ProvenanceReference.resolutionVerdictFields`）
/// - `value`：配對定位 `<holder> :: <literal>`（design D2）——holder 是 literal
///   所在的記錄：person-resolution 是 entry citekey、org-resolution 是持有
///   affiliations／parents 的 person／organization key
/// - `statement`：人話 + 尾註 `[rule: <name>]`（design D3——typed slot 被 #247
///   擋住的 v1 妥協；tolerant parse、缺席計入今日唯一合法值）
///
/// value／rule 的 encode 與 decode 只住這裡——慣例改動不外溢（deletion test：
/// 沒有它 = 重複提名回歸 + 計數無來源 + 慣例散落三處）。
public enum ResolutionLedger {

    /// 今日唯一的證據類別（resolver 的「完全命中且不歧義」規則）。
    public static let defaultRule = "author-name-exact"

    private static let separator = " :: "

    /// 判定種類——與 verdict 欄位對一一對應。
    public enum VerdictKind: String, CaseIterable {
        case confirmed = "resolution-confirmed"
        case rejected = "resolution-rejected"
    }

    /// 解析出的一筆判定（掛在哪個 record 上由呼叫端知道，故不含 judgedKey）。
    public struct Verdict: Equatable {
        public let kind: VerdictKind
        public let holder: String
        public let literal: String
        public let rule: String
    }

    // MARK: - 寫端（唯一產生器）

    /// 產生一筆 verdict reference。statement 收人話，尾註由本函式補——
    /// 呼叫端不自行拼 `[rule:]`（慣例單一來源）。
    public static func record(_ kind: VerdictKind, holder: String, literal: String,
                              rule: String, statement: String) -> ProvenanceReference {
        ProvenanceReference(
            field: kind.rawValue,
            value: "\(holder)\(separator)\(literal)",
            kind: .judgement(statement: "\(statement) [rule: \(rule)]", restsOn: []))
    }

    // MARK: - 讀端（唯一解析器）

    /// 從一份 references 解析 verdict。非 verdict 欄位完全忽略（不算 malformed）；
    /// verdict 欄位但 value 缺席／缺分隔符 → **loud** 進 `malformed`，不靜默丟
    /// （lossless-intake 的「丟棄必須可見」在讀端的對應）。
    public static func verdicts(references: [ProvenanceReference])
        -> (verdicts: [Verdict], malformed: [String]) {
        var out: [Verdict] = []
        var malformed: [String] = []
        for r in references {
            guard let kind = VerdictKind(rawValue: r.field) else { continue }
            guard let value = r.value, let range = value.range(of: separator) else {
                malformed.append(
                    "verdict reference（field: \(r.field)）的 value 無法定位配對"
                    + "（缺「\(separator)」分隔）：「\(r.value ?? "<nil>")」")
                continue
            }
            guard case .judgement(let statement, _) = r.kind else {
                malformed.append("verdict reference（field: \(r.field)）不是 judgement 型")
                continue
            }
            out.append(Verdict(
                kind: kind,
                holder: String(value[..<range.lowerBound]),
                literal: String(value[range.upperBound...]),
                rule: ruleTail(of: statement) ?? defaultRule))
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
                set.insert(ResolutionPairing(holder: v.holder, literal: v.literal,
                                             judgedKey: p.key))
            }
        }
        return set
    }

    /// organization 族的已否決配對（task 3.2——family 一次涵蓋）。
    public static func rejectedPairings(organizations: [Organization]) -> Set<ResolutionPairing> {
        var set = Set<ResolutionPairing>()
        for o in organizations {
            for v in verdicts(references: o.references).verdicts where v.kind == .rejected {
                set.insert(ResolutionPairing(holder: v.holder, literal: v.literal,
                                             judgedKey: o.key))
            }
        }
        return set
    }

    /// 三態計數（per rule；spec「Calibration counts SHALL be derived, never stored」）。
    ///
    /// - confirmed／rejected：從 references 現算（歷史全量）
    /// - pending：`candidatePairings` 中**無任何 verdict** 者——「還沒查」與
    ///   「查過了不是他」由 verdict 存在與否區分（spec「Rejection SHALL be
    ///   distinct from absence」），pending 歸入該候選所屬 rule（v1 全部
    ///   `defaultRule`——今日唯一證據類別）
    public static func counts(people: [Person],
                              candidatePairings: [ResolutionPairing])
        -> [String: (confirmed: Int, rejected: Int, pending: Int)] {
        countsCore(judged: people.map { ($0.key, $0.references) },
                   candidatePairings: candidatePairings)
    }

    /// organization 族的三態計數——同一個 core，只換被判定的記錄集合。
    public static func counts(organizations: [Organization],
                              candidatePairings: [ResolutionPairing])
        -> [String: (confirmed: Int, rejected: Int, pending: Int)] {
        countsCore(judged: organizations.map { ($0.key, $0.references) },
                   candidatePairings: candidatePairings)
    }

    private static func countsCore(judged sets: [(key: String, references: [ProvenanceReference])],
                                   candidatePairings: [ResolutionPairing])
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
                judged.insert(ResolutionPairing(holder: v.holder, literal: v.literal,
                                                judgedKey: s.key))
            }
        }
        for c in candidatePairings where !judged.contains(c) {
            var entry = result[defaultRule] ?? (0, 0, 0)
            entry.pending += 1
            result[defaultRule] = entry
        }
        return result
    }

    // MARK: - 沉底列（design D7「order without hiding」的唯一來源）

    /// person 族沉底列：仍在觀測中的已否決配對。literal 已從 entry 移除的 stale
    /// 否決不列——不是候選就無處沉；ledger 仍記得，計數照算。
    public struct ObservedRejection: Equatable {
        public let citekey: String
        public let authorIndex: Int
        public let literal: String
        public let judgedKey: String
    }

    public static func observedRejections(pairings: Set<ResolutionPairing>,
                                          entries: [Entry]) -> [ObservedRejection] {
        let byCitekey = Dictionary(entries.map { ($0.citekey, $0) },
                                   uniquingKeysWith: { a, _ in a })
        return pairings
            .sorted { ($0.holder, $0.literal, $0.judgedKey) < ($1.holder, $1.literal, $1.judgedKey) }
            .compactMap { p in
                guard let e = byCitekey[p.holder],
                      let i = e.authors.firstIndex(of: .literal(p.literal)) else { return nil }
                return ObservedRejection(citekey: p.holder, authorIndex: i,
                                         literal: p.literal, judgedKey: p.judgedKey)
            }
    }

    /// organization 族沉底列。holder 可能是 person（affiliations）或 organization
    /// （parents）——兩個命名空間可同名（#166），所以要標 kind。
    public struct ObservedOrgRejection: Equatable {
        public let holderIsPerson: Bool
        public let holder: String
        public let literal: String
        public let judgedKey: String
    }

    public static func observedRejections(pairings: Set<ResolutionPairing>,
                                          people: [Person],
                                          organizations: [Organization]) -> [ObservedOrgRejection] {
        let pByKey = Dictionary(people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let oByKey = Dictionary(organizations.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func holdsLiteral(_ segs: [TemporalValue<OrgRef>], _ literal: String) -> Bool {
            segs.contains { if case .literal(let l) = $0.value { return l == literal }
                            return false }
        }
        return pairings
            .sorted { ($0.holder, $0.literal, $0.judgedKey) < ($1.holder, $1.literal, $1.judgedKey) }
            .compactMap { p in
                if let person = pByKey[p.holder],
                   holdsLiteral(person.profile.affiliations.entries, p.literal) {
                    return ObservedOrgRejection(holderIsPerson: true, holder: p.holder,
                                                literal: p.literal, judgedKey: p.judgedKey)
                }
                if let org = oByKey[p.holder],
                   holdsLiteral(org.parents.entries, p.literal) {
                    return ObservedOrgRejection(holderIsPerson: false, holder: p.holder,
                                                literal: p.literal, judgedKey: p.judgedKey)
                }
                return nil
            }
    }
}

/// 一個被判定（或待判定）的配對——(literal 所在記錄, literal, 被判定的 record key)。
public struct ResolutionPairing: Hashable {
    public let holder: String
    public let literal: String
    public let judgedKey: String

    public init(holder: String, literal: String, judgedKey: String) {
        self.holder = holder
        self.literal = literal
        self.judgedKey = judgedKey
    }
}
