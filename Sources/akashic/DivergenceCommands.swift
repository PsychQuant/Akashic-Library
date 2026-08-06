import ArgumentParser
import Foundation
import AkashicCore
import AkashicIndex
import AkashicStoreIO

/// 消歧：把一筆歧異記錄的候選合併到指定的倖存者，並刪除記錄與被併實體。
///
/// **不提供「只刪記錄」的旗標。** 刪掉記錄卻不改寫參照，留下的是指向不存在鍵的
/// 引用——spec 明文拒絕提供那個操作。要放棄一筆歧異只有兩條路：消歧掉它，或手動
/// 編輯該檔（那時是人自己在承擔後果，不是工具替他做）。
struct ResolveDivergence: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-divergence",
        abstract: "消歧：合併別名 + 全庫參照重寫 + 刪除被併記錄與歧異記錄")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "歧異記錄的 id（UUID）") var id: String
    @Option(name: .long, help: "倖存者的鍵，必須是該記錄的候選之一") var survivor: String
    @Flag(name: .long, help: "只預告會做什麼（含連帶塌縮刪除的記錄），不動任何檔案")
    var dryRun: Bool = false

    func run() throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("『\(displaySafe(id, max: 200))』不是合法的 UUID")
        }
        let store = try options.openStore()
        if dryRun {   // #78-2：消歧會連帶刪除使用者沒指名的塌縮記錄——要能先看
            let preview = try store.previewResolveDivergence(id: uuid, survivor: survivor)
            print("dry-run（不動任何檔案）：")
            print("  併入 \(displaySafe(survivor, max: 200))：" +
                  preview.merged.map { displaySafe($0, max: 200) }.joined(separator: "、"))
            if !preview.rewritten.isEmpty {
                print("  參照將改寫：\(preview.rewritten.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
            }
            for c in preview.collapsedDetails {
                print("  ⚠ 連帶刪除（候選塌縮）：\(c.id)——「\(displaySafe(c.question, max: 300))」")
            }
            return
        }
        let report = try store.resolveDivergence(id: uuid, survivor: survivor)

        // **報告先印，索引後建，退出碼最後決定。** 消歧是破壞性操作；rebuild 擲錯會把
        // 「哪些改了、什麼被刪了」整份吞掉，而那是使用者唯一能據以收拾的東西。
        //
        // **刻意不用 `defer`**：`defer` 拿得到「報告先印」，卻在結構上改不了退出碼——
        // rebuild 失敗會變成 exit 0，而 `resolve-divergence … && <下一步>` 會照跑。
        // 索引過期可重建，但**靜默宣告成功**不行。所以把結果收進變數，最後一起判。
        var rebuildError: String?
        do {
            _ = try LibraryIndex(store: store).rebuild()
        } catch {
            rebuildError = displaySafe((error as? LocalizedError)?.errorDescription
                                       ?? String(describing: error), max: 512)
        }

        if !report.merged.isEmpty {
            print("✓ 併入 \(displaySafe(survivor, max: 200))："
                + report.merged.map { displaySafe($0, max: 200) }.joined(separator: "、"))
        }
        if !report.rewritten.isEmpty {
            print("參照已改寫：\(report.rewritten.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
        }
        if !report.removedDivergences.isEmpty {
            print("已刪除歧異記錄：\(report.removedDivergences.joined(separator: ", "))")
        }
        for c in report.collapsedDetails {   // #78-2：被連帶刪的是哪個問題，說出來
            print("  ⚠ 其中 \(c.id) 是候選塌縮的連帶刪除——「\(displaySafe(c.question, max: 300))」")
        }
        if report.hasFailures && report.survivorUpdated {
            FileHandle.standardError.write(Data(
                "⚠ 倖存者「\(displaySafe(survivor, max: 200))」已被改寫——磁碟上不是原狀\n".utf8))
        }
        for f in report.failures { FileHandle.standardError.write(Data("✗ \(displaySafe(f, max: 512))\n".utf8)) }
        if let rebuildError {
            FileHandle.standardError.write(Data(
                ("⚠ 索引重建失敗（資料已改，索引過期）：\(rebuildError)\n"
                 + "  跑 akashic doctor 重建索引。\n").utf8))
        }
        // 非零退出（design「失敗模式」最後一列）：沒有任何 run 該在
        // 「一部分參照改了、一部分沒改、而且什麼都沒說」的狀態下宣告成功。
        // 索引重建失敗同樣算——那時查詢面與資料面已經不一致。
        if report.hasFailures || rebuildError != nil {
            throw ExitCode.failure
        }
    }
}
