import Foundation
import ArgumentParser
import AkashicCore
import AkashicStoreIO

/// `akashic fmt` — 把記錄重寫為 canonical form（#69）。
///
/// canonical form 一直存在（三個 `encode` 函式就是它的定義），缺的只是**讓 encoder
/// 以外的人也能用**的入口。外部寫入者（storyline 的 R pipeline、手寫記錄、#64 的 CV
/// 補完流程、#68 的部分更新入口）不必各自重製排序與引號規則。
///
/// **`validate` 不擋排版，`fmt --check` 才擋**（design D5）。`Validate` 的失敗條件是
/// quarantine 與 `.error` severity——兩者都是資料正確性，而排版偏離不是。若 `validate`
/// 擋排版，外部 pipeline 每次寫完都得先跑 `fmt` 才過驗證，摩擦大到會讓人繞過 `validate`
/// 本身。`--check` 的語意與 `swift format --lint` 一致，給 CI 與 pipeline 當明確關卡。
struct Fmt: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fmt",
        abstract: "把記錄重寫為 canonical form（#69）；--check 只回報不寫檔")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "只回報偏離並以非零碼退出，不寫任何檔案")
    var check: Bool = false

    func run() throws {
        let store = try options.openStore()
        let r = try CanonicalFormat.scan(store: store, apply: !check)

        print("走訪 \(r.scanned) 筆記錄")
        if r.deviating.isEmpty && r.failures.isEmpty {
            print("✓ 全部已是 canonical form")
        } else if r.deviating.isEmpty {
            // 失敗的檔根本沒進比對集合——「全部」只能對被檢查過的說（#554 R6 verify 第 43 列，
            // `zero-instance-guards` 第 3 列「未涵蓋不得冒充通過」的形狀）
            // failures 混兩種來源（讀不到、`normalized()` 擲錯——含 validate 報 error 被拒），「未檢查」對第二種為假（R13 verify logic
            // 第 23 列）：說「未通過比對」並列出兩種。「寫不回去」在這個分支不可達——它只在 `deviating` 非空之後才可能被附加
            // （R17 verify logic 第 26 列：把一個不可能的原因列進封閉的三選一）
            print("✓ \(r.scanned - r.failures.count) 筆已是 canonical form；\(r.failures.count) 筆未通過（讀不到或 validate 拒絕——見下，逐檔具名）")   // display-safe-exempt: Int
        } else {
            print("偏離 canonical form: \(r.deviating.count) 筆")
            for f in r.deviating.prefix(20) { print("  - \(displaySafeInvisible(f, max: 200))") }
            if r.deviating.count > 20 { print("  …（共 \(r.deviating.count) 筆）") }
        }
        if !r.rewritten.isEmpty { print("已改寫 \(r.rewritten.count) 筆") }
        if check, !r.deviating.isEmpty {
            print("（--check：未寫任何檔案。去掉 --check 即可對齊）")
        }
        if !r.failures.isEmpty {
            print("失敗 \(r.failures.count) 筆（其餘記錄仍已處理完）：")
            for f in r.failures.prefix(10) {
                print("  ! \(displaySafeInvisible(f.file, max: 200))：\(displaySafeClipOnly(f.reason, max: 300))")   // display-safe-exempt: reason 已消毒（CanonicalFormat.describe → displaySafeError，R28 D80），只截——R27 verify 第 5／12／14 列的第三層
            }
            if r.failures.count > 10 { print("  …（共 \(r.failures.count) 筆）") }
        }

        // 偏離也算問題——`--check` 的用途正是當關卡。無 `--check` 時偏離已被改寫，
        // 此時仍非零退出只會讓「跑一次 fmt」這件正常操作看起來像失敗。
        if !r.failures.isEmpty || (check && !r.deviating.isEmpty) {
            throw ExitCode.failure
        }
    }
}
