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
    /// #18 多檔案：use 切換時重指（session-scoped）；store/index 為 computed，全部跟隨。
    private(set) var root: URL
    /// #37：index 位置取決於 registry key。與 root 同生命週期——`use` 切換時
    /// 兩者必須一起換，否則會用 A 的 index 查 B 的 store。nil＝未註冊（in-store 回落）。
    private(set) var storeKey: String?
    let configURL: URL
    /// #37：注入用——測試必須能把 index 導向假 home，否則會寫進使用者真實的
    /// `~/.akashic/index/`（`testFilesUseSwitchesUniverseCompletely` 實際踩到）。
    let environment: [String: String]

    public init(root: URL, key: String? = nil, configURL: URL? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.root = root
        self.storeKey = key
        // configURL 與 environment 必須同源（#110，AppState 同款）——預設由
        // env-aware 的 AkashicHome 解析，而非寫死真實家目錄。
        self.configURL = configURL ?? AkashicHome.configURL(environment: environment)
        self.environment = environment
    }

    /// #37：index 位置取決於 registry key（`storeKey`；nil＝未註冊 → in-store 回落）。
    var store: LibraryStore { LibraryStore(root: root, key: storeKey, environment: environment) }

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
            var d: [String: Any] = ["key": displaySafe(person.key, max: 200),
                                    "names": person.names.map { displaySafe($0, max: 200) }]
            if let orcid = person.orcid { d["orcid"] = orcid }
            if let openalex = person.openalex { d["openalex"] = openalex }
            if !person.unknownFields.isEmpty {   // #31：同 entryDict，只給 key
                d["unknownFields"] = person.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
            }
            return d
        }
        return try jsonString(dicts)
    }

    public func doctor() throws -> String {
        let load = try store.load()
        var d: [String: Any] = ["library": root.path]

        // #35（鏡射 CLI doctor 的順序；#138 verify F1）：跨記錄檢查必須在 rebuild
        // **之前**。重複 citekey / person key 時 rebuild 會撞 UNIQUE constraint——
        // consumer 拿到的是 SQLite 內部錯誤，而不是「你有兩筆同 citekey 的記錄」。
        // 診斷工具在這種狀態下正是最該說話的時候，不是最該掛掉的時候。
        // severity 逐條攜帶（#138 verify F3）：✗/⚠ 之別在 CLI 面有、MCP 面就不能丟。
        let cross = load.crossRecordIssues()
        let fatalCross = cross.filter { $0.severity == .error }
        if !cross.isEmpty {
            d["crossRecordIssues"] = [
                "count": cross.count,
                "first": cross.prefix(20).map {
                    ["severity": $0.severity == .error ? "error" : "warning",
                     "message": displaySafe($0.message, max: 300)]
                },
            ] as [String: Any]
        }
        // #107：佈局殘留（報告不動手刪）。與 CLI 同：排在 fatal 早退之前——
        // 重複 citekey 的 store 正是最需要看清全貌的時候。
        let residue = try store.layoutResidue()
        if !residue.isEmpty {
            d["layoutResidue"] = residue.map { displaySafe($0, max: 300) }
        }
        // #76：divergence 計數無條件給（0 也是資訊）；同樣在 fatal 早退之前。
        d["divergences"] = load.divergences.count
        if !load.quarantined.isEmpty {
            // R11（R10-verify M19）：reason 含 Yams 展開的逐字檔案內容且不截斷——
            // MCP 情境下是直接灌進 LLM context 的無上限未信任字串。
            d["quarantined"] = load.quarantined.map {
                ["file": displaySafe($0.file, max: 300), "reason": displaySafe($0.reason, max: 512)]
            }
        }
        // #23 tolerant-preserve：較新 schema 的檔案可用但應提示升級
        if !load.unknownFieldFiles.isEmpty {
            d["unknownFieldFiles"] = load.unknownFieldFiles.map { displaySafe($0, max: 200) }
        }
        guard fatalCross.isEmpty else {
            d["entries"] = load.entries.count
            d["indexRebuilt"] = false
            d["note"] = "index 未重建——先修好 crossRecordIssues 內 severity=error 的重複"
            return try jsonString(d)
        }

        let stats = try LibraryIndex(store: store).rebuild()
        d["indexRebuilt"] = true
        d["entries"] = stats.entries
        d["people"] = stats.people
        d["relations"] = stats.relations
        d["unresolvedAuthorLiterals"] = load.entries.flatMap { entry in
            entry.authors.compactMap { if case .literal = $0 { return 1 } else { return nil } }
        }.count
        d["orphaned"] = load.entries.filter { $0.provenance?.orphanedAt != nil }
            .map { displaySafe($0.citekey, max: 200) }
        // #81 / #82 / #67（#138 verify F3）：CLI doctor 的普查面 MCP 也要有——
        // 「同一個 store 不得從兩個 consumer 看到不同的事實」是本 change 的主旨。
        let nameGaps = load.recordsWithoutAuthorizedName()
        d["noAuthorizedName"] = [
            "people": nameGaps.people.count,
            "organizations": nameGaps.organizations.count,
            "firstPeople": nameGaps.people.prefix(10).map { displaySafe($0, max: 120) },
        ] as [String: Any]
        d["authorizedOnlyByCitationForm"] = load.recordsAuthorizedOnlyByCitationForm().count
        let deceasedOpen = load.recordsDeceasedWithOpenAffiliation()
        if !deceasedOpen.isEmpty {
            // 與 CLI 同：待人處理的工作清單，列全部不截斷
            d["deceasedWithOpenAffiliation"] = deceasedOpen.map { displaySafe($0, max: 120) }
        }
        return try jsonString(d)
    }

    /// #76：divergence 的 list-only 投影——「載入了幾筆、各是什麼」是可觀察性
    /// （#71 第 7 條自身的要求），與 doctor 計數同層。**不做**過濾與圖形化
    /// （那才是 #71 的「範圍外：歧異查詢或圖形化」）。
    public func listDivergences() throws -> String {
        let load = try store.load()
        return try jsonString([
            "count": load.divergences.count,
            "divergences": load.divergences
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { d in
                    [
                        "id": d.id.uuidString,
                        "question": displaySafe(d.question, max: 400),
                        "candidates": d.candidates.map {
                            ["key": displaySafe($0.key, max: 200), "shape": $0.shape.rawValue]
                        },
                        "hasJudgement": d.judgement != nil,
                    ] as [String: Any]
                },
        ])
    }

    // MARK: - 寫（衍生層 only）

    /// #18 多檔案：registry 檢視與 session 內切換（互不相通——切換即整個 universe 換掉）。
    /// use 不寫 config（server 是讀者；持久預設由 CLI file use 管）。
    public func files(action: String, key: String?) throws -> String {
        switch action {
        case "list":
            let config = try AkashicConfig.read(from: configURL)
            let list = config.files.keys.sorted().map { k -> [String: Any] in
                ["key": k, "path": displaySafe(config.files[k]!, max: 800),
                 "current": k == config.current]
            }
            var out: [String: Any] = ["files": list, "active_root": root.path]
            if let legacy = config.library { out["legacy_library"] = legacy }
            return try jsonString(out)
        case "use":
            guard let key, !key.isEmpty else {
                throw ServiceError.invalid("use 需要 key")
            }
            let config = try AkashicConfig.read(from: configURL)
            guard let path = config.files[key] else {
                let known = config.files.keys.sorted().joined(separator: ", ")
                throw ServiceError.notFound("檔案 key「\(key)」（已註冊：\(known.isEmpty ? "無" : known)）")
            }
            let newRoot = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard LibraryStore.isLibraryRoot(newRoot) else {
                throw ServiceError.invalid("「\(path)」不是 Akashic library（缺 entries/ 目錄）")
            }
            root = newRoot
            storeKey = key          // #37：index 必須跟著切，否則用舊 store 的 index 查新 store
            return try jsonString(["active_root": root.path, "key": key] as [String: Any])
        default:
            throw ServiceError.invalid("未知 action「\(action)」（list / use）")
        }
    }

    /// #14 人物檢索：person 聚合視圖。key 直查；模糊名回候選（絕不自動選）。
    /// key 與 name 互斥（同給擲錯）；空白輸入拒絕；候選上限 50。
    public func person(key rawKey: String?, name rawName: String?, library: String?) throws -> String {
        let key = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key, key.isEmpty { throw ServiceError.invalid("key 不可為空白") }
        if let name, name.isEmpty { throw ServiceError.invalid("name 不可為空白") }
        if key != nil && name != nil {
            throw ServiceError.invalid("key 與 name 互斥——擇一使用")
        }
        if let key {
            let load = try store.load()
            let record = load.people.first { $0.key == key }
            let engine = try freshEngine()
            // 存在性判準用全集（scoped 過濾不可誤報 notFound——person 可能只是不在該 library）
            let allPubs = try engine.personPublications(key: key, library: nil)
            guard record != nil || !allPubs.isEmpty else {
                throw ServiceError.notFound("person「\(key)」")
            }
            let pubs = library == nil ? allPubs
                : try engine.personPublications(key: key, library: library)
            let co = try engine.coAuthors(of: key, library: library)
            // resolved 合著者的 name 給人讀的名字（people.names 首項），key 另放 person_key
            let nameByKey = Dictionary(uniqueKeysWithValues: load.people.map { ($0.key, $0.displayName(in: .latn)) })
            var personDict: [String: Any] = ["key": key]
            if let record {
                personDict["names"] = record.names
                if !record.unknownFields.isEmpty {   // #31
                    personDict["unknownFields"] =
                        record.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
                }
                if let orcid = record.orcid { personDict["orcid"] = orcid }
            }
            return try jsonString([
                "person": personDict,
                "publications": pubs.map(summaryDict),
                "co_authors": co.map { c -> [String: Any] in
                    var d: [String: Any] = ["count": c.count]
                    if let pk = c.personKey {
                        d["person_key"] = pk
                        d["name"] = nameByKey[pk] ?? pk
                    } else {
                        d["name"] = c.name
                    }
                    return d
                },
            ] as [String: Any])
        }
        if let name {
            // 模糊名 → 候選清單（case-insensitive 子字串；單趟預算 pub counts；上限 50）
            let load = try store.load()
            let needle = name.lowercased()
            var keyPubCount: [String: Int] = [:]
            var literalCounts: [String: Int] = [:]
            for entry in load.entries {
                // per-entry 去重：publications 是「篇數」不是「掛名次數」
                //（同篇重複 author identity 只計一次，與 DISTINCT 語意對齊）
                var seenKeys = Set<String>()
                var seenLiterals = Set<String>()
                for author in entry.authors {
                    switch author {
                    case .key(let k): seenKeys.insert(k)
                    case .literal(let s):
                        if s.lowercased().contains(needle) { seenLiterals.insert(s) }
                    }
                }
                for k in seenKeys { keyPubCount[k, default: 0] += 1 }
                for s in seenLiterals { literalCounts[s, default: 0] += 1 }
            }
            var candidates: [[String: Any]] = []
            for p in load.people where p.names.contains(where: { $0.lowercased().contains(needle) })
                || p.key.lowercased().contains(needle) {
                candidates.append(["person_key": displaySafe(p.key, max: 200),
                                   "names": p.names.map { displaySafe($0, max: 200) },
                                   "publications": keyPubCount[p.key] ?? 0])
            }
            for (literal, count) in literalCounts.sorted(by: { $0.key < $1.key }) {
                candidates.append(["literal": literal, "publications": count])
            }
            let capped = Array(candidates.prefix(50))
            var out: [String: Any] = ["candidates": capped]
            if candidates.count > 50 { out["truncated"] = true }
            return try jsonString(out)
        }
        throw ServiceError.invalid("person 需要 key 或 name 至少其一")
    }

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
                var d: [String: Any] = ["key": displaySafe(lib.key, max: 200),
                                        "name": displaySafe(lib.name, max: 200),
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
            guard StoreKey.isValid(key) else {
                throw ServiceError.invalid("library key「\(key)」不符合 \(StoreKey.pattern)")
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
            return try jsonString(["citekey": displaySafe(citekey, max: 200),
                                   "libraries": entry.akashic.libraries])
        default:
            throw ServiceError.invalid("未知 action「\(action)」（list/create/add/remove）")
        }
    }

    public func setStatus(citekey: String, status: String?) throws -> String {
        var entry = try requireEntry(citekey)
        entry.akashic.status = status
        try writeAndReindex(entry)
        return try jsonString(["citekey": displaySafe(citekey, max: 200),
                               "status": status ?? NSNull()] as [String: Any])
    }

    public func tag(citekey: String, add: [String], remove: [String]) throws -> String {
        var entry = try requireEntry(citekey)
        for t in add where !entry.akashic.tags.contains(t) {
            entry.akashic.tags.append(t)
        }
        entry.akashic.tags.removeAll { remove.contains($0) }
        try writeAndReindex(entry)
        return try jsonString(["citekey": displaySafe(citekey, max: 200),
                               "tags": entry.akashic.tags])
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
            "citekey": displaySafe(citekey, max: 200),
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
                    "id": pair.id, "citekey": displaySafe(pair.candidate.citekey, max: 200),
                    "authorIndex": pair.candidate.authorIndex,
                    "literal": displaySafe(pair.candidate.literal, max: 400),
                    "personKey": displaySafe(pair.candidate.personKey, max: 200),
                    "reason": displaySafe(pair.candidate.reason, max: 400),
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
        var writeFailed: [String: String] = [:]
        // R7（R6-verify M21）：per-item 收容——單筆 encode 拒寫不中斷批次、
        // index 照 rebuild、失敗照實回報
        for (before, after) in zip(load.entries, applied) where before != after {
            do {
                try store.writeEntry(after)
                written += 1
            } catch {
                writeFailed[after.citekey] = displaySafe(String(describing: error), max: 512)
            }
        }
        // R9（R8-verify M8）：rebuild 擲錯不得吞掉 writeFailed 報告
        do {
            try LibraryIndex(store: store).rebuild()
        } catch {
            // R10（R9-verify L17）：附已改寫數——operator 才能對帳磁碟狀態
            throw ServiceError.invalid(
                "index rebuild 失敗：\(error)（本批已改寫 \(written) 檔；writeFailed \(writeFailed.count) 筆：\(writeFailed.map { "\(displaySafe($0.key, max: 200))（\(displaySafe($0.value, max: 512))）" }.sorted().joined(separator: "; "))）")
        }
        // R8（R7-verify L15）：applied 不誇報——排除寫入失敗的候選
        let appliedActual = chosen.filter { writeFailed[$0.citekey] == nil }
            .map { "\(displaySafe($0.citekey, max: 200)):\($0.authorIndex)" }
        var result: [String: Any] = ["applied": appliedActual, "entriesRewritten": written]
        if !writeFailed.isEmpty { result["writeFailed"] = Dictionary(uniqueKeysWithValues: writeFailed.map { (displaySafe($0.key, max: 200), displaySafe($0.value, max: 512)) }) }
        return try jsonString(result)
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
        return try jsonString(["citekey": displaySafe(citekey, max: 200),
                               "id": entry.id.uuidString])
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

    /// #77 層次 2：MCP 面的歧異記錄入口。LLM 驅動的補完流程遇到同一性疑問時
    /// **當場記錄而非當場判斷**（#71 的診斷點）。candidates 格式與 CLI 一致
    /// （`key:shape`）。刻意**無** MCP 版 resolve——消歧含合併＋全庫改寫＋刪檔，
    /// tracked+clean 前提與人工確認屬 CLI／App 的互動面。
    public func recordDivergence(question: String, candidates: [String],
                                 judgement: String?, restsOn: [String]) throws -> String {
        let parsed: [(key: String, shape: EntityKind)] = try candidates.map { spec in
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let shape = EntityKind(rawValue: parts[1]) else {
                throw ServiceError.invalid(
                    "候選格式為 `key:shape`（shape ∈ \(EntityKind.allCases.filter { $0 != .divergence }.map(\.rawValue).joined(separator: " / "))），得到「\(displaySafe(spec, max: 120))」")
            }
            return (key: parts[0], shape: shape)
        }
        let d = try store.recordDivergence(question: question, candidates: parsed,
                                           judgement: judgement, restsOn: restsOn)
        return try jsonString([
            "id": d.id.uuidString,
            "candidates": d.candidates.map(\.key),
            "hasJudgement": d.judgement != nil,
            "note": "記下判斷不等於消歧——合併請由人工跑 akashic resolve-divergence",
        ])
    }

    public func importZotero(zoteroDb: String?, libraryID: Int?) throws -> String {
        let path = ((zoteroDb ?? "~/Zotero/zotero.sqlite") as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw ServiceError.notFound("zotero.sqlite：\(path)")
        }
        try store.ensureLayout()
        let report = try ZoteroImporter(store: store)
            .run(zoteroDB: URL(fileURLWithPath: path), libraryID: libraryID)
        // R10（R9-verify M3/M5）：rebuild 擲錯不得吞掉整份 import report——
        // 磁碟滿等原因與 writeFailed 正相關，最需要報告的場景恰好最易被吞
        do {
            try LibraryIndex(store: store).rebuild()
        } catch {
            throw ServiceError.invalid(
                "index rebuild 失敗：\(error)（本趟 import 已落地：created \(report.created.count)、updated \(report.updated.count)、orphaned \(report.orphaned.count)；writeFailed \(report.writeFailed.count) 筆：\(report.writeFailed.keys.sorted().map { displaySafe($0, max: 200) }.joined(separator: ", "))）")
        }
        var d: [String: Any] = [
            "created": report.created.map { displaySafe($0, max: 200) },
            "updated": report.updated.map { displaySafe($0, max: 200) },
            "orphaned": report.orphaned.map { displaySafe($0, max: 200) },
            "orphanCleared": report.orphanCleared.map { displaySafe($0, max: 200) },
            "unchanged": report.unchanged,
            "droppedFields": report.droppedFields,
            "unnormalizedDates": report.unnormalizedDates.map { displaySafe($0, max: 200) },
            "skippedLinkedAttachments": report.skippedLinkedAttachments,
        ]
        if !report.authorsPreserved.isEmpty { d["authorsPreserved"] = report.authorsPreserved.map { displaySafe($0, max: 200) } }
        if !report.quarantineConflicts.isEmpty { d["quarantineConflicts"] = report.quarantineConflicts.map { displaySafe($0, max: 200) } }
        if !report.writeFailed.isEmpty { d["writeFailed"] = Dictionary(uniqueKeysWithValues: report.writeFailed.map { (displaySafe($0.key, max: 200), displaySafe($0.value, max: 512)) }) }
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
        // schema 版本 + store 身分先於 mtime（#13 verify、#122）：舊 binary 建的 index
        // 撞新查詢會 no such table；別的 store 建的 index（registry 路徑重新利用）
        // 內容整份是別人的
        if !LibraryIndex.isCurrent(indexPath: store.indexURL, expectedRoot: store.root) {
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
        // #35：**entities/ 必須在掃描範圍內**——format 2 的 store 所有 canonical 都在
        // 那裡，漏掉它會讓 index 永遠被判為 current 而回答過期的查詢（verify CRITICAL）。
        for dir in [store.entitiesDir, store.entriesDir, store.peopleDir] {
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
            "citekey": displaySafe(s.citekey, max: 200), "type": s.type,
            "title": displaySafe(s.title, max: 800),
            "authors": s.authors.map { displaySafe($0, max: 200) },
        ]
        if let year = s.year { d["year"] = year }
        if let journal = s.journal { d["journal"] = journal }
        return d
    }

    func entryDict(_ entry: Entry) -> [String: Any] {
        var d: [String: Any] = [
            "id": entry.id.uuidString,
            "citekey": displaySafe(entry.citekey, max: 200),
            "type": entry.type,
            "title": displaySafe(entry.title, max: 800),
            "authors": entry.authors.map { author -> [String: String] in
                switch author {
                case .key(let k): return ["key": displaySafe(k, max: 200)]
                // literal 是 Zotero 匯入的第三方原文——掃描器對 case 行的短變數
                // 值是盲點（見 DisplaySinkCoverageTests doc），此站點靠人工 + 測試釘
                case .literal(let s): return ["literal": displaySafe(s, max: 400)]
                }
            },
            // fields 值是 biblatex 第三方內容（journal、booktitle…）——與 title 同源
            "fields": entry.fields.mapValues { displaySafe($0, max: 800) },
        ]
        if let date = entry.date { d["date"] = date }
        if !entry.attachments.isEmpty {
            d["attachments"] = entry.attachments.map {
                [$0.kind.rawValue: displaySafe($0.path, max: 800)]
            }
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
        // #31：讀取面必須露出「這筆記錄有本 binary 不認得的欄位」。只給 key 不給值——
        // 值是未信任的逐字原文，灌進 LLM context 沒有意義且是注入面；key 足以讓使用者
        // 知道「這裡有東西、你的 binary 看不懂」並去升級。
        if !entry.unknownFields.isEmpty {
            d["unknownFields"] = entry.unknownFields.map { displaySafe($0.key, max: 200) }.sorted()
        }
        return d
    }

    func jsonString(_ obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
