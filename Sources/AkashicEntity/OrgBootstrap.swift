import Foundation
import AkashicCore

/// 從 literal 機構名 bootstrap organization 記錄（#70 第三題）。
///
/// 平移 `PersonBootstrap` 的機制到機構面。literal 機構名散落在兩處：
/// `person.profile.affiliations` 的 `.literal` OrgRef、`organization.parents` 的
/// `.literal`。這裡把它們按正規化分組、按門檻建 organization entity——低於門檻的
/// 留 `.literal`（`OrgRef.literal` 本來就是「未歸戶是合法長期狀態」的設計，§8）。
///
/// **同 person 側的鐵律**：只建立、不歸戶（歸戶是 `resolve-organizations` 的第二步、
/// 交人確認）。正規化只住配對鍵（`NameNormalization.matchingKey`，#81），輸出的
/// `names` 是原字串——「中央研究院」「中研院」「Academia Sinica」各自保留寫法為
/// variant，否則下次遇到那個寫法又重新分割一次。
public enum OrgBootstrap {

    public struct Candidate: Equatable {
        public var key: String
        public var names: [String]
        public var occurrences: Int
        public init(key: String, names: [String], occurrences: Int) {
            self.key = key
            self.names = names
            self.occurrences = occurrences
        }
    }

    /// 全部 literal 機構名的來源走訪（person affiliations + org parents）。
    private static func literalOrgNames(people: [Person],
                                        organizations: [Organization]) -> [String] {
        var out: [String] = []
        for p in people {
            for seg in p.profile.affiliations.entries {
                if case let .literal(s) = seg.value { out.append(s) }
            }
        }
        for o in organizations {
            for seg in o.parents.entries {
                if case let .literal(s) = seg.value { out.append(s) }
            }
        }
        return out
    }

    /// 從 literal 機構名產出候選。已存在的 organization（其 `names` variant）不重複產出。
    public static func candidates(people: [Person],
                                  organizations: [Organization]) -> [Candidate] {
        // 既有 org 的所有寫法（正規化）——已在 resolve 的比對範圍內，不重造
        let known = Set(organizations.flatMap { org in
            org.names.entries.map { NameNormalization.matchingKey($0.value) }
        })
        var takenKeys = Set(organizations.map(\.key))

        var groups: [String: (names: [String], count: Int)] = [:]
        for raw in literalOrgNames(people: people, organizations: organizations) {
            let name = CorporateName.unmark(raw).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let id = NameNormalization.matchingKey(name)
            guard !known.contains(id) else { continue }
            var g = groups[id] ?? ([], 0)
            if !g.names.contains(name) { g.names.append(name) }
            g.count += 1
            groups[id] = g
        }

        return groups.sorted { a, b in
            a.value.count == b.value.count ? a.key < b.key : a.value.count > b.value.count
        }.compactMap { (_, g) in
            let sortedNames = g.names.sorted()
            guard let key = suggestedKey(from: sortedNames[0], taken: takenKeys) else { return nil }
            takenKeys.insert(key)
            return Candidate(key: key, names: sortedNames, occurrences: g.count)
        }
    }

    /// 機構名 → key slug。機構名不做 `Last, First` 重排（那是人名的慣例）——
    /// 直接 slug 全名，取前幾個 token 避免 key 過長。
    ///
    /// **已知限制**（同 `PersonBootstrap.suggestedKey`，#140 verify 附帶觀察）：純
    /// CJK 名 slug 後全是非 ASCII、`StoreKey.isValid` 不過 → 回 nil、該候選被丟。
    /// 真實 affiliation 多半有英文形式可用；中文-only 機構需人先給 key。
    static func suggestedKey(from name: String, taken: Set<String>) -> String? {
        let tokens = name.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        func slug(_ s: String) -> String {
            String(s.map { $0.isLetter || $0.isNumber ? $0 : "-" })
                .split(separator: "-").joined(separator: "-")
        }
        // 前 4 個 token 足以辨識（「Institute of Statistical Science」→ institute-of-statistical-science）
        let base = tokens.prefix(4).map(slug).filter { !$0.isEmpty }.joined(separator: "-")
        guard !base.isEmpty, StoreKey.isValid(base) else { return nil }
        if !taken.contains(base) { return base }
        for i in 2...99 where StoreKey.isValid("\(base)-\(i)") && !taken.contains("\(base)-\(i)") {
            return "\(base)-\(i)"
        }
        return nil
    }

    public static func organizationsFor(_ candidates: [Candidate]) -> [Organization] {
        candidates.map { c in
            var org = Organization(key: c.key)
            // names 是時間軸——bootstrap 的寫法無時序，各成一段無日期
            org.names = TimelineOf(c.names.map { TemporalValue(value: $0, range: DateRange()) })
            return org
        }
    }
}
