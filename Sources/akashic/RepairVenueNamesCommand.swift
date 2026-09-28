import ArgumentParser
import Foundation
import AkashicMCPKit
import AkashicCore
import AkashicStoreIO

/// venue 名字不變式的機械修復面（#575，使用者 2026-09-28 裁決）。
///
/// 乾跑是預設：逐筆列出「venue／清單[index]：before → after」與要人判斷的項目；`--apply` 才改寫。只改確定性的那一類——
/// 字串只違反 canonical 形、正規化之後合法、改完整筆記錄通過 `validate()`（判準見 `VenueNameRepair` 的檔頭）；其餘只具名。
/// 維運例外（同 `fmt`／`migrate` 族，`mcp-cli-parity` 的 CLI-only 表）：沒有 MCP 面。
struct RepairVenueNames: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repair-venue-names",
        abstract: "修 venue 名字的 canonical 形（#575）：乾跑列出確定性改寫與要人判斷的項目，--apply 才寫（要求那些 venue 檔已 commit；任一筆寫入閘會拒就整批零寫入）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際改寫（預設只列出）。只改確定性的那一類；要人判斷的一筆都不動。寫入前要求那些 venue 檔已在 git 裡 commit、乾淨")
    var apply = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**——乾跑不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("repair-venue-names") }
        let store = try options.openStore()
        print("目標 store：\(displaySafeInvisible(store.root.path, max: 300))")
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let report = try service.repairVenueNames(apply: apply)
        Self.render(report, applyRequested: apply)
    }

    /// 要人判斷的項目每筆 venue 最多列幾項（同 `validate()` 的每筆記錄上限）；確定性改寫**不截**——要套用的每一筆都得看得到。
    static let judgmentsPerVenue = Entry.perRecordWarningCap

    static func render(_ report: VenueNameRepairReport, applyRequested: Bool) {
        let applicable = report.applicable
        let pending = report.needsJudgment
        // 帶了 --apply 而沒有可確定性改寫的項目時 service 不寫任何東西——標頭不得說「乾跑」（那不是呼叫者要的），也不得說「已寫入」
        print(report.applied ? "venue 名字修復（#575）——已寫入"
              : applyRequested ? "venue 名字修復（#575）——--apply：沒有可確定性改寫的項目，store 沒有被改動"
              : "venue 名字修復（#575）——乾跑，store 沒有被改動")
        // 讀不進來的檔不在走訪範圍：「沒有違反」只對走訪過的那幾筆成立（zero-instance-guards 第 3 列）
        if report.quarantined > 0 {
            print("另有 \(report.quarantined) 個記錄檔讀不進來（quarantine），不在走訪範圍內——akashic validate 逐檔列出")
        }
        guard !report.plans.isEmpty else {
            print("走訪 \(report.scanned) 筆 venue：名字內容沒有違反，無事可做")
            return
        }
        let count = applicable.reduce(0) { $0 + $1.rewrites.count }
        print("")
        print("\(report.applied ? "已改寫" : "確定性改寫")：\(count) 筆，涉及 \(applicable.count) 筆 venue（走訪 \(report.scanned) 筆）")
        for p in applicable {
            for r in p.rewrites { print("  " + line(p, r)) }
        }
        if !pending.isEmpty {
            print("")
            print("要人判斷、本命令一筆都不改：\(pending.count) 筆 venue（修法見理由；手改 YAML 之後再跑一次）")
            for p in pending {
                print("  \(displaySafeInvisible(p.key, max: 200))")
                for j in p.judgments.prefix(judgmentsPerVenue) {
                    switch j.subject {
                    case .value(let list, let index, let value):
                        print("    \(list)[\(index)]「\(displaySafeInvisible(value, max: 200))」：\(displaySafeClipOnly(j.reason, max: 4_096))")   // display-safe-exempt: reason 是 NameIdentity 的固定訊息或本 package 的固定句（已消毒），只截；list 是字面清單名、index 是 Int
                    case .record:
                        print("    記錄：\(displaySafeClipOnly(j.reason, max: 4_096))")   // display-safe-exempt: reason 是 validate() 的訊息（生產端已逐項 displaySafeInvisible）或本 package 的固定句，只截
                    }
                }
                if p.judgments.count > judgmentsPerVenue {
                    print("    …另有 \(p.judgments.count - judgmentsPerVenue) 項未列出")
                }
                if !p.rewrites.isEmpty {
                    print("    這筆另有 \(p.rewrites.count) 個確定性改寫，要等上面各項處理完才會套用（記錄還有 error 就寫不進去）：")
                    for r in p.rewrites.prefix(judgmentsPerVenue) { print("      " + line(p, r)) }
                    if p.rewrites.count > judgmentsPerVenue {
                        print("      …另有 \(p.rewrites.count - judgmentsPerVenue) 個未列出")
                    }
                }
            }
        }
        if let refusal = report.applyRefusal, !applicable.isEmpty {
            print("")
            print("--apply 會整批拒絕、零寫入：\(displaySafeClipOnly(refusal, max: 4_096))")   // display-safe-exempt: refusal 由 displaySafeError 產出（已消毒），只截
        }
        print("")
        if report.applied {
            print("接下來：`akashic validate` 確認名字內容的 error 只剩上面要人判斷的那些，然後 commit。")
        } else if !applicable.isEmpty {
            print("確認以上改寫無誤後加 --apply（寫入前要求那些 venue 檔已在 git 裡 commit、乾淨）。")
        }
    }

    /// 一筆改寫的一行：venue key、清單[index]、before → after、改了什麼。NFD → NFC 的兩個字串在終端機上看起來一樣，所以改動說明必印。
    static func line(_ p: VenueNameRepair.Plan, _ r: VenueNameRepair.Rewrite) -> String {
        "\(displaySafeInvisible(p.key, max: 200))  \(r.list)[\(r.index)]  「\(displaySafeInvisible(r.before, max: 200))」 → 「\(displaySafeInvisible(r.after, max: 200))」（\(r.changes.joined(separator: "、"))）"   // display-safe-exempt: list 是字面清單名、index 是 Int、changes 是本 package 的固定句
    }
}
