import Foundation
import AkashicCore
import AkashicEntity
import AkashicStoreIO
import AkashicIndex

/// resolve-organizations 的逐篇判定（#647）：`<列表的 id>@<orgKey>=理由`，把列表上的一列歸戶到指定的 organization，
/// 並寫一筆 `org-judged` 層級的 confirmed verdict（理由進 statement）。
///
/// 為什麼需要它：#643 讓 CLI 的篩選式 `--apply` 排除查過未決的候選——那是對的——但 CLI 沒有逐 id 的 apply，
/// 查過未決的候選因此在 CLI 上歸戶不了。使用者 2026-09-27 裁決：比照 resolve-people 的 `--judge`，理由必填、寫成逐篇判定。
///
/// 契約與 resolve-people 的 judge 同形（兩類失敗分開）：
/// - **輸入錯整批拒絕、零寫入**：格式、id 不在這次列表上、orgKey 不是那一列提名的、理由空白或過長、同一列判給兩個 org、
///   person 與 organization 同 key 而兩列都在列表上。
/// - **store 狀態不符該筆略過並具名**：work 的 citekey 重複或共用 id、上級機構判給自己或會成環、套用時那個位置已不是那個 literal。
///
/// id 的解析與 #643 的未決腿共用（`parseOrgIDSpecs`）；歧義條目也收——歧義的意思是提名器分不出來，不是人分不出來。
extension AkashicService {

    func judgeOrganizations(_ specs: [String]) throws -> String {
        guard specs.count <= Self.maxSpecsPerCall else {
            throw ServiceError.invalid("一次最多判定 \(Self.maxSpecsPerCall) 筆（這次 \(specs.count) 筆）——分次送")   // display-safe-exempt: Self.maxSpecsPerCall 與 specs.count 都是 Int
        }
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        guard storeFormat >= 8 else {
            throw ServiceError.invalid(
                "逐篇判定要寫 resolution-confirmed verdict，需要 store format ≥ 8（本 store 是 \(storeFormat)）")   // display-safe-exempt: Int
        }
        let load = try store.load()
        // 只認這次**列表**上的列（帶否決過濾）：已否決或已歸戶的配對不在列表上，判它是輸入錯——id 不是這次列表的 id
        let rejectedPairings = ResolutionLedger.rejectedPairings(organizations: load.organizations)
        let rejectedNorm = Set(rejectedPairings.map(OrgResolver.normalizedRejection))
        let listed = OrgResolver.resolve(people: load.people, organizations: load.organizations,
                                         rejected: rejectedPairings, entries: load.entries)
        typealias Row = (holder: OrgResolutionCandidate.Holder, literal: String, orgKeys: Set<String>)
        var rows: [[UInt8]: [ProvenanceReference.VerdictHolderKind: Row]] = [:]
        func add(_ holder: OrgResolutionCandidate.Holder, _ literal: String, _ orgKeys: [String]) {
            let id = Array(Self.orgRowID(holder, literal: literal).utf8)
            var row = rows[id]?[holder.verdictHolderKind] ?? (holder, literal, [])
            row.orgKeys.formUnion(orgKeys)
            rows[id, default: [:]][holder.verdictHolderKind] = row
        }
        for c in listed.candidates { add(c.holder, c.literal, [c.orgKey]) }
        for a in listed.ambiguities { add(a.holder, a.literal, a.orgKeys) }
        let parsed = try parseOrgIDSpecs(specs, rows: rows.mapValues {
            $0.values.reduce(into: Set<String>()) { $0.formUnion($1.orgKeys) }
        }, noun: "判定", tail: "理由")

        // 理由與「同一列判給兩個 org」都是輸入錯——在任何 store 狀態分支之前擋（people 的 #627 R5 同一個順序）
        var chosen: [Row] = []
        var slots = Set<[UInt8]>()
        for s in parsed {
            if s.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ServiceError.invalid(
                    "判定「\(displaySafeInvisible(s.id, max: 200))」的理由是空白——理由是「憑什麼這樣判」的紀錄，沒有它的歸戶與猜測無法區分")
            }
            guard s.statement.utf8.count <= Self.maxStatementBytes else {
                throw ServiceError.invalid(
                    "判定「\(displaySafeInvisible(s.id, max: 200))」的理由超過 \(Self.maxStatementBytes) 位元組——精簡它")   // display-safe-exempt: Self.maxStatementBytes 是 Int 常數
            }
            let kinds = rows[Array(s.rowID.utf8)] ?? [:]
            let matching = kinds.filter { $0.value.orgKeys.contains(s.orgKey) }
            if matching.count > 1 {
                throw ServiceError.invalid(
                    "判定「\(displaySafeInvisible(s.id, max: 200))」的 id 在列表上同時是 person 與 organization 兩列（兩者的 key 同名）"
                    + "——無法確定是哪一列，整批拒絕、零寫入；改名那個 person 的 key（rename-person）後再列一次")
            }
            guard let pick = matching.first else { continue }   // parse 已驗 orgKey 屬於這個 rowID——不可達
            guard slots.insert(Array(s.rowID.utf8) + [0] + Array(pick.key.rawValue.utf8)).inserted else {
                throw ServiceError.invalid(
                    "判定「\(displaySafeInvisible(s.id, max: 200))」：同一列在一次呼叫裡判了兩次——一列只能歸給一個 organization")
            }
            chosen.append(pick.value)
        }
        let orgKeysLoaded = Set(load.organizations.map(\.key))
        for s in parsed where !orgKeysLoaded.contains(s.orgKey) {
            throw ServiceError.notFound("organization「\(displaySafeInvisible(s.orgKey, max: 200))」")
        }

        // ── store 狀態：逐筆決定套用或略過（此段不寫任何東西）──
        let unlocatable = load.entries.unlocatableCitekeys
        // 上級機構的環：既有的 `.key` parents ＋ 本次已接受的判定（同 `OrgResolver.resolve` 的 #166 守衛——
        // 歧義報告刻意不過濾會成環的候選，那一道要在寫入端做）
        var edges: [String: Set<String>] = [:]
        for o in load.organizations {
            for seg in o.parents.entries { if case let .key(p) = seg.value { edges[o.key, default: []].insert(p) } }
        }
        func reaches(_ from: String, _ to: String) -> Bool {
            var stack = [from], seen = Set<String>()
            while let n = stack.popLast() {
                if n == to { return true }
                guard seen.insert(n).inserted else { continue }
                stack.append(contentsOf: edges[n] ?? [])
            }
            return false
        }
        var accepted: [(spec: OrgUndecidedSpec, row: Row)] = []
        var skipped: [(id: String, why: String)] = []
        for (s, row) in zip(parsed, chosen) {
            // 歧義條目的 orgKeys 取自原始命中集、不過濾否決（`OrgResolver` 刻意如此：唯一性由原始命中集決定），所以 id 驗得過
            // 而那個 org 已經否決過這個配對（候選列自 R3 起以正規化鍵過濾，走不到這裡）。照寫會留下 confirmed＋rejected 的矛盾對（#486，處置沒有工具面）——store 狀態不符，
            // 該筆略過並具名（#647 R2 verify DA）。翻轉判定不是這條腿的事。
            // 比對用正規化鍵（`OrgResolver.normalizedRejection`，與矛盾掃描同一套）——R3 verify：比原始 literal 時，大小寫變體繞得過
            if rejectedNorm.contains(OrgResolver.normalizedRejection(ResolutionPairing(
                holderKind: row.holder.verdictHolderKind, holder: row.holder.key,
                literal: row.literal, judgedKey: s.orgKey))) {
                skipped.append((s.id, "organization「\(displaySafe(s.orgKey, max: 200))」已否決過這個配對——逐篇判定不翻轉既有的否決，略過"))
                continue
            }
            switch row.holder {
            case let .work(citekey, _) where unlocatable.contains(citekey):
                skipped.append((s.id, "work「\(displaySafe(citekey, max: 200))」的 citekey 重複或與另一筆 work 共用 id——無法確定是哪一筆，略過（#628）"))
                continue
            case let .organization(k) where s.orgKey == k || reaches(s.orgKey, k):
                skipped.append((s.id, s.orgKey == k ? "上級機構不能是自己" : "判給這個上級機構會讓 organization 階層成環"))
                continue
            case let .organization(k):
                edges[k, default: []].insert(s.orgKey)   // 本次已接受的也算數
            default:
                break
            }
            accepted.append((s, row))
        }

        // ── 落地：套用、驗證是否真的改到、寫 verdict ──
        let applied = OrgResolver.apply(
            accepted.map { OrgResolutionCandidate(holder: $0.row.holder, literal: $0.row.literal,
                                                  orgKey: $0.spec.orgKey, reason: "逐篇判定") },
            to: load.people, organizations: load.organizations, entries: load.entries)
        let peopleBefore = Dictionary(load.people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let peopleAfter = Dictionary(applied.people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var orgs = Dictionary(applied.organizations.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let orgsBefore = Dictionary(load.organizations.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        // 針對**這一個 literal** 判斷：同一個 holder 在同一次呼叫裡可以有好幾列，整個 holder 有沒有變說不出是哪一列改到
        func migrated(_ before: TimelineOf<OrgRef>?, _ after: TimelineOf<OrgRef>?, _ literal: String, _ orgKey: String) -> Bool {
            guard let before, let after else { return false }
            return before.entries.contains { $0.value == .literal(literal) }
                && !after.entries.contains { $0.value == .literal(literal) }
                && after.entries.contains { $0.value == .key(orgKey) }
        }
        func landed(_ row: Row, _ orgKey: String) -> Bool {
            switch row.holder {
            case let .person(k):
                return migrated(peopleBefore[k]?.profile.affiliations, peopleAfter[k]?.profile.affiliations, row.literal, orgKey)
            case let .organization(k):
                return migrated(orgsBefore[k]?.parents, orgs[k]?.parents, row.literal, orgKey)
            case let .work(citekey, i):
                guard let e = applied.entries.first(where: { $0.citekey == citekey }), i < e.authors.count else { return false }
                return e.authors[i] == .organization(orgKey)
            }
        }
        // 歸戶落地了而理由沒寫進去時要說出來（#647 R1 verify logic 第 8 列；resolve-people 的 `verdictNotRecorded` 同一個形）：
        // verdict 以 (holder, literal) 配對、不帶作者位索引，同一筆 work 兩個作者位是同一個 literal 時，第二句理由會被去重吃掉；
        // format < 19 時提名層的 confirmed 也會擋下逐篇判定。同一句理由不算沒寫——它已經在。
        var judged: [(id: String, literal: String, orgKey: String, statement: String, notRecorded: String?)] = []
        var touchedOrgs = Set<String>()
        for (s, row) in accepted {
            guard landed(row, s.orgKey) else {
                skipped.append((s.id, "套用時那個位置已不是「\(displaySafe(row.literal, max: 200))」——列表過期，重新列出再判"))
                continue
            }
            var org = orgs[s.orgKey]!
            let ref = ResolutionLedger.record(
                .confirmed, holderKind: row.holder.verdictHolderKind,
                holder: row.holder.key, literal: row.literal,
                rule: ProvenanceReference.RuleName.orgResolveJudged,
                statement: s.statement)
            var notRecorded: String?
            if !ResolutionLedger.appendIfAbsent(ref, to: &org.references, allowCoexistence: storeFormat >= 19),
               !org.references.contains(where: { $0.verdictRecordKey == ref.verdictRecordKey && $0.kindByteKey == ref.kindByteKey }) {
                // 依**實際原因**選訊息，不依 format（R2 verify 三席）：同層級已有一筆 → 理由不同；否則是 format < 19 不讓提名層與逐篇並存
                notRecorded = org.references.contains(where: { $0.verdictRecordKey == ref.verdictRecordKey })
                    ? "已歸戶；這個配對已有一筆理由不同的逐篇判定——判定以 (holder, literal) 配對去重，這次的理由沒有寫入"
                    : "已歸戶；這個配對已有提名層的判定，逐篇判定與它並存需要 store format ≥ 19"
                        + "（本 store 是 \(storeFormat)），這次的理由沒有寫入"   // display-safe-exempt: Int
            }
            orgs[s.orgKey] = org
            touchedOrgs.insert(s.orgKey)
            judged.append((s.id, row.literal, s.orgKey, s.statement, notRecorded))
        }
        let changedPeople = applied.people.filter { after in peopleBefore[after.key].map { $0 != after } ?? false }
        let changedEntries = applied.entries.filter { e in !load.entries.contains(where: { $0 == e }) }
        let changedOrgKeys = Set(applied.organizations.filter { orgsBefore[$0.key] != $0 }.map(\.key)).union(touchedOrgs)
        // 寫入前先驗**整個寫入集合**，全部通過才寫（#647 R1 verify Codex HIGH：先前只驗收到 verdict 的目標 org，
        // person／entry／上級機構被改寫的 holder org 在寫入當下才被拒——前面的檔已經落盤）
        // 內容閘之外還有 #631 的目的檔檢查（`personWritePlan`／`entryWritePlan`／`assertEntitiesDestination`）——write* 在寫入當下
        // 才跑它，漏掉它就是同一種撕裂換一類拒絕（R2 verify DA 真 binary：legacy 未 commit 的 entry 讓 person 先落盤）。venue 路徑的先例同形。
        if !judged.isEmpty {
            for p in changedPeople {
                try LibraryStore.assertPersonWritable(p, format: { storeFormat })
                _ = try store.personWritePlan(p)
            }
            for e in changedEntries {
                try LibraryStore.assertEntryWritable(e, format: { storeFormat })
                _ = try store.entryWritePlan(e)
            }
            for key in changedOrgKeys.sorted() {
                try LibraryStore.assertOrganizationWritable(orgs[key]!, format: { storeFormat })
                try store.assertEntitiesDestination(id: orgs[key]!.id, kind: .organization)
            }
        }
        if !judged.isEmpty {
            for p in changedPeople { try store.writePerson(p) }
            for e in changedEntries { try store.writeEntry(e) }
            for key in changedOrgKeys.sorted() { try store.writeOrganization(orgs[key]!) }
            try LibraryIndex(store: store).rebuild()
        }
        let idMax = max(200, parsed.map { $0.id.unicodeScalars.count }.max() ?? 0)
        return try jsonString([
            "judged": judged.map { j -> [String: String] in
                var row = ["id": displaySafe(j.id, max: idMax),
                           "literal": displaySafe(j.literal, max: 200),
                           "orgKey": displaySafe(j.orgKey, max: 200),
                           "judgement": displaySafe(j.statement, max: Self.maxStatementBytes)]
                if let why = j.notRecorded { row["verdictNotRecorded"] = why }   // display-safe-exempt: why 是本函式的固定訊息，只插 Int
                return row
            },
            "skipped": skipped.map { ["id": displaySafe($0.id, max: idMax), "why": $0.why] },   // display-safe-exempt: why 是本函式的訊息，其中的 store 字串已消毒
            "peopleRewritten": judged.isEmpty ? 0 : changedPeople.count,   // display-safe-exempt: Int
            "entriesRewritten": judged.isEmpty ? 0 : changedEntries.count,   // display-safe-exempt: Int
            "organizationsRewritten": judged.isEmpty ? 0 : changedOrgKeys.count,   // display-safe-exempt: Int
        ] as [String: Any])
    }
}
