import Foundation
import AkashicCore
import AkashicStoreIO

/// `akashic fulltext text`（與之後的 `compare`）的確定性計算（#742，design D11）：從一筆 work 連著的全文取逐頁文字、判斷有沒有文字層。
///
/// **不寫 store、不連網、不做 OCR**。沒有文字層（`hasTextLayer: false`）是 `akashic-verify-work` skill 改走 bestOCR 的觸發條件（D14），
/// OCR 在 skill 那一層做：本 binary 的輸出要確定，而 OCR 的結果取決於本機裝了哪些引擎。
public enum FulltextReconcile {

    /// 沒有文字層的判準：所有頁的文字都不含任何 Unicode 字母（general category L——Lu／Ll／Lt／Lm／Lo）。
    /// 只有數字、標點、空白的頁不算有字母（掃描頁常被 OCR 前置流程塞進頁碼）。
    public static func hasTextLayer(_ pages: [String]) -> Bool {
        pages.contains { page in
            page.unicodeScalars.contains { s in
                switch s.properties.generalCategory {
                case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
                default: return false
                }
            }
        }
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
                throw SkillToolError.failure("\(label)連著不只一份可能是 PDF 的存檔，用 --source 指定一份："   // display-safe-exempt: label 已消毒
                    + (pdfs + unknown).map { d in d + (notLocal(d) ? "（本機 sources/ 讀不到，判不出種類）" : "") }.joined(separator: "、"))   // display-safe-exempt: d 已過 decode 的 isValidDigest
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

    /// `fulltext text` 的輸出 JSON：`{"citekey", "source", "pageCount", "hasTextLayer", "pages": [{"page", "text"}]}`。
    /// 頁文字是第三方原文，原樣寫出（給 skill 讀的機器格式；消毒會改寫它）。
    public static func textJSON(citekey: String, digest: String, pageCount: Int, pages: [String]) throws -> Data {
        let object: [String: Any] = [
            "citekey": citekey,
            "source": digest,
            "pageCount": pageCount,
            "hasTextLayer": hasTextLayer(pages),
            "pages": pages.enumerated().map { ["page": $0.offset + 1, "text": $0.element] as [String: Any] },
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    /// `--out` 必須在任何 git 工作樹之外（全文是第三方有版權的內容，design D11）；父目錄要已經存在，位置上不得是目錄。
    public static func checkOutput(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let dir = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw SkillToolError.failure("--out 的目錄 \(displaySafeInvisible(dir.path, max: 300)) 不存在")
        }
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            throw SkillToolError.failure("--out \(displaySafeInvisible(url.path, max: 300)) 是目錄，不是檔案")
        }
        guard !LibraryStore.isInsideVersionedWorkTree(dir) else {
            throw SkillToolError.failure("--out \(displaySafeInvisible(url.path, max: 300)) 在 git 工作樹裡——全文是第三方內容，"
                + "寫到 git 之外的暫存目錄（例如 mktemp -d）")
        }
        return url
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
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), !CFNumberIsFloatType(n), n.intValue >= 1 else {
            throw SkillToolError.failure("\(path) 必須是 ≥ 1 的整數（PDF 的實體頁序）")   // display-safe-exempt: path 程式構造
        }
        return n.intValue
    }

    /// 一個作者位在比對表裡的字串形——與替換記錄的段同一種寫法（literal 原值、`key:<k>`、`organization:<k>`）。
    public static func segment(_ a: Author) -> String {
        switch a {
        case .literal(let s): return s
        case .key(let k): return "key:\(k)"
        case .organization(let k): return "organization:\(k)"
        }
    }

    /// 逐欄比對，與（作者列或成員名單不同時）可直接交給 `update-entry --replace-authors` 的物件。不寫任何東西。
    public static func compare(entry: Entry, proposal p: Proposal) -> (rows: [[String: Any]], replaceAuthors: [String: Any]?) {
        let storeAuthors = entry.authors.map(segment)
        let proposedAuthors: [String] = p.authorItems.map { raw in
            guard let o = raw as? [String: Any], o.count == 1, let (k, v) = o.first else { return "（形狀不合）" }
            switch (k, v) {
            case ("literal", let s as String): return s
            case ("group", let s as String): return CorporateName.mark(s)
            case ("from", let n as NSNumber):
                let i = n.intValue
                return entry.authors.indices.contains(i) ? segment(entry.authors[i]) : "from \(i)（超出範圍）"
            default: return "（形狀不合）"
            }
        }
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
                                   equal: storeAuthors == proposedAuthors)
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
                status: status(store: s, proposed: given?.value, equal: s == given?.value))
        }
        let needsReplacement = authorsStatus != "same" || (membersStatus != "same" && membersStatus != "notProposed")
        guard needsReplacement else { return (rows, nil) }
        var replace: [String: Any] = [
            "source": p.source,
            "page": p.authorsPage,
            "reason": p.authorsReason ?? "PDF 第 \(p.authorsPage) 頁 byline",
            "authors": p.authorItems,
        ]
        if let r = p.release { replace["release"] = r }
        if let g = p.groupMembers { replace["groupMembers"] = g }
        return (rows, replace)
    }
}
