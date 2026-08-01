import Foundation
import Yams

public enum StoreYAMLError: Error, LocalizedError, Equatable {
    case notAMapping
    case missingField(String)
    case invalidField(String, String)

    public var errorDescription: String? {
        switch self {
        case .notAMapping: return "YAML 頂層不是 mapping"
        case .missingField(let f): return "缺少必要欄位：\(f)"
        case .invalidField(let f, let why): return "欄位 \(f) 無效：\(why)"
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
        try verifyUnknownValuesPreserved(rd.unknownFields, entry.unknownFields, context: "entry")
        try verifyUnknownValuesPreserved(rd.akashic.unknownFields, entry.akashic.unknownFields,
                                         context: "akashic")
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
                                             context: String) throws {
        guard got.count == want.count else {
            throw StoreYAMLError.invalidField(
                context, "encode 語意自檢失敗——未知欄位數不符，拒絕寫出")
        }
        var budget = 200_000
        for (g, w) in zip(got, want) {
            guard let gn = composeBlock(g.raw), let wn = composeBlock(w.raw) else {
                throw StoreYAMLError.invalidField(
                    context, "未知欄位「\(w.key)」寫出前後無法獨立解析——拒絕寫出")
            }
            switch nodesSemanticallyEqual(gn, wn, budget: &budget) {
            case true: break
            case false:
                throw StoreYAMLError.invalidField(
                    context, "未知欄位「\(w.key)」寫出前後語意不符（值漂移）——拒絕寫出")
            case nil:
                throw StoreYAMLError.invalidField(
                    context, "未知欄位「\(w.key)」超出驗證預算（單檔共用上限）——fail-closed")
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

    static let knownTopLevelKeys: Set<String> = [
        "id", "citekey", "type", "title", "authors", "date",
        "fields", "attachments", "provenance", "akashic",
    ]
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
            if k == "<<" {   // merge key 從不在 known set——語意在 parser 間分歧，不入 tolerant 範圍（§5）
                throw StoreYAMLError.invalidField(
                    context, "merge key「<<」不入 tolerant 範圍（見 docs/store-format.md §5）")
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
            composed = try Yams.compose(yaml: text)
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
        case true:
            break
        case false:
            throw StoreYAMLError.invalidField(
                context, "未知欄位「\(expectedKey)」的區塊值與 parse 結果不符（切分錯位，fail-closed）")
        case nil:
            // 預算耗盡 ≠ 不相符——比對次數與節點數線性相關：巨大未知子樹或
            // anchor/alias 重用型 DAG 都會觸發（R6 更正：R5 誤稱「與檔案大小
            // 無關」——alias-free 的 70k+ 節點子樹同樣打穿）。訊息分開，診斷
            // 才可行動。
            throw StoreYAMLError.invalidField(
                context, "未知欄位「\(expectedKey)」超出驗證預算（節點數或 anchor/alias 展開超過比對上限）——fail-closed")
        }
    }

    /// 預算制節點語意等值（scalar 比 string+resolvedTag；collection 逐元素）。
    /// 回傳 nil = 預算耗盡（alias 展開型 DAG 比對爆炸）——呼叫端 fail-closed。
    static func nodesSemanticallyEqual(_ a: Yams.Node, _ b: Yams.Node,
                                       budget: inout Int) -> Bool? {
        budget -= 1
        if budget <= 0 { return nil }
        switch (a, b) {
        case (.scalar(let x), .scalar(let y)):
            // Node.Scalar 的 == 即 string + resolvedTag 比較（Yams 公開語意）
            return x == y
        case (.sequence(let x), .sequence(let y)):
            guard x.count == y.count else { return false }
            for (u, v) in zip(x, y) {
                guard let r = nodesSemanticallyEqual(u, v, budget: &budget) else { return nil }
                if !r { return false }
            }
            return true
        case (.mapping(let x), .mapping(let y)):
            guard x.count == y.count else { return false }
            for ((k1, v1), (k2, v2)) in zip(Array(x), Array(y)) {
                guard let rk = nodesSemanticallyEqual(k1, k2, budget: &budget) else { return nil }
                if !rk { return false }
                guard let rv = nodesSemanticallyEqual(v1, v2, budget: &budget) else { return nil }
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
                                _ extract: (Yams.Node) -> T?) throws -> T? {
        guard let node else { return nil }
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
                                              expect: "scalar", { $0.scalar?.string }),
              let id = UUID(uuidString: idString) else {
            throw StoreYAMLError.missingField("id")
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
                                            expect: "sequence", { $0.sequence }) {
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
                                           expect: "mapping", { $0.mapping }) {
            var seenFieldKeys = Set<String>()
            for (k, v) in fieldMap {
                guard let kk = k.string, let vv = v.scalar?.string else {
                    throw StoreYAMLError.invalidField("fields", "鍵值必須是 scalar（以字串面解讀）")
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
                                         expect: "sequence", { $0.sequence }) {
            entry.attachments = try attSeq.map { node in
                guard let m = node.mapping, m.count == 1,
                      let first = m.first, let kindRaw = first.key.string,
                      let kind = AttachmentRef.Kind(rawValue: kindRaw),
                      let path = first.value.scalar?.string else {
                    throw StoreYAMLError.invalidField("attachments", "元素必須是 {zotero: path} 或 {pool: path}")
                }
                return AttachmentRef(kind: kind, path: path)
            }
        }
        if let provMap = try requireShape(map["provenance"], field: "provenance",
                                          expect: "mapping", { $0.mapping }) {
            try rejectUnknownKeys(provMap, known: knownProvenanceKeys, context: "provenance")
            guard let zKey = provMap["zotero_key"]?.scalar?.string else {
                throw StoreYAMLError.invalidField("provenance", "缺 zotero_key")
            }
            guard let zVerString = provMap["zotero_version"]?.scalar?.string,
                  let zVer = Int(zVerString) else {
                throw StoreYAMLError.invalidField("provenance", "缺 zotero_version")
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
            if let n = provMap["imported_at"] {
                guard let s = n.scalar?.string, let d = isoFormatter.date(from: s) else {
                    throw StoreYAMLError.invalidField(
                        "provenance.imported_at", "不是 ISO-8601 秒精度時間戳（fail-closed）")
                }
                prov.importedAt = d
            }
            if let n = provMap["orphaned_at"] {
                guard let s = n.scalar?.string, let d = isoFormatter.date(from: s) else {
                    throw StoreYAMLError.invalidField(
                        "provenance.orphaned_at", "不是 ISO-8601 秒精度時間戳（fail-closed）")
                }
                prov.orphanedAt = d
            }
            entry.provenance = prov
        }
        if let akMap = try requireShape(map["akashic"], field: "akashic",
                                        expect: "mapping", { $0.mapping }) {
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
                                            expect: "sequence", { $0.sequence }) {
                entry.akashic.tags = try stringList(tagSeq, context: "akashic.tags")
            }
            if let libNode = akMap["libraries"] {
                guard let libSeq = libNode.sequence else {
                    throw StoreYAMLError.invalidField("akashic.libraries", "必須是 sequence")
                }
                entry.akashic.libraries = try stringList(libSeq, context: "akashic.libraries")
            }
            entry.akashic.status = try requireShape(akMap["status"], field: "akashic.status",
                                                    expect: "scalar") { $0.scalar?.string }
            if let relMap = try requireShape(akMap["relations"], field: "akashic.relations",
                                             expect: "mapping", { $0.mapping }) {
                try rejectUnknownKeys(relMap, known: knownRelationsKeys, context: "akashic.relations")
                if let seq = try requireShape(relMap["cites"], field: "akashic.relations.cites",
                                              expect: "sequence", { $0.sequence }) {
                    entry.akashic.relations.cites = try stringList(seq, context: "akashic.relations.cites")
                }
                if let seq = try requireShape(relMap["related"], field: "akashic.relations.related",
                                              expect: "sequence", { $0.sequence }) {
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
            throw StoreYAMLError.invalidField(
                "library", "encode 語意自檢失敗——產物與模型不符，拒絕寫出")
        }
        try EntryYAML.verifyUnknownValuesPreserved(rd.unknownFields, library.unknownFields,
                                                   context: "library")
        return out
    }

    static let knownLibraryKeys: Set<String> = ["key", "name", "description"]

    public static func decode(_ yaml: String) throws -> Library {
        let yaml = EntryYAML.stripLeadingBOM(yaml)
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
        var pairs: [(Node, Node)] = [(Node("key"), Node(person.key))]
        if !person.names.isEmpty {
            pairs.append((Node("names"), Node(person.names.map { Node($0) })))
        }
        if let orcid = person.orcid { pairs.append((Node("orcid"), Node(orcid))) }
        if let openalex = person.openalex { pairs.append((Node("openalex"), Node(openalex))) }
        if let note = person.note { pairs.append((Node("note"), Node(note))) }
        var out = try Yams.serialize(node: Node(pairs), allowUnicode: true)
        try EntryYAML.appendRawBlocks(person.unknownFields, to: &out, targetIndent: 0,
                                      context: "person")
        // 語意 canary（R4；R6 起無條件執行，比較基準見 EntryYAML.encode 註解）
        try EntryYAML.encodeCanary(out, context: "person")
        let rd = try decode(out)
        var a = rd, b = person
        a.unknownFields = []; b.unknownFields = []
        guard a == b, rd.unknownFields.map(\.key) == person.unknownFields.map(\.key) else {
            throw StoreYAMLError.invalidField(
                "person", "encode 語意自檢失敗——產物與模型不符，拒絕寫出")
        }
        try EntryYAML.verifyUnknownValuesPreserved(rd.unknownFields, person.unknownFields,
                                                   context: "person")
        return out
    }

    static let knownPersonKeys: Set<String> = ["key", "names", "orcid", "openalex", "note"]

    public static func decode(_ yaml: String) throws -> Person {
        let yaml = EntryYAML.stripLeadingBOM(yaml)
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
        var person = Person(key: key)
        person.unknownFields = unknowns
        // R6（DA R5 HIGH 實測案例即 person.names）：形狀不符 fail-closed
        if let seq = try EntryYAML.requireShape(map["names"], field: "person.names",
                                                expect: "sequence", { $0.sequence }) {
            person.names = try EntryYAML.stringList(seq, context: "person.names")
        }
        person.orcid = try EntryYAML.requireShape(map["orcid"], field: "person.orcid",
                                                  expect: "scalar") { $0.scalar?.string }
        person.openalex = try EntryYAML.requireShape(map["openalex"], field: "person.openalex",
                                                     expect: "scalar") { $0.scalar?.string }
        person.note = try EntryYAML.requireShape(map["note"], field: "person.note",
                                                 expect: "scalar") { $0.scalar?.string }
        return person
    }
}
