import Foundation
import AkashicCore

public struct ResolutionCandidate: Equatable {
    public var citekey: String
    public var authorIndex: Int
    public var literal: String
    public var personKey: String
    public var reason: String

    public init(citekey: String, authorIndex: Int, literal: String,
                personKey: String, reason: String) {
        self.citekey = citekey
        self.authorIndex = authorIndex
        self.literal = literal
        self.personKey = personKey
        self.reason = reason
    }
}

/// 人物解析原語。鐵律：**絕不自動合併**——`candidates` 只提名，
/// `apply` 是使用者顯式確認後才呼叫的第二步。
public enum PersonResolver {
    /// 高信心候選：literal 與某人 alias 正規化後完全命中，且不歧義。
    public static func candidates(entries: [Entry], people: [Person]) -> [ResolutionCandidate] {
        // 正規化 alias → person keys（同 alias 對到 2+ 人＝歧義，整組排除）
        var aliasMap: [String: Set<String>] = [:]
        for person in people {
            for name in person.names {
                aliasMap[normalize(name), default: []].insert(person.key)
            }
        }

        var result: [ResolutionCandidate] = []
        for entry in entries {
            for (i, author) in entry.authors.enumerated() {
                guard case .literal(let literal) = author else { continue }
                guard let keys = aliasMap[normalize(literal)], keys.count == 1,
                      let key = keys.first else { continue }
                result.append(ResolutionCandidate(
                    citekey: entry.citekey, authorIndex: i, literal: literal,
                    personKey: key, reason: "alias 完全命中"))
            }
        }
        return result.sorted { ($0.citekey, $0.authorIndex) < ($1.citekey, $1.authorIndex) }
    }

    /// 把已確認的候選套用到 entries（回傳新副本，不動原陣列）。
    public static func apply(_ candidates: [ResolutionCandidate], to entries: [Entry]) -> [Entry] {
        // uniquingKeysWith：損壞 store 出現重複 citekey 時不 trap（後者勝，validate 另行報告）
        var byCitekey = Dictionary(entries.map { ($0.citekey, $0) }, uniquingKeysWith: { _, last in last })
        for candidate in candidates {
            guard var entry = byCitekey[candidate.citekey],
                  entry.authors.indices.contains(candidate.authorIndex),
                  case .literal(let current) = entry.authors[candidate.authorIndex],
                  current == candidate.literal else { continue }
            entry.authors[candidate.authorIndex] = .key(candidate.personKey)
            byCitekey[candidate.citekey] = entry
        }
        return entries.map { byCitekey[$0.citekey] ?? $0 }
    }

    /// 比對面吃正規化（#81：NFKC＋連字號家族＋空白收斂），輸出仍是原字串——
    /// 正規化只住在配對鍵裡，永不外洩成資料。
    static func normalize(_ s: String) -> String {
        NameNormalization.matchingKey(s)
    }
}
