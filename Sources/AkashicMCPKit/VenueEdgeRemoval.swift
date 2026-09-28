import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// resolve-venues 的移除腿（#572）：`<citekey>:<venueIndex>=理由`，把一筆 work 的一條 venue 邊刪掉。
///
/// 為什麼需要它：同一 work 兩條邊指同一 venue 是工具自己造得出來的狀態（兩條同刊名的 literal 邊各 apply 一次、
/// venue 合併後 literal 邊解析到已 key 的 venue；#554 R10／R11），而造出來之後 repoint／demote 對兩條邊都拒絕（D25）、
/// `Entry.validate()` 只能指「手改 YAML」——`replace-endnote-and-zotero` 第 4 條要記成 issue 的缺口。
///
/// 使用者 2026-09-27 裁決（移除面一族，#588／#572／#586 同一條）：**理由只進報告**（git 保存的是移除前的檔，理由要留在
/// git 得由操作者寫進 commit message，工具不代寫），移除前要求那筆 work 檔已 commit、乾淨（`assertRecordsRecoverable`），
/// **不改 store format**——所以沒有 `Entry.references` 的記錄、沒有新的值域。
///
/// 契約：
/// - **以 index 定位，不以值**。重複的兩條邊值相同，值定位分不出要刪哪一條——那正是這個面要處理的形狀。index 是
///   呼叫端從 `resolve-venues`／`get-entry` 讀到的**原始**位置；同一筆 work 的多筆一次過濾（以原始 index 的集合篩掉，不逐筆刪），呼叫端不必算位移。
/// - **key 邊只在刪完之後本 work 仍有另一條 key 邊指同一 venue 時可刪**。那時 venue 上的 confirmed verdict 仍由剩下的
///   那條邊實例化；刪掉唯一的 key 邊會留下一筆沒有邊的 confirmed（之後 D38 會把同 work 的另一個拼法擋在外面），
///   而那筆 verdict 該不該留是判定——出路是先 `--demote`（它退役 confirmed、寫 rejected）再刪 literal 邊。
/// - **literal 邊一律可刪**：literal 是未判定的誠實狀態，沒有 verdict 以它為前提。
/// - 理由必填、有上限；同一條邊在同一批出現兩次、越界、citekey 無法唯一定位，都整批拒絕、零寫入。單獨呼叫。
///
/// **誠實邊界**：刪掉一筆 work 的**全部** venue 邊之後，`migrate-venues`（只補沒有 venues 的 work）與 Zotero pull
/// 會從來源欄位重新推導出來——報告以 `emptied` 具名那些 work。
extension AkashicService {

    /// `--drop-venue`（drop_venue）的一筆（只看參數的解析結果，#654）。
    struct DropVenueSpec {
        let reason: String
        let idx: Int
        let citekey: String
    }

    /// CLI 的 `validate()` 用（#654）：`--drop-venue` 只看參數的全部檢查——與服務在讀 store 之前跑的是同一個函式。
    public static func checkDropVenueArguments(_ specs: [String]) throws {
        _ = try parseDropVenueSpecs(specs)
    }

    /// 一次的上限、`citekey:venueIndex=理由` 的形狀、理由的空白與長度、同一條邊兩次（#654 原樣搬出）。先前排在讀 store 之後。
    static func parseDropVenueSpecs(_ specs: [String]) throws -> [DropVenueSpec] {
        guard specs.count <= Self.maxSpecsPerCall else {
            throw ServiceError.invalid("一次最多移除 \(Self.maxSpecsPerCall) 條邊（這次 \(specs.count) 條）——分次送")   // display-safe-exempt: Self.maxSpecsPerCall 與 specs.count 都是 Int
        }
        var out: [DropVenueSpec] = []
        var seen = Set<String>()
        for raw in specs {
            guard let eq = raw.firstIndex(of: "=") else {
                throw ServiceError.invalid(
                    "移除「\(displaySafeInvisible(raw, max: 200))」不是 citekey:venueIndex=理由 形——理由必填")
            }
            let head = String(raw[..<eq])
            let reason = String(raw[raw.index(after: eq)...])
            let parts = head.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, let idx = Int(parts[1]), idx >= 0 else {
                throw ServiceError.invalid(
                    "移除「\(displaySafeInvisible(head, max: 200))」不是 citekey:venueIndex 形")
            }
            if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ServiceError.invalid(
                    "移除「\(displaySafeInvisible(head, max: 200))」的理由是空白——理由是「為什麼這條邊不該在」的紀錄，報告與 commit 靠它")
            }
            guard reason.utf8.count <= Self.maxStatementBytes else {
                throw ServiceError.invalid(
                    "移除「\(displaySafeInvisible(head, max: 200))」的理由超過 \(Self.maxStatementBytes) 位元組——精簡它")   // display-safe-exempt: Self.maxStatementBytes 是 Int 常數
            }
            let citekey = parts[0]
            guard seen.insert("\(citekey)\u{0}\(idx)").inserted else {
                throw ServiceError.invalid(
                    "同一條邊「\(displaySafeInvisible(head, max: 200))」在這次呼叫出現兩次——整批拒絕、零寫入")
            }
            out.append(DropVenueSpec(reason: reason, idx: idx, citekey: citekey))
        }
        return out
    }

    func dropVenueEdges(_ specs: [String]) throws -> String {
        let parsedSpecs = try Self.parseDropVenueSpecs(specs)   // 只看參數的檢查在讀 store 之前（#654）
        let load = try store.load()
        let unlocatable = load.entries.unlocatableCitekeys
        let byCitekey = Dictionary(load.entries.map { ($0.citekey, $0) }, uniquingKeysWith: { a, _ in a })

        struct Drop { let citekey: String; let index: Int; let reason: String }
        var drops: [Drop] = []
        for ps in parsedSpecs {   // 只看參數的檢查已在讀 store 之前做完（`parseDropVenueSpecs`，#654）
            let (reason, idx, citekey) = (ps.reason, ps.idx, ps.citekey)
            if unlocatable.contains(citekey) {
                throw ServiceError.invalid(
                    "work「\(displaySafeInvisible(citekey, max: 200))」無法唯一定位（\(UnlocatableReason.work)）——"
                    + "整批拒絕、零寫入；先修好（#628／#641）")
            }
            guard let entry = byCitekey[citekey] else {
                throw ServiceError.notFound("work「\(displaySafeInvisible(citekey, max: 200))」")
            }
            guard idx < entry.venues.count else {
                throw ServiceError.invalid(
                    "work「\(displaySafeInvisible(citekey, max: 200))」只有 \(entry.venues.count) 個 venue 邊，"   // display-safe-exempt: Int
                    + "index \(idx) 越界")   // display-safe-exempt: idx 是 Int
            }
            drops.append(Drop(citekey: citekey, index: idx, reason: reason))
        }

        // 逐筆 work 算刪完之後的邊集合，驗 key 邊的前提
        var after: [String: Entry] = [:]
        var removedEdges: [String: [Int: VenueRef]] = [:]
        for (ck, group) in Dictionary(grouping: drops, by: \.citekey) {
            var e = byCitekey[ck]!
            let gone = Set(group.map(\.index))
            var removed: [Int: VenueRef] = [:]
            for i in gone { removed[i] = e.venues[i] }
            let remaining = e.venues.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            for (i, ref) in removed.sorted(by: { $0.key < $1.key }) {
                guard case .key(let k) = ref else { continue }
                if !remaining.contains(.key(k)) {
                    throw ServiceError.invalid(
                        "work「\(displaySafeInvisible(ck, max: 200))」的第 \(i) 條邊是 venue「\(displaySafeInvisible(k, max: 200))」唯一的 key 邊——"   // display-safe-exempt: i 是 Int
                        + "刪掉它會讓那本刊上的 confirmed verdict 沒有邊。先 --demote 這條邊（退回 literal、改記 rejected），再移除 literal 邊；整批拒絕、零寫入")
                }
            }
            e.venues = remaining
            after[ck] = e
            removedEdges[ck] = removed
        }

        let touched = after.keys.sorted()
        try assertRecordsRecoverable(touched.map { ck in (byCitekey[ck]!.id, "work「\(displaySafeInvisible(ck, max: 200))」") },
                                     action: "這次會移除 \(drops.count) 條 venue 邊",   // display-safe-exempt: drops.count 是 Int
                                     issue: "#572")
        // #648：與其餘多檔寫入者同一個前置（`preflightWrite`＝writeEntry 在寫入當下跑的每一道），整批零寫入或整批寫
        for ck in touched { try store.preflightWrite(after[ck]!) }
        for ck in touched { try store.writeEntry(after[ck]!) }
        try LibraryIndex(store: store).rebuild()

        let reasonBy = Dictionary(drops.map { ("\($0.citekey)\u{0}\($0.index)", $0.reason) }, uniquingKeysWith: { a, _ in a })
        var items: [[String: Any]] = []
        for ck in touched {
            for (i, ref) in (removedEdges[ck] ?? [:]).sorted(by: { $0.key < $1.key }) {
                let edge: String
                switch ref {
                case .key(let k): edge = "key:" + displaySafe(k, max: 200)
                case .literal(let s): edge = "literal:" + displaySafe(s, max: 300)
                }
                items.append(["id": "\(displaySafe(ck, max: 200)):\(i)",   // display-safe-exempt: Int
                              "edge": edge,
                              "reason": displaySafe(reasonBy["\(ck)\u{0}\(i)"] ?? "", max: Self.maxStatementBytes)])
            }
        }
        var payload: [String: Any] = ["venueEdgesRemoved": items,
                                      "entriesRewritten": touched.count]   // display-safe-exempt: Int
        let emptied = touched.filter { after[$0]!.venues.isEmpty }
        if !emptied.isEmpty {
            payload["emptied"] = emptied.map { displaySafe($0, max: 200) }
            payload["emptiedNote"] = "這些 work 已沒有任何 venue 邊——migrate-venues 與 Zotero pull 會從 journaltitle／booktitle／publisher 重新推導"
        }
        payload["reasonNote"] = "理由只在這份報告裡——要留在 git，寫進接下來的 commit message（#572，使用者 2026-09-27 裁決）"
        return try jsonString(payload)
    }
}
