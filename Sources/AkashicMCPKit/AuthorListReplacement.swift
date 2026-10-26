import Foundation
import AkashicCore
import AkashicStoreIO

/// ## `--replace-authors`（`replace_authors`，#742）：依作品全文整組替換作者列
///
/// 在此之前會改 `authors` 的面全是局部的（`resolve-people` 改一格的身分、`--split-author`／`--un-split`／`--drop-author`
/// 改一格的數量、`enrich --include-absent-authors` 只在全空時補、Zotero pull 只對主來源是 Zotero 的 work）。觸發實例
/// `claw2018framework`：Crossref 給的 20 位與 PDF 第 1 頁 byline 的 7 位不同，唯一的修法是手改 YAML。
///
/// **它是判定**（`two-kinds-of-edits` 的 AI 欄）：哪一行是 byline、人名怎麼切、哪一段是成員名單，要讀全文才知道。所以依據
/// （哪一份全文、第幾頁）與理由必填，寫成一筆**作者列替換記錄**（`AuthorListReplacementRecordValue`，design D2／D3），
/// 實跑前要求這筆 work 的檔已 commit、乾淨（被移除的記錄在 git 裡有副本，design D5）。
///
/// 契約（design D1、D4–D6、Implementation Contract）：
/// - JSON 只有 `source`、`page`、`reason`、`authors` 四個必填鍵，`release`、`groupMembers` 可省；任何一層的未知鍵、缺鍵、型別不對都整批拒絕。
///   CLI 讀檔、MCP 把物件編回 JSON，兩面同一個解碼器（`decodeReplaceAuthors`）。
/// - `authors` 每一項恰好是 `literal`（個人名）、`group`（團體名，寫入時加 corporate 標記）或 `from`（原樣沿用舊作者列第 i 位，0 起算）之一。
/// - 舊作者列裡每個已歸戶的位置（`.key`／`.organization`）要嘛被恰好一個 `from` 沿用，要嘛列在 `release` 附理由；兩者都沒有即拒——
///   安靜丟掉一個 key 等於撤銷一個身分判定（`identity-is-judged-not-matched`），依名字自動對回是字串謂詞做身分判定。釋放不刪任何 verdict。
/// - 實寫時移除這筆 work 上描述舊作者列的記錄（拆分、移除、先前的替換記錄）與作者清單完整性證言，逐筆列在報告。作者列逐位元組
///   不變（只改成員名單）時只換掉先前的替換記錄、而且在原位換；什麼都沒變時 `unchanged`、不移除任何東西（#742 verify 第二輪）。
/// - `groupMembers` 有給（含空陣列）就整組替換成員名單；沒給就保留團體名仍對得上新作者列團體位的組，其餘移除並列出。團體位含
///   升格過的 organization 位（organization 上記著它是從哪個帶標記 literal 升格來的 confirmed verdict）。
/// - 預設乾跑。乾跑照樣跑寫入前檢查；store format 不足等寫入閘的拒絕在乾跑時寫進 `applyRefusal`、照樣報出計畫，實跑才擲錯。
/// - 不與另外四條腿組合（`parseUpdateEntryArguments`）。
///
/// **誠實邊界**：本面不讀全文——「這份 PDF 的 byline 是這 7 位」是呼叫端（`akashic-verify-work` skill 裡的模型與確認的人）的判斷，
/// 本面只驗形狀、身分判定有沒有被安靜丟掉，然後落地並記下依據。
struct AuthorListReplacementRequest: Equatable {
    enum Item: Equatable {
        case literal(String)
        case group(String)
        case from(Int)
    }
    struct Release: Equatable {
        let index: Int
        let reason: String
    }
    struct Members: Equatable {
        let group: String
        let page: Int
        let members: [String]
    }
    let source: String
    let page: Int
    let reason: String
    let authors: [Item]
    let release: [Release]
    /// nil＝沒給（保留仍對得上的組）；`[]`＝給了空陣列（整組替換成沒有名單）。
    let groupMembers: [Members]?
}

extension AkashicService {

    /// `verdictsOnRetiredLiterals` 在 MCP 面列幾筆（CLI 全列）。理由同 `sourcesAddedCap`：MCP 的輸出進 LLM context。
    public static let retiredLiteralVerdictsCap = 20

    // MARK: - 解碼（只看參數，#654 的形）

    static let replaceAuthorsTopKeys: Set<String> = ["source", "page", "reason", "authors", "release", "groupMembers"]

    /// 替換腿 JSON 的唯一解碼器。只看參數：不讀 store，所以 CLI 的 `validate()` 與服務都在開 store 之前跑它。
    static func decodeReplaceAuthors(_ data: Data) throws -> AuthorListReplacementRequest {
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: data) } catch {
            throw ServiceError.invalid("replace_authors 不是合法的 JSON：\(displaySafeError(error, max: 300))")   // display-safe-exempt: displaySafeError 已消毒
        }
        let top = try jsonObject(parsed, at: "replace_authors", known: replaceAuthorsTopKeys)
        let source = try jsonString(top["source"], at: "source")
        guard ProvenanceReference.isValidDigest(source) else {
            if source == ProvenanceReference.emptyContentDigest {
                throw ServiceError.invalid("source：" + ProvenanceReference.emptyContentDigestReason)   // display-safe-exempt: ProvenanceReference.emptyContentDigestReason 是常量句
            }
            throw ServiceError.invalid(
                "source「\(displaySafeInvisible(source, max: 120))」不是合法的 digest（sha256: 加 64 個小寫十六進位）")
        }
        let page = try jsonInteger(top["page"], at: "page")
        guard page >= 1 else { throw ServiceError.invalid("page 是 PDF 的實體頁序，從 1 起算；實得 \(page)") }   // display-safe-exempt: page 是 Int
        let reason = try checkedReason(try jsonString(top["reason"], at: "reason"), at: "reason")
        let authorValues = try jsonArray(top["authors"], at: "authors")
        guard !authorValues.isEmpty else { throw ServiceError.invalid("authors 不得為空——替換後的作者列至少要有一位") }
        let authors = try authorValues.enumerated().map { i, v in try decodeAuthorItem(v, at: "authors[\(i)]") }
        let release = try (top["release"].map { try jsonArray($0, at: "release") } ?? []).enumerated().map { i, v in
            let path = "release[\(i)]"
            let o = try jsonObject(v, at: path, known: ["index", "reason"])
            let index = try jsonInteger(o["index"], at: "\(path).index")
            guard index >= 0 else { throw ServiceError.invalid("\(path).index 是舊作者列的位置，從 0 起算；實得 \(index)") }   // display-safe-exempt: path 程式構造；index 是 Int
            return AuthorListReplacementRequest.Release(
                index: index, reason: try checkedReason(try jsonString(o["reason"], at: "\(path).reason"), at: "\(path).reason"))
        }
        let groupMembers = try top["groupMembers"].map { value in
            try jsonArray(value, at: "groupMembers").enumerated().map { i, v -> AuthorListReplacementRequest.Members in
                let path = "groupMembers[\(i)]"
                let o = try jsonObject(v, at: path, known: ["group", "page", "members"])
                let group = try checkedName(try jsonString(o["group"], at: "\(path).group"), at: "\(path).group")
                let gp = try jsonInteger(o["page"], at: "\(path).page")
                guard gp >= 1 else { throw ServiceError.invalid("\(path).page 是 PDF 的實體頁序，從 1 起算；實得 \(gp)") }   // display-safe-exempt: path 程式構造；gp 是 Int
                let members = try jsonArray(o["members"], at: "\(path).members").enumerated().map { j, m in
                    let s = try jsonString(m, at: "\(path).members[\(j)]")
                    guard s.utf8.count <= AddOnlyEnrichment.maxValueBytes else {
                        throw ServiceError.invalid("\(path).members[\(j)] 超過 65,536 bytes")   // display-safe-exempt: path 程式構造；j 是 Int
                    }
                    return s
                }
                return AuthorListReplacementRequest.Members(group: group, page: gp, members: members)
            }
        }
        return AuthorListReplacementRequest(source: source, page: page, reason: reason, authors: authors,
                                            release: release, groupMembers: groupMembers)
    }

    private static func decodeAuthorItem(_ value: Any, at path: String) throws -> AuthorListReplacementRequest.Item {
        guard let o = value as? [String: Any] else { throw ServiceError.invalid("\(path) 必須是 object") }   // display-safe-exempt: path 程式構造
        let unknown = o.keys.filter { !["literal", "group", "from"].contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw ServiceError.invalid("\(path) 有未知的鍵「\(unknown.map { displaySafeInvisible($0, max: 80) }.joined(separator: "、"))」——"   // display-safe-exempt: path 程式構造；鍵名逐一消毒
                + "作者項只收 literal、group、from")
        }
        guard o.count == 1, let (key, v) = o.first else {
            throw ServiceError.invalid("\(path) 必須恰好一個鍵（literal、group、from 三選一）")   // display-safe-exempt: path 程式構造
        }
        switch key {
        case "from":
            let i = try jsonInteger(v, at: "\(path).from")
            guard i >= 0 else { throw ServiceError.invalid("\(path).from 是舊作者列的位置，從 0 起算；實得 \(i)") }   // display-safe-exempt: path 程式構造；i 是 Int
            return .from(i)
        case "literal":
            let s = try checkedName(try jsonString(v, at: "\(path).literal"), at: "\(path).literal")
            guard !CorporateName.isMarked(s) else {
                throw ServiceError.invalid("\(path).literal 已帶 corporate 大括號——團體名改用 group 項（不含大括號），寫入時會加上標記")   // display-safe-exempt: path 程式構造
            }
            return .literal(s)
        default:
            let s = try checkedName(try jsonString(v, at: "\(path).group"), at: "\(path).group")
            guard !CorporateName.isMarked(s) else {
                throw ServiceError.invalid("\(path).group 不得自帶大括號——寫入時會加上 corporate 標記")   // display-safe-exempt: path 程式構造
            }
            // `mark` 只在外面包一層大括號、不確認結果：`A} {B` 會寫成 `{A} {B}`，那不是帶標記的名字，export-bib 照人名切開它（#742 verify）
            guard CorporateName.isMarked(CorporateName.mark(s)) else {
                throw ServiceError.invalid("\(path).group 的大括號不平衡——加上 corporate 標記之後不是一個帶標記的團體名；整批拒絕、零寫入")   // display-safe-exempt: path 程式構造
            }
            return .group(s)
        }
    }

    /// 作者名與團體名的共同上限：非空白、前後無空白、不含 repo 的不安全碼位（`nameScalarIssue`）、不在段括號旁黏字、不含替換記錄的段分隔字元、至多 65,536 bytes。
    private static func checkedName(_ s: String, at path: String) throws -> String {
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalid("\(path) 不得空白")   // display-safe-exempt: path 程式構造
        }
        guard s == s.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ServiceError.invalid("\(path) 前後不得有空白——寫進 store 的值是逐字的")   // display-safe-exempt: path 程式構造
        }
        if let issue = AuthorListReplacementRecordValue.nameScalarIssue(s) {
            throw ServiceError.invalid("\(path) \(issue)；整批拒絕、零寫入")   // display-safe-exempt: path 程式構造；issue 只含十六進位碼位與常量句
        }
        guard !s.contains(AuthorListReplacementRecordValue.openBracket),
              !s.contains(AuthorListReplacementRecordValue.closeBracket) else {
            throw ServiceError.invalid("\(path) 不得含 ⟦ 或 ⟧（替換記錄的段分隔字元）")   // display-safe-exempt: path 程式構造
        }
        guard s.utf8.count <= AddOnlyEnrichment.maxValueBytes else {
            throw ServiceError.invalid("\(path) 超過 65,536 bytes")   // display-safe-exempt: path 程式構造
        }
        return s
    }

    private static func checkedReason(_ s: String, at path: String) throws -> String {
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalid("\(path) 不得空白——替換與釋放都是判定，理由必填")   // display-safe-exempt: path 程式構造
        }
        guard s.utf8.count <= LibraryStore.maxStatementBytes else {
            throw ServiceError.invalid("\(path) 超過 4,096 bytes（實得 \(s.utf8.count)）")   // display-safe-exempt: path 程式構造；s.utf8.count 是 Int
        }
        return s
    }

    // MARK: JSON 的型別檢查（JSONSerialization 的值——bool 與浮點要明確擋，否則 `true`、`1.0` 會被當成整數）

    private static func jsonObject(_ value: Any?, at path: String, known: Set<String>) throws -> [String: Any] {
        guard let value else { throw ServiceError.invalid("缺 \(path)") }   // display-safe-exempt: path 程式構造
        guard let o = value as? [String: Any] else { throw ServiceError.invalid("\(path) 必須是 JSON object") }   // display-safe-exempt: path 程式構造
        let unknown = o.keys.filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw ServiceError.invalid("\(path) 有未知的鍵「\(unknown.map { displaySafeInvisible($0, max: 80) }.joined(separator: "、"))」"   // display-safe-exempt: path 程式構造；鍵名逐一消毒
                + "——只收 \(known.sorted().joined(separator: "、"))；整批拒絕、零寫入")   // display-safe-exempt: known 是程式常量
        }
        return o
    }

    private static func jsonArray(_ value: Any?, at path: String) throws -> [Any] {
        guard let value else { throw ServiceError.invalid("缺 \(path)") }   // display-safe-exempt: path 程式構造
        guard let a = value as? [Any] else { throw ServiceError.invalid("\(path) 必須是陣列") }   // display-safe-exempt: path 程式構造
        return a
    }

    private static func jsonString(_ value: Any?, at path: String) throws -> String {
        guard let value else { throw ServiceError.invalid("缺 \(path)") }   // display-safe-exempt: path 程式構造
        guard let s = value as? String else { throw ServiceError.invalid("\(path) 必須是字串") }   // display-safe-exempt: path 程式構造
        return s
    }

    private static func jsonInteger(_ value: Any?, at path: String) throws -> Int {
        guard let value else { throw ServiceError.invalid("缺 \(path)") }   // display-safe-exempt: path 程式構造
        switch JSONInteger.classify(value) {
        case .integer(let i): return i
        case .notAnInteger:
            throw ServiceError.invalid("\(path) 必須是整數（不收字串、布林或小數）")   // display-safe-exempt: path 程式構造
        case .outOfRange:
            throw ServiceError.invalid("\(path) 超出整數範圍——不截斷成另一個數；整批拒絕、零寫入")   // display-safe-exempt: path 程式構造
        }
    }

    // MARK: - 服務

    /// 作者位的位元組形：先標種類再接值——literal「key:x」與 person key「x」的段字串相同，位元組形不同。

    /// 一組成員名單的位元組形（`GroupMemberList.byteKey`），用來判斷「名單有沒有變」——`GroupMemberList ==` 比的是 Unicode 正規等價。
    static func memberListBytes(_ l: GroupMemberList) -> [UInt8] { l.byteKey }

    /// 一個作者位寫進替換記錄（與報告）的字串形：literal 原值、`key:<k>`、`organization:<k>`（design D3）。
    static func replacementSegment(_ a: Author) -> String {
        switch a {
        case .literal(let s): return s
        case .key(let k): return "key:\(k)"   // display-safe-exempt: k 受 StoreKey 約束（[a-z0-9-]）；呈現端另外消毒
        case .organization(let k): return "organization:\(k)"   // display-safe-exempt: k 受 StoreKey 約束；呈現端另外消毒
        }
    }

    func replaceEntryAuthors(citekey: String, request: AuthorListReplacementRequest, dryRun: Bool,
                             verdictsLimit: Int?) throws -> String {
        let entry = try requireEntry(citekey)   // 無法唯一定位（#628／#641）與不存在都在這裡拒絕
        let label = "work「\(displaySafeInvisible(citekey, max: 200))」"

        // 依據：連在這筆 work 上、本機有這份內容
        guard entry.akashic.sources.contains(request.source) else {
            throw ServiceError.invalid(
                "source \(request.source) 沒有連在\(label)的 akashic.sources——替換的依據必須是這篇作品自己的全文；"   // display-safe-exempt: request.source 已過 isValidDigest；label 已消毒
                + "先用 update-entry --add-source（MCP add_sources）連上，整批拒絕、零寫入")
        }
        switch try store.sourcePresence(digests: [request.source])[request.source] {
        case .stored(let index)?:
            // 依據要是作品的全文 PDF：替換記錄說「依據第 N 頁」，而筆記或補充檔沒有那一頁（#742 verify）
            guard index["media-type"] == "application/pdf" else {
                throw ServiceError.invalid(
                    "source \(request.source) 在 sources/ 的 media-type 是「\(displaySafeInvisible(index["media-type"] ?? "（無）", max: 80))」，"   // display-safe-exempt: request.source 已過 isValidDigest
                    + "不是 application/pdf——替換的依據要是這篇作品的全文 PDF；整批拒絕、零寫入")
            }
        case .absent?, nil:
            throw ServiceError.invalid("source \(request.source)：本機的 sources/ 沒有這份存檔——依據要在本機讀得到；整批拒絕、零寫入")   // display-safe-exempt: request.source 已過 isValidDigest
        default:
            throw ServiceError.invalid("source \(request.source)：sources/ 裡的這份存檔讀不到或與 index 對不上（先跑 akashic doctor）；整批拒絕、零寫入")   // display-safe-exempt: request.source 已過 isValidDigest
        }

        // design D4：已歸戶的位置要被沿用或明列釋放
        let old = entry.authors
        var carried = Set<Int>()
        for item in request.authors {
            guard case .from(let i) = item else { continue }
            guard i < old.count else {
                throw ServiceError.invalid("from \(i) 超出舊作者列的範圍（\(old.count) 位，0 起算）；整批拒絕、零寫入")   // display-safe-exempt: i 與 count 是 Int
            }
            guard carried.insert(i).inserted else {
                throw ServiceError.invalid("from \(i) 用了兩次——同一個舊位置只能沿用一次；整批拒絕、零寫入")   // display-safe-exempt: i 是 Int
            }
        }
        var released: [Int: String] = [:]
        for r in request.release {
            guard r.index < old.count else {
                throw ServiceError.invalid("release 的 index \(r.index) 超出舊作者列的範圍（\(old.count) 位）；整批拒絕、零寫入")   // display-safe-exempt: r.index 與 old.count 是 Int
            }
            if case .literal(let s) = old[r.index] {
                throw ServiceError.invalid(
                    "release 只收已歸戶的位置；第 \(r.index) 位是 literal「\(displaySafeInvisible(s, max: 200))」——literal 不需要釋放，不寫進新列即可")   // display-safe-exempt: r.index 是 Int
            }
            guard !carried.contains(r.index) else {
                throw ServiceError.invalid("第 \(r.index) 位同時被 from 沿用又列在 release——兩者擇一；整批拒絕、零寫入")   // display-safe-exempt: r.index 是 Int
            }
            guard released[r.index] == nil else {
                throw ServiceError.invalid("release 的 index \(r.index) 出現兩次；整批拒絕、零寫入")   // display-safe-exempt: r.index 是 Int
            }
            released[r.index] = r.reason
        }
        let dropped = old.enumerated().filter { i, a in
            if case .literal = a { return false }
            return !carried.contains(i) && released[i] == nil
        }
        guard dropped.isEmpty else {
            throw ServiceError.invalid(
                "舊作者列有 \(dropped.count) 個已歸戶的位置既沒有被 from 沿用、也沒有列在 release："   // display-safe-exempt: dropped.count 是 Int
                + dropped.map { "第 \($0.offset) 位 \(displaySafeInvisible(Self.replacementSegment($0.element), max: 200))" }.joined(separator: "、")   // display-safe-exempt: $0.offset 是 Int；值逐一消毒
                + "——安靜丟掉一個已歸戶的位置等於撤銷一個身分判定。用 {\"from\": i} 沿用，或在 release 逐位附理由；整批拒絕、零寫入")   // display-safe-exempt: i 是說明文字裡的字母，不是插值
        }

        // 新作者列
        let newAuthors: [Author] = request.authors.map { item in
            switch item {
            case .literal(let s): return .literal(s)
            case .group(let s): return .literal(CorporateName.mark(s))
            case .from(let i): return old[i]
            }
        }
        let segments = newAuthors.map(Self.replacementSegment)
        guard let record = AuthorListReplacementRecordValue(segments: segments, page: request.page, reason: request.reason) else {
            // 說出真正原因（#742 verify 第三輪：記錄寫不成有三種原因，訊息原本只說 ⟦ ⟧）。新寫入的名字已被名字閘擋過，
            // 走到這裡的是 from 沿用的舊值或理由
            if let (i, problem) = segments.enumerated().lazy.compactMap({ e in
                AuthorListReplacementRecordValue.segmentProblem(e.element).map { (e.offset, $0) } }).first {
                throw ServiceError.invalid(
                    "新作者列第 \(i) 位（\(displaySafeInvisible(segments[i], max: 200))）寫不成替換記錄的段：\(problem)——"   // display-safe-exempt: i 是 Int；problem 是常量句
                    + "那是以 from 沿用的舊值；先用 resolve-people 或 update-entry 處理那一位，整批拒絕、零寫入")
            }
            if let problem = AuthorListReplacementRecordValue.reasonProblem(request.reason) {
                throw ServiceError.invalid("reason \(problem)；整批拒絕、零寫入")   // display-safe-exempt: problem 是常量句
            }
            throw ServiceError.invalid("新作者列寫不成替換記錄；整批拒絕、零寫入")
        }

        // design D6：成員名單。團體位＝新作者列中帶 corporate 標記的 literal（不論來自 group 項還是 from 沿用），以及**升格過的團體位**：
        // organization 位，其 organization 帶一筆把本 work 與一個帶標記 literal 配對的 confirmed verdict（attribute-org 升格時留下、不動
        // group-members），那一位算作那個 literal——否則名單在升格後只活到下一次替換（#742 verify 第二輪）。比位元組（spec「byte-equal」）
        // 升格的三條路寫的 literal 形狀不同：attribute-org 寫作者位原值（帶大括號），resolve-organizations 的 --apply／--judge 寫
        // OrgResolver 去標記後的名字——兩種都認，一律先 mark(unmark(…))（#742 verify 第三輪）。organization key 不唯一時讀哪一筆取決於
        // 載入順序，取錯就刪掉名單，所以拒絕、不以先到先贏消解
        let load = try store.load()
        let orgsByKey = Dictionary(grouping: load.organizations, by: \.key)
        var newGroups = Set<[UInt8]>()
        for a in newAuthors {
            switch a {
            case .literal(let s) where CorporateName.isMarked(s):
                newGroups.insert(Array(s.utf8))
            case .organization(let k):
                let records = orgsByKey[k] ?? []
                guard records.count <= 1 else {
                    throw ServiceError.invalid(
                        "新作者列的 organization 位「\(displaySafeInvisible(k, max: 200))」對到 \(records.count) 筆 organization（key 重複）——"   // display-safe-exempt: records.count 是 Int
                        + "讀哪一筆的判定取決於載入順序；先修好重複（akashic validate 列出），整批拒絕、零寫入")
                }
                for r in records.first?.references ?? [] where r.field == ProvenanceReference.resolutionConfirmedField {
                    guard let v = r.value, let pv = ProvenanceReference.VerdictPairingValue.parse(v),
                          pv.holderKind == .work, pv.holder == entry.citekey else { continue }
                    newGroups.insert(Array(CorporateName.mark(CorporateName.unmark(pv.literal)).utf8))
                }
            default: break
            }
        }
        var membersAfter: [GroupMemberList]
        if let given = request.groupMembers {
            membersAfter = []
            for (i, m) in given.enumerated() {
                let group = CorporateName.mark(m.group)
                guard newGroups.contains(Array(group.utf8)) else {
                    throw ServiceError.invalid(
                        "groupMembers[\(i)] 的團體「\(displaySafeInvisible(m.group, max: 200))」對不上新作者列的任何團體位（逐字、逐位元組比）——"   // display-safe-exempt: i 是 Int
                        + "名單要掛在作者列裡那一個團體位上；整批拒絕、零寫入")
                }
                if let problem = GroupMemberList.problem(group: group, restsOn: request.source, page: m.page, members: m.members) {
                    throw ServiceError.invalid("groupMembers[\(i)]：\(problem)；整批拒絕、零寫入")   // display-safe-exempt: i 是 Int；problem 是常量句
                }
                membersAfter.append(GroupMemberList(group: group, restsOn: request.source, page: m.page, members: m.members)!)
            }
            if let problem = Entry.groupMembersProblem(membersAfter) {
                throw ServiceError.invalid("groupMembers：\(problem)；整批拒絕、零寫入")   // display-safe-exempt: problem 是常量句
            }
        } else {
            membersAfter = entry.groupMembers.filter { newGroups.contains(Array($0.group.utf8)) }
        }
        let membersRemoved = entry.groupMembers.filter { old in
            !membersAfter.contains { Self.memberListBytes($0) == Self.memberListBytes(old) }
        }

        // design D5：描述舊作者列的記錄一併移除——作者列逐位元組相同（典型是只補成員名單）時，舊列沒有被取代，拆分記錄、移除記錄與
        // 證言描述的仍是現在這份作者列，只換掉先前的替換記錄（替換記錄是 value 缺席的那一種，D3）
        let authorsUnchanged = newAuthors.map(\.byteKey) == old.map(\.byteKey)
        let isRemoved: (ProvenanceReference) -> Bool = { $0.field == "authors" && (!authorsUnchanged || $0.value == nil) }
        let newRecord = ProvenanceReference(field: "authors", value: nil,
                                            kind: .judgement(statement: record.encoded, restsOn: [request.source]))
        var updated = entry
        var recordsRemoved = entry.references.filter(isRemoved)
        updated.authors = newAuthors
        // 作者列相同時，先前的替換記錄**在原位**換成新的：references 是保序陣列，搬到最後會讓重跑同一份 JSON 因次序不同被判成有變
        //（#742 verify 第二輪）。作者列換了的時候舊記錄全部移除、新記錄接在最後
        var refs: [ProvenanceReference] = []
        var placed = false
        for r in entry.references {
            guard isRemoved(r) else { refs.append(r); continue }
            if authorsUnchanged && !placed { refs.append(newRecord); placed = true }
        }
        if !placed { refs.append(newRecord) }
        updated.references = refs
        let removedWitness = authorsUnchanged ? nil : entry.akashic.authorListCompleteness
        if !authorsUnchanged { updated.akashic.authorListCompleteness = nil }
        updated.groupMembers = membersAfter
        // `Entry ==` 比的是 Unicode 正規等價：只換了正規化寫法的替換會被當成沒變，所以作者列與名單另比位元組
        // references 也比位元組：只改理由的正規化寫法時 `updated == entry` 仍成立，新理由會被當成沒變而不寫（#742 verify 第三輪）
        let unchanged = updated == entry && authorsUnchanged
            && membersAfter.map(Self.memberListBytes) == entry.groupMembers.map(Self.memberListBytes)
            && updated.references.map(\.byteExactKey) == entry.references.map(\.byteExactKey)
        if unchanged { recordsRemoved = [] }   // 什麼都沒變：沒有東西被移除（先前列出原樣寫回的那一筆，#742 verify 第二輪）

        // 報告：person／organization 上仍指向本 work、literal 已不在新作者列任何 literal 位的 confirmed verdict（只列不改）。
        // **寫入之前算完**：寫入之後才讀 store，讀取失敗時檔案已改寫卻只回報錯誤，呼叫端拿不到被移除了什麼（#742 verify）
        let newLiterals = Set(newAuthors.compactMap { a -> [UInt8]? in if case .literal(let s) = a { return Array(s.utf8) } else { return nil } })
        let newKeys = Set(newAuthors.compactMap { a -> String? in if case .key(let k) = a { return "person:\(k)" } else { return nil } })
            .union(newAuthors.compactMap { a -> String? in if case .organization(let k) = a { return "organization:\(k)" } else { return nil } })
        var retired: [[String: Any]] = []
        func scan(_ refs: [ProvenanceReference], holder: String) {
            for r in refs where r.field == ProvenanceReference.resolutionConfirmedField {
                guard let v = r.value, let pv = ProvenanceReference.VerdictPairingValue.parse(v),
                      pv.holderKind == .work, pv.holder == citekey, !newLiterals.contains(Array(pv.literal.utf8)) else { continue }
                retired.append(["record": displaySafe(holder, max: 220),
                                "literal": displaySafe(pv.literal, max: 400),
                                "carriedOver": newKeys.contains(holder)])   // display-safe-exempt: Bool
            }
        }
        for p in load.people.sorted(by: { $0.key < $1.key }) { scan(p.references, holder: "person:\(p.key)") }
        for o in load.organizations.sorted(by: { $0.key < $1.key }) { scan(o.references, holder: "organization:\(o.key)") }

        // 寫入前的檢查兩種模式都跑；乾跑時寫入閘的拒絕（例如 store format 不足）只記在報告、照樣報出計畫
        var applyRefusal: String?
        if !unchanged {
            do { try store.preflightWrite(updated) } catch {
                if !dryRun { throw error }
                applyRefusal = displaySafeError(error, max: 1_200)
            }
        }
        var rebuildFailure: Error?
        if !dryRun && !unchanged {
            try assertRecordsRecoverable([(entry.id, label)],
                                         action: "這次會替換\(label)的作者列，並移除 \(recordsRemoved.count) 筆描述舊作者列的記錄",   // display-safe-exempt: label 已消毒；count 是 Int
                                         issue: "#742")
            try store.writeEntry(updated)
            rebuildFailure = rebuildIndexCapturingFailure()
        }

        func listed(_ authors: [Author]) -> [String] { authors.map { displaySafe(Self.replacementSegment($0), max: 400) } }
        func membersDict(_ l: GroupMemberList) -> [String: Any] {
            ["group": displaySafe(l.group, max: 400), "page": l.page,   // display-safe-exempt: page 是 Int
             "members": l.members.map { displaySafe($0, max: 400) },
             "restsOn": l.restsOn]   // display-safe-exempt: l.restsOn 是 GroupMemberList 建構時驗過的 digest（sha256:<64 hex>）
        }
        var payload: [String: Any] = [
            "citekey": displaySafe(citekey, max: 200),
            "dryRun": dryRun,   // display-safe-exempt: Bool
            "unchanged": unchanged,   // display-safe-exempt: Bool
            "authorsBefore": listed(old),
            "authorsAfter": listed(newAuthors),
            "replacementRecord": displaySafe(record.encoded, max: 70_000),
            "released": request.release.map { r -> [String: Any] in
                ["index": r.index,   // display-safe-exempt: Int
                 "value": displaySafe(Self.replacementSegment(old[r.index]), max: 400),
                 "reason": displaySafe(r.reason, max: Self.maxStatementBytes)]
            },
            "recordsRemoved": recordsRemoved.map { r -> [String: Any] in
                var d: [String: Any] = [:]
                if let v = r.value { d["value"] = displaySafe(v, max: 400) }
                if case .judgement(let s, let restsOn) = r.kind {
                    d["statement"] = displaySafe(s, max: 70_000)
                    d["restsOn"] = restsOn   // display-safe-exempt: restsOn 在 decode 時過 isValidDigest
                }
                return d
            },
            "witnessRemoved": removedWitness != nil,   // display-safe-exempt: Bool
            "groupMembersAfter": membersAfter.map(membersDict),
            "groupMembersRemoved": membersRemoved.map(membersDict),
            "verdictsOnRetiredLiterals": verdictsLimit.map { Array(retired.prefix($0)) } ?? retired,
        ]
        if let limit = verdictsLimit {
            payload["verdictsOnRetiredLiteralsTotal"] = retired.count   // display-safe-exempt: Int
            payload["truncated"] = retired.count > limit   // display-safe-exempt: Bool
        }
        if let w = removedWitness {
            // 裁決 4「逐筆列出」：證言是一筆，列出它斷言了什麼（完整原文在 git 的副本裡）
            payload["witnessRemovedDetail"] = [
                "fingerprint": w.fingerprint.digest,   // display-safe-exempt: digest 在 AuthorListFingerprint.init 過 isWellFormedDigest
                "attestedAuthors": listed(w.attestedAuthors),
                "references": w.references.count,   // display-safe-exempt: Int
            ] as [String: Any]
        }
        if !retired.isEmpty {
            payload["verdictsNote"] = "這些 confirmed verdict 判的 literal 已不在新作者列的任何 literal 位；本面不改它們。"
                + "carriedOver 為 true 的那幾筆，key 仍以 from 留在新作者列，verdict 是當初升格的依據，不必處理；"
                + "其餘的指向已退役的作者位，要不要留由人判斷"
        }
        if let applyRefusal {
            payload["applyRefusal"] = applyRefusal
        }
        if dryRun {
            payload["dryRunNote"] = "乾跑：沒有寫入。實跑（CLI --apply、MCP dry_run:false）要求這筆 work 的檔已在 git 裡 commit、乾淨"
        }
        if let rebuildFailure { Self.noteIndexRebuildFailure(rebuildFailure, in: &payload) }
        return try jsonString(payload)
    }
}
