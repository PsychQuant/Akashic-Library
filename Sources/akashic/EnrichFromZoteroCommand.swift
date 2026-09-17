import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicZoteroImport

/// 逐筆從 Zotero 補**缺著的**書目欄位（#340）。
///
/// 與 `import-zotero` 的差別寫在 `ZoteroEnrichment` 的型別註解裡（那是 canonical
/// 說明，此處不複製一份會分岔的副本）。這裡只記 CLI 面的兩個決定：
///
/// 1. **`--citekeys` 必填、無篩選式批次**。作用半徑由呼叫者逐筆指名，所以 #298
///    那個「破壞性 `--apply` 掃過整個 store」的形狀在這個命令上不存在。
///    （`--apply` 仍走 `assertDestructiveTargetNamed`——閘的成本是一行，
///    而豁免一個寫入命令需要的理由比加上它多。）
/// 2. **dry-run 是預設**，且 dry-run 印的就是 apply 會寫的那份計畫。
struct EnrichFromZotero: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enrich-from-zotero",
        abstract: "逐筆從 Zotero 補缺著的書目欄位（只加不覆寫；不動 type／venues；作者需 --include-absent-authors 且僅在完全為空時）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "要補值的 citekeys（逗號分隔，必填——本命令不做篩選式批次）")
    var citekeys: String

    @Option(name: .long, help: "zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）")
    var zoteroDb: String = "~/Zotero/zotero.sqlite"

    @Option(name: .long, help: "只讀這個 Zotero libraryID（預設全部）")
    var libraryId: Int?

    @Flag(name: .long, help: "實際寫入（預設只列出計畫）")
    var apply = false

    @Flag(name: .long, help: "`authors` 完全為空時，從 Zotero 補 literal 作者（#340；非空一律不動）")
    var includeAbsentAuthors = false

    func run() throws {
        if apply { try options.assertDestructiveTargetNamed("enrich-from-zotero") }
        let keys = citekeys.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !keys.isEmpty else {
            throw ValidationError("--citekeys 不得為空——本命令刻意不提供「全部」的寫法")
        }

        let dbURL = URL(fileURLWithPath: (zoteroDb as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw ValidationError("找不到 zotero.sqlite：\(displaySafeInvisible(dbURL.path, max: 300))")
        }

        let store = try options.openStore()
        let load = try store.load()
        let read = try ZoteroReader.readItems(dbPath: dbURL.path, libraryID: libraryId)
        let plan = ZoteroEnrichment.plan(entries: load.entries, items: read.items,
                                         citekeys: keys,
                                         includeAbsentAuthors: includeAbsentAuthors)

        print("指名 \(keys.count) 筆；可補 \(plan.additions.count)、"
              + "上游也沒有 \(plan.unchanged.count)、"
              + "無 zotero_key \(plan.noProvenance.count)、"
              + "Zotero 查無 \(plan.zoteroMissing.count)、"
              + "不在 store \(plan.notInStore.count)"
              + (plan.refusedOnly.isEmpty ? ""
                 : "、只有被拒的識別碼 \(plan.refusedOnly.count)"))

        for a in plan.additions.sorted(by: { $0.citekey < $1.citekey }) {
            print("")
            print("  \(displaySafe(a.citekey, max: 200))")
            if let d = a.addedDate {
                print("    + date = \(displaySafe(d, max: 200))")
            }
            for (k, v) in a.addedFields.sorted(by: { $0.key < $1.key }) {
                print("    + \(displaySafe(k, max: 80)) = \(displaySafe(v, max: 160))")
            }
            if !a.addedAuthors.isEmpty {
                let names = a.addedAuthors.map { author -> String in
                    if case .literal(let n) = author { return displaySafe(n, max: 120) }
                    return "?"
                }
                print("    + authors（literal ×\(a.addedAuthors.count)）= "
                      + names.joined(separator: "、"))
            }
            // 結構化識別碼——**不是 `fields` 殘留**（#394 verify）
            for d in a.addedDOIs { print("    + doi（結構化）= \(displaySafe(d.normalized, max: 160))") }
            for d in a.addedPMIDs { print("    + pmid（結構化）= \(displaySafe(d.normalized, max: 160))") }
            for d in a.addedISBNs { print("    + isbn（結構化）= \(displaySafe(d.normalized, max: 160))") }
            for r in a.refusedIdentifiers { print("    ✗ 不採用：\(displaySafe(r, max: 300))") }
            // **部分成功另有通道**（#394 verify R9）：它不是「不採用」——解出的那些
            // 已經採用了，所以不能沿用 ✗ 那個記號。
            for r in a.partiallyParsedIdentifiers { print("    ◐ 部分解析：\(displaySafe(r, max: 300))") }
        }

        // 第六類：Zotero 給了識別碼、我們刻意不收，而**沒有別的東西可補**。
        // 與 `unchanged` 分開的理由寫在 `Result.refusedOnly` 的 doc comment 裡。
        if !plan.refusedOnly.isEmpty {
            print("")
            print("Zotero 給了識別碼但刻意不採用（\(plan.refusedOnly.count)）：")
            for a in plan.refusedOnly.sorted(by: { $0.citekey < $1.citekey })
                .prefix(AmbiguityDisplayLimit.rows) {
                print("  \(displaySafe(a.citekey, max: 200))")
                for r in a.refusedIdentifiers { print("    ✗ \(displaySafe(r, max: 300))") }
                for r in a.partiallyParsedIdentifiers { print("    ◐ \(displaySafe(r, max: 300))") }
            }
            if plan.refusedOnly.count > AmbiguityDisplayLimit.rows {
                print("  …另 \(plan.refusedOnly.count - AmbiguityDisplayLimit.rows) 筆未顯示")
            }
        }

        /// 四類「沒補到」都要印出來。**只印可補的那一半，會讓「查過、上游沒有」
        /// 與「根本沒查」在輸出上完全一樣**——那是 `lossless-intake` 執行細節 3
        /// 的靜默形式，只是換到報告面。
        func section(_ title: String, _ keys: [String]) {
            guard !keys.isEmpty else { return }
            print("")
            print("\(title)（\(keys.count)）：")
            for k in keys.sorted().prefix(AmbiguityDisplayLimit.rows) {
                print("  \(displaySafe(k, max: 200))")
            }
            if keys.count > AmbiguityDisplayLimit.rows {
                print("  …另 \(keys.count - AmbiguityDisplayLimit.rows) 筆未顯示")
            }
        }
        section("Zotero 端也沒有缺著的那些欄位——需外部查證", plan.unchanged)
        section("無 provenance.zotero_key——無從查起", plan.noProvenance)
        section("有 zotero_key 但 Zotero 查無此 item", plan.zoteroMissing)
        section("citekey 不在 store 裡", plan.notInStore)

        guard apply else {
            print("")
            print("（dry-run）加 --apply 實際寫入。"
                  + "**只加原本不存在的鍵**——既有值、type、venues 一律不動；"
                  + "作者僅在 --include-absent-authors 且 authors 完全為空時補。")
            return
        }

        var byCitekey: [String: Entry] = [:]
        for e in load.entries { byCitekey[e.citekey] = e }
        var written = 0
        var failed: [String: String] = [:]
        for a in plan.additions {
            guard let entry = byCitekey[a.citekey] else { continue }
            do {
                try store.writeEntry(ZoteroEnrichment.applied(a, to: entry))
                written += 1
            } catch {
                // per-item 隔離：單筆寫入失敗不把整趟變成「部分套用且沒人知道哪些」
                failed[a.citekey] = displaySafeError(error, max: 512)
            }
        }
        print("")
        print("已寫入 \(written) 筆。")
        if !failed.isEmpty {
            print("寫入失敗 \(failed.count) 筆：")
            for (k, e) in failed.sorted(by: { $0.key < $1.key }) {
                print("  \(displaySafeInvisible(k, max: 200)): \(displaySafeClipOnly(e, max: 1_600))")   // display-safe-exempt: e 已消毒（displaySafeError 產出，R29 D81），只截
            }
        }
    }
}
