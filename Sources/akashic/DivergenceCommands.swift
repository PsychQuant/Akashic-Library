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
    /// #75 對一：記錄的判斷傾向另一個候選時，消歧拒絕——除非明說原判斷錯在哪。
    @Option(name: .long, help: "覆寫記錄的判斷傾向（prefers）時，說明為什麼原判斷不成立")
    var overrideReason: String?

    func run() throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("『\(displaySafe(id, max: 200))』不是合法的 UUID")
        }
        let store = try options.openStore()
        if dryRun {   // #78-2：消歧會連帶刪除使用者沒指名的塌縮記錄——要能先看
            // #159 verify 159-1：**必須把 overrideReason 一起傳**。少傳時 preview
            // 吃到 nil → dry-run 擲 contradictsJudgement 而實跑成功，方向還是壞的
            // 那個（謹慎的人被擋、直接做的人通過）。
            let preview = try store.previewResolveDivergence(
                id: uuid, survivor: survivor, overrideReason: overrideReason)
            print("dry-run（不動任何檔案）：")
            print("  併入 \(displaySafe(survivor, max: 200))：" +
                  preview.merged.map { displaySafe($0, max: 200) }.joined(separator: "、"))
            if !preview.rewritten.isEmpty {
                print("  參照將改寫：\(preview.rewritten.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
            }
            for c in preview.collapsedDetails {
                print("  ⚠ 連帶刪除（候選塌縮）：\(c.id)——「\(displaySafe(c.question, max: 300))」")
            }
            // #467：verdict 面的預告。**dry-run 有自己的渲染路徑**，所以 preview 補上
            // 這兩個欄位之後，這裡不接就等於沒補——使用者看到的仍然是沉默的那一份。
            if !preview.verdictValuesRewritten.isEmpty {
                print("  verdict value 將隨 holder 退役改寫（持有記錄）："
                    + preview.verdictValuesRewritten.map(\.describedSafely).joined(separator: ", "))   // display-safe-exempt: 消毒在 HolderRecord.describedSafely 內
            }
            if !preview.verdictsCollapsed.isEmpty {
                print("  ⚠ verdict 將收攏丟棄 \(preview.verdictsCollapsed.count) 筆"
                    + "（與倖存者既有的或遷移輸出同一配對——正規化後相等，留一筆）：")
                // 逐列以性質逃脫、上限 1,000（各段已在來源逐段截；R13 verify security 第 24 列、requirements 第 19 列）
                for c in preview.verdictsCollapsed { print("      · \(displaySafeInvisible(c, max: 1_000))") }
            }
            if !preview.quarantinedNotScanned.isEmpty {   // #497：未掃描不得看起來像掃過且沒有
                print("  ⚠ \(preview.quarantinedNotScanned.count) 個 quarantine 檔未掃描——"
                    + "其中若有 verdict 指向被併鍵，不會被遷移")
            }
            // #159 verify 159-5：warning 在 dry-run 也要印。「有判斷但無 prefers、
            // 無從機械核對」正是人最需要在按下破壞性合併之前看到的一條——先前
            // 只有實跑會印，等於在唯一還能反悔的時點沉默。
            for w in preview.warnings { print("  ⚠ \(w)") }
            return
        }
        let report = try store.resolveDivergence(id: uuid, survivor: survivor,
                                                 overrideReason: overrideReason)

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
            rebuildError = displaySafeError(error, max: 512)
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
        // #271：判定史的遷移要說出來——靜默搬移與靜默丟棄一樣不可稽核
        if !report.verdictReferencesMigrated.isEmpty {
            print("verdict 已隨合併遷移到倖存者：\(report.verdictReferencesMigrated.count) 筆"
                + "（\(report.verdictReferencesMigrated.map { displaySafe($0, max: 200) }.joined(separator: "；"))）")
        }
        if !report.verdictValuesRewritten.isEmpty {
            // **#498 起清單帶 kind**（`HolderRecord`）——這段先前寫著「使用者面不標 kind…
            // 扁平清單不帶 kind 的既有缺口」，那個缺口已經修掉了。跨型別同名鍵實測 2 個，
            // 而扁平清單在那時一個字串對應兩筆記錄。
            print("verdict value 已隨 holder 退役改寫（持有記錄 key）："
                + report.verdictValuesRewritten.map(\.describedSafely).joined(separator: ", "))   // display-safe-exempt: 消毒在 HolderRecord.describedSafely 內
        }
        if !report.quarantinedNotScanned.isEmpty {   // #497：未掃描不得看起來像掃過且沒有
            print("⚠ \(report.quarantinedNotScanned.count) 個 quarantine 檔未掃描——"
                  + "其中若有 verdict 指向被併鍵，不會被遷移：")
            for f in report.quarantinedNotScanned { print("  · \(displaySafe(f, max: 300))") }
        }
        if !report.verdictsCollapsed.isEmpty {   // #461：收攏丟列要說出來——靜默丟棄不可稽核
            // 兩類內容（R13 verify regression 第 28 列）：holder 遷移的收攏（與遷移輸出同鍵）、#271 的去重（與倖存者既有的同鍵）——
            // 鍵都是 `verdictEqualityKey`（正規化 literal），不是 (field, value)
            print("verdict 收攏丟棄 \(report.verdictsCollapsed.count) 筆（與倖存者既有的或遷移輸出同一配對——正規化後相等，留一筆）：")
            for c in report.verdictsCollapsed { print("  · \(displaySafeInvisible(c, max: 1_000))") }
        }
        for w in report.warnings {   // #75 對一：不擋但要說
            print("  ⚠ \(w)")
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
