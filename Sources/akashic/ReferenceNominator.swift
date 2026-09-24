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
/// 的斷行弄壞，所以不直接排除）。總分 ≥ `floor` 才提名，每筆至多 `topN` 名——門檻的意思是
/// 「單一欄位符合不夠」：同作者同年（0.5）或標題夠像（Dice ≥ 0.7）才進候選。
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
    }

    struct RefNomination: Codable {
        var index: Int
        var firstAuthor: String?
        var year: Int?
        var title: String?
        var doi: String?
        var inStore: String?
        var candidates: [Candidate]
    }

    struct WorkSummary: Codable {
        var openalex: String
        var doi: String?
        var title: String?
        var year: Int?
        var firstAuthor: String?
        var inStore: String?
    }

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
                "--openalex \(displaySafe(source)) 不是 OpenAlex 的回應 JSON（需為含 results 陣列的物件，或 work 陣列）")
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
                              year: work["publication_year"] as? Int,
                              authorNames: names))
        }
        return (works, skipped)
    }

    // MARK: - 提名

    static func nominate(refs: [ReferenceListExtractor.Reference], works: [Work],
                         inStore: [String: String]) -> Result {
        var nominated = Set<String>()
        let nominations = refs.map { ref -> RefNomination in
            let ranked = works.compactMap { w -> Candidate? in
                let (score, basis) = self.score(ref, w)
                guard score >= floor else { return nil }
                return Candidate(openalex: w.id, doi: w.doi?.normalized, title: w.title, year: w.year,
                                 firstAuthor: w.authorNames.first, score: score, basis: basis,
                                 inStore: w.doi.flatMap { inStore[$0.normalized] })
            }
            .sorted { ($0.score, $1.openalex) > ($1.score, $0.openalex) }
            let top = Array(ranked.prefix(topN))
            top.forEach { nominated.insert($0.openalex) }
            let refDOI = ref.doi.flatMap(DOI.init)
            return RefNomination(index: ref.index, firstAuthor: ref.firstAuthor, year: ref.year,
                                 title: ref.title, doi: ref.doi,
                                 inStore: refDOI.flatMap { inStore[$0.normalized] },
                                 candidates: top)
        }
        let unnominated = works.filter { !nominated.contains($0.id) }.map { w in
            WorkSummary(openalex: w.id, doi: w.doi?.normalized, title: w.title, year: w.year,
                        firstAuthor: w.authorNames.first,
                        inStore: w.doi.flatMap { inStore[$0.normalized] })
        }
        let counts = Counts(refs: refs.count, works: works.count,
                            refsWithCandidates: nominations.filter { !$0.candidates.isEmpty }.count,
                            unnominated: unnominated.count)
        return Result(refs: nominations, unnominated: unnominated, counts: counts, warnings: [])
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
