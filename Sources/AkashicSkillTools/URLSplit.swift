import Foundation

/// Python `urllib.parse.urlsplit` 的子集：scheme、netloc、path、（略去 query／fragment）（#629 移植；#613 起出版商的拼網址規則
/// `PdfUrlRules` 刪除之後，它單獨住在這裡）。
///
/// 重現 3.13 的三個前處理——去掉前導的 C0 控制字元與空白、刪掉 ASCII tab 與換行、`://` 之後到第一個 `/?#` 為 netloc。
/// `fulltext fetch` 用它比「分頁還在不在同一個站」與每日上限的站名（帶埠號的網址照字面，與不帶的是不同的站）。
struct URLSplit {
    var scheme = Scalars()
    var netloc = Scalars()
    var path = ""

    init(_ url: String) {
        var s = Scalars(url.unicodeScalars)
        while let f = s.first, f.value <= 0x20 { s.removeFirst() }
        s.removeAll { $0 == "\t" || $0 == "\r" || $0 == "\n" }
        if let colon = s.firstIndex(of: ":"), colon > 0, s[0].isASCII, s[0].properties.isAlphabetic,
           s[..<colon].allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "+" || $0 == "-" || $0 == ".") }) {
            scheme = PyText.lower(Scalars(s[..<colon]))
            s = Scalars(s[(colon + 1)...])
        }
        if PyText.hasPrefix(s, ["/", "/"]) {
            let rest = Scalars(s[2...])
            let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.count
            netloc = Scalars(rest[..<end])
            s = Scalars(rest[end...])
        }
        if let cut = s.firstIndex(of: "#") { s = Scalars(s[..<cut]) }
        if let cut = s.firstIndex(of: "?") { s = Scalars(s[..<cut]) }
        path = PyText.string(s)
    }

    /// `scheme://netloc`（Python `urlsplit` 的對照；netloc 含主機前的帳密）。
    var origin: String { "\(PyText.string(scheme))://\(PyText.string(netloc))" }

    /// netloc 去掉主機前的帳密（`user:pw@`，與 Python 的 `rpartition('@')` 同樣切最後一個 `@`）：主機加埠號。
    ///
    /// 兩處不照 Python（#613 b34，b33 X3 第 9、19 則）：
    /// - **反斜線結束 authority**：WHATWG 對 http(s) 把 `\` 當 `/`，`https://evil.example\@pub.example/x` 的主機是 `evil.example`。Python 的
    ///   netloc 不在 `\` 斷開，先前去帳密時切到最後一個 `@`，把它說成 `pub.example`——站的比對 fail open。
    /// - **以 Unicode scalar 找 `@`**：`@` 後面接組合符號時，以 `Character` 找會找不到，帳密就留著（`plainURL` 早就以 scalar 找）。
    var hostPort: String {
        var n = netloc
        if let backslash = n.firstIndex(of: "\\") { n = Scalars(n[..<backslash]) }
        if let at = n.lastIndex(of: "@") { n = Scalars(n[(at + 1)...]) }
        return PyText.string(n)
    }

    /// 主機名稱（小寫，不帶帳密與埠號）。登入／驗證頁的長相看主機時用它——帳密與埠號裡的字不是主機的字。
    var host: String {
        let h = hostPort.lowercased()
        if h.hasPrefix("[") { return h.split(separator: "]", maxSplits: 1).first.map { String($0) + "]" } ?? h }   // IPv6 字面
        guard let colon = h.lastIndex(of: ":"), h[h.index(after: colon)...].allSatisfy(\.isNumber) else { return h }
        return String(h[..<colon])
    }

    /// `scheme://主機[:埠號]`，不帶帳密（#613 R3，b31 W4 第 6、15、16 則）：`fulltext fetch` 比「分頁還在同一個站嗎」、印進訊息、
    /// 當每日帳本的站名，都用這一個——先前用 `origin`，轉址網址帶的帳密照樣出現在 stderr、stdout 的 `attempt:` 一行與帳本裡。
    var siteOrigin: String { "\(PyText.string(scheme))://\(hostPort)" }
}
