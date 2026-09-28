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
        guard FileManager.default.fileExists(atPath: root) else {
            throw RuntimeFailure.state("✗ \(displaySafeInvisible(root, max: 300)) 不存在")
        }
        let result = try YAMLProfileScan.scan(root: root, inspect: inspect)
        for line in YAMLProfileScan.render(result, inspect: inspect) { print(line) }   // display-safe-exempt: line：整行由 render 組成；檔名、路徑與行內容在 render 內逐項過 displaySafeInvisible
    }
}
