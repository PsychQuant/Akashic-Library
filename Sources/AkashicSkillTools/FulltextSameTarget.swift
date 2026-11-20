import Foundation

/// `akashic fulltext same-target`：按了頁面上這篇自己的連結之後視窗多出來的那一個分頁，顯示的是不是那個連結指的網址（#781 第 4 輪 verify
/// 第 1、2 列；維護者 2026-11-20 08:42 的決定第 2 點：「對得上連結才收、其餘停下」）。
///
/// skill 在按之前讀到連結的 `href`（屬性的原文：2026-11-20 在真的 Safari 上量到 `get attr … href` 印的是沒有解析過的屬性，#820 的 M2e），
/// 這裡把它對被按的那一頁的網址解析成絕對網址，再與新分頁的網址比。比的是 scheme、主機、埠號、路徑與查詢字串，**片段不比**。
///
/// 回答是封閉的三種：
/// - `match`：解析得出來，而且與新分頁的網址相同；
/// - `differ`：解析得出來，但新分頁顯示的是別的網址（含轉址過的連結，M2e；新分頁不是 https、主機不乾淨、帶帳密也算）；
/// - `unresolvable`：`href` 說不出另一份文件——空的、只有片段、不是 https、帶帳密、主機不是乾淨的 DNS 名稱、有本檔不解析的字元，
///   解析之後就是被按的那一頁自己，或被按的那一頁的網址本身不是乾淨的 https 網址。
///
/// **沒有量過的**：Safari 回報的分頁網址與這裡用 Foundation 解析出來的字串，在真的出版商網站上是否逐字相同（#820 只量到本機測試頁上
/// 新分頁顯示連結的目標，M2）。對不上的方向是 `differ`，也就是停下。為了不靠兩套解析器在邊角上剛好一致，`href` 只收不需要轉寫的字元
/// （RFC 3986 的 unreserved、reserved 與 `%`）：空白、非 ASCII、引號、反斜線、`<>{}|^` 與反引號一律 `unresolvable`。
public enum FulltextSameTarget {
    public enum Verdict: String, Equatable, Sendable {
        case match, differ, unresolvable
    }

    /// 一個檔最多讀這麼多位元組；更長的不是連結或網址。
    public static let maxBytes = 65_536

    /// 可以直接比的那幾段。
    struct Target: Equatable {
        let host: String
        let port: Int
        let path: String
        let query: String?
    }

    public static func judge(page: String, href: String, tab: String) -> Verdict {
        guard let pageText = oneLine(page), let pageTarget = target(pageText) else { return .unresolvable }
        guard let link = oneLine(href) else { return .unresolvable }
        // 瀏覽器會去掉屬性前後的空白；中間有空白或控制字元的不解析
        let trimmed = link.trimmingCharacters(in: CharacterSet(charactersIn: " \t\u{0C}"))
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed.unicodeScalars.allSatisfy(isPlainURLScalar) else { return .unresolvable }
        if let scheme = leadingScheme(trimmed), scheme != "https" { return .unresolvable }
        guard let base = URL(string: withoutFragment(pageText)),
              let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL.standardized,
              let linkTarget = target(resolved.absoluteString),
              linkTarget != pageTarget else { return .unresolvable }
        guard let tabText = oneLine(tab), let tabTarget = target(tabText) else { return .differ }
        return tabTarget == linkTarget ? .match : .differ
    }

    /// 檔案的內容 → 一行：去掉結尾的換行；中間還有換行或其他控制字元就不是一個值。
    static func oneLine(_ text: String) -> String? {
        var line = Substring(text)
        while let last = line.last, last == "\n" || last == "\r\n" || last == "\r" { line = line.dropLast() }
        guard line.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F || $0 == "\t" || $0.value == 0x0C }) else { return nil }
        return String(line)
    }

    /// RFC 3986 的 unreserved、reserved 與 `%`。
    static func isPlainURLScalar(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.isASCII else { return false }
        if ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar) { return true }
        return "-._~:/?#[]@!$&'()*+,;=%".unicodeScalars.contains(scalar)
    }

    /// 開頭的 scheme（小寫），沒有就是 nil。`//host/…` 與相對路徑都沒有。
    static func leadingScheme(_ text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let head = text[..<colon]
        guard let first = head.unicodeScalars.first, ("a"..."z").contains(first) || ("A"..."Z").contains(first),
              head.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || "+.-".unicodeScalars.contains($0) })
        else { return nil }
        return head.lowercased()
    }

    static func withoutFragment(_ text: String) -> String {
        guard let hash = text.firstIndex(of: "#") else { return text }
        return String(text[..<hash])
    }

    /// 絕對的 https 網址、沒有帳密、主機是乾淨的 DNS 名稱，才有可以比的幾段；否則 nil。片段不留。
    static func target(_ text: String) -> Target? {
        guard text.unicodeScalars.allSatisfy(isPlainURLScalar),
              let parts = URLComponents(string: withoutFragment(text)),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              let host = parts.host?.lowercased(), BotSignals.isPlainDNSName(host) else { return nil }
        let path = parts.percentEncodedPath
        return Target(host: host, port: parts.port ?? 443, path: path.isEmpty ? "/" : path, query: parts.percentEncodedQuery)
    }
}
