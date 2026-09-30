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

    /// `scheme://netloc`（呼叫端用它判斷「分頁還在同一個站嗎」）。
    var origin: String { "\(PyText.string(scheme))://\(PyText.string(netloc))" }
}
