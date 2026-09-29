import Foundation

/// 出版商規則：從落地頁最後停在的網址，推出 PDF 的網址（#629 由 `pdf_url_rules.py` 移植）。
///
/// 每條規則存在的理由都是：頁面自己的連結指到的是回 HTML 而不是檔案的地方。每條都記著觀察日期；一條沒有被重新觀察的
/// 規則，是關於某個出版商網站的**斷言**，可能已經漂移（見 `plugin/rules/assertions-must-be-measured.md`）。
/// `references/publishers.md` 記著每個站的觀察，改規則時同步改那裡。
///
/// 沒有規則適用時回 nil（呼叫端改用頁面自己的連結）。
public enum PdfUrlRules {

    /// 落地網址在 DOI **之後**可能帶的檢視段。DOI 本身可以含 `/`（SICI 式 DOI 就有），所以擷取不能停在第一個斜線；改成把已知的
    /// 檢視段從尾端剝掉。
    static let viewSuffixes = ["abstract", "full", "fulltext", "references", "citedby", "figures", "tables", "suppl",
                               "supplementary", "epdf", "pdf"]
    static let viewPrefixes = ["full/", "abs/", "epdf/", "reader/", "pdf/", "pdfdirect/"]

    /// `/doi/`（可接 `full/`、`abs/`、`epdf/`、`reader/`、`pdf/`、`pdfdirect/`）之後的 DOI。
    public static func doiFromPath(_ path: String) -> String? {
        let p = Scalars(path.unicodeScalars)
        let marker = Scalars("/doi/".unicodeScalars)
        var from = 0
        while let i = PyText.firstIndex(of: marker, in: p, from: from) {
            from = i + 1
            var j = i + marker.count
            for prefix in viewPrefixes {
                let q = Scalars(prefix.unicodeScalars)
                if PyText.hasPrefix(p, q, at: j) { j += q.count; break }
            }
            guard PyText.hasPrefix(p, Scalars("10.".unicodeScalars), at: j) else { continue }
            var k = j + 3
            while k < p.count, p[k] != "?", p[k] != "#" { k += 1 }
            guard k > j + 3 else { continue }
            var doi = PyText.rstrip(Scalars(p[j..<k]), ["/"])
            while let cut = viewSuffixStart(doi) { doi = PyText.rstrip(Scalars(doi[..<cut]), ["/"]) }
            return PyText.string(doi)
        }
        return nil
    }

    /// `/(abstract|…|pdf)/?$`（不分大小寫）：尾端若是一個檢視段，回它前面那個 `/` 的位置。
    private static func viewSuffixStart(_ doi: Scalars) -> Int? {
        for view in viewSuffixes {
            let v = Scalars(view.unicodeScalars)
            guard doi.count > v.count else { continue }
            let start = doi.count - v.count - 1
            guard doi[start] == "/" else { continue }
            let tail = doi[(start + 1)...]
            if zip(tail, v).allSatisfy({ asciiLower($0) == $1 }) { return start }
        }
        return nil
    }

    private static func asciiLower(_ s: Unicode.Scalar) -> Unicode.Scalar {
        (0x41...0x5A).contains(s.value) ? Unicode.Scalar(s.value + 0x20)! : s
    }

    /// `finalURL`：落地頁最後停在的網址；`pageLink`：頁面自己的 PDF 連結（PsycNet 停在 `doiLanding?doi=…` 時 id 從這裡取）。
    public static func pdfURL(finalURL: String, pageLink: String? = nil) -> String? {
        let parts = URLSplit(finalURL)
        let host = String(PyText.string(PyText.lower(parts.netloc)))
        let path = parts.path

        // SAGE — 2026-09-23：citation_pdf_url 指到 /doi/reader/（HTML 閱讀器，text/html）；
        // /doi/pdf/<doi>?download=true 回 application/pdf。
        if host == "journals.sagepub.com" {
            return doiFromPath(path).map { "https://journals.sagepub.com/doi/pdf/\($0)?download=true" }
        }
        // Wiley — 2026-09-23：/doi/pdf/<doi> 回 HTML 檢視器（text/html）；/doi/pdfdirect/<doi> 回 application/pdf。
        if host == "onlinelibrary.wiley.com" {
            return doiFromPath(path).map { "https://onlinelibrary.wiley.com/doi/pdfdirect/\($0)" }
        }
        // APA PsycNet — 2026-09-23：/record/<id> 與 /fulltext/<id>.html 都對到 /fulltext/<id>.pdf。網站停在
        // doiLanding?doi=… 時，id 從頁面的 /record/<id> 連結取（當作 pageLink 傳入）。
        if host == "psycnet.apa.org" {
            var id = psycnetID(in: Scalars(path.unicodeScalars), anchored: true, markers: ["/record/", "/fulltext/"])
            if id == nil, let link = pageLink, !link.isEmpty {
                id = psycnetID(in: PyText.unquote(Scalars(link.unicodeScalars)), anchored: false, markers: ["/record/"])
            }
            return id.map { "https://psycnet.apa.org/fulltext/\($0).pdf" }
        }
        return nil
    }

    /// `(\d{4}-\d{5}-\d{3})` 接在某個標記之後。`anchored` 對應 `re.match`（從頭），否則 `re.search`。
    private static func psycnetID(in s: Scalars, anchored: Bool, markers: [String]) -> String? {
        func idAt(_ i: Int) -> String? {
            let shape = [4, 5, 3]
            var j = i
            var out = Scalars()
            for (n, len) in shape.enumerated() {
                if n > 0 {
                    guard j < s.count, s[j] == "-" else { return nil }
                    out.append("-"); j += 1
                }
                for _ in 0..<len {
                    guard j < s.count, PyText.isDecimal(s[j]) else { return nil }
                    out.append(s[j]); j += 1
                }
            }
            return PyText.string(out)
        }
        for marker in markers {
            let m = Scalars(marker.unicodeScalars)
            if anchored {
                if PyText.hasPrefix(s, m), let id = idAt(m.count) { return id }
            } else {
                var from = 0
                while let i = PyText.firstIndex(of: m, in: s, from: from) {
                    if let id = idAt(i + m.count) { return id }
                    from = i + 1
                }
            }
        }
        return nil
    }
}

/// Python `urllib.parse.urlsplit` 的子集：scheme、netloc、path、（略去 query／fragment）。
///
/// 重現 3.13 的三個前處理——去掉前導的 C0 控制字元與空白、刪掉 ASCII tab 與換行、`://` 之後到第一個 `/?#` 為 netloc——因為
/// 規則以 `netloc.lower()` 精確比對主機（帶埠號的網址**不**符合，舊實作同樣）。
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
