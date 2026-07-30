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
        if !entry.akashic.isEmpty {
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
            try appendUnknownFields(entry.akashic.unknownFields, to: &a)
            pairs.append((Node("akashic"), Node(a)))
        }
        try appendUnknownFields(entry.unknownFields, to: &pairs)
        return try Yams.serialize(node: Node(pairs), allowUnicode: true)
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
    /// library 頂層與 akashic namespace）改走 partitionUnknownKeys 容忍保留。
    static func rejectUnknownKeys(_ map: Yams.Node.Mapping, known: Set<String>,
                                  context: String) throws {
        for (key, _) in map {
            guard let k = key.string else {
                throw StoreYAMLError.invalidField(context, "非字串鍵")
            }
            if !known.contains(k) {
                throw StoreYAMLError.invalidField(context, "未知欄位「\(k)」（strict schema；見 docs/store-format.md §5）")
            }
        }
    }

    /// tolerant-preserve（store-format §5 v1.3，#23）：未知欄位不 throw，
    /// value 節點整棵以 YAML 文字保留（保序），encode 端原樣寫回。
    /// 舊版 rejectUnknownKeys 用 throw 防「re-encode 靜默剝欄位」的資料毀損；
    /// 本 helper 用「保留 + 寫回」達成同一保證，同時讓較新 schema 的檔案保持可用。
    static func partitionUnknownKeys(_ map: Yams.Node.Mapping, known: Set<String>,
                                     context: String) throws -> [UnknownField] {
        var unknowns: [UnknownField] = []
        for (key, value) in map {
            guard let k = key.string else {
                throw StoreYAMLError.invalidField(context, "非字串鍵")
            }
            if !known.contains(k) {
                unknowns.append(UnknownField(
                    key: k, yaml: try Yams.serialize(node: value, allowUnicode: true)))
            }
        }
        return unknowns
    }

    /// 未知欄位寫回（encode 端）。compose 失敗＝保留載體毀損——throw，不靜默丟。
    static func appendUnknownFields(_ fields: [UnknownField],
                                    to pairs: inout [(Node, Node)]) throws {
        for f in fields {
            guard let node = try Yams.compose(yaml: f.yaml) else {
                throw StoreYAMLError.invalidField("unknownFields", "無法還原保留欄位「\(f.key)」")
            }
            pairs.append((Node(f.key), node))
        }
    }

    public static func decode(_ yaml: String) throws -> Entry {
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        let topUnknowns = try partitionUnknownKeys(map, known: knownTopLevelKeys, context: "entry")
        guard let idString = map["id"]?.string, let id = UUID(uuidString: idString) else {
            throw StoreYAMLError.missingField("id")
        }
        guard let citekey = map["citekey"]?.string else {
            throw StoreYAMLError.missingField("citekey")
        }
        guard let type = map["type"]?.string else {
            throw StoreYAMLError.missingField("type")
        }
        guard let title = map["title"]?.string else {
            throw StoreYAMLError.missingField("title")
        }

        var entry = Entry(id: id, citekey: citekey, type: type, title: title)
        entry.unknownFields = topUnknowns
        entry.date = map["date"]?.string

        if let authorSeq = map["authors"]?.sequence {
            entry.authors = try authorSeq.map { node in
                guard let m = node.mapping else {
                    throw StoreYAMLError.invalidField("authors", "元素不是 mapping")
                }
                try rejectUnknownKeys(m, known: ["key", "literal"], context: "authors")
                let key = try m["key"].map { try strictString($0, context: "authors.key") }
                let literal = try m["literal"].map { try strictString($0, context: "authors.literal") }
                switch (key, literal) {
                case (let k?, nil): return .key(k)
                case (nil, let s?): return .literal(s)
                default:
                    throw StoreYAMLError.invalidField("authors", "必須恰好有 key 或 literal 其一")
                }
            }
        }
        if let fieldMap = map["fields"]?.mapping {
            for (k, v) in fieldMap {
                guard let kk = k.string, let vv = v.string else {
                    throw StoreYAMLError.invalidField("fields", "鍵值必須是字串")
                }
                entry.fields[kk] = vv
            }
        }
        if let attSeq = map["attachments"]?.sequence {
            entry.attachments = try attSeq.map { node in
                guard let m = node.mapping, m.count == 1,
                      let first = m.first, let kindRaw = first.key.string,
                      let kind = AttachmentRef.Kind(rawValue: kindRaw),
                      let path = first.value.string else {
                    throw StoreYAMLError.invalidField("attachments", "元素必須是 {zotero: path} 或 {pool: path}")
                }
                return AttachmentRef(kind: kind, path: path)
            }
        }
        if let provMap = map["provenance"]?.mapping {
            try rejectUnknownKeys(provMap, known: knownProvenanceKeys, context: "provenance")
            guard let zKey = provMap["zotero_key"]?.string else {
                throw StoreYAMLError.invalidField("provenance", "缺 zotero_key")
            }
            guard let zVerString = provMap["zotero_version"]?.string ?? provMap["zotero_version"]?.scalar?.string,
                  let zVer = Int(zVerString) else {
                throw StoreYAMLError.invalidField("provenance", "缺 zotero_version")
            }
            var prov = Provenance(zoteroKey: zKey, zoteroVersion: zVer)
            if let s = provMap["library_id"]?.string ?? provMap["library_id"]?.scalar?.string {
                guard let lid = Int(s) else {
                    throw StoreYAMLError.invalidField("provenance", "library_id「\(s)」不是整數")
                }
                prov.libraryID = lid
            }
            prov.zoteroHash = provMap["zotero_hash"]?.string
            if let s = provMap["imported_at"]?.string {
                prov.importedAt = isoFormatter.date(from: s)
            }
            if let s = provMap["orphaned_at"]?.string {
                prov.orphanedAt = isoFormatter.date(from: s)
            }
            entry.provenance = prov
        }
        if let akMap = map["akashic"]?.mapping {
            entry.akashic.unknownFields =
                try partitionUnknownKeys(akMap, known: knownAkashicKeys, context: "akashic")
            if let tagSeq = akMap["tags"]?.sequence {
                entry.akashic.tags = try stringList(tagSeq, context: "akashic.tags")
            }
            if let libNode = akMap["libraries"] {
                guard let libSeq = libNode.sequence else {
                    throw StoreYAMLError.invalidField("akashic.libraries", "必須是 sequence")
                }
                entry.akashic.libraries = try stringList(libSeq, context: "akashic.libraries")
            }
            entry.akashic.status = akMap["status"]?.string
            if let relMap = akMap["relations"]?.mapping {
                try rejectUnknownKeys(relMap, known: knownRelationsKeys, context: "akashic.relations")
                if let seq = relMap["cites"]?.sequence {
                    entry.akashic.relations.cites = try stringList(seq, context: "akashic.relations.cites")
                }
                if let seq = relMap["related"]?.sequence {
                    entry.akashic.relations.related = try stringList(seq, context: "akashic.relations.related")
                }
            }
        }
        return entry
    }

    /// 序列元素必須全是字串——非字串元素 throw，不靜默略過（strict §5）。
    static func stringList(_ seq: Yams.Node.Sequence, context: String) throws -> [String] {
        try seq.map { try strictString($0, context: context) }
    }

    /// YAML 語意上的字串 scalar。plain-style 且可解析為 bool/int/double/null 的
    /// scalar（`123`、`true`、`~`）不是字串——`Node.string` 會回它的字面內容，
    /// 直接採納等於靜默型別轉換；quoted（`"123"`）才是字串。
    static func strictString(_ node: Yams.Node, context: String) throws -> String {
        guard let scalar = node.scalar else {
            throw StoreYAMLError.invalidField(context, "元素必須是字串")
        }
        if scalar.style == .plain {
            let raw = scalar.string
            let isNullish = raw.isEmpty || raw == "~"
                || ["null", "nan"].contains(raw.lowercased())
            if isNullish || Bool.construct(from: scalar) != nil
                || Int.construct(from: scalar) != nil
                || Double.construct(from: scalar) != nil {
                throw StoreYAMLError.invalidField(context, "「\(raw)」是非字串 scalar（int/bool/null）；要當字串請加引號")
            }
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
        try EntryYAML.appendUnknownFields(library.unknownFields, to: &pairs)
        return try Yams.serialize(node: Node(pairs), allowUnicode: true)
    }

    static let knownLibraryKeys: Set<String> = ["key", "name", "description"]

    public static func decode(_ yaml: String) throws -> Library {
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        let unknowns = try EntryYAML.partitionUnknownKeys(map, known: knownLibraryKeys, context: "library")
        guard let key = map["key"]?.string else {
            throw StoreYAMLError.missingField("key")
        }
        guard let name = map["name"]?.string else {
            throw StoreYAMLError.missingField("name")
        }
        var library = Library(key: key, name: name)
        library.unknownFields = unknowns
        if let descNode = map["description"] {
            guard let desc = descNode.string else {
                throw StoreYAMLError.invalidField("library.description", "必須是 string")
            }
            library.description = desc
        }
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
        try EntryYAML.appendUnknownFields(person.unknownFields, to: &pairs)
        return try Yams.serialize(node: Node(pairs), allowUnicode: true)
    }

    static let knownPersonKeys: Set<String> = ["key", "names", "orcid", "openalex", "note"]

    public static func decode(_ yaml: String) throws -> Person {
        guard let root = try Yams.compose(yaml: yaml), let map = root.mapping else {
            throw StoreYAMLError.notAMapping
        }
        let unknowns = try EntryYAML.partitionUnknownKeys(map, known: knownPersonKeys, context: "person")
        guard let key = map["key"]?.string else {
            throw StoreYAMLError.missingField("key")
        }
        var person = Person(key: key)
        person.unknownFields = unknowns
        if let seq = map["names"]?.sequence {
            person.names = try EntryYAML.stringList(seq, context: "person.names")
        }
        person.orcid = map["orcid"]?.string
        person.openalex = map["openalex"]?.string
        person.note = map["note"]?.string
        return person
    }
}
