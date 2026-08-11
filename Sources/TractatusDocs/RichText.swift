import Foundation

struct MarkdownImageReference {
    let alt: String
    let path: String
    let range: Range<String.Index>
}

enum MarkdownImageReferenceParser {
    /// 共用的窄 rich-text 語法：`images/` 相對路徑可含空白，但不可跨行或含 `)`。
    static func references(in value: String) -> [MarkdownImageReference] {
        scan(value, maximumCount: nil).references
    }

    /// 驗證路徑使用的有界掃描；一旦看見第 `maximumCount + 1` 筆就停止。
    static func references(
        in value: String,
        maximumCount: Int
    ) throws(CorpusSchemaError) -> [MarkdownImageReference] {
        let result = scan(value, maximumCount: maximumCount)
        guard !result.exceeded else {
            throw CorpusSchemaError.resourceLimit(
                kind: "referenced-asset-references",
                actual: maximumCount + 1,
                maximum: maximumCount
            )
        }
        return result.references
    }

    private static func scan(
        _ value: String,
        maximumCount: Int?
    ) -> (references: [MarkdownImageReference], exceeded: Bool) {
        let pattern = #"!\[(.*?)\]\((images/[^)\r\n]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return ([], false)
        }
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        var references: [MarkdownImageReference] = []
        var exceeded = false
        expression.enumerateMatches(in: value, range: fullRange) { match, _, stop in
            if let maximumCount, references.count >= maximumCount {
                exceeded = true
                stop.pointee = true
                return
            }
            guard let match,
                  let whole = Range(match.range(at: 0), in: value),
                  let alt = Range(match.range(at: 1), in: value),
                  let path = Range(match.range(at: 2), in: value) else {
                return
            }
            references.append(MarkdownImageReference(
                alt: String(value[alt]),
                path: String(value[path]),
                range: whole
            ))
        }
        return (references, exceeded)
    }
}
