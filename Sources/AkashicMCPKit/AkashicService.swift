import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicZoteroImport
import AkashicExport
import AkashicIndex
import AkashicQuery
import AkashicGraph

public enum ServiceError: Error, LocalizedError {
    case notFound(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let what): return "找不到：\(what)"
        case .invalid(let why): return why
        }
    }
}

/// akashic-mcp 的 handler 核心（可測試、不含 MCP 佈線）。
/// 讀走 index（mtime stale 自動重建）；寫只碰衍生層，寫後重建 index。
public final class AkashicService {
    let root: URL

    public init(root: URL) {
        self.root = root
    }

    var store: LibraryStore { LibraryStore(root: root) }

    // MARK: - 讀

    public func search(author: String? = nil, journal: String? = nil, tag: String? = nil,
                       type: String? = nil, yearFrom: Int? = nil, yearTo: Int? = nil,
                       library: String? = nil) throws -> String {
        let engine = try freshEngine()
        var filter = QueryFilter()
        filter.author = author
        filter.journal = journal
        filter.tag = tag
        filter.type = type
        filter.yearFrom = yearFrom
        filter.yearTo = yearTo
        filter.library = library
        return try jsonString(try engine.find(filter).map(summaryDict))
    }

    public func getEntry(citekey: String) throws -> String {
        let load = try store.load()
        guard let entry = load.entries.first(where: { $0.citekey == citekey }) else {
            throw ServiceError.notFound("citekey「\(citekey)」")
        }
        return try jsonString(entryDict(entry))
    }

    public func relations(citekey: String, kind: String) throws -> String {
        let engine = try freshEngine()
        let result: [EntrySummary]
        switch kind {
        case "same-journal": result = try engine.sameJournal(as: citekey)
        case "same-author": result = try engine.sameAuthor(as: citekey)
        case "cites": result = try engine.cites(of: citekey)
        case "cited-by": result = try engine.citedBy(citekey)
        case "related": result = try engine.related(to: citekey)
        default:
            throw ServiceError.invalid("kind 必須是 same-journal / same-author / cites / cited-by / related")
        }
        return try jsonString(result.map(summaryDict))
    }

    public func graph(focus: String, depth: Int, format: String) throws -> String {
        try ensureFreshIndex()
        let builder = try GraphBuilder(indexPath: store.indexURL)
        let neighborhood = try builder.neighborhood(focus: focus, depth: depth)
        switch format {
        case "mermaid": return GraphRenderer.mermaid(neighborhood)
        case "dot": return GraphRenderer.dot(neighborhood)
        case "graphml": return GraphRenderer.graphml(neighborhood)
        default: throw ServiceError.invalid("format 必須是 mermaid / dot / graphml")
        }
    }

    public func export(citekeys: [String]?, format: String) throws -> String {
        let load = try store.load()
        var entries = load.entries
        if let wanted = citekeys {
            let wantedSet = Set(wanted)
            entries = entries.filter { wantedSet.contains($0.citekey) }
            let missing = wantedSet.subtracting(entries.map(\.citekey))
            guard missing.isEmpty else {
                throw ServiceError.notFound("citekeys：\(missing.sorted().joined(separator: ", "))")
            }
        }
        switch format {
        case "bib": return BibExport.bibFile(entries: entries, people: load.people)
        case "csl-json": return try CSLExport.cslJSON(entries: entries, people: load.people)
        default: throw ServiceError.invalid("format 必須是 bib / csl-json")
        }
    }

    public func people(query: String?) throws -> String {
        var people = try store.load().people
        if let q = query?.lowercased(), !q.isEmpty {
            people = people.filter { person in
                person.key.lowercased().contains(q)
                    || person.names.contains { $0.lowercased().contains(q) }
            }
        }
        let dicts = people.map { person -> [String: Any] in
            var d: [String: Any] = ["key": person.key, "names": person.names]
            if let orcid = person.orcid { d["orcid"] = orcid }
            if let openalex = person.openalex { d["openalex"] = openalex }
            return d
        }
        return try jsonString(dicts)
    }

    public func doctor() throws -> String {
        let load = try store.load()
        let stats = try LibraryIndex(store: store).rebuild()
        let unresolved = load.entries.flatMap { entry in
            entry.authors.compactMap { if case .literal = $0 { return 1 } else { return nil } }
        }.count
        let orphaned = load.entries.filter { $0.provenance?.orphanedAt != nil }.map(\.citekey)
        var d: [String: Any] = [
            "library": root.path,
            "entries": stats.entries,
            "people": stats.people,
            "relations": stats.relations,
            "unresolvedAuthorLiterals": unresolved,
            "orphaned": orphaned,
        ]
        if !load.quarantined.isEmpty {
            d["quarantined"] = load.quarantined.map { ["file": $0.file, "reason": $0.reason] }
        }
        return try jsonString(d)
    }

    // MARK: - 寫（衍生層 only）

    /// #13 多 library：registry 管理 + 成員操作（衍生層寫入邊界內）。
    public func libraries(action: String, key: String?, name: String?,
                          description: String?, citekey: String?) throws -> String {
        switch action {
        case "list":
            let load = try store.load()
            var counts: [String: Int] = [:]
            for entry in load.entries {
                for k in Set(entry.akashic.libraries) { counts[k, default: 0] += 1 }
            }
            return try jsonString(load.libraries.map { lib -> [String: Any] in
                var d: [String: Any] = ["key": lib.key, "name": lib.name,
                                        "members": counts[lib.key] ?? 0]
                if let desc = lib.description { d["description"] = desc }
                return d
            })
        case "create":
            guard let key, let name else {
                throw ServiceError.invalid("create 需要 key 與 name")
            }
            // 驗證先行：未驗證 key 不得進任何路徑組合（存在性 oracle 防護）
            guard StoreKey.isValid(key) else {
                throw ServiceError.invalid("library key「\(key)」不符合 \(StoreKey.pattern)，拒絕寫入")
            }
            guard !FileManager.default.fileExists(atPath: store.libraryURL(key: key).path) else {
                throw ServiceError.invalid("library「\(key)」已存在")
            }
            _ = try store.writeLibrary(Library(key: key, name: name, description: description))
            return try jsonString(["created": key])
        case "add", "remove":
            guard let key, let citekey else {
                throw ServiceError.invalid("\(action) 需要 key 與 citekey")
            }
            let load = try store.load()
            // add 要求 registry 存在；remove 不要求——dangling membership（spec 允許）
            // 必須能用正式介面清理
            if action == "add", !load.libraries.contains(where: { $0.key == key }) {
                throw ServiceError.notFound("library「\(key)」")
            }
            guard var entry = load.entries.first(where: { $0.citekey == citekey }) else {
                throw ServiceError.notFound("citekey「\(citekey)」")
            }
            if action == "add" {
                if !entry.akashic.libraries.contains(key) { entry.akashic.libraries.append(key) }
            } else {
                entry.akashic.libraries.removeAll { $0 == key }
            }
            try writeAndReindex(entry)
            return try jsonString(["citekey": citekey, "libraries": entry.akashic.libraries])
        default:
            throw ServiceError.invalid("未知 action「\(action)」（list/create/add/remove）")
        }
    }

    public func setStatus(citekey: String, status: String?) throws -> String {
        var entry = try requireEntry(citekey)
        entry.akashic.status = status
        try writeAndReindex(entry)
        return try jsonString(["citekey": citekey, "status": status ?? NSNull()] as [String: Any])
    }

    public func tag(citekey: String, add: [String], remove: [String]) throws -> String {
        var entry = try requireEntry(citekey)
        for t in add where !entry.akashic.tags.contains(t) {
            entry.akashic.tags.append(t)
        }
        entry.akashic.tags.removeAll { remove.contains($0) }
        try writeAndReindex(entry)
        return try jsonString(["citekey": citekey, "tags": entry.akashic.tags])
    }

    public func link(citekey: String, kind: String, add: [String], remove: [String]) throws -> String {
        var entry = try requireEntry(citekey)
        switch kind {
        case "cites":
            for t in add where !entry.akashic.relations.cites.contains(t) {
                entry.akashic.relations.cites.append(t)
            }
            entry.akashic.relations.cites.removeAll { remove.contains($0) }
        case "related":
            for t in add where !entry.akashic.relations.related.contains(t) {
                entry.akashic.relations.related.append(t)
            }
            entry.akashic.relations.related.removeAll { remove.contains($0) }
        default:
            throw ServiceError.invalid("kind 必須是 cites / related")
        }
        try writeAndReindex(entry)
        return try jsonString([
            "citekey": citekey,
            "cites": entry.akashic.relations.cites,
            "related": entry.akashic.relations.related,
        ] as [String: Any])
    }

    /// apply=nil → 只列候選；apply=["citekey:index", …] → 逐候選套用（#5 的 MCP 面）。
    public func resolvePeople(apply: [String]?) throws -> String {
        let load = try store.load()
        let candidates = PersonResolver.candidates(entries: load.entries, people: load.people)
        let withIDs = candidates.map { c -> (id: String, candidate: ResolutionCandidate) in
            ("\(c.citekey):\(c.authorIndex)", c)
        }
        guard let selected = apply else {
            return try jsonString(withIDs.map { pair -> [String: Any] in
                [
                    "id": pair.id, "citekey": pair.candidate.citekey,
                    "authorIndex": pair.candidate.authorIndex,
                    "literal": pair.candidate.literal,
                    "personKey": pair.candidate.personKey,
                    "reason": pair.candidate.reason,
                ]
            })
        }
        let byID = Dictionary(withIDs.map { ($0.id, $0.candidate) }, uniquingKeysWith: { first, _ in first })
        let chosen = try selected.map { id -> ResolutionCandidate in
            guard let c = byID[id] else {
                throw ServiceError.notFound("候選 id「\(id)」（先不帶 apply 列出候選）")
            }
            return c
        }
        let applied = PersonResolver.apply(chosen, to: load.entries)
        var written = 0
        for (before, after) in zip(load.entries, applied) where before != after {
            try store.writeEntry(after)
            written += 1
        }
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["applied": selected, "entriesRewritten": written] as [String: Any])
    }

    public func createEntry(type: String, title: String, authors: [String],
                            date: String?, fields: [String: String]) throws -> String {
        guard !type.trimmingCharacters(in: .whitespaces).isEmpty,
              !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ServiceError.invalid("type 與 title 不可為空")
        }
        let load = try store.load()
        // quarantined 檔 basename 佔住 citekey（Phase 1 合約：quarantined 檔永不被自動覆寫）
        var existing = Set(load.entries.map(\.citekey))
        for q in load.quarantined where q.file.hasPrefix("entries/") {
            let basename = String(q.file.dropFirst("entries/".count)).lowercased()
            if basename.hasSuffix(".yaml") {
                existing.insert(String(basename.dropLast(".yaml".count)))
            }
        }
        let family = authors.first.flatMap { $0.split(separator: " ").last.map(String.init) }
        let citekey = Citekey.generate(
            familyName: family, year: date, title: title, existing: existing)
        // 最後防線：目的檔已存在（含 quarantined/大小寫別名）→ 拒寫
        guard !FileManager.default.fileExists(atPath: store.entryURL(citekey: citekey).path) else {
            throw ServiceError.invalid("目的檔已存在：entries/\(citekey).yaml（可能是 quarantined 檔）")
        }
        var entry = Entry(id: UUID(), citekey: citekey, type: type, title: title,
                          authors: authors.map { .literal($0) }, date: date)
        entry.fields = fields
        try writeAndReindex(entry)
        return try jsonString(["citekey": citekey, "id": entry.id.uuidString])
    }

    public func addPerson(key: String, names: [String], orcid: String?, openalex: String?) throws -> String {
        let load = try store.load()
        guard !load.people.contains(where: { $0.key == key }) else {
            throw ServiceError.invalid("person key「\(key)」已存在")
        }
        // quarantined people 檔同樣受保護：目的檔存在即拒寫
        guard !FileManager.default.fileExists(atPath: store.personURL(key: key).path) else {
            throw ServiceError.invalid("people/\(key).yaml 已存在（可能是 quarantined 檔），不覆寫")
        }
        let person = Person(key: key, names: names, orcid: orcid, openalex: openalex)
        try store.writePerson(person)
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["key": key, "names": names])
    }

    public func importZotero(zoteroDb: String?, libraryID: Int?) throws -> String {
        let path = ((zoteroDb ?? "~/Zotero/zotero.sqlite") as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw ServiceError.notFound("zotero.sqlite：\(path)")
        }
        try store.ensureLayout()
        let report = try ZoteroImporter(store: store)
            .run(zoteroDB: URL(fileURLWithPath: path), libraryID: libraryID)
        try LibraryIndex(store: store).rebuild()
        var d: [String: Any] = [
            "created": report.created, "updated": report.updated,
            "orphaned": report.orphaned, "orphanCleared": report.orphanCleared,
            "unchanged": report.unchanged,
            "droppedFields": report.droppedFields,
            "unnormalizedDates": report.unnormalizedDates,
            "skippedLinkedAttachments": report.skippedLinkedAttachments,
        ]
        if !report.authorsPreserved.isEmpty { d["authorsPreserved"] = report.authorsPreserved }
        if !report.quarantineConflicts.isEmpty { d["quarantineConflicts"] = report.quarantineConflicts }
        return try jsonString(d)
    }

    // MARK: - Internals

    func requireEntry(_ citekey: String) throws -> Entry {
        guard let entry = try store.load().entries.first(where: { $0.citekey == citekey }) else {
            throw ServiceError.notFound("citekey「\(citekey)」")
        }
        return entry
    }

    func writeAndReindex(_ entry: Entry) throws {
        try store.writeEntry(entry)
        try LibraryIndex(store: store).rebuild()
    }

    /// index stale（entries/people 有更新 mtime 或 index 缺）→ 重建，再開 QueryEngine。
    func ensureFreshIndex() throws {
        // schema 版本先於 mtime：舊 binary 建的 index 撞新查詢會 no such table（#13 verify）
        if try !LibraryIndex.isCurrent(indexPath: store.indexURL) {
            try LibraryIndex(store: store).rebuild()
            return
        }
        let fm = FileManager.default
        let indexPath = store.indexURL.path
        let indexMtime = (try? fm.attributesOfItem(atPath: indexPath)[.modificationDate] as? Date) ?? nil
        guard let indexMtime else {
            try LibraryIndex(store: store).rebuild()
            return
        }
        var newest = Date.distantPast
        for dir in [store.entriesDir, store.peopleDir] {
            // 目錄自身 mtime 在檔案增刪時更新——外部刪檔靠這個偵測
            if let dirM = (try? fm.attributesOfItem(atPath: dir.path)[.modificationDate]) as? Date,
               dirM > newest {
                newest = dirM
            }
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for f in files {
                if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   m > newest {
                    newest = m
                }
            }
        }
        if newest > indexMtime {
            try LibraryIndex(store: store).rebuild()
        }
    }

    func freshEngine() throws -> QueryEngine {
        try ensureFreshIndex()
        return try QueryEngine(indexPath: store.indexURL)
    }

    func summaryDict(_ s: EntrySummary) -> [String: Any] {
        var d: [String: Any] = [
            "citekey": s.citekey, "type": s.type, "title": s.title, "authors": s.authors,
        ]
        if let year = s.year { d["year"] = year }
        if let journal = s.journal { d["journal"] = journal }
        return d
    }

    func entryDict(_ entry: Entry) -> [String: Any] {
        var d: [String: Any] = [
            "id": entry.id.uuidString,
            "citekey": entry.citekey,
            "type": entry.type,
            "title": entry.title,
            "authors": entry.authors.map { author -> [String: String] in
                switch author {
                case .key(let k): return ["key": k]
                case .literal(let s): return ["literal": s]
                }
            },
            "fields": entry.fields,
        ]
        if let date = entry.date { d["date"] = date }
        if !entry.attachments.isEmpty {
            d["attachments"] = entry.attachments.map { [$0.kind.rawValue: $0.path] }
        }
        if let prov = entry.provenance {
            var p: [String: Any] = ["zotero_key": prov.zoteroKey, "zotero_version": prov.zoteroVersion]
            if let lid = prov.libraryID { p["library_id"] = lid }
            if let hash = prov.zoteroHash { p["zotero_hash"] = hash }
            let iso = ISO8601DateFormatter()
            if let at = prov.importedAt { p["imported_at"] = iso.string(from: at) }
            if let at = prov.orphanedAt {
                p["orphaned"] = true
                p["orphaned_at"] = iso.string(from: at)
            }
            d["provenance"] = p
        }
        var akashic: [String: Any] = [:]
        if !entry.akashic.tags.isEmpty { akashic["tags"] = entry.akashic.tags }
        if !entry.akashic.libraries.isEmpty { akashic["libraries"] = entry.akashic.libraries }
        if let status = entry.akashic.status { akashic["status"] = status }
        if !entry.akashic.relations.cites.isEmpty { akashic["cites"] = entry.akashic.relations.cites }
        if !entry.akashic.relations.related.isEmpty { akashic["related"] = entry.akashic.relations.related }
        d["akashic"] = akashic
        return d
    }

    func jsonString(_ obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
