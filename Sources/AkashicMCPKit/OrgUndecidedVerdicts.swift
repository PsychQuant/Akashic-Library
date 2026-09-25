import Foundation
import AkashicCore
import AkashicEntity
import AkashicStoreIO
import AkashicIndex

/// resolve-organizations 的未決腿（change `org-undecided-leg`，#643）。
///
/// 與 people／venues 的未決腿同契約（`UndecidedVerdicts.swift`）：輸入錯整批拒絕、零寫入；store 狀態不符該筆略過並具名；
/// 完全相同＝`alreadyRecorded`。不同的只有 id：org 候選的回程把手帶 literal（`holderKey::literal`、`citekey[i]::literal`），
/// 而 literal 是機構名稱、可能含 `=`、`:`、`@`，所以不能以第一個或最後一個 `=` 切——見 `splitOrgUndecided`。
extension AkashicService {

    /// 列表的回程把手（#378）——候選列、歧義條目、未決 id 共用這一個定義。**刻意不消毒**：呼叫端要逐字送回來，
    /// 消毒會讓它對不上（且 `displaySafe` 不冪等）。控制字元由 JSON 編碼處理；CLI 印出時自己消毒。
    public static func orgRowID(_ holder: OrgResolutionCandidate.Holder, literal: String) -> String {
        if case let .work(citekey, i) = holder { return "\(citekey)[\(i)]::\(literal)" }   // display-safe-exempt: 回程把手須逐字
        return "\(holder.key)::\(literal)"   // display-safe-exempt: 同上
    }

    /// 一筆 org 未決（輸入驗證後的形狀）。
    struct OrgUndecidedSpec: Equatable {
        let id: String        // 呼叫端送來的 `<rowID>@<orgKey>`（不含說明）——回應與訊息用
        let rowID: String
        let orgKey: String
        let statement: String
    }

    /// 一個切法：`@` 之前是 rowID、StoreKey 是 orgKey、`=` 之後是說明。
    struct OrgUndecidedSplit: Equatable {
        let rowID: String
        let orgKey: String
        let statement: String
    }

    /// 在每個「`@` ＋ StoreKey ＋ `=`」的位置試切，只收前綴恰為已知 rowID 的切法（使用者 2026-09-25 裁決，#643）。
    ///
    /// 回傳**全部**成立的切法——恰一個才可以用，零個或多個由呼叫端整批拒絕（不猜）。literal 或說明裡的 `@`、`=`
    /// 不會切錯：一個位置要同時對得上已知 rowID 與 StoreKey 才算數。
    static func splitOrgUndecided(_ spec: String, knownRowIDs: Set<String>) -> (accepted: [OrgUndecidedSplit], tried: Int) {
        let chars = Array(spec.unicodeScalars)
        var accepted: [OrgUndecidedSplit] = []
        var tried = 0
        func isKeyChar(_ s: Unicode.Scalar, first: Bool) -> Bool {
            switch s.value {
            case 0x61...0x7A, 0x30...0x39: return true          // a-z 0-9
            case 0x2D: return !first                             // - 不能打頭（StoreKey.pattern）
            default: return false
            }
        }
        for (i, c) in chars.enumerated() where c == "@" {
            var j = i + 1
            while j < chars.count, isKeyChar(chars[j], first: j == i + 1) { j += 1 }
            guard j > i + 1, j < chars.count, chars[j] == "=" else { continue }
            tried += 1
            let rowID = String(String.UnicodeScalarView(chars[..<i]))
            guard knownRowIDs.contains(rowID) else { continue }
            accepted.append(OrgUndecidedSplit(
                rowID: rowID,
                orgKey: String(String.UnicodeScalarView(chars[(i + 1)..<j])),
                statement: String(String.UnicodeScalarView(chars[(j + 1)...]))))
        }
        return (accepted, tried)
    }

    /// 解析一批 org 未決。`rows` 是這次呼叫當下的列表：rowID → 那一列提名的 org（候選列一個、歧義條目 2+ 個）。
    /// 輸入錯一律 throw（整批拒絕、零寫入）。
    func parseOrgUndecidedSpecs(_ specs: [String], restsOn: [String],
                                rows: [String: Set<String>]) throws -> [OrgUndecidedSpec] {
        try checkUndecidedCall(specCount: specs.count, restsOn: restsOn)
        let known = Set(rows.keys)
        var out: [OrgUndecidedSpec] = []
        var seen = Set<String>()
        for spec in specs {
            let r = Self.splitOrgUndecided(spec, knownRowIDs: known)
            guard r.accepted.count == 1, let s = r.accepted.first else {
                let why = r.accepted.isEmpty
                    ? "找不到可切的位置——格式是 <列表的 id>@<orgKey>=<說明>，id 要逐字取自這次不帶參數列出的候選或歧義條目"
                    : "有 \(r.accepted.count) 個位置都切得成已知的 id——無法確定是哪一列，不猜"   // display-safe-exempt: count 是 Int
                throw ServiceError.invalid("未決「\(displaySafeInvisible(spec, max: 200))」\(why)")   // display-safe-exempt: why 是本函式的固定訊息
            }
            let id = s.rowID + "@" + s.orgKey
            guard rows[s.rowID]?.contains(s.orgKey) == true else {
                let nominated = (rows[s.rowID] ?? []).sorted().map { displaySafeInvisible($0, max: 80) }.joined(separator: "、")
                throw ServiceError.invalid(
                    "未決「\(displaySafeInvisible(id, max: 200))」點名的 organization 不是這一列提名的——"
                    + "這一列的候選是：\(nominated)")   // display-safe-exempt: nominated 已逐筆 displaySafeInvisible
            }
            try checkUndecidedStatement(id: id, statement: s.statement)
            guard seen.insert(id).inserted else {
                throw ServiceError.invalid("未決 id「\(displaySafeInvisible(id, max: 200))」在一次呼叫裡重複")
            }
            out.append(OrgUndecidedSpec(id: id, rowID: s.rowID, orgKey: s.orgKey, statement: s.statement))
        }
        return out
    }

    /// resolve-organizations 的未決腿（#643）。
    func recordUndecidedOrganizations(_ specs: [String], restsOn: [String]) throws -> String {
        let load = try store.load()
        // 已知 rowID 取自**不帶否決過濾**的一次 resolve：一個已否決配對的 id 仍然認得，才能走「已判定、逐筆略過」
        // 而不是被當成「不認得的 id」整批拒絕（spec 把已判定列為逐筆略過）。
        let report = OrgResolver.resolve(people: load.people, organizations: load.organizations,
                                         rejected: [], entries: load.entries)
        var rows: [String: (holder: OrgResolutionCandidate.Holder, literal: String, orgs: Set<String>)] = [:]
        for c in report.candidates {
            rows[Self.orgRowID(c.holder, literal: c.literal), default: (c.holder, c.literal, [])].orgs.insert(c.orgKey)
        }
        for a in report.ambiguities {
            rows[Self.orgRowID(a.holder, literal: a.literal), default: (a.holder, a.literal, [])].orgs.formUnion(a.orgKeys)
        }
        let parsed = try parseOrgUndecidedSpecs(specs, restsOn: restsOn, rows: rows.mapValues(\.orgs))
        var orgs = Dictionary(load.organizations.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for s in parsed where orgs[s.orgKey] == nil {
            throw ServiceError.notFound("organization「\(displaySafeInvisible(s.orgKey, max: 200))」")
        }
        let unlocatable = load.entries.unlocatableCitekeys
        var recorded: [(id: String, literal: String, statement: String)] = []
        var skipped: [(id: String, why: String)] = []
        var already: [String] = []
        var touched = Set<String>()
        var writtenThisCall = Set<[[UInt8]]>()   // 鍵帶被判 org（同 people／venues 的 R2 修正）
        for s in parsed {
            let row = rows[s.rowID]!
            if case let .work(citekey, _) = row.holder, unlocatable.contains(citekey) {
                skipped.append((s.id, "work「\(displaySafe(citekey, max: 200))」的 citekey 重複或與另一筆 work 共用 id——無法確定是哪一筆，略過（#628）"))
                continue
            }
            let kind = row.holder.verdictHolderKind
            let value = ProvenanceReference.VerdictPairingValue(holderKind: kind, holder: row.holder.key,
                                                                literal: row.literal).encoded
            var org = orgs[s.orgKey]!
            if Self.pairingIsDecided(org.references, value: value) {
                skipped.append((s.id, "這個配對已判定（\(Self.existingDecision(org.references, value: value))）——未決不改變已判定配對的狀態"))   // display-safe-exempt: 封閉的欄位名
                continue
            }
            let ref = ResolutionLedger.record(undecided: kind, holder: row.holder.key, literal: row.literal,
                                              statement: s.statement, restsOn: restsOn)
            let dedup = [Array(s.orgKey.utf8)] + ref.byteExactKey
            if ResolutionLedger.appendIfAbsent(ref, to: &org.references) {
                orgs[s.orgKey] = org
                touched.insert(s.orgKey)
                recorded.append((s.id, row.literal, s.statement))
                writtenThisCall.insert(dedup)
            } else if writtenThisCall.contains(dedup) {
                // 同一次呼叫的另一個 id 寫下了同一筆（同一筆 work 兩個作者位、同一 literal、同一句說明——記錄不帶位置）
                recorded.append((s.id, row.literal, s.statement))
            } else {
                already.append(s.id)
            }
        }
        // 寫入前先驗每一筆，全部通過才寫（同 people／venues 的 R1 修正）
        let format = (try? StoreVersion.read(root: store.root)) ?? 1
        for key in touched.sorted() { try LibraryStore.assertOrganizationWritable(orgs[key]!, format: { format }) }
        var landed: [String] = []
        do {
            for key in touched.sorted() { try store.writeOrganization(orgs[key]!); landed.append(key) }
            if !touched.isEmpty { try LibraryIndex(store: store).rebuild() }
        } catch {
            throw ServiceError.invalid("未決記錄的寫入或 index 重建失敗（已落地的 organization：\(landed.map { displaySafeInvisible($0, max: 120) }.joined(separator: "、"))）："   // display-safe-exempt: landed 已逐筆逃脫
                + displaySafeError(error, max: 400))
        }
        return try undecidedPayload(rows: recorded, skipped: skipped, already: already,
                                    restsOn: restsOn, rewritten: touched.count, holderName: "organizationsRewritten")
    }
}
