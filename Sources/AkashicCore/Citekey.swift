import Foundation

/// citekey 生成規則（2026-07-22 使用者定案）：
/// 小寫第一作者姓 + 年份 + 標題首個實詞；同 key 衝突在年份後插 b/c/…。
public enum Citekey {
    static let stopwords: Set<String> = [
        "a", "an", "the", "on", "of", "in", "for", "and", "or", "with",
        "to", "from", "at", "by", "is", "are", "as", "its", "their",
        "do", "does", "can", "toward", "towards", "via",
    ]

    public static func generate(familyName: String?, year: String?, title: String?,
                                existing: Set<String>) -> String {
        let fam = familyName.flatMap { nonEmpty(slug($0)) } ?? "anon"
        let yr = year.flatMap { extractYear($0) } ?? "nd"
        let word = title.flatMap { firstSignificantWord($0) } ?? "entry"

        let base = fam + yr + word
        guard existing.contains(base) else { return base }

        // 衝突：年份後插 b, c, … z
        for letter in "bcdefghijklmnopqrstuvwxyz" {
            let candidate = fam + yr + String(letter) + word
            if !existing.contains(candidate) { return candidate }
        }
        // 26 個都撞（幾乎不可能）→ 數字後綴
        var n = 2
        while existing.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// ASCII 摺疊 + 只留 [a-z0-9]。CJK 等非拉丁字元會被移除（呼叫端 fallback）。
    static func slug(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .unicodeScalars
            .filter { ("a"..."z").contains(Character($0)) || ("0"..."9").contains(Character($0)) }
            .map(String.init)
            .joined()
    }

    static func firstSignificantWord(_ title: String) -> String? {
        let tokens = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for token in tokens {
            let slugged = slug(String(token))
            if slugged.isEmpty { continue }
            if stopwords.contains(slugged) { continue }
            return slugged
        }
        return nil
    }

    static func extractYear(_ raw: String) -> String? {
        if let range = raw.range(of: "[0-9]{4}", options: .regularExpression) {
            return String(raw[range])
        }
        return nonEmpty(slug(raw))
    }

    private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
