import Foundation
import AkashicCore

/// 單筆記錄的定址：CLI `validate --owner` 與 MCP `akashic_doctor` 的 `owner`（#581）。
///
/// 文法是 `<kind>:<key>`，kind 是 `EntityKind` 的五個值之一（work／person／organization／venue／divergence）——與 verdict value
/// （第 13 條邊）的 `<kind>:<key>` 同一套 kind 名。
///
/// **kind 必填、不猜**：不同 kind 的 key 可以相同。2026-09-28 實測 live store：organization 與 venue 共用 2 個 key
/// （`american-psychological-association`、`american-educational-research-association`——同一個機構既是團體作者也是出版社），
/// 其餘 kind 兩兩之間 0 個。省略 kind 等於讓程式在兩筆記錄之間挑一筆（`disambiguate-before-irreversible-writes` 的
/// 「判不出來的不猜」，這裡雖然是讀取面，挑錯的代價是把另一筆記錄的明細當成這一筆的）。
///
/// 錯誤訊息的參數名兩面都寫出來（`owner（CLI validate --owner／MCP akashic_doctor 的 owner）`）——兩面共用這些拒絕，只寫 CLI 的
/// 會讓 MCP 呼叫端找不到自己傳錯了哪個參數。每個擲出點寫字面量，不抽常數：`SanitizationBoundaryTests` 要求 `what:` 是字面量。
///
/// **library 不在值域內**：它不是 `EntityKind`（registry 住在 `libraries/`，不在 `entities/`），而且它沒有任何有列出上限的族
/// ——`validate` 本來就逐則全列它的問題。
public struct RecordAddress: Equatable {
    public let kind: EntityKind
    /// work 是 citekey；divergence 是正規化後的 UUID 字串（大寫，與 `Divergence.id.uuidString` 同形）；其餘是 StoreKey。
    public let key: String

    /// `StoreHealth.OwnedIssue.kind` 的族名——work 在那裡叫 `entry`（`perRecordIssues(from:listing:only:)` 的既有族名）。
    public var ownedIssueKind: String { kind == .work ? "entry" : kind.rawValue }

    init(kind: EntityKind, key: String) {
        self.kind = kind
        self.key = key
    }

    /// 只看字串就判得出來的檢查——CLI 在 `validate()` 呼叫它（用法錯誤、exit 64；`RuntimeFailure` 的判準）。
    /// divergence 的 UUID 大小寫都收、正規化成大寫（UUID 文法本身不分大小寫，那不是猜）；其餘 kind 的 key 要符合 `StoreKey.pattern`
    /// ——不合的 key 在 load 時就被 quarantine，不可能對應任何已載入的記錄。
    public static func parse(_ raw: String) throws -> RecordAddress {
        guard let colon = raw.firstIndex(of: ":") else {
            throw StoreIOError.invalidInput(
                what: "owner（CLI validate --owner／MCP akashic_doctor 的 owner）",
                why: "「\(displaySafeInvisible(raw, max: 120))」沒有 kind——要寫成 <kind>:<key>，kind 是 "
                    + "\(EntityKind.allCases.map(\.rawValue).joined(separator: "／")) 之一；不同 kind 的 key 可以相同，所以不猜")
        }
        let kindText = String(raw[..<colon])
        let key = String(raw[raw.index(after: colon)...])
        guard let kind = EntityKind(rawValue: kindText) else {
            throw StoreIOError.invalidInput(
                what: "owner（CLI validate --owner／MCP akashic_doctor 的 owner）",
                why: "kind「\(displaySafeInvisible(kindText, max: 60))」不是 "
                    + "\(EntityKind.allCases.map(\.rawValue).joined(separator: "／")) 之一（大小寫不折疊；"
                    + "library 沒有有列出上限的族，不帶 owner 的 validate 本來就逐則全列）")
        }
        if kind == .divergence {
            guard let id = UUID(uuidString: key) else {
                throw StoreIOError.invalidInput(
                    what: "owner（CLI validate --owner／MCP akashic_doctor 的 owner）",
                    why: "divergence 的 key 要是 UUID（`akashic divergences` 列出的 id），收到「\(displaySafeInvisible(key, max: 120))」")
            }
            return RecordAddress(kind: kind, key: id.uuidString)
        }
        guard StoreKey.isValid(key) else {
            throw StoreIOError.invalidInput(
                what: "owner（CLI validate --owner／MCP akashic_doctor 的 owner）",
                why: "key「\(displaySafeInvisible(key, max: 120))」不符合 \(StoreKey.pattern)——不合的 key 在 load 時就被 quarantine，"
                    + "不可能對應任何已載入的記錄")
        }
        return RecordAddress(kind: kind, key: key)
    }
}

public extension LibraryStore {
    /// 單筆記錄的**完整** per-record 明細（#581）：不套每筆記錄的列出上限（`PerRecordListing.full`），求值上限照舊。
    ///
    /// 族序、掃描清單與 error 先排和 `health(from:)` 是同一份（`perRecordIssues(from:listing:only:)`）。跨記錄檢查
    /// （`crossRecordIssues`）與 quarantine 不屬於任何一筆記錄，不在這裡——看它們用不帶 owner 的 `validate`／`akashic_doctor`。
    ///
    /// 定位不唯一就拒絕、不猜：找不到（含被 quarantine 的檔——讀不進來的記錄沒有 key 可比）、或同 kind 同 key 有兩筆以上
    /// ——per-record 問題以 (族名, key) 標記，兩筆同 key 的記錄在那個結構裡分不開，篩出來的會是它們的聯集，而輸出的標題說「這一筆」
    /// （`zero-instance-guards` 第 38 列）。拒絕訊息列出各筆的 UUID（檔名），因為重複的 key 本身指不到任何一個檔。
    /// 同 kind 同 key 的重複，`crossRecordIssues` 都以 error 報：citekey 與 person key 原本就有，venue 與 organization 由 #669
    /// 補上（在那之前這則訊息照實說「沒有檢查報它」）。divergence 的 key 是檔名 UUID，不會重複。
    /// 2026-09-28 實測 live store 同 kind 同 key 的重複 0 組。
    func perRecordIssues(from load: LibraryLoad, owner: RecordAddress) throws -> [StoreHealth.OwnedIssue] {
        let ids: [UUID]
        switch owner.kind {
        case .work: ids = load.entries.filter { $0.citekey == owner.key }.map(\.id)
        case .person: ids = load.people.filter { $0.key == owner.key }.map(\.id)
        case .organization: ids = load.organizations.filter { $0.key == owner.key }.map(\.id)
        case .venue: ids = load.venues.filter { $0.key == owner.key }.map(\.id)
        case .divergence: ids = load.divergences.filter { $0.id.uuidString == owner.key }.map(\.id)
        }
        let found = ids.count
        if found == 0 {
            throw StoreIOError.invalidInput(
                what: "owner（CLI validate --owner／MCP akashic_doctor 的 owner）",
                why: "找不到已載入的 \(owner.kind.rawValue) 記錄「\(displaySafeInvisible(owner.key, max: 120))」"
                    + (load.quarantined.isEmpty ? "" : "——另有 \(load.quarantined.count) 個檔被 quarantine、讀不進來；"
                        + "若它在其中，先跑不帶 --owner 的 validate（MCP：不帶 owner 的 akashic_doctor）看原因"))
        }
        if found > 1 {
            let files = ids.map(\.uuidString).sorted().prefix(10).joined(separator: "、") + (found > 10 ? "…" : "")
            let crossRecord = "不帶 --owner 的 validate 以跨記錄 error 列出這個重複"
            throw StoreIOError.invalidInput(
                what: "owner（CLI validate --owner／MCP akashic_doctor 的 owner）",
                why: "有 \(found) 筆已載入的 \(owner.kind.rawValue) 記錄的 key 都是「\(displaySafeInvisible(owner.key, max: 120))」"
                    + "（entities/ 下的檔名 UUID：\(files)）"   // display-safe-exempt: files 是 UUID.uuidString（hex＋dash）
                    + "——無法唯一定位，不猜（以 key 篩出的明細會是它們的聯集）；\(crossRecord)")   // display-safe-exempt: crossRecord 是字面常量
        }
        return perRecordIssues(from: load, listing: .full, only: owner)
    }
}
