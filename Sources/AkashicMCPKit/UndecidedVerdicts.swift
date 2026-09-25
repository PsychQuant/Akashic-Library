import Foundation
import AkashicCore
import AkashicEntity
import AkashicStoreIO
import AkashicIndex

/// 未決記錄的寫入面（change `resolution-verdict-states`，#619）：「查過、判不出來」與查了什麼。
///
/// 兩面同一條路徑：resolve-people 與 resolve-venues 的 `undecided` 腿（CLI `--undecided`／`--rests-on`，
/// MCP `undecided`／`rests_on`）都落到這裡。失敗語意分兩類（同 `judge` 的既有契約）：
/// 輸入錯整批拒絕、零寫入；store 狀態不符該筆略過並具名，其餘照寫。
///
/// **不是判定**：它不動 entry、不抑制提名、不構成矛盾。配對已被判定（任一層級的 confirmed／rejected）時略過——
/// 未決對 decided 的配對不改變狀態，寫進去只是一筆沒有讀者的記錄。
extension AkashicService {

    /// 未決腿收到的一筆 id（輸入驗證後的形狀）。
    struct UndecidedSpec {
        let id: String
        let citekey: String
        let index: Int
        let entityKey: String
        let statement: String
    }

    /// 解析 `<citekey>:<index>:<entityKey>=<說明>`（以第一個 `=` 切——說明是自由文字）。輸入錯一律 throw。
    func parseUndecidedSpecs(_ specs: [String], restsOn: [String], indexName: String) throws -> [UndecidedSpec] {
        let storeFormat = (try? StoreVersion.read(root: store.root)) ?? 1
        guard storeFormat >= 19 else {
            throw ServiceError.invalid(
                "未決記錄（resolution-undecided）需要 store format ≥ 19（本 store 是 \(storeFormat)）"   // display-safe-exempt: storeFormat 是 Int
                + "——確認 CLI/MCP/App 都已升級後，把 store.yaml 的 format: 改成 19")
        }
        // rests-on 的形狀走 ProvenanceReference 平面 init（單一驗證入口）：一個 dummy 值驗整組 digest
        do {
            _ = try ProvenanceReference(field: ProvenanceReference.resolutionUndecidedField,
                                        value: "work:x :: x", url: nil, retrieved: nil, status: nil,
                                        mediaType: nil, content: nil, judgement: "x", restsOn: restsOn)
        } catch {
            throw ServiceError.invalid("rests_on 不合法：\(displaySafeError(error, max: 400))")
        }
        var out: [UndecidedSpec] = []
        var seen = Set<String>()
        for spec in specs {
            guard let eq = spec.firstIndex(of: "=") else {
                throw ServiceError.invalid(
                    "未決「\(displaySafeInvisible(spec, max: 200))」缺少 `=`——格式是 "
                    + "citekey:\(indexName):key=查了什麼、為何判不出來")   // display-safe-exempt: indexName 是呼叫端的字面常量（authorIndex／venueIndex）
            }
            let id = String(spec[..<eq])
            let statement = String(spec[spec.index(after: eq)...])
            let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let idx = Int(parts[1]), idx >= 0, !parts[0].isEmpty, !parts[2].isEmpty else {
                throw ServiceError.invalid(
                    "未決 id「\(displaySafeInvisible(id, max: 200))」不是三段形 citekey:\(indexName):key"   // display-safe-exempt: indexName 是呼叫端的字面常量
                    + "（\(indexName) 是從 0 起的非負整數）")   // display-safe-exempt: indexName 是呼叫端的字面常量
            }
            if statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ServiceError.invalid(
                    "未決「\(displaySafeInvisible(id, max: 200))」的說明是空白——要寫查了什麼、為何判不出來；"
                    + "沒有它，這筆記錄與「沒查過」無法區分")
            }
            guard seen.insert("\(parts[0]):\(idx):\(parts[2])").inserted else {   // display-safe-exempt: 集合鍵，不輸出
                throw ServiceError.invalid(
                    "未決 id「\(displaySafeInvisible(id, max: 200))」在一次呼叫裡重複")
            }
            out.append(UndecidedSpec(id: id, citekey: parts[0], index: idx, entityKey: parts[2], statement: statement))
        }
        return out
    }

    /// 該 holder 的 references 裡，這個配對是否已被判定（任一層級的 confirmed／rejected）。
    static func pairingIsDecided(_ refs: [ProvenanceReference], value: String) -> Bool {
        guard let key = ProvenanceReference.verdictPairingKey(value: value) else { return false }
        return refs.contains {
            ($0.field == ProvenanceReference.resolutionConfirmedField
                || $0.field == ProvenanceReference.resolutionRejectedField)
                && ProvenanceReference.verdictPairingKey(value: $0.value) == key
        }
    }

    /// 已存在的判定欄位名（給略過訊息用）。
    static func existingDecision(_ refs: [ProvenanceReference], value: String) -> String {
        let key = ProvenanceReference.verdictPairingKey(value: value)
        let fields = Set(refs.filter { ProvenanceReference.verdictPairingKey(value: $0.value) == key }.map(\.field))
        return [ProvenanceReference.resolutionConfirmedField, ProvenanceReference.resolutionRejectedField]
            .filter(fields.contains).joined(separator: "、")
    }

    /// resolve-people 的未決腿。
    func recordUndecidedAuthorships(_ specs: [String], restsOn: [String]) throws -> String {
        let parsed = try parseUndecidedSpecs(specs, restsOn: restsOn, indexName: "authorIndex")
        let load = try store.load()
        let byCitekey = Dictionary(load.entries.map { ($0.citekey, $0) }, uniquingKeysWith: { _, last in last })
        let unlocatable = load.entries.unlocatableCitekeys
        var people = Dictionary(load.people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for s in parsed where people[s.entityKey] == nil {
            throw ServiceError.notFound("person「\(displaySafeInvisible(s.entityKey, max: 200))」")
        }
        var recorded: [(spec: UndecidedSpec, literal: String)] = []
        var skipped: [(id: String, why: String)] = []
        var already: [String] = []
        var touched = Set<String>()
        for s in parsed {
            guard !unlocatable.contains(s.citekey) else {
                skipped.append((s.id, "work「\(displaySafe(s.citekey, max: 200))」的 citekey 重複或與另一筆 work 共用 id——無法確定是哪一筆，略過（#627）"))
                continue
            }
            guard let entry = byCitekey[s.citekey] else {
                skipped.append((s.id, "work「\(displaySafe(s.citekey, max: 200))」不存在")); continue
            }
            guard entry.authors.indices.contains(s.index) else {
                skipped.append((s.id, "作者索引 \(s.index) 超出範圍（0…\(entry.authors.count - 1)）")); continue   // display-safe-exempt: Int
            }
            guard case let .literal(literal) = entry.authors[s.index] else {
                skipped.append((s.id, "該作者位不是 literal——已歸戶的位置沒有「判不出來」可記")); continue
            }
            let value = ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: s.citekey, literal: literal).encoded
            var person = people[s.entityKey]!
            if Self.pairingIsDecided(person.references, value: value) {
                skipped.append((s.id, "這個配對已判定（\(Self.existingDecision(person.references, value: value))）——未決不改變已判定配對的狀態"))   // display-safe-exempt: 封閉的欄位名
                continue
            }
            let ref = ResolutionLedger.record(undecided: .work, holder: s.citekey, literal: literal,
                                              statement: s.statement, restsOn: restsOn)
            if ResolutionLedger.appendIfAbsent(ref, to: &person.references) {
                people[s.entityKey] = person
                touched.insert(s.entityKey)
                recorded.append((s, literal))
            } else {
                already.append(s.id)
            }
        }
        for key in touched.sorted() { try store.writePerson(people[key]!) }
        if !touched.isEmpty { try LibraryIndex(store: store).rebuild() }
        return try undecidedPayload(recorded: recorded, skipped: skipped, already: already,
                                    restsOn: restsOn, rewritten: touched.count, holderName: "personsRewritten")
    }

    /// resolve-venues 的未決腿。
    func recordUndecidedVenues(_ specs: [String], restsOn: [String]) throws -> String {
        let parsed = try parseUndecidedSpecs(specs, restsOn: restsOn, indexName: "venueIndex")
        let load = try store.load()
        let byCitekey = Dictionary(load.entries.map { ($0.citekey, $0) }, uniquingKeysWith: { _, last in last })
        let unlocatable = load.entries.unlocatableCitekeys
        var venues = Dictionary(load.venues.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for s in parsed where venues[s.entityKey] == nil {
            throw ServiceError.notFound("venue「\(displaySafeInvisible(s.entityKey, max: 200))」")
        }
        var recorded: [(spec: UndecidedSpec, literal: String)] = []
        var skipped: [(id: String, why: String)] = []
        var already: [String] = []
        var touched = Set<String>()
        for s in parsed {
            guard !unlocatable.contains(s.citekey) else {
                skipped.append((s.id, "work「\(displaySafe(s.citekey, max: 200))」的 citekey 重複或與另一筆 work 共用 id——無法確定是哪一筆，略過（#628）"))
                continue
            }
            guard let entry = byCitekey[s.citekey] else {
                skipped.append((s.id, "work「\(displaySafe(s.citekey, max: 200))」不存在")); continue
            }
            guard entry.venues.indices.contains(s.index) else {
                skipped.append((s.id, "venue 索引 \(s.index) 超出範圍（共 \(entry.venues.count) 條邊）")); continue   // display-safe-exempt: Int
            }
            guard case let .literal(literal) = entry.venues[s.index] else {
                skipped.append((s.id, "該 venue 邊不是 literal——已歸戶的邊沒有「判不出來」可記")); continue
            }
            let value = ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: s.citekey, literal: literal).encoded
            var venue = venues[s.entityKey]!
            if Self.pairingIsDecided(venue.references, value: value) {
                skipped.append((s.id, "這個配對已判定（\(Self.existingDecision(venue.references, value: value))）——未決不改變已判定配對的狀態"))   // display-safe-exempt: 封閉的欄位名
                continue
            }
            let ref = ResolutionLedger.record(undecided: .work, holder: s.citekey, literal: literal,
                                              statement: s.statement, restsOn: restsOn)
            if ResolutionLedger.appendIfAbsent(ref, to: &venue.references) {
                venues[s.entityKey] = venue
                touched.insert(s.entityKey)
                recorded.append((s, literal))
            } else {
                already.append(s.id)
            }
        }
        for key in touched.sorted() { try store.writeVenue(venues[key]!) }
        if !touched.isEmpty { try LibraryIndex(store: store).rebuild() }
        return try undecidedPayload(recorded: recorded, skipped: skipped, already: already,
                                    restsOn: restsOn, rewritten: touched.count, holderName: "venuesRewritten")
    }

    private func undecidedPayload(recorded: [(spec: UndecidedSpec, literal: String)], skipped: [(id: String, why: String)],
                                  already: [String], restsOn: [String], rewritten: Int, holderName: String) throws -> String {
        try jsonString([
            "undecided": recorded.map { r -> [String: Any] in
                ["id": displaySafe(r.spec.id, max: 200),
                 "literal": displaySafe(r.literal, max: 300),
                 "statement": displaySafe(r.spec.statement, max: 800),
                 "restsOn": restsOn.map { displaySafe($0, max: 80) }]
            },
            "skipped": skipped.map { ["id": displaySafe($0.id, max: 200), "why": $0.why] },   // display-safe-exempt: why 由本檔組裝，內含值已消毒
            "alreadyRecorded": already.map { displaySafe($0, max: 200) },
            holderName: rewritten,
        ])
    }
}
