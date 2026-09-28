import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// `repair-venue-names` 的報告（#575）。計畫本身是 `VenueNameRepair.Plan`（純函式）；這裡加上 store 層的兩件事：
/// 寫入閘的預演與 git 可回溯閘的結果。
public struct VenueNameRepairReport {
    /// 名字內容有事可說的 venue（依 key 排序）。沒有違反的不列。
    public let plans: [VenueNameRepair.Plan]
    /// 走訪過的 venue 筆數（載入成功的；quarantine 的檔不在內，`validate` 報它們）。
    public let scanned: Int
    /// store 裡讀不進來的記錄檔數（任何形狀——讀不進來就不知道是不是 venue）。非零時「沒有違反」只對走訪過的那幾筆成立
    /// （`zero-instance-guards` 第 3 列：未涵蓋不得冒充通過），輸出面要說出來。
    public let quarantined: Int
    /// 這次真的寫了。
    public let applied: Bool
    /// 乾跑時：`--apply` 會以什麼理由整批拒絕（nil＝不會）。已消毒。`--apply` 本身遇到同樣的理由是直接擲錯、不寫任何一筆。
    public let applyRefusal: String?

    /// 可以（或已經）改寫的 venue。
    public var applicable: [VenueNameRepair.Plan] { plans.filter { $0.repaired != nil } }
    /// 要人判斷、本命令一筆都不改的 venue。
    public var needsJudgment: [VenueNameRepair.Plan] { plans.filter { $0.repaired == nil } }
}

/// venue 名字不變式的機械修復面（#575，使用者 2026-09-28 裁決：乾跑預設 → 顯式 `--apply`）。只有 CLI 面——維運例外，同 `fmt`／`migrate`
/// 族（`mcp-cli-parity` 的 CLI-only 表）；放在 service 是為了用 `assertRecordsRecoverable` 那一支 git 閘，不是為了開 MCP 面。
///
/// 契約：
/// - 乾跑與 `--apply` 算**同一份**計畫、跑**同一組**閘；乾跑把閘的拒絕當預告放進報告，`--apply` 遇到就擲錯。
/// - 寫入前：每一筆要改寫的 venue 先過 `writeVenue` 的全部前置（`preflightWrite`：寫入閘、encode 與位元組上限、#631 目的檔），再要求那些 venue 檔已在 git 裡 commit、乾淨
///   （`assertRecordsRecoverable`——被改寫前的位元組只剩 git 裡那一份）。任一筆不過即整批拒絕、零寫入。
/// - 要人判斷的 venue 一筆都不動（計畫裡 `repaired == nil`）。
extension AkashicService {

    public func repairVenueNames(apply: Bool) throws -> VenueNameRepairReport {
        let load = try store.load()
        let plans = load.venues.sorted { $0.key < $1.key }.compactMap(VenueNameRepair.plan)
        let targets = plans.compactMap(\.repaired)
        var refusal: String?
        do {
            try assertVenueNameRepairWritable(targets)
        } catch {
            if apply { throw error }
            refusal = displaySafeError(error, max: 4_096)
        }
        guard apply, !targets.isEmpty else {
            return VenueNameRepairReport(plans: plans, scanned: load.venues.count, quarantined: load.quarantined.count,
                                         applied: false, applyRefusal: refusal)
        }
        for v in targets { try store.writeVenue(v) }
        try LibraryIndex(store: store).rebuild()
        return VenueNameRepairReport(plans: plans, scanned: load.venues.count, quarantined: load.quarantined.count,
                                     applied: true, applyRefusal: nil)
    }

    /// 寫入前的兩道閘，乾跑與實跑共用：先 `writeVenue` 的全部前置（`preflightWrite`），再 git 可回溯閘。
    private func assertVenueNameRepairWritable(_ targets: [Venue]) throws {
        guard !targets.isEmpty else { return }
        // `preflightWrite`＝`writeVenue` 在寫入當下跑的每一道（store root、format 閘、validate、#648 的 encode 與位元組上限、
        // #631 的目的檔檢查），不寫。先前這裡手寫了其中兩道（`assertVenueWritable`＋不帶 `replacing:` 的 encode），
        // 少了目的檔檢查——那一道擲錯時前面幾筆已經落盤（#575 C2a verify）。
        for v in targets {
            do {
                try store.preflightWrite(v)
            } catch {
                throw ServiceError.invalid(
                    "venue「\(displaySafeInvisible(v.key, max: 200))」改寫之後過不了寫入閘：\(displaySafeError(error, max: 2_000))"
                    + "——整批拒絕、零寫入（#575）")
            }
        }
        try assertRecordsRecoverable(targets.map { ($0.id, "venue「\(displaySafeInvisible($0.key, max: 200))」") },
                                     action: "這次會改寫 \(targets.count) 筆 venue 的名字",   // display-safe-exempt: targets.count 是 Int
                                     issue: "#575")
    }
}
