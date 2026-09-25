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
    /// 不會切錯：一個位置要同時對得上已知 rowID 與 StoreKey 才算數。**這句保證以「原本要點名的列仍在列表上」為前提**：
    /// 若某個 literal 恰好是另一個 literal 接上 `@<key>=`，而較短的那一列已歸戶而離開列表，同一個輸入會改切到較長的那一列
    /// （#643 R1 verify DA 重現；成立條件很窄，設計文件記為已知邊界）。
    ///
    /// **比對是位元組層的**（#643 R1 verify）：Swift `String` 的 `==` 是 canonical equivalence，NFC 與 NFD 兩個拼法會被
    /// 當成同一列；spec 要的是與列表回傳的 id 位元組相同。**工作量是線性的**：只在前綴長度（scalar 數）等於某個已知 rowID
    /// 的位置才組字串比對——先前每個 `@` 都組一次前綴，60 KB 的輸入跑 14 秒（R1 verify 實測）。
    static func splitOrgUndecided(_ spec: String, knownRowIDs: Set<[UInt8]>) -> (accepted: [OrgUndecidedSplit], tried: Int) {
        let chars = Array(spec.unicodeScalars)
        var knownLengths = Set<Int>()
        for k in knownRowIDs { knownLengths.insert(String(decoding: k, as: UTF8.self).unicodeScalars.count) }
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
            guard knownLengths.contains(i) else { continue }
            let rowID = String(String.UnicodeScalarView(chars[..<i]))
            guard knownRowIDs.contains(Array(rowID.utf8)) else { continue }
            accepted.append(OrgUndecidedSplit(
                rowID: rowID,
                orgKey: String(String.UnicodeScalarView(chars[(i + 1)..<j])),
                statement: String(String.UnicodeScalarView(chars[(j + 1)...]))))
        }
        return (accepted, tried)
    }

    /// 測試與文件範例用：以字串給已知 rowID。
    static func splitOrgUndecided(_ spec: String, knownRowIDs: Set<String>) -> (accepted: [OrgUndecidedSplit], tried: Int) {
        splitOrgUndecided(spec, knownRowIDs: Set(knownRowIDs.map { Array($0.utf8) }))
    }

    /// 單筆 id 的長度上限：最長的已知 rowID ＋ `@`、orgKey、`=` 的餘裕 ＋ 說明上限。超過的不可能是合法 id，在試切之前就擋
    /// （#643 R1 verify：說明的 4,096 位元組上限原本在切完之後才檢查，對解析的工作量沒有作用）。
    static let orgKeyAllowanceBytes = 256

    /// 解析一批 org 未決。`rows` 是這次呼叫當下的列表：rowID（UTF-8 位元組）→ 那一列提名的 org（候選列一個、歧義條目 2+ 個）。
    /// 輸入錯一律 throw（整批拒絕、零寫入）。
    func parseOrgUndecidedSpecs(_ specs: [String], restsOn: [String],
                                rows: [[UInt8]: Set<String>]) throws -> [OrgUndecidedSpec] {
        try checkUndecidedCall(specCount: specs.count, restsOn: restsOn)
        let known = Set(rows.keys)
        let maxSpecBytes = (known.map(\.count).max() ?? 0) + Self.orgKeyAllowanceBytes + Self.maxStatementBytes
        var out: [OrgUndecidedSpec] = []
        var seen = Set<[UInt8]>()
        for spec in specs {
            guard spec.utf8.count <= maxSpecBytes else {
                throw ServiceError.invalid(
                    "未決「\(displaySafeInvisible(spec, max: 200))」長 \(spec.utf8.count) 位元組，超過任何合法 id 的上限 \(maxSpecBytes)"   // display-safe-exempt: spec.utf8.count 與 maxSpecBytes 是 Int
                    + "（最長的列表 id ＋ \(Self.orgKeyAllowanceBytes) ＋ 說明上限 \(Self.maxStatementBytes)）——精簡說明，承重內容用 rests_on 附存檔")   // display-safe-exempt: Self.orgKeyAllowanceBytes 與 Self.maxStatementBytes 是 Int 常數
            }
            let r = Self.splitOrgUndecided(spec, knownRowIDs: known)
            guard r.accepted.count == 1, let s = r.accepted.first else {
                let why: String
                if r.accepted.count > 1 {
                    why = "有 \(r.accepted.count) 個位置都切得成已知的 id——無法確定是哪一列，不猜"   // display-safe-exempt: count 是 Int
                } else if r.tried == 0 {
                    why = "不是 <列表的 id>@<orgKey>=<說明> 的格式（orgKey 是小寫英數與連字號）"
                } else {
                    why = "@ 之前的部分不是這次列表的 id——那一列可能已歸戶或否決而離開列表，或 id 沒有逐字取自不帶參數列出的候選／歧義條目"
                }
                throw ServiceError.invalid("未決「\(displaySafeInvisible(spec, max: 200))」\(why)")   // display-safe-exempt: why 是本函式的固定訊息
            }
            let id = s.rowID + "@" + s.orgKey
            let rowNominates = rows[Array(s.rowID.utf8)] ?? []
            guard rowNominates.contains(s.orgKey) else {
                let nominated = rowNominates.sorted().map { displaySafeInvisible($0, max: 80) }.joined(separator: "、")
                throw ServiceError.invalid(
                    "未決「\(displaySafeInvisible(id, max: 200))」點名的 organization 不是這一列提名的——"
                    + "這一列的候選是：\(nominated)")   // display-safe-exempt: nominated 已逐筆 displaySafeInvisible
            }
            try checkUndecidedStatement(id: id, statement: s.statement)
            guard seen.insert(Array(id.utf8)).inserted else {
                throw ServiceError.invalid("未決 id「\(displaySafeInvisible(id, max: 200))」在一次呼叫裡重複")
            }
            out.append(OrgUndecidedSpec(id: id, rowID: s.rowID, orgKey: s.orgKey, statement: s.statement))
        }
        return out
    }

    /// 測試用：以字串給列表。
    func parseOrgUndecidedSpecs(_ specs: [String], restsOn: [String],
                                rows: [String: Set<String>]) throws -> [OrgUndecidedSpec] {
        try parseOrgUndecidedSpecs(specs, restsOn: restsOn,
                                   rows: Dictionary(rows.map { (Array($0.key.utf8), $0.value) }, uniquingKeysWith: { $0.union($1) }))
    }

    /// resolve-organizations 的未決腿（#643）。
    func recordUndecidedOrganizations(_ specs: [String], restsOn: [String]) throws -> String {
        // 上限與 format 在 load 之前擋（#643 R1 verify：原本 201 個 id 也要先載入全庫、跑完提名才被拒）
        try checkUndecidedCall(specCount: specs.count, restsOn: restsOn)
        let load = try store.load()
        // 已知 rowID 取自**兩次** resolve 的聯集（#643 R1 verify）：
        // - 帶否決過濾的那次＝列表本身。parents 的循環守衛會讀本輪已接受的邊，而否決過的邊不在其中，
        //   所以列表會出現一些「不帶否決」那次會被守衛擋掉的列——只取後者，列表上的 id 會被當成不認得。
        // - 不帶否決過濾的那次：已否決的配對仍然認得，才能走「已判定、逐筆略過」而不是整批拒絕。
        let listed = OrgResolver.resolve(people: load.people, organizations: load.organizations,
                                         rejected: ResolutionLedger.rejectedPairings(organizations: load.organizations),
                                         entries: load.entries)
        let unfiltered = OrgResolver.resolve(people: load.people, organizations: load.organizations,
                                             rejected: [], entries: load.entries)
        // rowID → holder 身分（kind）→ 那一列。person 與 organization 的 key 可以同名，兩者的 rowID 都是 `key::literal`
        // （#643 R1 verify）；同一個 rowID 對到兩種 holder 時整批拒絕，不猜是哪一個。
        var rows: [[UInt8]: [ProvenanceReference.VerdictHolderKind: (holder: OrgResolutionCandidate.Holder, literal: String, orgs: Set<String>)]] = [:]
        func add(_ holder: OrgResolutionCandidate.Holder, _ literal: String, _ orgKeys: [String]) {
            let id = Array(Self.orgRowID(holder, literal: literal).utf8)
            rows[id, default: [:]][holder.verdictHolderKind, default: (holder, literal, [])].orgs.formUnion(orgKeys)
        }
        for report in [listed, unfiltered] {
            for c in report.candidates { add(c.holder, c.literal, [c.orgKey]) }
            for a in report.ambiguities { add(a.holder, a.literal, a.orgKeys) }
        }
        let parsed = try parseOrgUndecidedSpecs(specs, restsOn: restsOn,
                                                rows: rows.mapValues { $0.values.reduce(into: Set<String>()) { $0.formUnion($1.orgs) } })
        for s in parsed where (rows[Array(s.rowID.utf8)]?.count ?? 0) > 1 {
            let kinds = rows[Array(s.rowID.utf8)]!.keys.map(\.rawValue).sorted().joined(separator: "、")
            throw ServiceError.invalid(
                "未決「\(displaySafeInvisible(s.id, max: 200))」的 id 同時對應 \(kinds) 兩種 holder（person 與 organization 的 key 可以同名）"   // display-safe-exempt: kinds 是封閉的 holder kind 值
                + "——無法確定是哪一個，整批拒絕、零寫入。apply／reject 的 id 同樣相撞，目前沒有工具面分得開這兩列：改名那個 person 的 key（rename-person；organization 沒有改名面）後再列一次")
        }
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
        var decidedKeys: [String: Set<String>] = [:]   // 每個 org 只掃一次 references（同 people／venues 的 R3 修正）
        for s in parsed {
            let row = rows[Array(s.rowID.utf8)]!.values.first!
            if case let .work(citekey, _) = row.holder, unlocatable.contains(citekey) {
                skipped.append((s.id, "work「\(displaySafe(citekey, max: 200))」的 citekey 重複或與另一筆 work 共用 id——無法確定是哪一筆，略過（#628）"))
                continue
            }
            let kind = row.holder.verdictHolderKind
            let value = ProvenanceReference.VerdictPairingValue(holderKind: kind, holder: row.holder.key,
                                                                literal: row.literal).encoded
            var org = orgs[s.orgKey]!
            let decided = decidedKeys[s.orgKey] ?? Self.decidedPairingKeys(org.references)
            decidedKeys[s.orgKey] = decided
            if let key = ProvenanceReference.verdictPairingKey(value: value), decided.contains(key) {
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
