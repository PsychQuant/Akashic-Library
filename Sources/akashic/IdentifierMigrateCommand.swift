import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

/// `Entry.fields` 的識別碼殘留 → 結構化欄位；work 的 `issn` → 它的 venue（#394 §8）。
///
/// 形狀比照 `migrate-venues`：預設乾跑、`--apply` 才寫入、只改寫 git 追蹤中的檔、
/// **不自動 bump format**（bump 是人工的最後一步，見 design.md 的部署順序）。
struct MigrateIdentifiers: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate-identifiers",
        abstract: "識別碼自 fields 升格為結構化欄位；work 的 issn 移位至 venue（預設乾跑）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只預演；只改寫 git 追蹤中的檔）")
    var apply = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——乾跑不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("migrate-identifiers") }
        let store = try options.openStore()
        let report = try IdentifierMigration.run(store: store, apply: apply)
        let prefix = apply ? "✓" : "（dry-run）"

        print("\(prefix) \(apply ? "已改動" : "將改動") \(report.plans.count) 筆 work、"
              + "\(report.identifierCount) 個識別碼；venue 落點 \(report.venuePlans.count) 個")

        if !report.plans.isEmpty {
            print("\n── work 側 ──")
            for p in report.plans {
                print("  \(displaySafe(p.citekey, max: 200))")
                for c in p.changes { print("      \(displaySafe(c, max: 400))") }
            }
        }
        if !report.venuePlans.isEmpty {
            // **「去重後合併」與「保留多值」分開列**（task 8.2）——前者是異寫法收斂，
            // 後者是 print／electronic 兩個真的號，人要分辨得出來。
            print("\n── venue 側：去重後合併為單值 ──")
            for v in report.venuePlans where !v.keptMultiple {
                print("  \(v.venueKey): \(v.values.joined(separator: "、"))"
                      + "   ← 來源 \(v.mergedFrom.joined(separator: " ｜ "))")
            }
            print("\n── venue 側：保留多值（print／electronic 是兩個真的號）──")
            for v in report.venuePlans where v.keptMultiple {
                print("  \(v.venueKey): \(v.values.joined(separator: "、"))"
                      + "   ← 來源 \(v.mergedFrom.joined(separator: " ｜ "))")
            }
        }
        if !report.skipped.isEmpty {
            print("\n── 略過（不猜、不丟棄，原值留在 fields）──")
            for s in report.skipped {
                print("  \(displaySafe(s.citekey, max: 200)) [\(s.field)] "
                      + "「\(displaySafe(s.value, max: 120))」")   // display-safe-exempt: field 值域是 workIdentifierKeys 封閉集合
                print("      \(displaySafe(s.reason, max: 800))")
            }
        }
        if !report.shapeUpgraded.isEmpty {
            print("\n── 形狀升級（format 12 → 13）：\(report.shapeUpgraded.count) 檔 ──")
            print("  `issn`／`isbn` 序列的裸純量元素改寫為 `- value: …`。"
                  + "舊形狀在新解碼器下是整檔 quarantine，所以這一步必須先跑。")
        }
        if !report.discardedAnnotations.isEmpty {
            print("\n── 被剝掉的括號註記（\(report.discardedAnnotations.count) 筆）──")
            print("  這些是有書目語意的 qualifier，不是雜訊；現行模型沒有欄位存它們。")
            print("  剝掉是為了讓值解析得出來——但 lossless-intake 要求丟棄必須可見。")
            for a in report.discardedAnnotations {
                print("  \(displaySafe(a.citekey, max: 200)) [\(a.field)] "   // display-safe-exempt: field 值域是 workIdentifierKeys 封閉集合
                      + "「\(displaySafe(a.raw, max: 200))」")
                print("      丟棄：\(a.annotations.map { displaySafe($0, max: 60) }.joined(separator: "、"))")
            }
        }
        print("\n── provenance value 改寫：\(report.provenanceRewrites.count) 筆 ──")
        if report.provenanceRewrites.isEmpty {
            print("  （零實例是預期的：Entry.references 是本 change 新增、全庫為空；"
                  + "venue 的 issn reference 需要 format 13 才寫得進去，而 store 仍是 12）")
        }
        if !report.blockers.isEmpty {
            print(apply ? "\n── 已擋下（未寫入）──"
                        : "\n── 會被擋下（--apply 時這些不會寫入）──")
            for f in report.blockers { print("  \(f)") }
            // **乾跑不 exit 1**：乾跑本身成功了，它的工作就是把這些顯示出來。
            // apply 才是錯誤——有東西沒搬成，使用者必須知道。
            if apply { throw ExitCode(1) }
        }
        if !apply {
            print("\n這是乾跑，store 沒有被改動。確認以上處置無誤後加 --apply。")
            print("**--apply 不會改 store.yaml 的 format**——那是驗證之後的人工最後一步。")
        }
    }
}
