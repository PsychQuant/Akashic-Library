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

    func run() throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("『\(displaySafe(id, max: 200))』不是合法的 UUID")
        }
        let store = try options.openStore()
        let report = try store.resolveDivergence(id: uuid, survivor: survivor)

        // **報告先印，索引後建。** 消歧是破壞性操作；rebuild 擲錯會把「哪些改了、
        // 哪些沒改、什麼被刪了」整份吞掉，而那是使用者唯一能據以收拾的東西。
        // rebuild 失敗只是索引過期（可重建），報告遺失才是不可回復的。
        defer {
            do {
                _ = try LibraryIndex(store: store).rebuild()
            } catch {
                print("⚠ 索引重建失敗（資料已改，索引過期）："
                    + displaySafe((error as? LocalizedError)?.errorDescription
                                  ?? String(describing: error), max: 512))
                print("  跑 akashic doctor 重建索引。")
            }
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
        guard !report.hasFailures else {
            for f in report.failures { print("✗ \(displaySafe(f, max: 512))") }
            // 非零退出（design「失敗模式」最後一列）：沒有任何 run 該在
            // 「一部分參照改了、一部分沒改、而且什麼都沒說」的狀態下宣告成功。
            throw ExitCode.failure
        }
    }
}
