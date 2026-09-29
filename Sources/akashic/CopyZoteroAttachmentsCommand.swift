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
        // 有單筆寫入失敗或補存失敗仍以非零退出（收容不是吞掉——自動化才看得到，`import-zotero` 的同一條）
        if !report.writeFailed.isEmpty || !report.restoreFailed.isEmpty { throw ExitCode(1) }
    }

    static func render(_ r: ZoteroAttachmentCopyReport, applyRequested: Bool) {
        // #606 R2 verify：`applied` 只說走到了寫入那一段；標題要說真的改了什麼（全部略過時不說「已寫入」，只補存時不說改寫了 work）
        print(!r.applied ? (applyRequested ? "Zotero 附件複製（#606）——--apply：沒有新東西要複製，store 沒有被改動"
                                           : "Zotero 附件複製（#606）——乾跑，store 沒有被改動")
              : !r.written.isEmpty ? "Zotero 附件複製（#606）——已寫入"
              : r.changedAnything ? "Zotero 附件複製（#606）——已補存本機 sources/，沒有改寫任何 work 檔"
              : "Zotero 附件複製（#606）——--apply：沒有改寫任何 work 檔、也沒有補存任何檔（見下方的略過與失敗）")
        print("帶 zotero 附件記錄的 work：\(r.considered)；\(r.applied ? "已複製" : "要複製")：\(r.planned.count) 個檔；已連過：\(r.alreadyLinked.count)；略過：\(r.skipped.count)")
        for item in r.planned { print(itemLine(item)) }
        if !r.restoredLocally.isEmpty {
            // #606 R1 verify：「已連過」看的是本機位元組，不是連結——sources/ 不進 git，別台 clone 的連結在、位元組不在
            print("")
            print("已連過、但本機 sources/ 沒有位元組——\(r.applied ? "已補存" : "要補存")（不改連結、不動 work 檔）：\(r.restoredLocally.count) 個檔")   // display-safe-exempt: Int
            for item in r.restoredLocally { print(itemLine(item)) }
        }
        if !r.recordRestored.isEmpty {
            // #606 R2 verify：位元組在、index 沒有條目（孤兒 blob）——以前算已連過，每次重跑都說做完了
            print("")
            print("已連過、位元組在本機，但 sources/index.jsonl 沒有它的取得記錄——\(r.applied ? "已補記" : "要補記")（位元組不重寫、不改連結、不動 work 檔）：\(r.recordRestored.count) 個檔")   // display-safe-exempt: Int
            for item in r.recordRestored { print(itemLine(item)) }
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
            print("已改寫 \(r.written.count) 筆 work 的 akashic.sources")   // display-safe-exempt: Int
            if !r.provenanceNotRecorded.isEmpty {
                // lossless-intake：丟棄必須可見——index 已有這份內容的條目、以先到的為準，這次的 Zotero 來源沒有寫進去。
                // 位元組可能早就在，也可能這一次才存（index 留著、blob 被清過）——逐行說是哪一種（#606 R2 verify：以前一律說「早就在」）
                print("index 已有這份內容的取得記錄、這次的 Zotero 來源（origin 與 note）沒有寫進去（以先到的那一條為準）：\(r.provenanceNotRecorded.count) 個檔")   // display-safe-exempt: Int
                for n in r.provenanceNotRecorded.prefix(Entry.perRecordWarningCap * 5) {
                    let bytes = n.bytesWereAlreadyStored ? "位元組已在（先前或這一趟稍早存的）" : "位元組這一次才存進 sources/"
                    print("  \(displaySafeInvisible(n.item.citekey, max: 200))  \(displaySafeInvisible(n.item.path, max: 300))  \(bytes)；保留的 origin：\(n.keptOrigin.map { displaySafeClipOnly($0, max: 300) } ?? "（讀不到）")")   // display-safe-exempt: keptOrigin 已由 service 以 displaySafeInvisible 消毒，只截；bytes 是本檔的固定句
                }
                if r.provenanceNotRecorded.count > Entry.perRecordWarningCap * 5 {
                    print("  …另有 \(r.provenanceNotRecorded.count - Entry.perRecordWarningCap * 5) 個未列出")   // display-safe-exempt: Int
                }
            }
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
        if !r.restoreFailed.isEmpty {
            print("")
            print("補存失敗（連結沒動、work 檔沒動；重跑會再補）: \(r.restoreFailed.count)")   // display-safe-exempt: Int
            for f in r.restoreFailed {
                print("  ✗ \(displaySafeInvisible(f.item.citekey, max: 200))  \(displaySafeInvisible(f.item.path, max: 300)) — \(displaySafeClipOnly(f.message, max: 4_096))")   // display-safe-exempt: message 已消毒（service 以 displaySafeError 產出），只截
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
        if r.applied && !r.written.isEmpty {
            print("接下來：`akashic validate` 確認，然後 commit。連錯的副本宣告用 `update-entry <citekey> --remove-source <digest>=理由` 收回。")
        } else if r.applied {
            // 只補存或全部略過：沒有 work 檔被改寫，sources/ 不進 git（#606 R2 verify）
            print("沒有改寫任何 work 檔，沒有東西要 commit（sources/ 不進 git）。")
        } else if !r.planned.isEmpty || !r.restoredLocally.isEmpty || !r.recordRestored.isEmpty {
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
        case .localCopyUnverifiable(let why): return "已連過，但判不出本機 sources/ 有沒有這份位元組（\(displaySafeClipOnly(why, max: 600))）——不重存、不動連結；用 akashic doctor 查 sources/"   // display-safe-exempt: why 已由 service 消毒，只截
        }
    }

    private static func itemLine(_ item: ZoteroAttachmentCopyReport.Item) -> String {
        "  \(displaySafeInvisible(item.citekey, max: 200))  \(displaySafeInvisible(item.path, max: 300))  \(item.bytes) bytes  \(displaySafeInvisible(item.mediaType, max: 100))  \(item.digest)"   // display-safe-exempt: bytes 是 Int；digest 是本 binary 算的 SHA-256 十六進位
    }
}
