import ArgumentParser
import Foundation
import AkashicCore
import AkashicMCPKit
import AkashicStoreIO
import AkashicZoteroImport

/// 把 Zotero 的附件檔複製進 Akashic 自己的 `sources/`，並連到那筆 work 的 `akashic.sources`（#606）。
///
/// 為日後切斷 Zotero 鋪路（#605 的 sibling concern）：附件記錄只存 `zotero: storage/...` 相對路徑，PDF 本體只在 Zotero 那邊——停用 `import-zotero`
/// 或清理 Zotero 之後這些附件就會失聯。本命令不動 `attachments`（Zotero 擁有的區塊，pull 會還原它；它同時是這份副本的來源記錄），只**追加** `akashic.sources`
/// 的 digest 並把位元組存進內容定址區。設計理由、契約與誠實邊界在 `AkashicService.copyZoteroAttachments` 的型別 doc。
///
/// 乾跑是預設；`--apply` 才寫（要求被改寫的 work 檔已在 git 裡 commit、乾淨，且 `sources/` 已被版控排除——後者是第三方版權位元組不得進 remote 的承重閘）。
/// 只有 CLI 面：批次、操作者規模、讀本機 Zotero 資料目錄（`mcp-cli-parity` 的 CLI-only 表）。
struct CopyZoteroAttachments: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy-zotero-attachments",
        abstract: "把 Zotero 附件檔複製進 sources/ 並連到 work 的 akashic.sources（乾跑預設，--apply 才寫；要求被改的 work 檔已 commit；#606）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）；它所在的目錄要是 Zotero 資料目錄（附件在它的 storage/ 底下）")
    var zoteroDb: String = "~/Zotero/zotero.sqlite"

    @Option(name: .long, help: "只處理這些 citekeys（逗號分隔）；省略＝store 裡全部帶 zotero 附件記錄的 work")
    var citekeys: String?

    @Flag(name: .long, help: "實際複製並寫入（預設只列出計畫）。寫入前要求被改寫的 work 檔已在 git 裡 commit、乾淨，且 sources/ 已被版控排除；任何一道過不了就整批零寫入")
    var apply = false

    /// `--citekeys` 切開後的清單（空段丟掉）——`validate()` 與 `run()` 讀同一個。
    private var citekeyList: [String]? {
        citekeys.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    }

    /// 只看 argv，所以在 `validate()`：早於目標確認閘與開 store（#654）。
    func validate() throws {
        if let list = citekeyList, list.isEmpty {
            throw ValidationError("--citekeys 給了但沒有任何 citekey——要處理全部就省略這個旗標")
        }
    }

    func run() throws {
        // #298：實跑會寫 store（存檔＋改寫記錄）——先確認目標 store 已被指名。乾跑不閘（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("copy-zotero-attachments") }
        let store = try options.openStore()
        print("目標 store：\(displaySafeInvisible(store.root.path, max: 300))")
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let report = try service.copyZoteroAttachments(zoteroDb: zoteroDb, citekeys: citekeyList, apply: apply)
        Self.render(report, applyRequested: apply)
        // 有單筆寫入失敗仍以非零退出（收容不是吞掉——自動化才看得到，`import-zotero` 的同一條）
        if !report.writeFailed.isEmpty { throw ExitCode(1) }
    }

    static func render(_ r: ZoteroAttachmentCopyReport, applyRequested: Bool) {
        print(r.applied ? "Zotero 附件複製（#606）——已寫入"
              : applyRequested ? "Zotero 附件複製（#606）——--apply：沒有新東西要複製，store 沒有被改動"
              : "Zotero 附件複製（#606）——乾跑，store 沒有被改動")
        print("帶 zotero 附件記錄的 work：\(r.considered)；\(r.applied ? "已複製" : "要複製")：\(r.planned.count) 個檔；已連過：\(r.alreadyLinked.count)；略過：\(r.skipped.count)")
        for item in r.planned {
            print("  \(displaySafeInvisible(item.citekey, max: 200))  \(displaySafeInvisible(item.path, max: 300))  \(item.bytes) bytes  \(displaySafeInvisible(item.mediaType, max: 100))  \(item.digest)")   // display-safe-exempt: bytes 是 Int；digest 是本 binary 算的 SHA-256 十六進位
        }
        if !r.skipped.isEmpty {
            print("")
            print("略過（本命令不動這些附件；原因見各行）：")
            for s in r.skipped.prefix(Entry.perRecordWarningCap * 5) {
                print("  \(displaySafeInvisible(s.citekey, max: 200))  \(displaySafeInvisible(s.path, max: 300))：\(reasonText(s.reason))")   // display-safe-exempt: reasonText(s.reason)、s.reason：s.reason 是本 package 的封閉列舉、reasonText 只回本檔的固定句（其中的 kind 已 displaySafeInvisible）
            }
            if r.skipped.count > Entry.perRecordWarningCap * 5 {
                print("  …另有 \(r.skipped.count - Entry.perRecordWarningCap * 5) 個未列出")   // display-safe-exempt: Int
            }
        }
        if !r.unlocatable.isEmpty {
            print("")
            print("無法唯一定位（\(UnlocatableReason.work)）——本趟不碰：\(r.unlocatable.map { displaySafeInvisible($0, max: 200) }.joined(separator: ", "))")
        }
        if !r.notInStore.isEmpty {
            print("--citekeys 點名、store 裡沒有：\(r.notInStore.map { displaySafeInvisible($0, max: 200) }.joined(separator: ", "))")
        }
        if !r.noZoteroAttachments.isEmpty {
            print("--citekeys 點名、沒有 zotero 附件記錄：\(r.noZoteroAttachments.map { displaySafeInvisible($0, max: 200) }.joined(separator: ", "))")
        }
        if r.applied {
            print("")
            print("已改寫 \(r.written.count) 筆 work 的 akashic.sources；\(r.blobsAlreadyStored) 個檔的位元組早就在 sources/（不重複寫）")   // display-safe-exempt: Int
            switch r.exclusionVerified {
            case .some(true): print("sources/ 的版控排除已驗證")
            case .some(false): print("⚠ store 不在 git 裡：sources/ 的版控排除沒有驗證——確認它不會被推上 remote")
            case .none: break
            }
        }
        if !r.writeFailed.isEmpty {
            print("")
            print("write failed（單筆失敗，已略過續跑；重跑會補上）: \(r.writeFailed.count)")   // display-safe-exempt: Int
            for key in r.writeFailed.keys.sorted() {
                print("  ✗ \(displaySafeInvisible(key, max: 200)) — \(displaySafeClipOnly(r.writeFailed[key]!, max: 4_096))")   // display-safe-exempt: 已消毒（service 以 displaySafeError 產出），只截
            }
        }
        if let why = r.indexRebuildFailure {
            print("⚠ index rebuild 失敗（記錄與存檔都已落地）：\(displaySafeClipOnly(why, max: 1_024))；跑 `akashic doctor` 重建")   // display-safe-exempt: 已消毒（service 以 displaySafeError 產出），只截
        }
        if let refusal = r.applyRefusal {
            print("")
            print("--apply 會整批拒絕、零寫入：\(displaySafeClipOnly(refusal, max: 4_096))")   // display-safe-exempt: 已消毒（service 以 displaySafeError 產出），只截
        }
        print("")
        if r.applied {
            print("接下來：`akashic validate` 確認，然後 commit。連錯的副本宣告用 `update-entry <citekey> --remove-source <digest>=理由` 收回。")
        } else if !r.planned.isEmpty {
            print("確認以上無誤後加 --apply（要求被改寫的 work 檔已在 git 裡 commit、乾淨，且 sources/ 已被版控排除）。")
        }
    }

    private static func reasonText(_ reason: ZoteroAttachmentCopyReport.SkipReason) -> String {
        switch reason {
        case .file(.badPath): return "路徑不是 storage/<KEY>/<檔名>"
        case .file(.missing): return "Zotero 資料目錄裡沒有這個檔（沒同步、被刪、或這個 KEY 不在這台機器上）"
        case .file(.outsideStorage): return "真實位置在 storage/ 之外（KEY 目錄是指出去的 symlink）"
        case .file(.notRegularFile(let kind)): return "位置上是\(displaySafeInvisible(kind, max: 40))、不是普通檔"
        case .file(.empty): return "0 byte（空內容的 digest 不指認任何一份存檔）"
        case .unreadable: return "檔案在、但讀不出來"
        case .changedDuringRun: return "計畫算完之後內容變了（digest 對不上）——不存、不連；重跑會重新計畫"
        }
    }
}
