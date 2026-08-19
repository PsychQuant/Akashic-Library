import Foundation
import AkashicCore

/// venue 的解析候選（鏡像 `ResolutionCandidate`，#304）。
///
/// **刻意不與 person 共用型別**：兩個定義域的候選在 apply 端走不同的改寫路徑
/// （`entry.venues` vs `entry.authors`），共用型別會讓「把 venue 候選 apply 到
/// authors」在型別層寫得出來。
public struct VenueResolutionCandidate: Equatable {
    public var citekey: String
    public var venueIndex: Int
    public var literal: String
    public var venueKey: String
    public var reason: String

    public init(citekey: String, venueIndex: Int, literal: String,
                venueKey: String, reason: String) {
        self.citekey = citekey
        self.venueIndex = venueIndex
        self.literal = literal
        self.venueKey = venueKey
        self.reason = reason
    }

    /// 唯一識別：`"<citekey>:<venueIndex>"`（同 `ResolutionCandidate.rowID` 的理由——
    /// 複合鍵住在型別上，不讓三個呼叫端各寫一次）。
    public var rowID: String { "\(citekey):\(venueIndex)" }   // display-safe-exempt: 回程把手須逐字，消毒會讓 apply 對不上（且 displaySafe 不冪等）
}

/// 同一個 literal 對到 2+ 個 venue——需要人判斷（同 `AmbiguousMatch` 的立場：
/// 回報它，不解決它）。
public struct VenueAmbiguousMatch: Equatable {
    public var entryID: UUID
    public var citekey: String
    public var venueIndex: Int
    public var literal: String
    /// 命中的 venue key，已排序且 `count >= 2`。
    public var venueKeys: [String]

    public init?(entryID: UUID, citekey: String, venueIndex: Int,
                 literal: String, venueKeys: Set<String>) {
        guard venueKeys.count >= 2 else { return nil }
        self.entryID = entryID
        self.citekey = citekey
        self.venueIndex = venueIndex
        self.literal = literal
        self.venueKeys = venueKeys.sorted()
    }

    public var rowID: String { "\(entryID.uuidString):\(venueIndex)" }
}

/// 一次 venue 解析的完整結果（candidates 可 apply、ambiguities 不可——
/// 「不小心 apply 一個歧義」在型別層寫不出來，同 `ResolutionReport`）。
public struct VenueResolutionReport: Equatable {
    public var candidates: [VenueResolutionCandidate]
    public var ambiguities: [VenueAmbiguousMatch]

    public init(candidates: [VenueResolutionCandidate], ambiguities: [VenueAmbiguousMatch]) {
        self.candidates = candidates
        self.ambiguities = ambiguities
    }
}

/// venue 解析原語。鐵律同 `PersonResolver`：**絕不自動合併**——`candidates` 只提名，
/// `apply` 是使用者顯式確認後的第二步（`literal-first-then-key` 的升格路徑）。
public enum VenueResolver {

    /// 單一 traversal（不為歧義另寫遍歷——#140 的分岔血案同適用）。
    /// `rejected` 刻意必填（同 PersonResolver：`= []` 會讓新呼叫面靜默略過否決史）。
    ///
    /// 正規化走 `NameNormalization.matchingKey`（NFKC＋lowercase＋空白收斂）——
    /// WoS 全大寫形（`PSYCHOMETRIKA`）與正式刊名因此同鍵，這正是 371 個 distinct
    /// journaltitle 的主要異形來源。
    public static func resolve(entries: [Entry], venues: [Venue],
                               rejected: Set<ResolutionPairing>) -> VenueResolutionReport {
        var aliasMap: [String: Set<String>] = [:]
        for venue in venues {
            // 全部名字（時間軸各段——沿革中的舊刊名照樣配對；舊文章掛舊刊名是常態）。
            for seg in venue.names.entries {
                aliasMap[normalize(seg.value), default: []].insert(venue.key)
            }
        }

        var candidates: [VenueResolutionCandidate] = []
        var ambiguities: [VenueAmbiguousMatch] = []
        for entry in entries {
            for (i, ref) in entry.venues.enumerated() {
                guard case .literal(let literal) = ref else { continue }
                // 無任何 venue 叫這個名字＝合法長期狀態，不回報（噪音紀律同 person）。
                guard let keys = aliasMap[normalize(literal)] else { continue }
                if keys.count == 1, let key = keys.first {
                    guard !rejected.contains(ResolutionPairing(
                        holderKind: .work, holder: entry.citekey,
                        literal: literal, judgedKey: key)) else { continue }
                    candidates.append(VenueResolutionCandidate(
                        citekey: entry.citekey, venueIndex: i, literal: literal,
                        venueKey: key, reason: "venue name 完全命中"))
                } else if let m = VenueAmbiguousMatch(entryID: entry.id, citekey: entry.citekey,
                                                      venueIndex: i, literal: literal,
                                                      venueKeys: keys) {
                    ambiguities.append(m)
                }
            }
        }
        return VenueResolutionReport(
            candidates: candidates.sorted { ($0.citekey, $0.venueIndex) < ($1.citekey, $1.venueIndex) },
            ambiguities: ambiguities.sorted {
                ($0.citekey, $0.venueIndex, $0.entryID.uuidString)
                    < ($1.citekey, $1.venueIndex, $1.entryID.uuidString)
            })
    }

    /// 把已確認的候選套用到 entries（回傳新副本，不動原陣列；同 PersonResolver.apply）。
    public static func apply(_ candidates: [VenueResolutionCandidate], to entries: [Entry]) -> [Entry] {
        var byCitekey = Dictionary(entries.map { ($0.citekey, $0) }, uniquingKeysWith: { _, last in last })
        for candidate in candidates {
            guard var entry = byCitekey[candidate.citekey],
                  entry.venues.indices.contains(candidate.venueIndex),
                  case .literal(let current) = entry.venues[candidate.venueIndex],
                  current == candidate.literal else { continue }
            entry.venues[candidate.venueIndex] = .key(candidate.venueKey)
            byCitekey[candidate.citekey] = entry
        }
        return entries.map { byCitekey[$0.citekey] ?? $0 }
    }

    static func normalize(_ s: String) -> String {
        NameNormalization.matchingKey(s)
    }
}
