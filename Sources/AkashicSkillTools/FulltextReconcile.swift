import Foundation
import AkashicCore
import AkashicStoreIO

/// `akashic fulltext text`（與之後的 `compare`）的確定性計算（#742，design D11）：從一筆 work 連著的全文取逐頁文字、判斷有沒有文字層。
///
/// **不寫 store、不連網、不做 OCR**。沒有文字層（`hasTextLayer: false`）是 `akashic-verify-work` skill 改走 bestOCR 的觸發條件（D14），
/// OCR 在 skill 那一層做：本 binary 的輸出要確定，而 OCR 的結果取決於本機裝了哪些引擎。
public enum FulltextReconcile {

    /// 一頁有沒有字母：含任何 Unicode 字母（general category L——Lu／Ll／Lt／Lm／Lo）。只有數字、標點、空白的頁不算有字母
    /// （掃描頁常被 OCR 前置流程塞進頁碼）。skill 以逐頁的值決定哪幾頁走 OCR——出版商加一頁有字的封面、其餘是掃描圖的 PDF，
    /// 整份看起來有文字層，byline 所在的頁卻沒有字（#742 verify、使用者 2026-10-25 的決定）。
    public static func hasLetters(_ page: String) -> Bool {
        page.unicodeScalars.contains { s in
            switch s.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
            default: return false
            }
        }
    }

    /// 沒有文字層的判準：沒有任何一頁有字母。
    public static func hasTextLayer(_ pages: [String]) -> Bool {
        pages.contains(where: hasLetters)
    }

    /// 這筆 work 要讀哪一份全文：`akashic.sources` 裡 index 記為 `application/pdf` 的那一份。
    /// 連著不只一份（或有讀不出種類的）而沒指定時拒絕、列出各 digest——不猜是哪一份。
    public static func chooseSource(entry: Entry, requested: String?, store: LibraryStore) throws -> (digest: String, url: URL) {
        let label = "work「\(displaySafeInvisible(entry.citekey, max: 200))」"
        let linked = entry.akashic.sources
        let presence = linked.isEmpty ? [:] : try store.sourcePresence(digests: linked)
        func isPDF(_ d: String) -> Bool {
            if case .stored(let e)? = presence[d] { return e["media-type"] == "application/pdf" }
            return false
        }
        func notLocal(_ d: String) -> Bool {
            if case .stored? = presence[d] { return false }
            return true
        }
        let digest: String
        if let requested {
            guard linked.contains(requested) else {
                throw SkillToolError.failure("--source \(displaySafeInvisible(requested, max: 120)) 沒有連在\(label)的 akashic.sources——"   // display-safe-exempt: label 已消毒
                    + "只讀這篇作品自己的全文（先用 update-entry --add-source 連上）")
            }
            digest = requested
        } else {
            let pdfs = linked.filter(isPDF)
            let unknown = linked.filter(notLocal)
            guard !(pdfs.isEmpty && unknown.isEmpty) else {
                throw SkillToolError.failure("\(label)沒有連任何 PDF 全文（akashic.sources 裡沒有 media-type 是 application/pdf 的存檔）——"   // display-safe-exempt: label 已消毒
                    + "先用 akashic-fetch-fulltext 取得並連上")
            }
            guard pdfs.count + unknown.count == 1 else {
                let listed = (pdfs + unknown).map { d in d + (notLocal(d) ? "（本機 sources/ 讀不到，判不出種類）" : "") }
                    .joined(separator: "、")
                throw SkillToolError.failure("\(label)連著不只一份可能是 PDF 的存檔，用 --source 指定一份：\(listed)")   // display-safe-exempt: label 已消毒；listed 的每一項是 decode 時過 isValidDigest 的 digest 加固定句
            }
            digest = pdfs.first ?? unknown[0]
        }
        switch presence[digest] {
        case .stored(let e)?:
            guard e["media-type"] == "application/pdf" else {
                throw SkillToolError.failure("\(digest) 的 media-type 是「\(displaySafeInvisible(e["media-type"] ?? "（無）", max: 80))」，不是 application/pdf")   // display-safe-exempt: digest 已過 isValidDigest
            }
        case .absent?, nil:
            throw SkillToolError.failure("\(digest)：本機的 sources/ 沒有這份存檔——sources/ 不進 git，換機器後要重新取得")   // display-safe-exempt: digest 已過 isValidDigest
        default:
            throw SkillToolError.failure("\(digest)：sources/ 裡的這份存檔讀不到或與 index 對不上（先跑 akashic doctor）")   // display-safe-exempt: digest 已過 isValidDigest
        }
        guard let url = store.sourceBlobURL(digest: digest) else {
            throw SkillToolError.failure("\(digest) 不是合法的 digest 形狀")   // display-safe-exempt: digest 已過 isValidDigest
        }
        return (digest, url)
    }

    /// `fulltext text` 的輸出 JSON：`{"citekey", "source", "sourcePath", "pageCount", "hasTextLayer", "pages": [{"page", "hasLetters", "text"}]}`。
    /// 頁文字是第三方原文，原樣寫出（給 skill 讀的機器格式；消毒會改寫它）。`sourcePath` 是那份全文在本機 `sources/` 的實體路徑——
    /// skill 要把它複製給 bestOCR，不必自己拼分片規則（位址規則只有 `SourceStore` 一份）。
    public static func textJSON(citekey: String, digest: String, sourcePath: String, pageCount: Int, pages: [String]) throws -> Data {
        let object: [String: Any] = [
            "citekey": citekey,   // display-safe-exempt: citekey 受 StoreKey 約束；本 JSON 是給 skill 讀的機器格式
            "source": digest,
            "sourcePath": sourcePath,   // display-safe-exempt: 本 JSON 是給 skill 讀的機器格式
            "pageCount": pageCount,
            "hasTextLayer": hasTextLayer(pages),
            "pages": pages.enumerated().map {
                ["page": $0.offset + 1, "hasLetters": hasLetters($0.element), "text": $0.element] as [String: Any]
            },
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    /// `--out` 的規則（design D11）：父目錄以實體路徑判斷，必須在任何 git 工作樹之外（全文是第三方有版權的內容）；目標**必須還不存在**——
    /// `--out` 是 agent 可被引導指定的路徑（同 `fulltext take`），不得覆寫一個既有的檔、不得跟隨 symlink、不得寫進 FIFO（#742 verify）。
    /// 回傳實體路徑；寫入一律經 `write(_:to:)`。
    public static func checkOutput(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let dir = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw SkillToolError.failure("--out 的目錄 \(displaySafeInvisible(dir.path, max: 300)) 不存在")
        }
        let physicalDir = URL(fileURLWithPath: dir.path).resolvingSymlinksInPath().path
        let target = physicalDir + "/" + url.lastPathComponent
        switch try OutputFile.inspect(target) {
        case .absent: break
        case .regular:
            throw SkillToolError.failure("--out \(displaySafeInvisible(target, max: 300)) 已經存在——本命令不覆寫既有的檔；換一個檔名")
        case .other(let kind):
            throw SkillToolError.failure("--out \(displaySafeInvisible(target, max: 300)) 已經存在而且是 \(displaySafeInvisible(kind, max: 40))——"
                + "本命令只寫新的普通檔，不跟隨 symlink")
        }
        guard !LibraryStore.isInsideVersionedWorkTree(URL(fileURLWithPath: physicalDir)) else {
            throw SkillToolError.failure("--out \(displaySafeInvisible(target, max: 300)) 在 git 工作樹裡——全文是第三方內容，"
                + "寫到 git 之外的暫存目錄（例如 mktemp -d）")
        }
        return target
    }

    /// 以只有擁有者可讀寫的權限原子寫出（全文是第三方內容）。`checkOutput` 之後到這裡之間有人放了東西，`OutputFile.replace` 會拒絕非普通檔。
    public static func write(_ data: Data, to target: String) throws {
        guard case .absent = try OutputFile.inspect(target) else {
            throw SkillToolError.failure("--out \(displaySafeInvisible(target, max: 300)) 在檢查之後出現了——不覆寫")
        }
        try OutputFile.replace(path: target, with: data, mode: 0o600)
    }
}

// MARK: - fulltext compare（design D11、Implementation Contract）

extension FulltextReconcile {

    /// 模型從全文讀出的提議。`authors.items` 與 `release`、`groupMembers` 原樣交給替換腿（它們的形狀由替換腿的唯一解碼器驗），
    /// 這裡只驗外層的鍵與純量欄位。
    public struct Proposal {
        public let source: String
        public let authorsPage: Int
        /// 選填：替換理由。沒給時 compare 填「PDF 第 N 頁 byline」。依 OCR 文字替換時 skill 要寫明依據是 OCR（D14）。
        public let authorsReason: String?
        public let authorItems: [Any]
        public let release: [Any]?
        public let groupMembers: [Any]?
        public let scalars: [String: (value: String, page: Int)]
    }

    /// 純量欄位與它在 store 裡的位置（封閉列舉）。卷、期、頁碼、article number 住 `fields`，鍵名照 biblatex（`number` 是期、`eid` 是 article number）。
    public static let scalarFields: [(name: String, read: (Entry) -> String?)] = [
        ("title", { $0.title }),
        ("volume", { $0.fields["volume"] }),
        ("issue", { $0.fields["number"] }),
        ("pages", { $0.fields["pages"] }),
        ("articleNumber", { $0.fields["eid"] }),
        ("date", { $0.date }),
    ]

    public static func decodeProposal(_ data: Data) throws -> Proposal {
        let top: [String: Any]
        do {
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SkillToolError.failure("--proposal 必須是 JSON object")
            }
            top = o
        } catch let e as SkillToolError { throw e } catch {
            throw SkillToolError.failure("--proposal 不是合法的 JSON：\(displaySafeErrorText(error))")
        }
        let known: Set<String> = Set(["source", "authors", "release", "groupMembers"] + scalarFields.map(\.name))
        try rejectUnknown(top, known: known, at: "proposal")
        guard let source = top["source"] as? String else { throw SkillToolError.failure("proposal 缺 source（字串）") }
        guard let authors = top["authors"] as? [String: Any] else { throw SkillToolError.failure("proposal 缺 authors（object：page、items、可選 reason）") }
        try rejectUnknown(authors, known: ["page", "items", "reason"], at: "authors")
        let page = try integer(authors["page"], at: "authors.page")
        guard let items = authors["items"] as? [Any] else { throw SkillToolError.failure("authors.items 必須是陣列") }
        let reason: String?
        if let r = authors["reason"] {
            guard let s = r as? String else { throw SkillToolError.failure("authors.reason 必須是字串") }
            reason = s
        } else { reason = nil }
        func array(_ key: String) throws -> [Any]? {
            guard let v = top[key] else { return nil }
            guard let a = v as? [Any] else { throw SkillToolError.failure("\(key) 必須是陣列") }   // display-safe-exempt: key 是程式常量
            return a
        }
        var scalars: [String: (value: String, page: Int)] = [:]
        for (name, _) in scalarFields {
            guard let v = top[name] else { continue }
            guard let o = v as? [String: Any] else { throw SkillToolError.failure("\(name) 必須是 object（value、page）") }   // display-safe-exempt: name 是程式常量
            try rejectUnknown(o, known: ["value", "page"], at: name)
            guard let value = o["value"] as? String else { throw SkillToolError.failure("\(name).value 必須是字串") }   // display-safe-exempt: name 是程式常量
            scalars[name] = (value, try integer(o["page"], at: "\(name).page"))
        }
        return Proposal(source: source, authorsPage: page, authorsReason: reason, authorItems: items,
                        release: try array("release"), groupMembers: try array("groupMembers"), scalars: scalars)
    }

    private static func rejectUnknown(_ o: [String: Any], known: Set<String>, at path: String) throws {
        let unknown = o.keys.filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw SkillToolError.failure("\(path) 有未知的鍵「\(unknown.map { displaySafeInvisible($0, max: 80) }.joined(separator: "、"))」——"   // display-safe-exempt: path 程式構造；鍵名逐一消毒
                + "只收 \(known.sorted().joined(separator: "、"))")   // display-safe-exempt: known 是程式常量
        }
    }

    private static func integer(_ v: Any?, at path: String) throws -> Int {
        switch v.map(JSONInteger.classify) {
        case .integer(let i)? where i >= 1: return i
        case .outOfRange?:
            throw SkillToolError.failure("\(path) 超出整數範圍——不截斷成另一個頁序")   // display-safe-exempt: path 程式構造
        default:
            throw SkillToolError.failure("\(path) 必須是 ≥ 1 的整數（PDF 的實體頁序）")   // display-safe-exempt: path 程式構造
        }
    }

    /// 一個作者位在比對表裡的字串形——與替換記錄的段同一種寫法（literal 原值、`key:<k>`、`organization:<k>`）。
    public static func segment(_ a: Author) -> String {
        switch a {
        case .literal(let s): return s
        case .key(let k): return "key:\(k)"   // display-safe-exempt: k 受 StoreKey 約束（[a-z0-9-]）
        case .organization(let k): return "organization:\(k)"   // display-safe-exempt: k 受 StoreKey 約束
        }
    }

    /// 逐欄比對。`validation` 是這份提議對應的替換腿物件——**不論要不要替換都交給替換腿乾跑一次**（不需要替換的提議也可能不合法，
    /// 例如 `release` 指到 literal 位；那樣的提議不得以 `refusal: null` 過關，#742 verify）；`replaceAuthors` 只在作者列或成員名單
    /// 不同時給（成員名單只有替換腿寫得進去）。比較一律逐位元組。不寫任何東西。
    public static func compare(entry: Entry, proposal p: Proposal)
        -> (rows: [[String: Any]], replaceAuthors: [String: Any]?, validation: [String: Any]) {
        let storeAuthors = entry.authors.map(segment)
        let proposedAuthors: [String] = p.authorItems.map { raw in
            guard let o = raw as? [String: Any], o.count == 1, let (k, v) = o.first else { return "（形狀不合）" }
            switch (k, v) {
            case ("literal", let s as String): return s
            case ("group", let s as String): return CorporateName.mark(s)
            case ("from", let n):
                guard case .integer(let i) = JSONInteger.classify(n) else { return "（形狀不合）" }
                return entry.authors.indices.contains(i) ? segment(entry.authors[i]) : "from \(i)（超出範圍）"
            default: return "（形狀不合）"
            }
        }
        func sameBytes(_ a: [String], _ b: [String]) -> Bool { a.map { Array($0.utf8) } == b.map { Array($0.utf8) } }
        func status(store: Any?, proposed: Any?, equal: Bool) -> String {
            if proposed == nil { return "notProposed" }
            if store == nil { return "absentInStore" }
            return equal ? "same" : "differs"
        }
        var rows: [[String: Any]] = []
        func row(_ field: String, store: Any?, proposed: Any?, page: Int?, status: String) {
            rows.append(["field": field, "store": store ?? NSNull(), "proposed": proposed ?? NSNull(),
                         "page": page.map { $0 as Any } ?? NSNull(), "status": status])
        }
        let authorsStatus = status(store: storeAuthors.isEmpty ? nil : storeAuthors, proposed: proposedAuthors,
                                   equal: sameBytes(storeAuthors, proposedAuthors))
        row("authors", store: storeAuthors.isEmpty ? nil : storeAuthors, proposed: proposedAuthors, page: p.authorsPage,
            status: authorsStatus)
        // 成員名單：與替換腿同一個寫入，所以它不同時也要產生替換物件
        let storeMembers: [[String: Any]] = entry.groupMembers.map { ["group": $0.group, "page": $0.page, "members": $0.members] }
        let proposedMembers: [[String: Any]]? = p.groupMembers?.map { raw in
            guard let o = raw as? [String: Any] else { return ["group": "（形狀不合）"] }
            var d = o
            if let g = o["group"] as? String { d["group"] = CorporateName.mark(g) }
            return d
        }
        let membersEqual: Bool = {
            guard let proposedMembers else { return true }
            let a = try? JSONSerialization.data(withJSONObject: storeMembers, options: .sortedKeys)
            let b = try? JSONSerialization.data(withJSONObject: proposedMembers, options: .sortedKeys)
            return a == b
        }()
        let membersStatus = status(store: storeMembers.isEmpty ? nil : storeMembers, proposed: proposedMembers,
                                   equal: membersEqual)
        row("groupMembers", store: storeMembers.isEmpty ? nil : storeMembers, proposed: proposedMembers,
            page: nil, status: membersStatus)
        for (name, read) in scalarFields {
            let s = read(entry).flatMap { $0.isEmpty ? nil : $0 }
            let given = p.scalars[name]
            row(name, store: s, proposed: given?.value, page: given?.page,
                status: status(store: s, proposed: given?.value, equal: sameBytes([s ?? ""], [given?.value ?? ""])))
        }
        let needsReplacement = authorsStatus != "same" || (membersStatus != "same" && membersStatus != "notProposed")
        var replace: [String: Any] = [
            "source": p.source,
            "page": p.authorsPage,   // display-safe-exempt: p.authorsPage 是 Int
            "reason": p.authorsReason ?? "PDF 第 \(p.authorsPage) 頁 byline",   // display-safe-exempt: p.authorsReason 是呼叫端提議的原文，進給替換腿讀的機器格式（替換腿的 payload 另外消毒）；p.authorsPage 是 Int
            "authors": p.authorItems,
        ]
        if let r = p.release { replace["release"] = r }
        if let g = p.groupMembers { replace["groupMembers"] = g }
        return (rows, needsReplacement ? replace : nil, replace)
    }
}
