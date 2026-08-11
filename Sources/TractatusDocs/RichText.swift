import Foundation

struct MarkdownImageReference {
    let alt: String
    let path: String
    let range: Range<String.Index>
}

enum MarkdownImageReferenceParser {
    /// 共用的窄 rich-text 語法：`images/` 相對路徑可含空白，但不可跨行或含 `)`。
    static func references(in value: String) -> [MarkdownImageReference] {
        let pattern = #"!\[(.*?)\]\((images/[^)\r\n]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: fullRange).compactMap { match in
            guard let whole = Range(match.range(at: 0), in: value),
                  let alt = Range(match.range(at: 1), in: value),
                  let path = Range(match.range(at: 2), in: value) else {
                return nil
            }
            return MarkdownImageReference(
                alt: String(value[alt]),
                path: String(value[path]),
                range: whole
            )
        }
    }
}
