import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

/// `akashic scan-yaml-profile`：統計 store YAML profile 外的語法用了多少（開發用；#629 由 `scripts/scan-yaml-profile.py` 移植）。
///
/// #33（store YAML 輸入 profile）的證據來源——「真實 corpus 遷移成本為零」那張表由它產出，放進 repo 是為了讓結論
/// 可重跑、可核對。掃描語意與輸出見 `YAMLProfileScan`（AkashicCore）。**唯讀、不經 `openStore()`**：要能掃讀端拒開的 store。
struct ScanYAMLProfileCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan-yaml-profile",
        abstract: "（開發用）統計 store 的 YAML 檔用了多少 profile 外的語法——#33 的證據來源，唯讀")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "額外印出每個 anchor／inline comment regex 命中的實際文字，用來人工判斷是不是 false positive")
    var inspect = false

    func run() throws {
        let root = try options.resolved().root.path
        var result: YAMLProfileScan.Result
        do { result = try YAMLProfileScan.scan(root: root, inspect: inspect) } catch let failure as YAMLProfileScan.Failure {
            throw RuntimeFailure.state(failure.message)   // display-safe-exempt: failure：message 在 Failure 內已逐項 displaySafeInvisible
        }
        // 路徑縮成 `~` 形式：輸出會被貼進 issue（#33 的證據表），不印使用者名——與 `literal-census` 同一條紀律（R1 verify 第 52 則）
        result.root = LiteralCensus.tilde(root)
        for line in YAMLProfileScan.render(result, inspect: inspect) { print(line) }   // display-safe-exempt: line：整行由 render 組成；檔名、路徑與行內容在 render 內逐項過 displaySafeInvisible
        // 空集合不得冒充通過：零個 .yaml 印出的全零表與「corpus 乾淨」長得一樣，而它多半是路徑指錯了
        if result.files.isEmpty {
            FileHandle.standardError.write(Data("✗ 沒有掃到任何 .yaml 檔——上面的全零不是「corpus 乾淨」，是沒有東西可掃（路徑對嗎？）\n".utf8))
            throw ExitCode(3)
        }
    }
}
