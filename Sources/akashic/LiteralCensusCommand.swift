import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

/// `akashic literal-census`：四域 literal 普查（#303 D5；#629 由 `literal-census.sh` 移植）。
///
/// literal 歸零 campaign（`akashic-promote-literals` skill）每輪開場與收尾各跑一次，落一筆進度。
/// 計數語意與輸出格式見 `LiteralCensus`（AkashicStoreIO）。
///
/// **唯讀、且不經 `openStore()`**：普查要能對讀端拒開的 store（版號太新、marker 壞掉）照樣印出計數——
/// 那正是它要標「這一輪的數字不能拿去定批次範圍」的情形。所以這裡只解析 store root
/// （`LibraryOptions.resolved()`，不檢查版號），marker 由 `StoreVersion.read` 自己判。
///
/// exit code：0 印出報告（含 ⚠ 全域警告的情形——警告是報告的一部分，不是失敗）；
/// 2 不是 Akashic store；3 掃不下去（`entities/` 非空但沒有 `.yaml`、或某個記錄檔讀不進來）。
struct LiteralCensusCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "literal-census",
        abstract: "四域 literal 普查（author／venue／affiliation／org-parents）——literal 歸零 campaign 的進度量測（唯讀）")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let root = try options.resolved().root.path
        let report: LiteralCensus.Report
        do {
            report = try LiteralCensus.run(root: root)
        } catch let failure as LiteralCensus.Failure {
            FileHandle.standardError.write(Data((failure.message + "\n").utf8))
            throw ExitCode(failure.exitCode)
        }
        // 路徑縮成 ~ 形式再消毒：輸出會被貼進 issue，不印使用者名。
        let shown = displaySafeInvisible(LiteralCensus.tilde(root), max: 300)
        for line in LiteralCensus.render(report, displayRoot: shown) { print(line) }   // display-safe-exempt: line：整行由 render 組成；store 內容只有 marker 的問題行（已過 displaySafeInvisible）與路徑（上一行已消毒），計數是整數
    }
}
