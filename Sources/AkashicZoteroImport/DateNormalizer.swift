import Foundation

/// Zotero raw date 正規化（#2）：抓 ISO-ish 前綴 `YYYY[-MM[-DD]]`，
/// `00` 月/日截斷（`1989-00-00 1989` → `1989`）；無 ISO 前綴 → nil（呼叫端保留原字串＋report）。
public enum DateNormalizer {
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // 邊界：ISO 前綴後必須是字串尾或空白（1989/05/15 不得截成 1989）
        guard let match = trimmed.range(
            of: #"\A(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?(?=\s|$)"#,
            options: .regularExpression) else {
            return nil
        }
        let prefix = String(trimmed[match])
        let parts = prefix.split(separator: "-").map(String.init)
        let year = parts[0]
        let month = parts.count > 1 && parts[1] != "00" ? parts[1] : nil
        let day = parts.count > 2 && parts[2] != "00" && month != nil ? parts[2] : nil
        // 範圍驗證：超界月/日（2025-99）＝malformed，整串交回 report
        if let m = month, !(1...12).contains(Int(m) ?? 0) { return nil }
        if let d = day, !(1...31).contains(Int(d) ?? 0) { return nil }

        var result = year
        if let month { result += "-\(month)" }
        if let day { result += "-\(day)" }
        return result
    }
}
