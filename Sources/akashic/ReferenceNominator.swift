import Foundation
import ArgumentParser
import AkashicCore

/// `akashic references nominate` 的提名邏輯（#617）：PDF 參考文獻 × OpenAlex
/// `referenced_works` 的雙向提名。
///
/// **只提名、不判定**（D3；`identity-is-judged-not-matched`：字串相似只能提名）。分數只用來
/// 排序與過濾明顯無關者，輸出裡沒有「接受」——每一組候選由模型逐筆判定並寫下理由。
///
/// 計分（起點值，#617 S6 以真實論文校準）：標題 Dice 係數 × 0.5 ＋ 第一作者 × 0.25 ＋
/// 年份 × 0.25。兩邊都有 DOI 且相同 → 1.0；不同 → 減半（PDF 的 DOI 可能被 pdftotext
/// 的斷行弄壞，所以不直接排除）。總分 ≥ `floor`（0.35）才提名，每筆至多 `topN` 名。
///
/// 標題**完全不像**（Dice = 0）時仍會通過門檻的組合，封閉列舉只有這三種（#617 verify：
/// 原本這裡只寫了第一種）：
/// 1. 第一作者 ＋ 同年 = 0.5
/// 2. 第一作者 ＋ 年份差 1 = 0.375
/// 3. 非第一作者的作者 ＋ 同年 = 0.375
/// 其餘都需要標題有一定相似度（單靠標題：Dice ≥ 0.7）。這三種是刻意留下的——同作者同年的
/// 兄弟作品要讓判定看見——代價是多產作者會多出雜訊候選，由逐筆判定排除。
enum ReferenceNominator {

    struct Work {
        let id: String
        let doi: DOI?
        let title: String?
        let year: Int?
        let authorNames: [String]
    }

    struct Candidate: Codable {
        var openalex: String
        var doi: String?
        var title: String?
        var year: Int?
        var firstAuthor: String?
        var score: Double
        var basis: [String]
        var inStore: String?
        /// 這個 DOI 在 store 裡對到不只一筆（#637 的形狀）：`inStore` 留空、全部列在這裡，
        /// 不以任何順序擅選一筆（#617 verify F6）
        var inStoreConflict: [String]?
        /// 以**這個候選的標題**比對 store（R2 G4：PDF 標題可能被切壞，而真正要寫入的是這一筆）
        var storeMatches: [StoreMatch]
    }

    /// store 裡標題與年份都相近的記錄——抓「沒填 DOI、或填了另一個 DOI 的同一篇」
    /// （#617 verify F2／F3）。只提名，是不是同一篇由模型判定。
    struct StoreMatch: Codable {
        var citekey: String
        var title: String
        var year: Int?
        var score: Double
    }

    struct RefNomination: Codable {
        var index: Int
        var firstAuthor: String?
        var year: Int?
        var title: String?
        var doi: String?
        var inStore: String?
        var inStoreConflict: [String]?
        var storeMatches: [StoreMatch]
        var candidates: [Candidate]
    }

    struct WorkSummary: Codable {
        var openalex: String
        var doi: String?
        var title: String?
        var year: Int?
        var firstAuthor: String?
        var inStore: String?
        var inStoreConflict: [String]?
    }

    /// store 的一筆記錄，供標題＋年份比對
    struct StoreRecord {
        let citekey: String
        let title: String
        let tokens: Set<String>
        let year: Int?
    }

    /// DOI（正規形）→ 持有它的 citekey（已排序、去重）
    typealias DOIIndex = [String: [String]]

    struct Counts: Codable {
        var refs: Int
        var works: Int
        var refsWithCandidates: Int
        var unnominated: Int
    }

    struct Result: Codable {
        var refs: [RefNomination]
        var unnominated: [WorkSummary]
        var counts: Counts
        var warnings: [String]
        /// 輸出契約版本，同 extract（R2 G5）
        var contract: Int?
    }

    static let topN = 3
    static let floor = 0.35
    static let titleWeight = 0.5
    static let authorWeight = 0.25
    static let yearWeight = 0.25

    static let stopwords: Set<String> = [
        "a", "an", "the", "of", "and", "in", "on", "for", "to", "with", "by", "at", "from", "as",
    ]

    // MARK: - OpenAlex 回應

    /// `{"results": [...]}`（API 回應原樣）或 work 陣列。同一 work 出現在多批 → 保留第一次。
    static func parseWorks(_ data: Data, source: String) throws -> (works: [Work], skipped: Int) {
        let top = try? JSONSerialization.jsonObject(with: data)
        let list: [Any]
        if let obj = top as? [String: Any], let results = obj["results"] as? [Any] {
            list = results
        } else if let arr = top as? [Any] {
            list = arr
        } else {
            throw ValidationError(
                "--openalex \(displaySafeInvisible(source, max: 300)) 不是 OpenAlex 的回應 JSON（需為含 results 陣列的物件，或 work 陣列）")
        }
        var works: [Work] = []
        var skipped = 0
        for item in list {
            guard let work = item as? [String: Any], let rawID = work["id"] as? String else {
                skipped += 1
                continue
            }
            let id = rawID.replacingOccurrences(of: "https://openalex.org/", with: "")
            let names = (work["authorships"] as? [[String: Any]] ?? []).compactMap { a -> String? in
                (a["author"] as? [String: Any])?["display_name"] as? String ?? a["raw_author_name"] as? String
            }
            works.append(Work(id: id,
                              doi: (work["doi"] as? String).flatMap(DOI.init),
                              title: work["title"] as? String ?? work["display_name"] as? String,
                              year: plausibleYear(work["publication_year"] as? Int),
                              authorNames: names))
        }
        return (works, skipped)
    }

    // MARK: - 提名

    static func nominate(refs: [ReferenceListExtractor.Reference], works: [Work],
                         doiIndex: DOIIndex, store: [StoreRecord] = []) -> Result {
        // refs 的年份也只收 0…9999（R2 G7：R1 只擋了 OpenAlex 那側，`Int.min` 仍在年份相減時溢位）
        let refs = refs.map { r -> ReferenceListExtractor.Reference in
            var c = r
            c.year = plausibleYear(r.year)
            return c
        }
        var nominated = Set<String>()
        var warnings: [String] = []
        let nominations = refs.map { ref -> RefNomination in
            let ranked = works.compactMap { w -> Candidate? in
                let (score, basis) = self.score(ref, w)
                guard score >= floor else { return nil }
                let (held, conflict) = lookup(w.doi, in: doiIndex)
                return Candidate(openalex: w.id, doi: w.doi?.normalized, title: w.title, year: w.year,
                                 firstAuthor: w.authorNames.first, score: score, basis: basis,
                                 inStore: held, inStoreConflict: conflict,
                                 storeMatches: storeMatches(title: w.title, year: w.year, in: store))
            }
            .sorted { ($0.score, $1.openalex) > ($1.score, $0.openalex) }
            let top = Array(ranked.prefix(topN))
            top.forEach { nominated.insert($0.openalex) }
            let (held, conflict) = lookup(ref.doi.flatMap(DOI.init), in: doiIndex)
            let refMatches = storeMatches(title: ref.title, year: ref.year, in: store)
            // 同分的多筆 store 記錄：可能是重複記錄，不得擅選一筆（R2 G8）
            let lists = [refMatches] + top.map(\.storeMatches)
            if lists.contains(where: { $0.count >= 2 && $0[0].score == $0[1].score }) {
                warnings.append("第 \(ref.index) 筆在 store 裡有多筆標題與年份同分的記錄——可能是重複記錄；"
                                + "不要擅選一筆連 cites，先處理重複（akashic-merge-twins）")
            }
            return RefNomination(index: ref.index, firstAuthor: ref.firstAuthor, year: ref.year,
                                 title: ref.title, doi: ref.doi,
                                 inStore: held, inStoreConflict: conflict,
                                 storeMatches: refMatches,
                                 candidates: top)
        }
        let unnominated = works.filter { !nominated.contains($0.id) }.map { w -> WorkSummary in
            let (held, conflict) = lookup(w.doi, in: doiIndex)
            return WorkSummary(openalex: w.id, doi: w.doi?.normalized, title: w.title, year: w.year,
                               firstAuthor: w.authorNames.first, inStore: held, inStoreConflict: conflict)
        }
        let counts = Counts(refs: refs.count, works: works.count,
                            refsWithCandidates: nominations.filter { !$0.candidates.isEmpty }.count,
                            unnominated: unnominated.count)
        return Result(refs: nominations, unnominated: unnominated, counts: counts, warnings: warnings,
                      contract: ReferenceListExtractor.contractVersion)
    }

    /// 一筆記錄 → `inStore`；多筆 → `inStoreConflict`（不擅選）；沒有 → 兩者皆空
    static func lookup(_ doi: DOI?, in index: DOIIndex) -> (String?, [String]?) {
        guard let d = doi, let held = index[d.normalized], !held.isEmpty else { return (nil, nil) }
        return held.count == 1 ? (held[0], nil) : (nil, held)
    }

    /// 標題詞集合 Dice ≥ `storeMatchThreshold`、年份差 ≤ 1（任一邊沒有年份則不比年份）。
    /// **不截斷**（R2 G3：原本只取前 3，skill 卻把它當成完整的重複檢查——真正那筆排第 4 就漏）。
    static let storeMatchThreshold = 0.8
    static func storeMatches(title: String?, year: Int?, in store: [StoreRecord]) -> [StoreMatch] {
        let tokens = titleTokens(title ?? "")
        guard !tokens.isEmpty else { return [] }
        return store.compactMap { rec -> StoreMatch? in
            if let a = year, let b = rec.year, abs(a - b) > 1 { return nil }
            let d = dice(tokens, rec.tokens)
            guard d >= storeMatchThreshold else { return nil }
            return StoreMatch(citekey: rec.citekey, title: rec.title, year: rec.year,
                              score: (d * 1_000).rounded() / 1_000)
        }
        .sorted { ($0.score, $1.citekey) > ($1.score, $0.citekey) }
    }

    /// 第三方年份只收 0…9999；其餘當作沒有（#617 verify F15：`Int.min` 會讓年份相減溢位 trap）
    static func plausibleYear(_ y: Int?) -> Int? {
        guard let y, (0...9_999).contains(y) else { return nil }
        return y
    }

    /// store 記錄的年份：`date` 開頭的四位數字
    static func year(of date: String?) -> Int? {
        guard let d = date, d.count >= 4, let y = Int(d.prefix(4)) else { return nil }
        return plausibleYear(y)
    }

    static func score(_ ref: ReferenceListExtractor.Reference, _ work: Work) -> (Double, [String]) {
        var basis: [String] = []

        let sim = dice(titleTokens(ref.title ?? ""), titleTokens(work.title ?? ""))
        if sim > 0 { basis.append(String(format: "title=%.2f", sim)) }

        let author = authorScore(ref, work)
        if author == 1 { basis.append("firstAuthor") } else if author > 0 { basis.append("author") }

        var year = 0.0
        if let a = ref.year, let b = work.year {
            if a == b { year = 1; basis.append("year") } else if abs(a - b) == 1 { year = 0.5; basis.append("year±1") }
        }

        var score = titleWeight * sim + authorWeight * author + yearWeight * year
        if let rd = ref.doi.flatMap(DOI.init), let wd = work.doi {
            if rd.normalized == wd.normalized {
                score = 1
                basis.insert("doi", at: 0)
            } else {
                score *= 0.5
                basis.append("doiMismatch")
            }
        }
        return ((score * 1_000).rounded() / 1_000, basis)
    }

    /// 1 ＝ 第一作者對上（姓在最後，或 OpenAlex 名字是姓在前的形式）；0.5 ＝ 對上的是其他作者。
    /// 機構作者比整個名字的詞集合。
    static func authorScore(_ ref: ReferenceListExtractor.Reference, _ work: Work) -> Double {
        guard let first = ref.firstAuthor, let workFirst = work.authorNames.first else { return 0 }
        if ref.groupAuthor {
            return dice(titleTokens(first), titleTokens(workFirst)) >= 0.8 ? 1 : 0
        }
        guard let key = nameTokens(first).last else { return 0 }
        if nameTokens(workFirst).contains(key) { return 1 }
        return work.authorNames.dropFirst().contains { nameTokens($0).contains(key) } ? 0.5 : 0
    }

    // MARK: - 正規化

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// 標題的詞集合：去 HTML 標籤、去連字號（`Within-person` 與斷字接回的 `longi-tudinal`
    /// 都變成一個詞）、其餘非英數字元當分隔、去虛詞。
    static func titleTokens(_ s: String) -> Set<String> {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        t = fold(t).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "\u{2010}", with: "")
        let words = t.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopwords.contains($0) }
        return Set(words)
    }

    /// 名字的詞：只留字母（`Hsin-Yi` → `hsinyi`、`O’Brien` → `obrien`）
    static func nameTokens(_ s: String) -> [String] {
        fold(s).split(whereSeparator: { $0.isWhitespace }).map { $0.filter(\.isLetter) }
            .filter { !$0.isEmpty }
    }

    static func dice(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        return 2 * Double(a.intersection(b).count) / Double(a.count + b.count)
    }
}
