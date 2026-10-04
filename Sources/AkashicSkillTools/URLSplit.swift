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
    var hostPort: String {
        let n = PyText.string(netloc)
        guard let at = n.lastIndex(of: "@") else { return n }
        return String(n[n.index(after: at)...])
    }

    /// `scheme://主機[:埠號]`，不帶帳密（#613 R3，b31 W4 第 6、15、16 則）：`fulltext fetch` 比「分頁還在同一個站嗎」、印進訊息、
    /// 當每日帳本的站名，都用這一個——先前用 `origin`，轉址網址帶的帳密照樣出現在 stderr、stdout 的 `attempt:` 一行與帳本裡。
    var siteOrigin: String { "\(PyText.string(scheme))://\(hostPort)" }
}
