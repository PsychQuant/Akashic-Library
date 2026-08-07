import Foundation
import AkashicCore

/// 機構解析原語（#70 第二題）——org 版的 `PersonResolver`。
///
/// 「從未見過的字串認出屬於哪個 org」的入口。與 person 側同鐵律：**只提名，
/// 絕不自動歸戶**——`candidates` 出候選、`apply` 是使用者顯式確認後的第二步。
/// 比對走 `NameNormalization.matchingKey`（#81，統一連字號家族／NFKC／Cf 剝除／
/// 空白收斂），命中且不歧義才提名；同鍵對到 2+ 個 org＝歧義，整組排除。
public struct OrgResolutionCandidate: Equatable {
    /// 哪個 person 的哪一段 affiliation（用**值**定位，不用索引——段可能重排）。
    public var personKey: String
    public var literal: String
    public var orgKey: String
    public var reason: String

    public init(personKey: String, literal: String, orgKey: String, reason: String) {
        self.personKey = personKey
        self.literal = literal
        self.orgKey = orgKey
        self.reason = reason
    }
}

public enum OrgResolver {
    /// 高信心候選：person 的 affiliation literal 與某 org 的 name variant 正規化後
    /// 完全命中、且不歧義。
    public static func candidates(people: [Person],
                                  organizations: [Organization]) -> [OrgResolutionCandidate] {
        // 正規化 org name variant → org keys（同名對 2+ org＝歧義，整組排除）
        var nameMap: [String: Set<String>] = [:]
        for org in organizations {
            for seg in org.names.entries {
                nameMap[NameNormalization.matchingKey(seg.value), default: []].insert(org.key)
            }
        }

        var result: [OrgResolutionCandidate] = []
        for person in people.sorted(by: { $0.key < $1.key }) {
            for seg in person.profile.affiliations.entries {
                guard case let .literal(literal) = seg.value else { continue }
                guard let keys = nameMap[NameNormalization.matchingKey(literal)],
                      keys.count == 1, let key = keys.first else { continue }
                result.append(OrgResolutionCandidate(
                    personKey: person.key, literal: literal, orgKey: key,
                    reason: "org name 完全命中"))
            }
        }
        return result
    }

    /// 把已確認的候選套用到 people（回傳新副本，不動原陣列）。
    /// **只改真的還是那個 literal 的段**（值比對；段被改過就跳過——避免套用
    /// 一份過期的候選）。
    public static func apply(_ candidates: [OrgResolutionCandidate],
                             to people: [Person]) -> [Person] {
        var byKey = Dictionary(people.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        for c in candidates {
            guard var person = byKey[c.personKey] else { continue }
            var changed = false
            let migrated = person.profile.affiliations.entries.map { seg -> TemporalValue<OrgRef> in
                if case let .literal(s) = seg.value, s == c.literal {
                    changed = true
                    return TemporalValue(value: .key(c.orgKey), range: seg.range,
                                         source: seg.source, note: seg.note)
                }
                return seg
            }
            if changed {
                person.profile.affiliations = TimelineOf(migrated)
                byKey[c.personKey] = person
            }
        }
        return people.map { byKey[$0.key] ?? $0 }
    }
}
