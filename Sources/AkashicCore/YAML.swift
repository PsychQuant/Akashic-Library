import Foundation
import Yams

public enum StoreYAMLError: Error, LocalizedError, Equatable {
    case notAMapping
    case missingField(String)
    case invalidField(String, String)
    /// 頂層沒有任何已知的形狀裸標籤。`stray` 是看到的其他裸鍵（可能是打錯的形狀名）。
    case unknownShapeLabel([String])
    /// 形狀標籤帶了值（`person: true`）。允許帶值等於重新造出一個後設欄位。
    case shapeLabelHasValue(String)
    /// 多個互不從屬的形狀標籤——沒有唯一的最具體者，不猜。
    case ambiguousShapeLabels([String])
    /// 標籤與 `type:` 各自指向不同形狀。不得挑一邊。
    case shapeLabelContradiction(label: String, typeField: String)

    public var errorDescription: String? {
        let known = EntityKind.knownLabels.sorted().joined(separator: "、")
        switch self {
        case .notAMapping: return "YAML 頂層不是 mapping"
        case .missingField(let f): return "缺少必要欄位：\(f)"
        case .invalidField(let f, let why): return "欄位 \(f) 無效：\(why)"
        case .unknownShapeLabel(let stray):
            // 具名 + 重導。只說「不認得」只證明它在這個位置沒有意義；
            // 讀者還需要知道哪個位置有意義。
            guard !stray.isEmpty else {
                return "缺少形狀標籤。每筆記錄的頂層須有一個無值的形狀鍵（已知：\(known)）。"
            }
            let names = stray.map { "「\(displaySafe($0))」" }.joined(separator: "、")
            let redirects = stray.compactMap { EntityKind.misplacedElsewhere[$0] }
            let tail = redirects.isEmpty ? "" : "——\(redirects.joined(separator: "；"))"
            return "頂層的無值鍵 \(names) 不是已知形狀（已知：\(known)）\(tail)。"
        case .shapeLabelHasValue(let name):
            return """
                形狀標籤「\(displaySafe(name))」不得帶值——它是標籤，不是欄位。\
                帶值等於重新造出一個後設欄位，只是名字換成形狀名。
                """
        case .ambiguousShapeLabels(let labels):
            return """
                有多個互不從屬的形狀標籤（\(labels.map { displaySafe($0) }.joined(separator: "、"))），\
                無法決定最具體者。不猜——請只留下最具體的那一個。
                """
        case let .shapeLabelContradiction(label, typeField):
            return """
                形狀標籤「\(displaySafe(label))」與 type 欄位的「\(displaySafe(typeField))」矛盾。\
                type 是 work 專屬的書目類型，不是形狀名；兩者衝突時不得挑一邊。
                """
        }
    }
}

/// store 格式刻意只存秒精度（無 fractional seconds）——truncation 是規格不是 bug。
/// canary 比對前必須把模型的 Date 正規化到同一精度（R5 CRITICAL：次秒 Date 的
/// 合法寫入被 identity 比對誤拒）。
private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

/// Entry ↔ YAML。手動建 Node 以控制欄位順序（id → citekey → type → title →
/// authors → date → fields → attachments → provenance → akashic），
/// 空集合省略——round-trip 以值相等為準。
public enum EntryYAML {
    public static func encode(_ entry: Entry) throws -> String {
        var pairs: [(Node, Node)] = []
        // 形狀裸標籤放最前面：讀檔的人第一眼看到的就是「這是什麼」。
        // 值是空 scalar，序列化成 `work:`（無值）。
        pairs.append((Node(EntityKind.work.rawValue), Node("")))
        pairs.append((Node("id"), Node(entry.id.uuidString)))
        pairs.append((Node("citekey"), Node(entry.citekey)))
        pairs.append((Node("type"), Node(entry.type)))
        pairs.append((Node("title"), Node(entry.title)))
        if !entry.authors.isEmpty {
            let authorNodes: [Node] = entry.authors.map { author in
                switch author {
                case .key(let k): return Node([(Node("key"), Node(k))] as [(Node, Node)])
                case .literal(let s): return Node([(Node("literal"), Node(s))] as [(Node, Node)])
                }
            }
            pairs.append((Node("authors"), Node(authorNodes)))
        }
        if let date = entry.date {
            pairs.append((Node("date"), Node(date)))
        }
        if !entry.fields.isEmpty {
            let fieldPairs: [(Node, Node)] = entry.fields.keys.sorted().map {
                (Node($0), Node(entry.fields[$0]!))
            }
            pairs.append((Node("fields"), Node(fieldPairs)))
        }
        if !entry.attachments.isEmpty {
            let nodes: [Node] = entry.attachments.map {
                Node([(Node($0.kind.rawValue), Node($0.path))] as [(Node, Node)])
            }
            pairs.append((Node("attachments"), Node(nodes)))
        }
        if let prov = entry.provenance {
            var p: [(Node, Node)] = [
                (Node("zotero_key"), Node(prov.zoteroKey)),
                (Node("zotero_version"), Node(String(prov.zoteroVersion))),
            ]
            if let lid = prov.libraryID {
                p.append((Node("library_id"), Node(String(lid))))
            }
            if let hash = prov.zoteroHash {
                p.append((Node("zotero_hash"), Node(hash)))
            }
            if let at = prov.importedAt {
                p.append((Node("imported_at"), Node(isoFormatter.string(from: at))))
            }
            if let at = prov.orphanedAt {
                p.append((Node("orphaned_at"), Node(isoFormatter.string(from: at))))
            }
            pairs.append((Node("provenance"), Node(p)))
        }
        var a: [(Node, Node)] = []
        if !entry.akashic.tags.isEmpty {
            a.append((Node("tags"), Node(entry.akashic.tags.map { Node($0) })))
        }
        if !entry.akashic.libraries.isEmpty {
            a.append((Node("libraries"), Node(entry.akashic.libraries.map { Node($0) })))
        }
        if let status = entry.akashic.status {
            a.append((Node("status"), Node(status)))
        }
        if !entry.akashic.relations.isEmpty {
            var r: [(Node, Node)] = []
            if !entry.akashic.relations.cites.isEmpty {
                r.append((Node("cites"), Node(entry.akashic.relations.cites.map { Node($0) })))
            }
            if !entry.akashic.relations.related.isEmpty {
                r.append((Node("related"), Node(entry.akashic.relations.related.map { Node($0) })))
            }
            a.append((Node("relations"), Node(r)))
        }
        // akashic 有 known 內容才進 serialize；它是 pairs 的最後一段——
        // 之後 append 的縮排 2 nested raw 區塊仍屬 akashic mapping（α 佈局不變式）
        if !a.isEmpty {
            pairs.append((Node("akashic"), Node(a)))
        }
        var out = try Yams.serialize(node: Node(pairs), allowUnicode: true)
        if !entry.akashic.unknownFields.isEmpty {
            if a.isEmpty { out += "akashic:\n" }   // known 全空但有 nested raw → 手寫 header
            try appendRawBlocks(entry.akashic.unknownFields, to: &out, targetIndent: 2,
                                context: "akashic")
        }
        try appendRawBlocks(entry.unknownFields, to: &out, targetIndent: 0, context: "entry")
        // 語意 canary（R4，R6 修訂）：parse-only 驗不出「合法但不是我們要寫的
        // 東西」。R6 兩項修訂（DA R5）：
        // (1) 無條件執行——R5 只在有未知欄位時跑，漏掉純 known 檔的寫入自毀
        //     路徑（emitter plain 樣式與 decode 嚴格性不對合時，寫得出、讀不回）。
        // (2) 比較對象是「正規化後的模型」不是 identity——store 只存秒精度，
        //     次秒 Date 必須先截到 encoder 精度，否則合法寫入被誤拒（R5 CRITICAL）。
        try encodeCanary(out, context: "entry")
        let rd = try decode(out)
        var ca = rd, cb = canaryNormalized(entry)
        ca.unknownFields = []; cb.unknownFields = []
        ca.akashic.unknownFields = []; cb.akashic.unknownFields = []
        guard ca == cb,
              rd.unknownFields.map(\.key) == entry.unknownFields.map(\.key),
              rd.akashic.unknownFields.map(\.key) == entry.akashic.unknownFields.map(\.key)
        else {
            // R7：指認不符欄位（R6-verify M13——泛用訊息無從人工行動）
            throw StoreYAMLError.invalidField(
                "entry", "encode 語意自檢失敗——\(canaryMismatchDetail(ca, cb))，拒絕寫出")
        }
        // R6（L16）：未知欄位「值」的語意比對——key 序列相符不蘊含值未漂移
        // （縮排平移等寫出路徑的防護此前只靠切分計數偶然擋下）。
        // R8：encode 側預算同樣單次呼叫共用（跨 entry/akashic 兩層）。
        // R10 更正（R9-verify L18/L26）：R9 的 2× 放寬無效——實際約束是上方
        // canary 的內層 decode（自帶 200k），且 compose 不計預算、兩側消耗
        // 對稱。維持與 decode 相同的 200k。
        var encodeBudget = 200_000
        try verifyUnknownValuesPreserved(rd.unknownFields, entry.unknownFields,
                                         context: "entry", budget: &encodeBudget)
        try verifyUnknownValuesPreserved(rd.akashic.unknownFields, entry.akashic.unknownFields,
                                         context: "akashic", budget: &encodeBudget)
        return out
    }

    /// canary 的比較基準：把序列化有損的已知欄位（provenance 的兩個 Date，
    /// 秒精度）正規化到 encoder 精度。字串欄位另有一條已知有損通道——**前導
    /// U+FEFF**（Yams serialize 後 compose 會吃掉 quoted 開頭的 BOM）——刻意
    /// **不**正規化：那是資料品質問題，fail-closed 拒寫 + 欄位指認訊息
    /// （見 canaryMismatchDetail），不做靜默改資料（R6-verify M13）。
    static func canaryNormalized(_ entry: Entry) -> Entry {
        var e = entry
        if let d = e.provenance?.importedAt {
            e.provenance?.importedAt = isoFormatter.date(from: isoFormatter.string(from: d))
        }
        if let d = e.provenance?.orphanedAt {
            e.provenance?.orphanedAt = isoFormatter.date(from: isoFormatter.string(from: d))
        }
        return e
    }

    /// canary 不符時指認欄位（R7）：泛用「產物與模型不符」讓人工無從行動。
    static func canaryMismatchDetail(_ a: Entry, _ b: Entry) -> String {
        var bad: [String] = []
        if a.id != b.id { bad.append("id") }
        if a.citekey != b.citekey { bad.append("citekey") }
        if a.type != b.type { bad.append("type") }
        if a.title != b.title { bad.append("title") }
        if a.authors != b.authors { bad.append("authors") }
        if a.date != b.date { bad.append("date") }
        if a.fields != b.fields { bad.append("fields") }
        if a.attachments != b.attachments { bad.append("attachments") }
        if a.provenance != b.provenance { bad.append("provenance") }
        if a.akashic != b.akashic { bad.append("akashic") }
        return bad.isEmpty
            ? "未知欄位 key 序列不符"
            : "欄位不符：\(bad.joined(separator: "、"))（常見原因：值含前導 U+FEFF 等序列化有損字元）"
    }

    /// R6（L16）：寫出前後各未知區塊獨立 compose、語意比對——值漂移拒寫。
    /// 兩側 raw 縮排可能不同（平移是合法的），比對走 node 語意不走文字。
    /// R7（R6-verify HIGH）：預算為**單次呼叫共用**、不是 per-block 重置——
    /// N 個接近上限的區塊不可聚合成 N × 200k 的比對量（CPU 放大面）。
    static func verifyUnknownValuesPreserved(_ got: [UnknownField], _ want: [UnknownField],
                                             context: String, budget: inout Int) throws {
        guard got.count == want.count else {
            throw StoreYAMLError.invalidField(
                context, "encode 語意自檢失敗——未知欄位數不符，拒絕寫出")
        }
        for (g, w) in zip(got, want) {
            guard let gn = composeBlock(g.raw), let wn = composeBlock(w.raw) else {
                throw StoreYAMLError.invalidField(
                    context, "未知欄位「\(w.key)」寫出前後無法獨立解析——拒絕寫出")
            }
            // 顯式 .some/.none：`case true/false/nil` 對 `Bool?` 的窮盡性檢查
            // 在 Swift 6.3 通過、6.1.2 不通過（「add missing case: '.some(_)'」）。
            // 寫成 pattern 才與宣告的 swift-tools-version 5.9 相稱。
            switch nodesSemanticallyEqual(gn, wn, budget: &budget) {
            case .some(true): break
            case .some(false):
                throw StoreYAMLError.invalidField(
                    context, "未知欄位「\(w.key)」寫出前後語意不符（值漂移）——拒絕寫出")
            case .none:
                // R8（R7-verify L21）：共用預算——耗盡可能來自較早的區塊
                throw StoreYAMLError.invalidField(
                    context, "未知欄位「\(w.key)」處超出共用驗證預算（消耗可能來自同檔較早的區塊）——fail-closed")
            }
        }
    }

    /// 區塊獨立 compose（以首行縮排 dedent；nested raw 帶原縮排、直接 compose 不合法）。
    static func composeBlock(_ raw: String) -> Yams.Node? {
        let text = raw.hasSuffix("\n") ? raw : raw + "\n"
        let firstLine = text.prefix(while: { $0 != "\n" })
        let base = firstLine.count - firstLine.drop(while: { $0 == " " }).count
        var dedented = text
        if base > 0 {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.last?.isEmpty == true { lines.removeLast() }
            dedented = ""
            for line in lines {
                let strip = min(base, line.prefix(while: { $0 == " " }).count)
                dedented += line.dropFirst(strip) + "\n"
            }
        }
        return (try? Yams.compose(yaml: dedented)) ?? nil
    }

    /// fields 鍵允許的 resolved tag 閉集（R10）：plain 樣式在 core resolver 下
    /// 可能落到的型別面。merge（`<<`）/ value（`=`）不在集內——語意在 parser
    /// 間分歧（merge 面產物他家 loader 會展開/報錯）。顯式 core tag（`!!int 123`）
    /// 與 plain `123` 在 Yams resolved-tag 層不可區分——接受並正規化為 plain
    /// （已記載於 §5 的保真邊界）。
    static let fieldsKeyTags: [Tag] = [
        Tag(.str), Tag(.int), Tag(.float), Tag(.bool), Tag(.null), Tag(.timestamp),
    ]

    /// **形狀裸標籤也算已知鍵。** 不列入的話，tolerant-preserve 會把它當未知欄位
    /// 逐字保留並在寫回時重新產生——舊的 `type: person` 也是同理，見 `knownPersonKeys`。
    static let knownTopLevelKeys: Set<String> = Set([
        "id", "citekey", "type", "title", "authors", "date",
        "fields", "attachments", "provenance", "akashic",
    ]).union(EntityKind.knownLabels)
    static let knownAkashicKeys: Set<String> = ["tags", "libraries", "status", "relations"]
    static let knownRelationsKeys: Set<String> = ["cites", "related"]
    static let knownProvenanceKeys: Set<String> = [
        "zotero_key", "zotero_version", "library_id", "zotero_hash",
        "imported_at", "orphaned_at",
    ]

    /// store-format §5 strict 策略（v1.3 起僅限 closed shape：authors / provenance /
    /// akashic.relations）：未知欄位＝decode 錯誤。開放演化層（entry / person /
    /// library 頂層與 akashic namespace）改走 captureUnknownBlocks 逐字保留（α）。
    static func rejectUnknownKeys(_ map: Yams.Node.Mapping, known: Set<String>,
                                  context: String) throws {
        for (key, _) in map {
            guard let k = key.string else {
                throw StoreYAMLError.invalidField(context, "非字串鍵")
            }
            // R7（R6-verify security HIGH）：closed shape 的 tagged-shadow 守衛——
            // tag 非 str 的同名鍵 subscript 讀不到，optional 欄位會被靜默歸零、
            // 寫回即剝除（required 欄位本就 fail-closed）。與 keyStrings 同款。
            if key.tag != Tag(.str) {
                throw StoreYAMLError.invalidField(
                    context, "鍵「\(k)」帶非字串 tag——closed shape 不接受（fail-closed）")
            }
            if !known.contains(k) {
                throw StoreYAMLError.invalidField(context, "未知欄位「\(k)」（strict schema；見 docs/store-format.md §5）")
            }
        }
    }

    // MARK: - tolerant-preserve（§5 v1.3 α，#23）：raw-text 保留

    /// 列出 mapping 的 key 字串（文件序）並施行 key 層檢查：
    /// 非 scalar 鍵（complex key）→ throw；merge key `<<` → throw；
    /// R6（M5/M8）：字串與 known key 同名但 tag 非 str 的鍵 → throw——這種鍵
    /// `map[...]`（str-tag subscript）讀不到、又被字串比對歸為 known 而不進
    /// unknownFields，寫回即靜默剝除，fail-closed。unknown 鍵不受此限（含同
    /// 字串不同 tag 的重複——切分/oracle/寫回全走文件序 index，型別在 raw 內
    /// 保真；testTypedKeysSurviveWriteBack 守著這條）。
    static func keyStrings(_ map: Yams.Node.Mapping, known: Set<String>,
                           context: String) throws -> [String] {
        var keys: [String] = []
        for (key, _) in map {
            guard let k = key.string else {
                throw StoreYAMLError.invalidField(context, "非字串鍵")
            }
            // R11（R10-verify H1，codex+logic 雙 lens 實測）：merge / value 語意由
            // **tag** 決定，不由鍵名字串決定——Yams 自己的 merge 實作就是比 tag
            // （`Node.Mapping.flatten()` 判 `pair.key.tag.name == .merge`）。R10 以前
            // 用 `k == "<<"` 字串比對，兩個方向都錯：
            //   漏擋：`!!merge foo:` 的字串面是 `foo`，字串測試看不到 → 被當未知
            //         欄位收下並原樣寫回；merge-aware loader 讀同一份檔案會展開成
            //         另一份記錄（實測可把 `orcid` 這種 known 欄位注入進去）。
            //   過擋：quoted `'<<'` 依 YAML 是普通字串（tag = str），卻被字串測試拒收。
            // 改判 tag 後兩個方向同時修正。`=`（value 面）同理——R10-verify DA 實測
            // 頂層 `=` 被收下並原樣寫回。
            if key.tag == Tag(.merge) || key.tag == Tag(.value) {
                let face = key.tag == Tag(.merge) ? "merge「<<」" : "value「=」"
                throw StoreYAMLError.invalidField(
                    context, "\(face)面的鍵不入 tolerant 範圍——語意在 parser 間分歧"
                             + "（見 docs/store-format.md §5）")
            }
            if known.contains(k), key.tag != Tag(.str) {
                throw StoreYAMLError.invalidField(
                    context, "鍵「\(k)」帶非字串 tag 且與 known 欄位同名——不入 tolerant 範圍（fail-closed）")
            }
            keys.append(k)
        }
        return keys
    }

    /// 行尾守衛（R6 限縮、R7 更正）：擋 **CR/CRLF/NEL** 三個「有損通道」——
    /// libyaml 讀取時會把 quoted scalar 內的 CR/NEL 摺疊成空白（毀字），且本
    /// binary 的 emitter 對兩者都 escape（自家產物永不含 raw CR/NEL，守衛零
    /// 誤殺）；CR 另有 Swift grapheme 行模型分歧（R4 CRITICAL 死碼守衛）。
    /// **LS/PS 不擋**：quoted 內被 libyaml 依 YAML 1.1 摺疊規則**保留**（實測
    /// round-trip 無損），且 emitter 自己就會寫出 raw U+2028——R5 的全文掃描
    /// 把自家產物整檔誤殺（DA R5 (b)+(c)）。plain scalar 含裸 LS 會讓 libyaml
    /// 多切出 key：帶未知欄位時由切分計數 oracle fail-closed；純 known 檔無此
    /// 防線（已知盲區，§5 記載）。必須在 unicodeScalar 層比對。
    static func assertLFOnly(_ text: String, context: String) throws {
        if text.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\u{85}" }) {
            throw StoreYAMLError.invalidField(
                context, "CR/CRLF/NEL 不支援（libyaml 讀取時摺疊毀字、行模型分歧，fail-closed；請正規化為 LF 或以 escape 表示）")
        }
    }

    /// 毀字通道守衛——**全部 decode 入口無條件執行**（R8：R7 的守衛只長在
    /// splitBlocks，純 known 檔（無未知欄位、不走切分）仍會被 libyaml 靜默
    /// 摺疊毀字後寫回——DA M23 只關了一半）。R9 限縮到 **NEL only**
    /// （R8-verify M11/L26 更正）：CR 系（CRLF、lone-CR 行尾）是 libyaml 依規範
    /// 正規化的**行尾慣例**（classic-Mac lone-CR 檔 v1.2 可無損載入，R8 的
    /// 裸 CR 掃描把它推下懸崖）；quoted 內的 CR 摺疊與 LF/CRLF 摺疊結果完全
    /// 相同（spec 摺疊語意，非毀字）。NEL 不同：不是任何行尾慣例、emitter
    /// 一律 escape（自家產物零誤殺）、且是 cp1252 `…` 誤轉的常見內容字元——
    /// 內容被摺疊即為毀字。帶未知欄位的檔另由 splitBlocks 的 assertLFOnly
    /// 全面拒收 CR + NEL（切分結構分歧）。
    /// **關於 alias-in-key 的 DoS——為什麼這裡沒有守衛（R12 更正）**：R11 曾在此
    /// 加一道文字層 `? key` 守衛，試圖擋 `Yams.compose` 內部的 hash 展開。該修復
    /// **兩個方向都錯**，已 revert：
    ///   - **沒關掉洞**：YAML 的 mapping key 根本不需要 `?`。實測三條繞道
    ///     （`*a12: 1` block 隱式、`{? *a12 : 1}` flow 顯式、`{*a12: 1}` flow 隱式）
    ///     在 630–645 bytes 下全部 25 s timeout。判準（`? ` 語法）與要防的失敗
    ///     （alias 落在 key 位置）不是同一件事。
    ///   - **製造新回歸**：守衛掃全文字、無 YAML context，於是 block scalar 與
    ///     折行續行以 `? ` 開頭的**合法內容**被誤判——實測 `note: |` 內含
    ///     `? what is this` 的檔案被 quarantine，而 encode 內含 decode canary，
    ///     這種記錄變成永遠寫不回。
    /// 該 DoS **不是本 PR 引入的**（`main` 的三個 decode 入口同樣 compose-first）；
    /// 文字層補不到 flow context 與 implicit alias key，正確的層是 profile gate
    /// （禁 anchor/alias，見 #33）或 Yams 端。已另立 issue 追蹤（#36），本檔不再嘗試
    /// 在文字層攔截——繼續加 `?` 變體只會重複 R5/R6/R10 的震盪。
    static func assertNoLossyContentChars(_ text: String, context: String) throws {
        if text.unicodeScalars.contains(where: { $0 == "\u{85}" }) {
            throw StoreYAMLError.invalidField(
                context, "NEL (U+0085) 不支援（libyaml 讀取時摺疊毀字，fail-closed；請正規化或以 escape 表示）")
        }
        // R10（R9-verify HIGH，DA 判別式）：CR 的雙面性以「檔內有無 LF」裁決——
        // 全檔無 LF ⇒ CR 是 classic-Mac 行尾（v1.2 可無損載入，放行）；
        // 檔內有 LF ⇒ 行尾已由 LF/CRLF 承擔，**不接 LF 的裸 CR 只能是內容**
        // （Word/RIS 貼入 quoted scalar 的 0x0D），libyaml 讀取時摺疊毀字 →
        // 拒收（R8 的保護回歸；R9 把它連同行尾慣例一起拆掉是回歸）。emitter
        // 對內容 CR 一律 escape（IS_PRINTABLE 不含 0x0D），自家產物零誤殺。
        let scalars = text.unicodeScalars
        guard scalars.contains(where: { $0 == "\n" }) else { return }
        var i = scalars.startIndex
        while i < scalars.endIndex {
            if scalars[i] == "\r" {
                let next = scalars.index(after: i)
                if next == scalars.endIndex || scalars[next] != "\n" {
                    throw StoreYAMLError.invalidField(
                        context, "裸 CR 不支援（LF 檔內的 CR 是內容字元，libyaml 讀取時摺疊毀字，fail-closed；請以 escape 表示）")
                }
            }
            i = scalars.index(after: i)
        }
    }

    /// stream 標記行判定：`---`/`...` token 之後僅允許空白或註解（YAML 允許
    /// `--- # comment`、`... ` 等變體——R5 只認裸字串，變體被誤判為 entry
    /// 起始而整檔 quarantine——R5 M6/L14）。
    static func isStreamMarkerBody(_ trimmed: Substring) -> Bool {
        guard trimmed.hasPrefix("---") || trimmed.hasPrefix("...") else { return false }
        let rest = trimmed.dropFirst(3).drop(while: { $0 == " " || $0 == "\t" })
        return rest.isEmpty || rest.first == "#"
    }

    /// 把 block-style YAML 文件切成同層 entry 的原文區塊（保留原縮排與註解）。
    /// `indent` 為該層 entry 的基準縮排（頂層 = 0）。entry 起始行 = 縮排恰為基準、
    /// 首字非 `#`、非 sequence 指標（`-` + 空白/行尾）、非 stream 標記
    /// （`---`/`...` 含尾隨空白/註解變體）、非 col-0 `%` directive 的行；
    /// 其餘行歸屬當前區塊。前導行（entry 開始前的註解、directive、`---`）不屬
    /// 任何區塊。CR/CRLF → throw（見 assertLFOnly）。
    /// 多文件由 root compose 拒收（單文件 stream 假設），此處不設文字層守衛
    /// （R3：守衛只會誤傷 block scalar 內容行）。
    static func splitBlocks(_ text: String, indent: Int, context: String) throws -> [String] {
        try assertLFOnly(text, context: context)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // 只移除 split 的檔尾 artifact（最後一個 \n 之後的空片段）——
        // 真實空行（含 |+ keep-chomping 的尾端空行）逐字保留，且 round-trip 不累積
        if text.hasSuffix("\n"), lines.last?.isEmpty == true {
            lines.removeLast()
        }
        var blocks: [[Substring]] = []
        var current: [Substring] = []
        for line in lines {
            let trimmed = line.drop(while: { $0 == " " })
            let lineIndent = line.count - trimmed.count
            let isDocMarker = isStreamMarkerBody(trimmed)
                || (lineIndent == 0 && trimmed.first == "%")
            let isSequenceItem = trimmed.first == "-"
                && (trimmed.count == 1 || trimmed.dropFirst().first == " "
                    || trimmed.dropFirst().first == "\t")
            let isEntryStart = lineIndent == indent && !trimmed.isEmpty
                && trimmed.first != "#" && !isSequenceItem && !isDocMarker
            if isEntryStart {
                if !current.isEmpty { blocks.append(current) }
                current = [line]
            } else if !current.isEmpty {
                current.append(line)
            }
            // else: 前導行，丟棄（known 欄位重寫本就不保留檔案級註解）
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks.map { $0.joined(separator: "\n") + "\n" }
    }

    /// 未知欄位的原文擷取：切分區塊 → 以 compose 的 key 序對齊 → 計數校驗 →
    /// **對齊 oracle**（R3：計數相等不蘊含對齊——flow 錯位 / tagged decoy 都能
    /// 保持計數抵銷）。每個未知區塊必須：獨立 compose 成功（跨區塊 anchor/alias
    /// 在此擋下）、恰為單一 entry、key 相符、值與原 parse 的節點語意相等（預算
    /// 走訪）。任何一項不成立 → throw → load 層 quarantine（檔案原封不動，
    /// 絕不冒錯位寫壞的險）。無未知欄位時零成本快路徑。
    static func captureUnknownBlocks(text: String, map: Yams.Node.Mapping, keys: [String],
                                     known: Set<String>, indent: Int,
                                     context: String, budget: inout Int) throws -> [UnknownField] {
        guard keys.contains(where: { !known.contains($0) }) else { return [] }
        let blocks = try splitBlocks(text, indent: indent, context: context)
        guard blocks.count == keys.count else {
            throw StoreYAMLError.invalidField(
                context,
                "無法可靠切分未知欄位原文（區塊 \(blocks.count) ≠ 欄位 \(keys.count)；版面超出容忍層契約，見 docs/store-format.md §5 版面契約）")
        }
        let entries = Array(map)
        var out: [UnknownField] = []
        for (i, k) in keys.enumerated() where !known.contains(k) {
            let raw = stripDocMarkers(blocks[i])
            try verifyBlockOracle(raw: raw, dedent: indent, expectedKey: k,
                                  originalValue: entries[i].value, context: context,
                                  budget: &budget)
            out.append(UnknownField(key: k, raw: raw))
        }
        return out
    }

    /// 流層標記剝除（R4，R6 擴為變體規則）：column-0 的 `---` / `...`（含尾隨
    /// 空白/註解變體）與 `%` directive 是 stream-scoped token、不屬於任何欄位
    /// 資料；被吸進可搬移的未知區塊會讓 encode 產物永遠無法解析（「讀得到但
    /// 永遠寫不回」）。縮排的 `...` 是 scalar 內容，不受影響。
    static func stripDocMarkers(_ raw: String) -> String {
        guard raw.contains("---") || raw.contains("...") || raw.contains("%") else { return raw }
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        if raw.hasSuffix("\n"), lines.last?.isEmpty == true { lines.removeLast() }
        let kept = lines.filter { line in
            let trimmed = line.drop(while: { $0 == " " })
            let isColZeroMarker = line.count == trimmed.count
                && (isStreamMarkerBody(trimmed) || trimmed.first == "%")
            return !isColZeroMarker
        }
        return kept.joined(separator: "\n") + "\n"
    }

    /// 對齊 oracle：區塊獨立 re-parse 並與原 parse 節點比對。
    /// R7：`budget` 由呼叫端供給、**單次 decode 全檔共用**（不 per-block 重置）。
    static func verifyBlockOracle(raw: String, dedent: Int, expectedKey: String,
                                  originalValue: Yams.Node, context: String,
                                  budget: inout Int) throws {
        var text = raw
        if dedent > 0 {
            var shifted = ""
            var lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            if raw.hasSuffix("\n"), lines.last?.isEmpty == true { lines.removeLast() }
            for line in lines {
                let strip = min(dedent, line.prefix(while: { $0 == " " }).count)
                shifted += line.dropFirst(strip) + "\n"
            }
            text = shifted
        }
        let composed: Yams.Node?
        do {
            // #36：oracle 的獨立 compose 同樣要先過預算——未知區塊本身也可能是 bomb，
            // 而它在這裡是被單獨 compose 的（整檔的守衛涵蓋不到「區塊獨立解析」這一步
            // 的成本，因為整檔通過不代表每個切片都便宜）。
            try AliasEventBudget.check(text, context: context)
            composed = try Yams.compose(yaml: text)
        } catch let e as AliasBudgetError {
            throw e
        } catch {
            throw StoreYAMLError.invalidField(
                context, "未知欄位「\(expectedKey)」的區塊無法獨立解析（跨區塊 anchor/alias 或切分錯位）")
        }
        guard let m = composed?.mapping, m.count == 1, let entry = m.first,
              entry.key.string == expectedKey else {
            throw StoreYAMLError.invalidField(
                context, "未知欄位「\(expectedKey)」的區塊對齊校驗失敗（切分錯位，fail-closed）")
        }
        switch nodesSemanticallyEqual(entry.value, originalValue, budget: &budget) {
        case .some(true):
            break
        case .some(false):
            throw StoreYAMLError.invalidField(
                context, "未知欄位「\(expectedKey)」的區塊值與 parse 結果不符（切分錯位，fail-closed）")
        case .none:
            // 預算耗盡 ≠ 不相符——比對次數與節點數線性相關：巨大未知子樹或
            // anchor/alias 重用型 DAG 都會觸發（R6 更正：R5 誤稱「與檔案大小
            // 無關」——alias-free 的 70k+ 節點子樹同樣打穿）。訊息分開，診斷
            // 才可行動。
            throw StoreYAMLError.invalidField(
                context, "未知欄位「\(expectedKey)」超出驗證預算（節點數、anchor/alias 展開或巢狀深度超過上限）——fail-closed")
        }
    }

    /// 預算制節點語意等值（scalar 比 string+resolvedTag；collection 逐元素）。
    /// 回傳 nil = 預算耗盡（alias 展開型 DAG 比對爆炸）或深度超限——呼叫端
    /// fail-closed。R8（R7-verify L31）：預算只界定廣度；深巢狀子樹會先
    /// stack overflow 崩潰而非 quarantine，故另設遞迴深度上限。
    static func nodesSemanticallyEqual(_ a: Yams.Node, _ b: Yams.Node,
                                       budget: inout Int, depth: Int = 0) -> Bool? {
        budget -= 1
        if budget <= 0 || depth > 512 { return nil }
        switch (a, b) {
        case (.scalar(let x), .scalar(let y)):
            // Node.Scalar 的 == 即 string + resolvedTag 比較（Yams 公開語意）
            return x == y
        case (.sequence(let x), .sequence(let y)):
            guard x.count == y.count else { return false }
            for (u, v) in zip(x, y) {
                guard let r = nodesSemanticallyEqual(u, v, budget: &budget, depth: depth + 1) else { return nil }
                if !r { return false }
            }
            return true
        case (.mapping(let x), .mapping(let y)):
            guard x.count == y.count else { return false }
            for ((k1, v1), (k2, v2)) in zip(Array(x), Array(y)) {
                guard let rk = nodesSemanticallyEqual(k1, k2, budget: &budget, depth: depth + 1) else { return nil }
                if !rk { return false }
                guard let rv = nodesSemanticallyEqual(v1, v2, budget: &budget, depth: depth + 1) else { return nil }
                if !rv { return false }
            }
            return true
        default:
            return false
        }
    }

    /// 未知區塊寫回：逐字 append（零 parse、零 serialize——保真與防放大的機制核心）。
    /// `targetIndent` ≠ 原縮排時做**等量平移**：整塊每行加/減同量前導空白，
    /// YAML 相對縮排不變（block scalar 內容安全）。dedent 時縮排不足的**語意行**
    /// → throw（R6 M7：clamp 會把續行推到 column 0，產生 decode 切不開的產物
    /// ——「讀得到但永遠寫不回」的凍結記錄；fail-closed 比默默寫壞好）；
    /// 註解/空行 clamp 無害（compose 忽略、`#` 行不觸發 entry-start）。
    /// CR 守衛同樣適用於程式化構造的 raw（R5 L17：encode 路徑此前無守衛，
    /// 靠 canary 間接攔且訊息歸錯因）。
    static func appendRawBlocks(_ fields: [UnknownField], to out: inout String,
                                targetIndent: Int, context: String) throws {
        for f in fields {
            // 不變式：raw 以 \n 結尾（程式化構造缺尾換行時補上，
            // 否則 split 的 artifact 移除會吃掉最後一行內容——R3 LOW）
            let raw = f.raw.hasSuffix("\n") ? f.raw : f.raw + "\n"
            try assertLFOnly(raw, context: context)
            let firstLine = raw.prefix(while: { $0 != "\n" })
            let baseIndent = firstLine.count - firstLine.drop(while: { $0 == " " }).count
            if baseIndent == targetIndent {
                out += raw
                continue
            }
            let delta = targetIndent - baseIndent
            var lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.last?.isEmpty == true { lines.removeLast() }   // 檔尾 artifact only
            for (i, line) in lines.enumerated() {
                if line.isEmpty {
                    out += "\n"
                    continue
                }
                let indentCount = line.prefix(while: { $0 == " " }).count
                let body = line.dropFirst(indentCount)
                // 平移不變式（R6 M7，R7 精確化）：語意續行平移後必須仍深於
                // targetIndent，否則在下一次 decode 會被判為同層 entry 起始——
                // 區塊切不開、該記錄「讀得到但永遠寫不回」。豁免三類與
                // splitBlocks 的 entry-start oracle 對齊的行（R6-verify HIGH：
                // 不變式必須鏡射切分規則，不能只看縮排）：
                // (a) 註解行——`#` 行不觸發 entry-start，clamp 無害；
                // (b) 空白-only 行——語意等同空行（R6 只認零長度是 bug）；
                // (c) sequence 指標行——YAML 允許 indentationless sequence，
                //     splitBlocks 亦排除 `- ` 行；平移後落在 targetIndent 合法，
                //     低於 targetIndent 才是結構破壞。
                let isSeqIndicator = body.first == "-"
                    && (body.count == 1 || body.dropFirst().first == " "
                        || body.dropFirst().first == "\t")
                let floor = isSeqIndicator ? targetIndent - 1 : targetIndent
                if i > 0, !body.isEmpty, body.first != "#",
                   indentCount + delta <= floor {
                    throw StoreYAMLError.invalidField(
                        context,
                        "未知欄位「\(f.key)」縮排平移會破壞原文結構（續行平移後不深於目標縮排），無法安全寫回")
                }
                if delta > 0 {
                    out += String(repeating: " ", count: delta) + line + "\n"
                } else {
                    out += line.dropFirst(min(-delta, indentCount)) + "\n"
                }
            }
        }
    }

    /// encode 自檢 canary（R3；R6 起無條件執行——「純 known 檔案由 emitter 保證
    /// 合法」只保證能 parse，不保證 decode 得回同一模型，見語意 canary）：
    /// 寫出前 compose 產物——重複鍵、dangling alias、任何未來切分 bug 都攔在
    /// 磁碟之前（refuse-to-write，絕不原子性覆蓋合法檔案）。
    static func encodeCanary(_ out: String, context: String) throws {
        do {
            // #36：canary 同樣先過預算——emitter 若寫出超預算的東西，那是 bug
            // 不是攻擊，要在這裡就爆而不是留給下一次 decode。
            try AliasEventBudget.check(out, context: "encode canary", isWritePath: true)
            _ = try Yams.compose(yaml: out)
        } catch {
            throw StoreYAMLError.invalidField(
                context, "encode 自檢失敗（產物無法解析）——拒絕寫出：\(error)")
        }
    }

    /// R6（DA R5 HIGH）：known key 存在但形狀不符 → throw → quarantine。
    /// v1.2 的 strict gate 事實上同時保護 shape 演化（unknown key 先 throw、
    /// 檔案永不被寫回）；v1.3 拆掉 gate 後若只接「加 key」那一半，較新 schema
    /// 把既有 key 變豐富（如 names: sequence → mapping）時，舊 binary 的 RMW
    /// 會把該欄位整段靜默剝除。known 欄位的形狀演化不入 tolerant 範圍。
    static func requireShape<T>(_ node: Yams.Node?, field: String, expect: String,
                                nullIsAbsent: Bool = false,
                                _ extract: (Yams.Node) -> T?) throws -> T? {
        guard let node else { return nil }
        // R8（R7-verify M3）、R9 限縮（R8-verify CRITICAL）：explicit/implicit
        // null（`akashic:` 空值行）視同「欄位不存在」——但**只對 collection 形狀
        // 的欄位**。null 沒有可被剝除的子樹、且 collection extractor 對 null 會
        // 走進「形狀不符」quarantine（可用性懸崖）才需要這條救。scalar 欄位的
        // extractor 本來就以字串面收下 null-face（R6 normative；emitter 對
        // ""/"null"/"~" 就是輸出 plain null-face——套用 null-as-absent 會讓
        // Zotero 無標題 item 永遠寫不進 store、v1.2 的 `title: Null` 檔被
        // quarantine，R8 CRITICAL）。face 白名單擋 `!!null foo` 這種帶內容的
        // 顯式 tag（R8-verify L22：內容不可靜默丟）。
        if nullIsAbsent, let scalar = node.scalar, scalar.style == .plain,
           node.tag == Tag(.null),
           ["", "~", "null", "Null", "NULL"].contains(scalar.string) {
            return nil
        }
        guard let v = extract(node) else {
            throw StoreYAMLError.invalidField(
                field, "形狀不符——必須是 \(expect)（known 欄位的形狀演化不入 tolerant 範圍，fail-closed；見 docs/store-format.md §5）")
        }
        return v
    }

    /// stream 開頭的 UTF-8 BOM 剝除（R7）：Yams/libyaml 把它當 stream BOM 吃掉，
    /// 但文字層切分不會——第一個欄位若是未知欄位，BOM 會被吸進 raw、寫回時
    /// 搬到文件中段（R6-verify M6）。屬 stream-scoped 保真例外（§5）。
    static func stripLeadingBOM(_ yaml: String) -> String {
        yaml.hasPrefix("\u{FEFF}") ? String(yaml.dropFirst()) : yaml
    }

    public static func decode(_ yaml: String) throws -> Entry {
        let yaml = stripLeadingBOM(yaml)
        try assertNoLossyContentChars(yaml, context: "entry")
        // #36：alias 展開預算在 compose **之前**。判準走 parser 的 event 層
        // （`yaml_parser_parse` 不展開 alias），不是文字掃描——後者在本 repo 失敗過
        // 五次，見 docs/store-format.md §5 的排除表。
        try AliasEventBudget.check(yaml, context: "entry")
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        // oracle 預算：單次 decode 全檔共用（R7——per-block 重置可被 N 區塊
        // 聚合成 CPU 放大面，R6-verify HIGH）
        var oracleBudget = 200_000
        let topKeys = try keyStrings(map, known: knownTopLevelKeys, context: "entry")
        let topUnknowns = try captureUnknownBlocks(
            text: yaml, map: map, keys: topKeys, known: knownTopLevelKeys,
            indent: 0, context: "entry", budget: &oracleBudget)
        // 必填欄位走 requireShape（R7）：存在但形狀不符要報「形狀不符」而非
        // 「缺欄位」（誤導診斷）；且 `Node.string` 對含 `=`（!!value）鍵的
        // mapping 有 construct 特例，必須用 `scalar?.string` 驗真 scalar
        // （R6-verify M14——mapping 假扮 scalar 通過形狀檢查、RMW 靜默扁平化）。
        guard let idString = try requireShape(map["id"], field: "id",
                                              expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("id")
        }
        // R8（R7-verify L18）：id 存在但非 UUID → 報格式錯誤，不誤報「缺欄位」
        guard let id = UUID(uuidString: idString) else {
            throw StoreYAMLError.invalidField("id", "「\(idString)」不是 UUID")
        }
        guard let citekey = try requireShape(map["citekey"], field: "citekey",
                                             expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("citekey")
        }
        guard let type = try requireShape(map["type"], field: "type",
                                          expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("type")
        }
        guard let title = try requireShape(map["title"], field: "title",
                                           expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("title")
        }

        var entry = Entry(id: id, citekey: citekey, type: type, title: title)
        entry.unknownFields = topUnknowns
        entry.date = try requireShape(map["date"], field: "date", expect: "scalar") { $0.scalar?.string }

        if let authorSeq = try requireShape(map["authors"], field: "authors",
                                            expect: "sequence", nullIsAbsent: true, { $0.sequence }) {
            entry.authors = try authorSeq.map { node in
                guard let m = node.mapping else {
                    throw StoreYAMLError.invalidField("authors", "元素不是 mapping")
                }
                try rejectUnknownKeys(m, known: ["key", "literal"], context: "authors")
                let key = try m["key"].map { try scalarString($0, context: "authors.key") }
                let literal = try m["literal"].map { try scalarString($0, context: "authors.literal") }
                switch (key, literal) {
                case (let k?, nil): return .key(k)
                case (nil, let s?): return .literal(s)
                default:
                    throw StoreYAMLError.invalidField("authors", "必須恰好有 key 或 literal 其一")
                }
            }
        }
        if let fieldMap = try requireShape(map["fields"], field: "fields",
                                           expect: "mapping", nullIsAbsent: true, { $0.mapping }) {
            var seenFieldKeys = Set<String>()
            for (k, v) in fieldMap {
                // R8（R7-verify M2）+ R9 修正（R8-verify HIGH）+ R10 收斂
                // （R9-verify M4/M6/M7）：鍵側要真 scalar（擋 `=`-鍵 mapping 的
                // construct 扁平化）且 tag 屬**隱式 resolver 可產出的閉集**——
                // emitter 對 fields 鍵輸出 plain 樣式，`2026`/`no` 這類鍵
                // re-parse resolve 成 int/bool，必須以字串面收下（等冪）；但
                // R9 的 namespace 前綴判準放行了 merge（`<<`——本 PR 各層明文
                // 拒收、且他家 parser 讀不動我們寫出的產物）、value（`=`）與
                // 任意顯式 core tag。閉集把這些一併擋回。
                guard let kScalar = k.scalar,
                      fieldsKeyTags.contains(k.tag),
                      let vv = v.scalar?.string else {
                    throw StoreYAMLError.invalidField(
                        "fields", "鍵必須是隱式可解析的 scalar（str/int/float/bool/null/timestamp 面）、值必須是 scalar（以字串面解讀）")
                }
                let kk = kScalar.string
                // R11（R10-verify H3，DA 實測）：閉集只擋得住 tag 面。quoted
                // `'<<'` / `'='` 的 resolved tag 是 str → 通過閉集被 decode 收下，
                // 但 encode 時 `Node("<<")` 是 implicit → resolve 成 merge/value →
                // emit 成裸 `<<:` → 內層 canary 的 decode(out) 撞閉集 → 永遠 throw。
                // 結果是 §5 自己命名的最壞形態「讀得到但永遠寫不回」，且**零可見性**
                // （不進 quarantine、無未知欄位所以不進 unknownFieldFiles、validate()
                // 也不吐 warning）。decode 端補上字串面 fail-closed，讓這種檔案在
                // 載入時就進 quarantine——可見、可救、不會在下次 pull 才炸。
                guard kk != "<<", kk != "=" else {
                    throw StoreYAMLError.invalidField(
                        "fields", "鍵「\(kk)」的字串面與 merge/value 指示符相同——本 binary 的"
                                + " emitter 會把它寫成裸指示符而無法讀回（自我毒化），fail-closed")
                }
                // R7（R6-verify M16）：Yams 只擋 string+tag 全等的重複鍵——
                // `'123'` 與 `123` 是不同 Node 但同字串面，塞進 dictionary 會
                // 靜默壓成一筆且 canary 看不見（模型端已丟）。fail-closed。
                guard seenFieldKeys.insert(kk).inserted else {
                    throw StoreYAMLError.invalidField(
                        "fields", "鍵「\(kk)」字串面重複（tag 區分的同名鍵）——fail-closed")
                }
                entry.fields[kk] = vv
            }
        }
        if let attSeq = try requireShape(map["attachments"], field: "attachments",
                                         expect: "sequence", nullIsAbsent: true, { $0.sequence }) {
            entry.attachments = try attSeq.map { node in
                // R8（R7-verify M2）：元素鍵同樣真 scalar + str tag（此層無
                // rejectUnknownKeys，R7 的 tagged-shadow 守衛此前搆不到）
                guard let m = node.mapping, m.count == 1,
                      let first = m.first, first.key.tag == Tag(.str),
                      let kindRaw = first.key.scalar?.string,
                      let kind = AttachmentRef.Kind(rawValue: kindRaw),
                      let path = first.value.scalar?.string else {
                    throw StoreYAMLError.invalidField("attachments", "元素必須是 {zotero: path} 或 {pool: path}（鍵為字串 scalar）")
                }
                return AttachmentRef(kind: kind, path: path)
            }
        }
        if let provMap = try requireShape(map["provenance"], field: "provenance",
                                          expect: "mapping", nullIsAbsent: true, { $0.mapping }) {
            try rejectUnknownKeys(provMap, known: knownProvenanceKeys, context: "provenance")
            // R8（R7-verify L13）：必填欄位也走 requireShape——形狀不符要報
            // 「形狀不符」，缺席才報「缺欄位」（誤導診斷類）
            guard let zKey = try requireShape(provMap["zotero_key"],
                                              field: "provenance.zotero_key",
                                              expect: "scalar", { $0.scalar?.string }) else {
                throw StoreYAMLError.invalidField("provenance", "缺 zotero_key")
            }
            guard let zVerString = try requireShape(provMap["zotero_version"],
                                                    field: "provenance.zotero_version",
                                                    expect: "scalar", { $0.scalar?.string }) else {
                throw StoreYAMLError.invalidField("provenance", "缺 zotero_version")
            }
            guard let zVer = Int(zVerString) else {
                throw StoreYAMLError.invalidField(
                    "provenance.zotero_version", "「\(zVerString)」不是整數")
            }
            var prov = Provenance(zoteroKey: zKey, zoteroVersion: zVer)
            if let s = try requireShape(provMap["library_id"], field: "provenance.library_id",
                                        expect: "scalar", { $0.scalar?.string }) {
                guard let lid = Int(s) else {
                    throw StoreYAMLError.invalidField("provenance", "library_id「\(s)」不是整數")
                }
                prov.libraryID = lid
            }
            prov.zoteroHash = try requireShape(provMap["zotero_hash"],
                                               field: "provenance.zotero_hash",
                                               expect: "scalar") { $0.scalar?.string }
            // R6（F2 延伸）：無法解析的時間戳此前被靜默丟棄（importedAt=nil）→
            // 下次改寫即剝除。形狀/值不符一律 fail-closed。
            // R9（R8-verify M14）：null 面（`imported_at:` 空值行）視同欄位不存在
            // ——模型是 Optional<Date>，nil↔省略等冪，v1.2 亦可載入這種良性檔。
            if let s = try requireShape(provMap["imported_at"], field: "provenance.imported_at",
                                        expect: "scalar", nullIsAbsent: true,
                                        { $0.scalar?.string }) {
                guard let d = isoFormatter.date(from: s) else {
                    throw StoreYAMLError.invalidField(
                        "provenance.imported_at", "不是 ISO-8601 秒精度時間戳（fail-closed）")
                }
                prov.importedAt = d
            }
            if let s = try requireShape(provMap["orphaned_at"], field: "provenance.orphaned_at",
                                        expect: "scalar", nullIsAbsent: true,
                                        { $0.scalar?.string }) {
                guard let d = isoFormatter.date(from: s) else {
                    throw StoreYAMLError.invalidField(
                        "provenance.orphaned_at", "不是 ISO-8601 秒精度時間戳（fail-closed）")
                }
                prov.orphanedAt = d
            }
            entry.provenance = prov
        }
        if let akMap = try requireShape(map["akashic"], field: "akashic",
                                        expect: "mapping", nullIsAbsent: true, { $0.mapping }) {
            let akKeys = try keyStrings(akMap, known: knownAkashicKeys, context: "akashic")
            if akKeys.contains(where: { !knownAkashicKeys.contains($0) }) {
                // 需要 akashic 區塊原文：由頂層切分取出（同樣計數校驗，fail-closed）
                let topBlocks = try splitBlocks(yaml, indent: 0, context: "entry")
                guard topBlocks.count == topKeys.count,
                      let akIdx = topKeys.firstIndex(of: "akashic") else {
                    throw StoreYAMLError.invalidField(
                        "akashic", "無法可靠切分未知欄位原文（頂層區塊對齊失敗）")
                }
                // 去掉 "akashic:" 首行，對子行以其基準縮排做子層切分
                let childText = String(topBlocks[akIdx].drop(while: { $0 != "\n" }).dropFirst())
                let wLine = childText.split(separator: "\n", omittingEmptySubsequences: false)
                    .first(where: { l in
                        let t = l.drop(while: { $0 == " " })
                        return !t.isEmpty && t.first != "#"
                    })
                let childIndent = wLine.map { $0.count - $0.drop(while: { $0 == " " }).count } ?? 2
                let childBlocks = try splitBlocks(childText, indent: childIndent, context: "akashic")
                guard childBlocks.count == akKeys.count else {
                    throw StoreYAMLError.invalidField(
                        "akashic",
                        "無法可靠切分未知欄位原文（子區塊 \(childBlocks.count) ≠ 欄位 \(akKeys.count)；版面超出容忍層契約，見 docs/store-format.md §5 版面契約）")
                }
                let akEntries = Array(akMap)
                var akUnknowns: [UnknownField] = []
                for (i, k) in akKeys.enumerated() where !knownAkashicKeys.contains(k) {
                    let raw = stripDocMarkers(childBlocks[i])
                    try verifyBlockOracle(raw: raw, dedent: childIndent,
                                          expectedKey: k, originalValue: akEntries[i].value,
                                          context: "akashic", budget: &oracleBudget)
                    akUnknowns.append(UnknownField(key: k, raw: raw))
                }
                entry.akashic.unknownFields = akUnknowns
            }
            if let tagSeq = try requireShape(akMap["tags"], field: "akashic.tags",
                                            expect: "sequence", nullIsAbsent: true, { $0.sequence }) {
                entry.akashic.tags = try stringList(tagSeq, context: "akashic.tags")
            }
            if let libSeq = try requireShape(akMap["libraries"], field: "akashic.libraries",
                                             expect: "sequence", nullIsAbsent: true,
                                             { $0.sequence }) {
                entry.akashic.libraries = try stringList(libSeq, context: "akashic.libraries")
            }
            entry.akashic.status = try requireShape(akMap["status"], field: "akashic.status",
                                                    expect: "scalar") { $0.scalar?.string }
            if let relMap = try requireShape(akMap["relations"], field: "akashic.relations",
                                             expect: "mapping", nullIsAbsent: true, { $0.mapping }) {
                try rejectUnknownKeys(relMap, known: knownRelationsKeys, context: "akashic.relations")
                if let seq = try requireShape(relMap["cites"], field: "akashic.relations.cites",
                                              expect: "sequence", nullIsAbsent: true, { $0.sequence }) {
                    entry.akashic.relations.cites = try stringList(seq, context: "akashic.relations.cites")
                }
                if let seq = try requireShape(relMap["related"], field: "akashic.relations.related",
                                              expect: "sequence", nullIsAbsent: true, { $0.sequence }) {
                    entry.akashic.relations.related = try stringList(seq, context: "akashic.relations.related")
                }
            }
        }
        return entry
    }

    /// 序列元素必須是 scalar，以字串面解讀；sequence/mapping 元素 throw。
    static func stringList(_ seq: Yams.Node.Sequence, context: String) throws -> [String] {
        try seq.map { try scalarString($0, context: context) }
    }

    /// scalar 的字串面（R6，取代 R3 的 strictString）。emitter 對「長得像
    /// int/bool/null 的字串」（如 tag「2026」）輸出 plain 樣式，plain `2026`
    /// re-parse 後 resolve 成 int——R5 前的嚴格拒收使這種**本 binary 自己寫出**
    /// 的檔案永久 decode 失敗（寫得出、讀不回的自我毒化，DA R5 更正二）。
    /// 字串欄位的語意型別本就是字串，取 scalar 的字面內容即與 emitter 對合、
    /// encode/decode 等冪。非 scalar（sequence/mapping）仍 throw。
    static func scalarString(_ node: Yams.Node, context: String) throws -> String {
        guard let scalar = node.scalar else {
            throw StoreYAMLError.invalidField(context, "必須是 scalar（以字串面解讀）")
        }
        return scalar.string
    }
}

/// Library registry YAML（#13）：metadata-only，strict decode。
public enum LibraryYAML {
    public static func encode(_ library: Library) throws -> String {
        var pairs: [(Node, Node)] = [
            (Node("key"), Node(library.key)),
            (Node("name"), Node(library.name)),
        ]
        if let description = library.description {
            pairs.append((Node("description"), Node(description)))
        }
        var out = try Yams.serialize(node: Node(pairs), allowUnicode: true)
        try EntryYAML.appendRawBlocks(library.unknownFields, to: &out, targetIndent: 0,
                                      context: "library")
        // 語意 canary（R4；R6 起無條件執行，比較基準見 EntryYAML.encode 註解）
        try EntryYAML.encodeCanary(out, context: "library")
        let rd = try decode(out)
        var a = rd, b = library
        a.unknownFields = []; b.unknownFields = []
        guard a == b, rd.unknownFields.map(\.key) == library.unknownFields.map(\.key) else {
            // R8（R7-verify L14）：欄位指認（與 EntryYAML 對齊）
            var bad: [String] = []
            if a.key != b.key { bad.append("key") }
            if a.name != b.name { bad.append("name") }
            if a.description != b.description { bad.append("description") }
            let detail = bad.isEmpty ? "未知欄位 key 序列不符" : "欄位不符：\(bad.joined(separator: "、"))"
            throw StoreYAMLError.invalidField(
                "library", "encode 語意自檢失敗——\(detail)，拒絕寫出")
        }
        // R9（R8-verify L25）：encode 側比對含 got/want 雙側 re-compose，單位消耗
        // 高於 decode oracle——放寬為 2×，避免「讀得到但永遠寫不回」的邊界檔
        // R11（R10-verify M16/M20）：R10 只在 EntryYAML 撤回 R9 的 2× 放寬，
        // Person/Library 留在 400k 與 §5 的 normative「200,000」分叉。對齊。
        var encodeBudget = 200_000
        try EntryYAML.verifyUnknownValuesPreserved(rd.unknownFields, library.unknownFields,
                                                   context: "library", budget: &encodeBudget)
        return out
    }

    static let knownLibraryKeys: Set<String> = ["key", "name", "description"]

    public static func decode(_ yaml: String) throws -> Library {
        let yaml = EntryYAML.stripLeadingBOM(yaml)
        try EntryYAML.assertNoLossyContentChars(yaml, context: "library")
        // #36：alias 展開預算在 compose **之前**。判準走 parser 的 event 層
        // （`yaml_parser_parse` 不展開 alias），不是文字掃描——後者在本 repo 失敗過
        // 五次，見 docs/store-format.md §5 的排除表。
        try AliasEventBudget.check(yaml, context: "person")
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        var oracleBudget = 200_000
        let keys = try EntryYAML.keyStrings(map, known: knownLibraryKeys, context: "library")
        let unknowns = try EntryYAML.captureUnknownBlocks(
            text: yaml, map: map, keys: keys, known: knownLibraryKeys,
            indent: 0, context: "library", budget: &oracleBudget)
        guard let key = try EntryYAML.requireShape(map["key"], field: "library.key",
                                                   expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("key")
        }
        guard let name = try EntryYAML.requireShape(map["name"], field: "library.name",
                                                    expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("name")
        }
        var library = Library(key: key, name: name)
        library.unknownFields = unknowns
        library.description = try EntryYAML.requireShape(
            map["description"], field: "library.description",
            expect: "scalar") { $0.scalar?.string }
        return library
    }
}

public enum PersonYAML {
    public static func encode(_ person: Person) throws -> String {
        // 形狀裸標籤放最前面（取代原本的 `type: person`）。
        // 原本用 `type:` 標形狀，使形式種類與書目類型成為同一個 key 的平輩值——
        // 那正是 `type: view` 看起來合理的原因。標籤與 `type:` 現在分屬兩層。
        var pairs: [(Node, Node)] = [(Node(EntityKind.person.rawValue), Node("")),
                                     (Node("id"), Node(person.id.uuidString)),
                                     (Node("key"), Node(person.key))]
        if !person.names.isEmpty {
            pairs.append((Node("names"), Node(person.names.map { Node($0) })))
        }
        // #81：對外可稱呼的名字。空的不序列化——既有記錄多數尚未指定，寫出空序列只是
        // 讓每個檔多一行雜訊。緊接 names 之後是因為它是 names 的子集，讀的人要能對照。
        if !person.authorized.isEmpty {
            pairs.append((Node("authorized"), Node(person.authorized.map { Node($0) })))
        }
        if let orcid = person.orcid { pairs.append((Node("orcid"), Node(orcid))) }
        if let openalex = person.openalex { pairs.append((Node("openalex"), Node(openalex))) }
        // #67：逝世日期。缺席**不寫出任何鍵**——缺席的語意是右設限（尚未觀察到），
        // 寫成空字串或 null 會把「沒觀察到」偽裝成一個有內容的觀測。
        // 緊鄰 note 之前：#66 落地前來源寫在 note，兩者相鄰讓人一眼看到日期與其依據。
        if let died = person.died { pairs.append((Node("died"), Node(died))) }
        if let note = person.note { pairs.append((Node("note"), Node(note))) }
        // #20：profile 空的不序列化（與 tags 同慣例）——避免每個 person 檔多一個空 map
        if !person.profile.isEmpty {
            try pairs.append((Node("profile"), PersonYAML.profileNode(person.profile)))
        }
        // #66：欄位層級的 provenance。空清單不寫出——既有記錄零 diff。
        if !person.references.isEmpty {
            try pairs.append((Node("references"), ProvenanceYAML.node(person.references)))
        }
        var out = try Yams.serialize(node: Node(pairs), allowUnicode: true)
        try EntryYAML.appendRawBlocks(person.unknownFields, to: &out, targetIndent: 0,
                                      context: "person")
        // 語意 canary（R4；R6 起無條件執行，比較基準見 EntryYAML.encode 註解）
        try EntryYAML.encodeCanary(out, context: "person")
        let rd = try decode(out)
        var a = rd, b = person
        a.unknownFields = []; b.unknownFields = []
        guard a == b, rd.unknownFields.map(\.key) == person.unknownFields.map(\.key) else {
            // R8（R7-verify L14）：欄位指認（與 EntryYAML 對齊）
            var bad: [String] = []
            if a.id != b.id { bad.append("id") }
            if a.key != b.key { bad.append("key") }
            if a.names != b.names { bad.append("names") }
            if a.authorized != b.authorized { bad.append("authorized") }
            if a.orcid != b.orcid { bad.append("orcid") }
            if a.openalex != b.openalex { bad.append("openalex") }
            if a.died != b.died { bad.append("died") }
            if a.note != b.note { bad.append("note") }
            if a.profile != b.profile { bad.append("profile") }
            if a.references != b.references { bad.append("references") }
            let detail = bad.isEmpty ? "未知欄位 key 序列不符" : "欄位不符：\(bad.joined(separator: "、"))"
            throw StoreYAMLError.invalidField(
                "person", "encode 語意自檢失敗——\(detail)，拒絕寫出")
        }
        // R9（R8-verify L25）：encode 側比對含 got/want 雙側 re-compose，單位消耗
        // 高於 decode oracle——放寬為 2×，避免「讀得到但永遠寫不回」的邊界檔
        // R11（R10-verify M16/M20）：R10 只在 EntryYAML 撤回 R9 的 2× 放寬，
        // Person/Library 留在 400k 與 §5 的 normative「200,000」分叉。對齊。
        var encodeBudget = 200_000
        try EntryYAML.verifyUnknownValuesPreserved(rd.unknownFields, person.unknownFields,
                                                   context: "person", budget: &encodeBudget)
        return out
    }

    /// `type` **刻意保留在已知鍵內**，即使 person 不再寫出它：移出去會讓既有檔案的
    /// `type: person` 被 tolerant-preserve 當成未知欄位保存下來、並在寫回時重新產生，
    /// 與「停止寫出形狀名」的目的相反。留在已知鍵內＝讀得到、忽略其值、不寫回。
    /// 形狀裸標籤同理必須列入。
    static let knownPersonKeys: Set<String> = Set(["id", "type", "key", "names", "authorized",
                                                   "orcid", "openalex", "died", "note", "profile",
                                                   "references"])
        .union(EntityKind.knownLabels)

    public static func decode(_ yaml: String) throws -> Person {
        let yaml = EntryYAML.stripLeadingBOM(yaml)
        try EntryYAML.assertNoLossyContentChars(yaml, context: "person")
        // #36：alias 展開預算在 compose **之前**。判準走 parser 的 event 層
        // （`yaml_parser_parse` 不展開 alias），不是文字掃描——後者在本 repo 失敗過
        // 五次，見 docs/store-format.md §5 的排除表。
        try AliasEventBudget.check(yaml, context: "library")
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        var oracleBudget = 200_000
        let keys = try EntryYAML.keyStrings(map, known: knownPersonKeys, context: "person")
        let unknowns = try EntryYAML.captureUnknownBlocks(
            text: yaml, map: map, keys: keys, known: knownPersonKeys,
            indent: 0, context: "person", budget: &oracleBudget)
        guard let key = try EntryYAML.requireShape(map["key"], field: "person.key",
                                                   expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("key")
        }
        // #35：`id` 缺席 → 由 key 確定性推出（legacy `people/<key>.yaml` 沒有這個欄位）。
        // 在場但格式錯 → fail-closed，**不猜**：亂猜一個 id 會讓這筆記錄與別處的引用
        // 對不上，而且錯得很安靜。
        var explicitID: UUID?
        if let raw = try EntryYAML.requireShape(map["id"], field: "person.id",
                                                expect: "scalar", nullIsAbsent: true,
                                                { $0.scalar?.string }) {
            guard let u = UUID(uuidString: raw) else {
                throw StoreYAMLError.invalidField("person.id", "不是合法的 UUID")
            }
            explicitID = u
        }
        // `type` 在 entities 佈局用來分辨記錄種類；person 檔只接受 "person"。
        if let t = try EntryYAML.requireShape(map["type"], field: "person.type",
                                              expect: "scalar", nullIsAbsent: true,
                                              { $0.scalar?.string }), t != "person" {
            throw StoreYAMLError.invalidField("person.type", "person 檔的 type 必須是「person」，實得「\(t)」")
        }
        var person = Person(key: key, id: explicitID)
        person.unknownFields = unknowns
        // R6（DA R5 HIGH 實測案例即 person.names）：形狀不符 fail-closed
        if let seq = try EntryYAML.requireShape(map["names"], field: "person.names",
                                                expect: "sequence", nullIsAbsent: true, { $0.sequence }) {
            person.names = try EntryYAML.stringList(seq, context: "person.names")
        }
        // #81：對外可稱呼的名字。**形狀不符 fail-closed**（與 names 同）——`authorized:`
        // 若被寫成 mapping（例如誤以為要以書寫系統為鍵），靜默剝除會讓一次舊 binary 的
        // read-modify-write 把整段指定吃掉。
        if let seq = try EntryYAML.requireShape(map["authorized"], field: "person.authorized",
                                                expect: "sequence", nullIsAbsent: true, { $0.sequence }) {
            person.authorized = try EntryYAML.stringList(seq, context: "person.authorized")
        }
        // #20：profile。**形狀不符 fail-closed**（與 names 同——known 欄位的形狀演化
        // 不入 tolerant 範圍，見 §5）。
        if let pm = try EntryYAML.requireShape(map["profile"], field: "person.profile",
                                               expect: "mapping", nullIsAbsent: true,
                                               { $0.mapping }) {
            person.profile = try PersonYAML.decodeProfile(pm)
        }
        // #66：references。逐筆驗證（互斥、必要欄位、digest 形狀）住
        // ProvenanceYAML.decode；欄位/值的存在性驗證在整筆 person 組完後跑
        // （它需要其他欄位都就位）。
        // null 當缺席（#145 verify F5——與其他 collection 欄位的 nullIsAbsent 慣例
        // 一致；`references:` 後面空白是常見的手改殘留，不值得整檔 quarantine）
        if let rn = try EntryYAML.requireShape(map["references"], field: "person.references",
                                               expect: "sequence", nullIsAbsent: true,
                                               { $0.sequence != nil ? $0 : nil }) {
            person.references = try ProvenanceYAML.decode(rn, context: "person")
        }
        person.orcid = try EntryYAML.requireShape(map["orcid"], field: "person.orcid",
                                                  expect: "scalar") { $0.scalar?.string }
        person.openalex = try EntryYAML.requireShape(map["openalex"], field: "person.openalex",
                                                     expect: "scalar") { $0.scalar?.string }
        // #67：值原樣讀入，**不驗證是否為合法 ISO 前綴**——與 `DateRange` 的
        // `start` / `end` 及 `Organization.founded` / `dissolved` 同慣例。這裡拒絕的
        // 只有形狀錯誤（sequence / mapping），內容的可信度屬使用端的判斷。
        //
        // `nullIsAbsent: true` 是**認得缺席的不同寫法**，不是驗證內容：`null` / `~` /
        // `NULL` 是 YAML 表達「沒有值」的記法，不是值。這與 R8 對 scalar 不套此旗標的
        // 決定不衝突——那條的理由是 `title` 的空值可能是真實狀態，而 `died` 的值域
        // （ISO 8601 前綴）本來就不含任何 null-face。**這一項在此不可省**：`died: null`
        // 的字串面是 `"null"`，去空白去不掉它。
        //
        // 空白值的正規化**不在這裡做**——`person` 此時已初始化完成，賦值會觸發
        // `Person.died` 的 `didSet`。在此再做一次是重複的第二個判準，而「同一概念兩套
        // 判準」正是本欄位第一個缺陷的成因。
        person.died = try EntryYAML.requireShape(map["died"], field: "person.died",
                                                 expect: "scalar", nullIsAbsent: true,
                                                 { $0.scalar?.string })
        person.note = try EntryYAML.requireShape(map["note"], field: "person.note",
                                                 expect: "scalar") { $0.scalar?.string }
        // #66 task 3.3：reference 附著的存在性驗證——欄位全部就位後才有意義
        try person.validateReferenceAttachment()
        return person
    }
}

/// `entities/<uuid>.yaml` 的種類判別（#35）。
///
/// **不用文字掃描**——`type:` 可能出現在註解、字串值、未知欄位裡，用 grep 判準是
/// #36 那一族錯誤的同一種形態。這裡老實 compose 一次讀那個欄位。成本由 #30 的實測
/// 背書（500 檔 baseline 0.29 s），而正確性不打折。
/// 記錄的**形狀**。形狀名以**裸標籤**出現在檔案頂層（一個沒有值的鍵），
/// 不是某個後設欄位的值。
///
/// ## 為什麼不是 `kind: person`
///
/// `kind: person` 設立一個叫 `kind` 的後設欄位，把「種類」物化成一個可查詢、可比較、
/// 有值域的欄位——那正是 Tractatus 4.1272 說的把形式概念當成真正的概念用。裸標籤沒有
/// 後設欄位：`person` 不是誰的值，它就在那裡。
///
/// ## 為什麼不是「完全不放標籤、由欄位組成推斷」
///
/// 那需要「identity 欄位名跨形狀唯一」的約束，而那條約束會讓 identity 欄位名兼差當形狀名
/// （`citekey` / `key` / `orgkey` / `venuekey`）——形狀資訊被塞進欄位的名字裡，一名二職。
/// 而且欄位組成只能決定**一個**形狀；標籤可以有多個，本體因此不必是平坦分割。
///
/// ## 標籤不得帶值
///
/// 允許帶值就等於重新造出一個後設欄位，只是名字換成形狀名。這扇門必須關死。
///
/// ## 新增形狀時
///
/// 加進 `knownLabels`，並在 `subsumes` 補上它與既有形狀的層級關係（若有）。
/// **可由 schema 推出的上位標籤不寫進檔案**——「person 是 agent」是 schema 的事實，
/// 不是每一筆記錄的事實，寫進每個檔是把同一件事複製 N 份。
public enum EntityKind: String, CaseIterable {
    case work
    case person
    case organization
    /// 未決的同一性問題（#71）。它決定自己的欄位（question / candidates / judgement），
    /// 因而選出自己的 decoder——這是 entity-boundary 的判別測試所要求的唯一條件。
    /// 對照被同一個測試拒絕的 `view`：view 選不出任何形狀，載入器只會把它當成某個
    /// 既有形狀來讀。
    case divergence

    /// 封閉集合。不在其中的裸標籤 → quarantine，不猜。
    public static let knownLabels: Set<String> = Set(allCases.map(\.rawValue))

    /// `label → 它的上位標籤`。目前兩個形狀互不從屬，所以是空的；
    /// 加入 organization、或引入 agent 這類上位概念時在此登記。
    static let subsumes: [String: Set<String>] = [:]

    /// 本專案在別處處理、因而值得給出**具名重導**的非形狀名稱。
    ///
    /// 只說「不認得」等於只證明它在這個位置沒有意義；讀者還需要知道哪個位置有意義
    /// （Tractatus 5.4733 的診斷方向：記法的失敗，不是形上學的失敗）。
    static let misplacedElsewhere: [String: String] = [
        "view": "view 的判準屬於 config.yaml，外延屬於衍生索引（見 #54）",
        "index": "索引結構屬於衍生層，不進 entities/",
        "query": "查詢屬於 config.yaml 或呼叫端，不進 entities/",
    ]

    /// 從檔案內容判定形狀。
    ///
    /// - Parameter strict: `true` 時缺標籤即擲錯；`false` 時以欄位組成回退
    ///   （有 citekey → work、有 key → person）。由 store format 決定：format ≥ 3
    ///   的檔案是本機制之後寫的，沒有理由缺標籤；format ≤ 2 的舊資料本來就沒有標籤，
    ///   而**遷移程式必須先讀得動它才能替它貼標籤**——無條件嚴格會造成順序死結。
    ///
    ///   不認得的標籤、標籤帶值、多個互不從屬的標籤、與 `type:` 矛盾——這四種在
    ///   兩種模式下都擲錯。它們是明確的錯誤，不是舊格式的正常狀態。
    public static func peek(_ yaml: String, strict: Bool = true) throws -> EntityKind {
        let text = EntryYAML.stripLeadingBOM(yaml)
        // #36：**這是 entities 佈局的第一個動作**——沒有這道守衛，decode 端的預算根本
        // 來不及跑。（實測：接了三個 decode 入口仍 timeout，因為 load() 先走這裡。）
        try AliasEventBudget.check(text, context: "entity")
        guard let root = try Yams.compose(yaml: text), let map = root.mapping else {
            throw StoreYAMLError.invalidField("entity", "根節點必須是 mapping")
        }

        // 裸鍵 ＝ 值為空 scalar。`person:` 解析成 scalar("")；`person: true` 不是裸鍵。
        var bareKeys: [String] = []
        for (k, v) in map {
            guard let name = k.string, k.tag == Tag(.str) else { continue }
            if let s = v.scalar, s.string.isEmpty { bareKeys.append(name) }
        }

        // 已知形狀名出現但**帶了值** → 明說，不要讓它掉進「缺少標籤」。
        for name in knownLabels {
            if let v = map[name], !(v.scalar.map { $0.string.isEmpty } ?? false) {
                throw StoreYAMLError.shapeLabelHasValue(name)
            }
        }

        let labels = bareKeys.filter { knownLabels.contains($0) }
        switch labels.count {
        case 1:
            let kind = EntityKind(rawValue: labels[0])!
            try checkNoContradiction(map, label: kind)
            return kind
        case 0:
            let stray = bareKeys.filter { !knownLabels.contains($0) }
            // 不認得的裸鍵（`view:`）在兩種模式下都是錯——它是一個明確的形狀主張，只是錯的。
            if !stray.isEmpty { throw StoreYAMLError.unknownShapeLabel(stray) }
            if !strict, let inferred = inferFromComposition(map) { return inferred }
            throw StoreYAMLError.unknownShapeLabel([])
        default:
            // 多個：只有在其中一個被其餘全部從屬（最具體）時才可判定。
            let mostSpecific = labels.filter { cand in
                labels.allSatisfy { $0 == cand || subsumes[cand]?.contains($0) == true }
            }
            guard mostSpecific.count == 1 else {
                throw StoreYAMLError.ambiguousShapeLabels(labels.sorted())
            }
            let kind = EntityKind(rawValue: mostSpecific[0])!
            try checkNoContradiction(map, label: kind)
            return kind
        }
    }

    /// format ≤ 2 的回退：由 identity 欄位的出現判斷形狀。
    ///
    /// **只用於讀取舊資料**，不是判準（判準是標籤）。兩個 identity 欄位同時出現或都不出現
    /// 時回 `nil`——回退也不猜。
    private static func inferFromComposition(_ map: Yams.Node.Mapping) -> EntityKind? {
        // organization 是 format 4 才有的形狀，format ≤ 2 的舊資料不可能是它，
        // 所以回退只需分辨 work / person。
        let hasCitekey = map["citekey"] != nil
        let hasKey = map["key"] != nil
        switch (hasCitekey, hasKey) {
        case (true, false): return .work
        case (false, true): return .person
        default: return nil
        }
    }

    /// `type:` 若被拿來當形狀名用，且與標籤不符 → 矛盾，不得挑一邊。
    ///
    /// `type:` 是 work 專屬的**書目類型**（值域開放，`article` / `dataset` / …）。
    /// 值恰好是某個形狀名時才有矛盾的可能。
    private static func checkNoContradiction(_ map: Yams.Node.Mapping,
                                             label: EntityKind) throws {
        guard let t = map["type"]?.scalar?.string, knownLabels.contains(t),
              t != label.rawValue else { return }
        throw StoreYAMLError.shapeLabelContradiction(label: label.rawValue, typeField: t)
    }
}

// MARK: - PersonProfile 的 YAML 編解碼（#20）

extension PersonYAML {
    /// 時間軸的鍵名 ↔ `PersonProfile` 欄位。**contacts 以外的維度是固定的**——
    /// 新增維度要改 code，那是刻意的：維度是結構，不是資料。
    /// **affiliations 不在此清單內**：它的值是 `OrgRef`（指涉或字面），不是字串，
    /// 所以走自己的編解碼。其餘四個維度的值域來自外部且會變，維持純字串。
    static let timelineKeys: [(String, WritableKeyPath<PersonProfile, Timeline>)] = [
        ("ranks", \.ranks),
        ("administrative", \.administrative),
        ("appointments", \.appointments),
        ("fields", \.fields),
    ]

    static func profileNode(_ p: PersonProfile) throws -> Node {
        var pairs: [(Node, Node)] = []
        if !p.affiliations.isEmpty {
            pairs.append((Node("affiliations"), try orgTimelineNode(p.affiliations)))
        }
        for (key, path) in timelineKeys where !p[keyPath: path].isEmpty {
            pairs.append((Node(key), try timelineNode(p[keyPath: path])))
        }
        let contacts = p.contacts.filter { !$0.value.isEmpty }
        if !contacts.isEmpty {
            try pairs.append((Node("contacts"),
                          Node(contacts.keys.sorted().map { k in
                              (Node(k), try timelineNode(contacts[k]!))
                          } as [(Node, Node)])))
        }
        return Node(pairs)
    }

    /// 時間軸序列化為 sequence。**排序後輸出**——每次 encode 的順序必須相同，
    /// 否則同一份資料會產生假 diff。
    ///
    /// 用 `inSerializationOrder` 而非 `sorted`（#69）：後者是相等性用的全序，會在
    /// `range` 相同時以 `value` 決勝，把無日期的主名推到後面。
    /// encoder 側的矛盾防線（#131 verify Codex-H1）：`DateRange` 是公開可寫的
    /// struct，model 層可以構造出 `end` 有值 + `endedUnknown` 的矛盾 instance——
    /// decoder 會拒絕那個輸出，於是 `decode(encode(model))` 不安全（encode canary
    /// 只會報難懂的自檢失敗）。與 decode 端同一條「拒絕、不猜」：在寫出前指明矛盾。
    static func rejectContradictoryRange(_ r: DateRange) throws {
        if r.end != nil && r.endedUnknown {
            throw StoreYAMLError.invalidField(
                "timeline.range", "end 與 endedUnknown 並存是矛盾——end 有值即已結束於該時點")
        }
    }

    static func timelineNode(_ t: Timeline) throws -> Node {
        try Node(t.inSerializationOrder.map { v -> Node in
            try rejectContradictoryRange(v.range)
            var pairs: [(Node, Node)] = [(Node("value"), Node(v.value))]
            if let s = v.range.start { pairs.append((Node("start"), Node(s))) }
            if let e = v.range.end { pairs.append((Node("end"), Node(e))) }
            if v.range.endedUnknown { pairs.append((Node("ended"), Node("true", .implicit, .plain))) }
            if let s = v.source { pairs.append((Node("source"), Node(s))) }
            if let n = v.note { pairs.append((Node("note"), Node(n))) }
            return Node(pairs)
        })
    }

    /// 隸屬時間軸。`value` 是 `{key: …}` 或 `{literal: …}`——與 `authors` 同形，
    /// 因為那是本專案已經解過一次的同型問題。
    static func orgTimelineNode(_ t: TimelineOf<OrgRef>) throws -> Node {
        try Node(t.inSerializationOrder.map { v -> Node in
            try rejectContradictoryRange(v.range)
            let valueNode: Node
            switch v.value {
            case .key(let k):     valueNode = Node([(Node("key"), Node(k))] as [(Node, Node)])
            case .literal(let s): valueNode = Node([(Node("literal"), Node(s))] as [(Node, Node)])
            }
            var pairs: [(Node, Node)] = [(Node("value"), valueNode)]
            if let s = v.range.start { pairs.append((Node("start"), Node(s))) }
            if let e = v.range.end { pairs.append((Node("end"), Node(e))) }
            if v.range.endedUnknown { pairs.append((Node("ended"), Node("true", .implicit, .plain))) }
            if let s = v.source { pairs.append((Node("source"), Node(s))) }
            if let n = v.note { pairs.append((Node("note"), Node(n))) }
            return Node(pairs)
        })
    }

    static func decodeOrgTimeline(_ node: Node, context: String) throws -> TimelineOf<OrgRef> {
        guard let seq = node.sequence else {
            throw StoreYAMLError.invalidField(context, "必須是 sequence")
        }
        var out: [TemporalValue<OrgRef>] = []
        for item in seq {
            guard let m = item.mapping else {
                throw StoreYAMLError.invalidField(context, "每一段必須是 mapping")
            }
            try EntryYAML.rejectUnknownKeys(
                m, known: ["value", "start", "end", "ended", "source", "note"], context: context)
            guard let vNode = m["value"] else {
                throw StoreYAMLError.missingField("\(context).value")
            }
            let ref: OrgRef
            if let vm = vNode.mapping {
                try EntryYAML.rejectUnknownKeys(vm, known: ["key", "literal"],
                                                context: "\(context).value")
                let k = try vm["key"].map { try EntryYAML.scalarString($0, context: "\(context).value.key") }
                let l = try vm["literal"].map { try EntryYAML.scalarString($0, context: "\(context).value.literal") }
                switch (k, l) {
                case (let k?, nil):  ref = .key(k)
                case (nil, let l?):  ref = .literal(l)
                case (_?, _?):
                    throw StoreYAMLError.invalidField("\(context).value",
                                                      "key 與 literal 只能擇一——兩者並存無法判斷歸戶狀態")
                case (nil, nil):
                    throw StoreYAMLError.missingField("\(context).value.key 或 .literal")
                }
            } else {
                // 純字串視為未歸戶的字面值（相容於尚未升級的寫法）。
                ref = .literal(try EntryYAML.scalarString(vNode, context: "\(context).value"))
            }
            out.append(TemporalValue(
                value: ref,
                range: try decodeRange(m, context: context),
                source: try m["source"].map { try EntryYAML.scalarString($0, context: context) },
                note: try m["note"].map { try EntryYAML.scalarString($0, context: context) }))
        }
        return TimelineOf(out)
    }

    static func decodeProfile(_ m: Node.Mapping) throws -> PersonProfile {
        try EntryYAML.rejectUnknownKeys(
            m, known: Set(timelineKeys.map(\.0) + ["affiliations", "contacts"]),
            context: "person.profile")
        var p = PersonProfile()
        if let a = m["affiliations"] {
            p.affiliations = try decodeOrgTimeline(a, context: "person.profile.affiliations")
        }
        for (key, path) in timelineKeys {
            guard let node = m[key] else { continue }
            p[keyPath: path] = try decodeTimeline(node, context: "person.profile.\(key)")
        }
        if let c = m["contacts"] {
            guard let cm = c.mapping else {
                throw StoreYAMLError.invalidField("person.profile.contacts", "必須是 mapping")
            }
            for (k, v) in cm {
                guard let name = k.scalar?.string else {
                    throw StoreYAMLError.invalidField("person.profile.contacts", "鍵必須是字串")
                }
                p.contacts[name] = try decodeTimeline(
                    v, context: "person.profile.contacts.\(name)")
            }
        }
        return p
    }

    static func decodeTimeline(_ node: Node, context: String) throws -> Timeline {
        guard let seq = node.sequence else {
            throw StoreYAMLError.invalidField(context, "必須是 sequence")
        }
        return Timeline(try seq.map { el in
            guard let m = el.mapping else {
                throw StoreYAMLError.invalidField(context, "元素必須是 mapping")
            }
            try EntryYAML.rejectUnknownKeys(
                m, known: ["value", "start", "end", "ended", "source", "note"], context: context)
            guard let value = m["value"]?.scalar?.string else {
                throw StoreYAMLError.invalidField(context, "缺 value")
            }
            func str(_ k: String) throws -> String? {
                guard let n = m[k] else { return nil }
                if n.null != nil { return nil }
                guard let s = n.scalar?.string else {
                    throw StoreYAMLError.invalidField("\(context).\(k)", "必須是 scalar")
                }
                return s
            }
            return TemporalValue(
                value: value,
                range: try decodeRange(m, context: context),
                source: try str("source"), note: try str("note"))
        })
    }

    /// 共用的 range 解析（#63）：`ended: true` + `end` 缺席 ＝ 已結束、時點未知。
    /// `end` 有值時 `ended: true` 是矛盾——end 本身就是「已結束於此」，兩者並存
    /// 無法判斷哪個是真話：拒絕，不猜。`ended: false` 冗餘但無矛盾（寬容讀入、
    /// encode 不寫出）。
    static func decodeRange(_ m: Node.Mapping, context: String) throws -> DateRange {
        func str(_ k: String) throws -> String? {
            guard let n = m[k] else { return nil }
            if n.null != nil { return nil }
            guard let s = n.scalar?.string else {
                throw StoreYAMLError.invalidField("\(context).\(k)", "必須是 scalar")
            }
            return s
        }
        let end = try str("end")
        var endedUnknown = false
        if let endedNode = m["ended"] {
            // 本 store 格式的第一個 boolean——慣例在此建立（#131 verify F4）：
            // 只收裸寫的 true/false。引號版（"true" 是 !!str 不是 boolean）與
            // YAML 1.1 變體（True/yes/on/1）一律拒絕——fail-closed 與 requireShape
            // 的形狀紀律一致，訊息指路即可。
            guard let sc = endedNode.scalar, sc.style == .plain,
                  let b = Bool(sc.string) else {
                throw StoreYAMLError.invalidField(
                    "\(context).ended", "必須是裸寫的 true 或 false（不加引號、不用 Yes/On/1 等變體）")
            }
            if b, end != nil {
                throw StoreYAMLError.invalidField(
                    "\(context)",
                    "end 與 ended: true 並存是矛盾——end 有值即已結束於該時點，" +
                    "ended 只用於「已結束、時點未知」。二擇一。")
            }
            endedUnknown = b
        }
        return DateRange(start: try str("start"), end: end, endedUnknown: endedUnknown)
    }
}

// MARK: - Organization ↔ YAML

/// 機構的編解碼。沿用 person 的慣例：形狀裸標籤在最前、未知欄位 tolerant-preserve、
/// encode 後自檢（canary）。
public enum OrganizationYAML {
    static let knownKeys: Set<String> = Set(["id", "key", "names", "authorized",
                                             "founded", "dissolved",
                                             "parents", "note", "references"])
        .union(EntityKind.knownLabels)

    public static func encode(_ org: Organization) throws -> String {
        var pairs: [(Node, Node)] = [(Node(EntityKind.organization.rawValue), Node("")),
                                     (Node("id"), Node(org.id.uuidString)),
                                     (Node("key"), Node(org.key))]
        if !org.names.isEmpty {
            try pairs.append((Node("names"), PersonYAML.timelineNode(org.names)))
        }
        // #81：緊接 names 之後，讀的人要能對照「指定的是時間軸上的哪幾個」。
        if !org.authorized.isEmpty {
            pairs.append((Node("authorized"), Node(org.authorized.map { Node($0) })))
        }
        if let f = org.founded { pairs.append((Node("founded"), Node(f))) }
        if let d = org.dissolved { pairs.append((Node("dissolved"), Node(d))) }
        if !org.parents.isEmpty {
            try pairs.append((Node("parents"), PersonYAML.orgTimelineNode(org.parents)))
        }
        if let n = org.note { pairs.append((Node("note"), Node(n))) }
        // #66：欄位層級的 provenance。空清單不寫出——既有記錄零 diff。
        if !org.references.isEmpty {
            try pairs.append((Node("references"), ProvenanceYAML.node(org.references)))
        }
        var text = try Yams.serialize(node: Node(pairs), allowUnicode: true)
        try EntryYAML.appendRawBlocks(org.unknownFields, to: &text, targetIndent: 0,
                                      context: "organization")
        // canary：寫出去的東西必須讀得回同一個值，否則拒寫（v1.3 fail-closed）。
        let back = try decode(text)
        guard back == org else {
            throw StoreYAMLError.invalidField("organization", "encode 自檢失敗：讀回的值與原值不符")
        }
        return text
    }

    public static func decode(_ yaml: String) throws -> Organization {
        let yaml = EntryYAML.stripLeadingBOM(yaml)
        try EntryYAML.assertNoLossyContentChars(yaml, context: "organization")
        try AliasEventBudget.check(yaml, context: "library")
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        var oracleBudget = 200_000
        let keys = try EntryYAML.keyStrings(map, known: knownKeys, context: "organization")
        let unknowns = try EntryYAML.captureUnknownBlocks(
            text: yaml, map: map, keys: keys, known: knownKeys,
            indent: 0, context: "organization", budget: &oracleBudget)
        guard let key = try EntryYAML.requireShape(map["key"], field: "organization.key",
                                                   expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("key")
        }
        var explicitID: UUID?
        if let raw = try EntryYAML.requireShape(map["id"], field: "organization.id",
                                                expect: "scalar", nullIsAbsent: true,
                                                { $0.scalar?.string }) {
            guard let u = UUID(uuidString: raw) else {
                throw StoreYAMLError.invalidField("organization.id", "不是合法的 UUID")
            }
            explicitID = u
        }
        var org = Organization(key: key, id: explicitID)
        org.unknownFields = unknowns
        if let n = map["names"] {
            org.names = try PersonYAML.decodeTimeline(n, context: "organization.names")
        }
        // #81：形狀不符 fail-closed（與 person.authorized 同紀律）。
        if let seq = try EntryYAML.requireShape(map["authorized"], field: "organization.authorized",
                                                expect: "sequence", nullIsAbsent: true,
                                                { $0.sequence }) {
            org.authorized = try EntryYAML.stringList(seq, context: "organization.authorized")
        }
        org.founded = try EntryYAML.requireShape(map["founded"], field: "organization.founded",
                                                 expect: "scalar", nullIsAbsent: true,
                                                 { $0.scalar?.string })
        org.dissolved = try EntryYAML.requireShape(map["dissolved"], field: "organization.dissolved",
                                                   expect: "scalar", nullIsAbsent: true,
                                                   { $0.scalar?.string })
        if let p = map["parents"] {
            org.parents = try PersonYAML.decodeOrgTimeline(p, context: "organization.parents")
        }
        org.note = try EntryYAML.requireShape(map["note"], field: "organization.note",
                                              expect: "scalar", nullIsAbsent: true,
                                              { $0.scalar?.string })
        // #66：references（同 person——逐筆驗證住 ProvenanceYAML，附著驗證在組完後）
        if let rn = try EntryYAML.requireShape(map["references"], field: "organization.references",
                                               expect: "sequence", nullIsAbsent: true,
                                               { $0.sequence != nil ? $0 : nil }) {
            org.references = try ProvenanceYAML.decode(rn, context: "organization")
        }
        try org.validateReferenceAttachment()
        return org
    }
}

// MARK: - Divergence（#71）

/// `divergence` ↔ YAML。欄位順序：裸標籤 → id → question → candidates → judgement → rests-on。
///
/// 拒絕條件不是防禦性檢查，是形狀的意義：少於兩個候選的「歧異」沒有東西可以與之
/// 相同；跨形狀的候選不是未決的問題而是類別錯誤；沒有依據的判斷不是判斷。
public enum DivergenceYAML {
    static let knownKeys: Set<String> = Set(["id", "question", "candidates",
                                             "judgement", "rests-on"])
        .union(EntityKind.knownLabels)

    static let knownCandidateKeys: Set<String> = Set(["key", "shape"])

    public static func encode(_ d: Divergence) throws -> String {
        var pairs: [(Node, Node)] = [(Node(EntityKind.divergence.rawValue), Node("")),
                                     (Node("id"), Node(d.id.uuidString)),
                                     (Node("question"), Node(d.question))]
        // 候選依 (shape, key) 排序輸出——同一組候選不論寫入順序都得到同一份位元組。
        let sorted = d.candidates.sorted { ($0.shape.rawValue, $0.key) < ($1.shape.rawValue, $1.key) }
        pairs.append((Node("candidates"), Node(sorted.map { c -> Node in
            Node([(Node("key"), Node(c.key)),
                  (Node("shape"), Node(c.shape.rawValue))] as [(Node, Node)])
        })))
        if let j = d.judgement {
            pairs.append((Node("judgement"), Node(j.statement)))
            pairs.append((Node("rests-on"), Node(j.restsOn.sorted().map { Node($0) })))
        }
        var text = try Yams.serialize(node: Node(pairs), allowUnicode: true)
        try EntryYAML.appendRawBlocks(d.unknownFields, to: &text, targetIndent: 0,
                                      context: "divergence")
        // canary：寫出去的東西必須讀得回同一個值，否則拒寫（v1.3 fail-closed）。
        let back = try decode(text)
        guard back == d else {
            throw StoreYAMLError.invalidField("divergence", "encode 自檢失敗：讀回的值與原值不符")
        }
        return text
    }

    public static func decode(_ yaml: String) throws -> Divergence {
        let yaml = EntryYAML.stripLeadingBOM(yaml)
        try EntryYAML.assertNoLossyContentChars(yaml, context: "divergence")
        try AliasEventBudget.check(yaml, context: "entity")
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        var oracleBudget = 200_000
        let keys = try EntryYAML.keyStrings(map, known: knownKeys, context: "divergence")
        let unknowns = try EntryYAML.captureUnknownBlocks(
            text: yaml, map: map, keys: keys, known: knownKeys,
            indent: 0, context: "divergence", budget: &oracleBudget)

        guard let question = try EntryYAML.requireShape(
            map["question"], field: "divergence.question",
            expect: "scalar", { $0.scalar?.string }) else {
            throw StoreYAMLError.missingField("question")
        }
        // 空的 question 不是「未決的問題」——記錄的整個意義就是那句話。
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreYAMLError.invalidField("divergence.question", "不得為空")
        }
        guard let rawID = try EntryYAML.requireShape(
            map["id"], field: "divergence.id",
            expect: "scalar", nullIsAbsent: true, { $0.scalar?.string }),
              let id = UUID(uuidString: rawID) else {
            throw StoreYAMLError.invalidField("divergence.id", "缺少或不是合法的 UUID")
        }

        guard let seq = try EntryYAML.requireShape(
            map["candidates"], field: "divergence.candidates",
            expect: "sequence", { $0.sequence }) else {
            throw StoreYAMLError.missingField("candidates")
        }
        var candidates: [DivergenceCandidate] = []
        for node in seq {
            guard let m = node.mapping else {
                throw StoreYAMLError.invalidField("divergence.candidates", "每個候選必須是 mapping")
            }
            try EntryYAML.rejectUnknownKeys(m, known: knownCandidateKeys, context: "candidates")
            // requireShape 而非 `?.scalar?.string`：known 欄位的形狀演化不入 tolerant
            // 範圍（fail-closed）。直接取 scalar 會把「key 寫成序列」誤報成「缺 key」。
            guard let key = try EntryYAML.requireShape(
                m["key"], field: "divergence.candidates[].key",
                expect: "scalar", { $0.scalar?.string }), !key.isEmpty else {
                throw StoreYAMLError.invalidField(
                    "divergence.candidates", "候選的 key 缺少或為空")
            }
            guard let rawShape = try EntryYAML.requireShape(
                m["shape"], field: "divergence.candidates[].shape",
                expect: "scalar", { $0.scalar?.string }) else {
                throw StoreYAMLError.invalidField(
                    "divergence.candidates",
                    "候選「\(displaySafe(key, max: 200))」缺少 shape"
                    + "——鍵在不同形狀之間可以同名，形狀無法推導")
            }
            // 歧異記錄本身不是可被指涉的對象（它沒有 key，身分是 UUID），所以它
            // 不能當候選——「這兩個歧異是不是同一個」不是本形狀承載的問題。
            if rawShape == EntityKind.divergence.rawValue {
                throw StoreYAMLError.invalidField(
                    "divergence.candidates",
                    "候選「\(displaySafe(key, max: 200))」的 shape 不得是 divergence"
                    + "——歧異記錄沒有 key，不是可被指涉的對象")
            }
            guard let shape = EntityKind(rawValue: rawShape) else {
                throw StoreYAMLError.invalidField(
                    "divergence.candidates",
                    "候選「\(displaySafe(key, max: 200))」的 shape"
                    + "「\(displaySafe(rawShape, max: 100))」不是已知形狀")
            }
            candidates.append(DivergenceCandidate(key: key, shape: shape))
        }

        // 歧異需要有東西與之相同。**先去重再數**：兩個一模一樣的候選沒有東西可以
        // 與之相同，卻能通過「至少兩個」——而消歧路徑對同一組候選的判定相反（它會
        // 去重後視為塌縮並刪除記錄）。同一份資料兩種判定，其中一種必然是錯的。
        var seenCandidate = Set<String>()
        for c in candidates where !seenCandidate.insert("\(c.shape.rawValue)\u{0}\(c.key)").inserted {
            throw StoreYAMLError.invalidField(
                "divergence.candidates",
                "候選「\(displaySafe(c.key, max: 200))」（\(c.shape.rawValue)）重複"
                + "——重複的候選不構成歧異，它沒有東西可以與之相同")
        }
        guard candidates.count >= 2 else {
            throw StoreYAMLError.invalidField(
                "divergence.candidates",
                "歧異至少需要兩個候選，實際 \(candidates.count) 個")
        }
        // 跨形狀不是未決的問題，是類別錯誤——錯誤同時指名兩個候選與各自的形狀。
        if let first = candidates.first,
           let odd = candidates.first(where: { $0.shape != first.shape }) {
            throw StoreYAMLError.invalidField(
                "divergence.candidates",
                "候選跨越不同形狀：「\(displaySafe(first.key, max: 200))」是 \(first.shape.rawValue)，"
                + "「\(displaySafe(odd.key, max: 200))」是 \(odd.shape.rawValue)"
                + "——「是否為同一個」跨形狀無法回答")
        }

        // judgement 與 rests-on 成對；只有其一時「這筆 provenance 完不完整」無法機械判定。
        let statement = try EntryYAML.requireShape(
            map["judgement"], field: "divergence.judgement",
            expect: "scalar", nullIsAbsent: true, { $0.scalar?.string })
        let restsOnSeq = try EntryYAML.requireShape(
            map["rests-on"], field: "divergence.rests-on",
            expect: "sequence", nullIsAbsent: true, { $0.sequence })
        // **stringList 而非 compactMap**：非 scalar 元素要擲錯，不得靜默丟棄。
        // 失敗情境：`- sha256: 9a23…`（冒號後多一個空格）在 YAML 是 mapping。若靜默
        // 丟掉而其餘項合法，那筆證據就永久消失——而 canary 的 decode(encode(d)) 兩側
        // 都缺同一項所以比對相等、照樣寫出。這正是 canary 要擋卻擋不到的靜默遺失。
        let restsOn = try restsOnSeq.map {
            try EntryYAML.stringList($0, context: "divergence.rests-on")
        } ?? []
        // 空的斷言不是判斷，空的摘要不是依據——與空 question 同一條理由。
        if let s = statement, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StoreYAMLError.invalidField("divergence.judgement", "不得為空")
        }
        if let bad = restsOn.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            _ = bad
            throw StoreYAMLError.invalidField("divergence.rests-on", "元素不得為空")
        }
        var judgement: Judgement?
        switch (statement, restsOn.isEmpty) {
        case (nil, true):
            judgement = nil
        case (let s?, false):
            judgement = Judgement(statement: s, restsOn: restsOn)
        default:
            throw StoreYAMLError.invalidField(
                "divergence.judgement",
                "judgement 與 rests-on 必須成對出現——"
                + "沒有依據的斷言不是判斷，沒有斷言的依據不知道在支持什麼")
        }

        var d = Divergence(id: id, question: question, candidates: candidates,
                           judgement: judgement)
        d.unknownFields = unknowns
        return d
    }
}
