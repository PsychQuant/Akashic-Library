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
///
/// **key 產生的定義域**（#154 verify 154-1／154-5）：key 取機構名 NFKC 後的
/// **ASCII 字母數字 token**——雙語寫法（`國立臺灣大學 National Taiwan University`，
/// 台灣機構最常見）用英文部分產 key，全形拉丁先經 NFKC 折回 ASCII。純 CJK（NFKC 後
/// 仍無任何 ASCII token）產不出 key，但**不靜默丟**：進 `result` 的 `dropped`，由
/// CLI 明列（需人工指定 key）。用 `result`（帶 dropped）而非 `candidates`（只有能
/// 建的）才看得到全貌。
///
/// **殘留**（#154 verify 154-6，誠實記錄，不在本 change 修）：
/// 1. **中文-only 機構仍需人工給 key**。這不是 bug 是設計缺口——`bootstrap` 現在
///    只能產 ASCII slug，而「中央研究院統計科學研究所」這類是本 store 的**主要**
///    形狀。真正的修法是讓使用者能為 dropped 項目直接指定 key（互動或
///    `--key <name>=<key>`），而不是繞去手寫 YAML。
/// 2. **`suggestedKey` 的 6-token 上限與去重 `-2…-99`** 沒有測試覆蓋，也沒有依據
///    ——6 是拍腦袋的數字。長機構名截斷後可能撞在一起，靠 `-2` 尾碼區分，但那個
///    尾碼對人沒有意義（`national-taiwan-university-2` 是誰？）。
/// 3. **`resolve-organizations` 的歧義判準**只看正規化後完全相等，不做子字串／
///    縮寫比對（「中研院」vs「中央研究院」配不上）。同義詞歸戶屬 alias 層，未做。
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

    /// 產不出合法 key 而被丟棄的機構名（#154 verify 154-1）——**不能靜默丟**：
    /// 使用者看到 N 個候選，不知道其實有 N+M 個機構名、M 個因無 ASCII 可 slug
    /// 被略過。CLI 據此明列，而非讓 `無候選` 訊息誤導成「都已建好或低於門檻」。
    public struct Result: Equatable {
        public var candidates: [Candidate]
        public var dropped: [(name: String, occurrences: Int)]
        public static func == (a: Result, b: Result) -> Bool {
            a.candidates == b.candidates
                && a.dropped.map { "\($0.name)|\($0.occurrences)" }
                    == b.dropped.map { "\($0.name)|\($0.occurrences)" }
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
    ///
    /// **只是 `result` 的投影**（#154 verify 154-4 附帶）：原本兩者各有一份分組邏輯
    /// ——兩份會漂移，而且漂移的方向恰好是「`candidates` 靜默丟、`result` 有記錄」，
    /// 也就是這個 issue 本來要修的病。收斂成單一來源。
    public static func candidates(people: [Person],
                                  organizations: [Organization]) -> [Candidate] {
        result(people: people, organizations: organizations).candidates
    }

    /// 候選 + 丟棄清單（#154 verify 154-1）：產不出 key 的機構名要能被 CLI 說出來，
    /// 不是靜默消失。這是分組與 key 產生的**唯一**實作。
    public static func result(people: [Person],
                              organizations: [Organization]) -> Result {
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

        var cands: [Candidate] = []
        var dropped: [(name: String, occurrences: Int)] = []
        for (_, g) in groups.sorted(by: {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }) {
            let sortedNames = g.names.sorted()
            if let key = suggestedKey(from: sortedNames[0], taken: takenKeys) {
                takenKeys.insert(key)
                cands.append(Candidate(key: key, names: sortedNames, occurrences: g.count))
            } else {
                dropped.append((name: sortedNames[0], occurrences: g.count))
            }
        }
        return Result(candidates: cands, dropped: dropped)
    }

    /// 機構名 → key slug。機構名不做 `Last, First` 重排（那是人名的慣例）。
    ///
    /// **只取 ASCII token**（#154 verify 154-1）：台灣機構最常見的寫法是雙語
    /// （`國立臺灣大學 National Taiwan University`），英文名就在同一字串裡——slug
    /// 全名會因 CJH 字元讓 `StoreKey.isValid` 失敗、整個候選被丟。改成濾出**純
    /// ASCII 字母數字的 token**（CJK token 略過），雙語名用英文部分產 key。
    ///
    /// **先 NFKC 相容正規化**（#154 verify 154-5）：全形拉丁（`Ｎａｔｉｏｎａｌ`）
    /// 在 Unicode 上不是 ASCII，逐字元判斷會整串濾掉、機構被誤丟。全形英數在 CJK
    /// 輸入法下是**常見**產物，不是邊角。這與配對鍵的做法一致——`NameNormalization`
    /// `matchingKey` 第一步就是 NFKC；key 產生沿用同一個正規化階梯才不會出現
    /// 「配得上但建不出來」的錯位。正規化只用於**產 key**，`names` 仍存原字串。
    ///
    /// **殘留限制**：純 CJK（NFKC 後仍無任何 ASCII token）產不出 key → 回 nil，由
    /// `result` 的 `dropped` 回報、CLI 明列（不再靜默）。中文-only 機構需人先給 key。
    static func suggestedKey(from name: String, taken: Set<String>) -> String? {
        // token 內只保留 ASCII 字母數字；含 CJK 的 token slug 後為空、被濾掉
        func asciiSlug(_ s: String) -> String {
            String(s.lowercased().map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" })
                .split(separator: "-").joined(separator: "-")
        }
        let name = name.precomposedStringWithCompatibilityMapping
        let asciiTokens = name.split(whereSeparator: \.isWhitespace)
            .map { asciiSlug(String($0)) }.filter { !$0.isEmpty }
        guard !asciiTokens.isEmpty else { return nil }
        let base = asciiTokens.prefix(6).joined(separator: "-")
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
