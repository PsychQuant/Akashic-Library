import ArgumentParser
import Foundation
import AkashicCore
import AkashicEntity
import AkashicStoreIO

/// 從 literal 刊名批次建 venue 記錄（#367）。
///
/// 鏡像 `bootstrap-people`／`bootstrap-organizations` 的形狀：dry-run 預設、
/// `--apply` 才寫、破壞性寫入走 #298 的閘。
struct BootstrapVenues: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bootstrap-venues",
        abstract: "從 literal 刊名建 venue 記錄（type 由來源欄位判定，寧可分割絕不合併）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只列出）")
    var apply = false

    @Option(name: .long, help: "只處理出現次數 ≥ N 的（投報率優先）")
    var minOccurrences: Int = 1

    @Option(name: .long, help: "最多處理前 N 個")
    var limit: Int?

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("bootstrap-venues") }
        let store = try options.openStore()
        let load = try store.load()

        let result = VenueBootstrap.result(entries: load.entries, existing: load.venues)
        var cands = result.candidates.filter { $0.occurrences >= minOccurrences }
        let total = cands.count
        if let limit { cands = Array(cands.prefix(limit)) }

        print("literal 刊名 → venue 候選：\(total) 個"
              + (minOccurrences > 1 ? "（已濾出現次數 ≥ \(minOccurrences)）" : ""))
        for c in cands {
            let names = c.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
            // **evidence 一定印**：讓審 dry-run 的人看得出 type 是讀出來的還是猜的。
            print("  ×\(c.occurrences)  \(displaySafe(c.key, max: 200))"
                  + "  [\(c.type.rawValue) ← \(c.evidence)]  \(names)")
        }
        if total > cands.count {
            print("  …另 \(total - cands.count) 筆未顯示（--limit）")
        }

        /// #548：與既有 venue **寬鬆共鍵**的群——不建檔，先消歧。
        ///
        /// 印在 `guard apply` **之前**，所以乾跑與 `--apply` 兩條路都看得到。
        /// 那正是 #547 的 BLOCKING：只在 model 端加桶而沒有輸出讀它，與丟棄在效果
        /// 上完全相同（`lossless-intake` §3：靜默是最糟的形式）。
        let pending = result.pendingResolution.filter { $0.occurrences >= minOccurrences }
        if !pending.isEmpty {
            print("")
            print("與既有 venue 寬鬆共鍵、**先消歧再說**（\(pending.count)）——建檔會鑄造重複記錄：")
            for g in pending.prefix(AmbiguityDisplayLimit.rows) {
                let names = g.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
                let keys = g.matchedKeys.map { displaySafe($0, max: 200) }.joined(separator: "、")
                print("  ×\(g.occurrences)  \(names)  ↔ 既有：\(keys)")
            }
            if pending.count > AmbiguityDisplayLimit.rows {
                print("  …另 \(pending.count - AmbiguityDisplayLimit.rows) 筆未顯示")
            }
            print("  處置：同鍵只代表**值得看**，不代表同一本刊。查證後——是同一本 → "
                  + "akashic update-venue <既有 key> --add-variant \"<這個寫法>\"（key 是位置參數），"
                  + "下一輪它就是精確命中、由 resolve-venues 歸戶；是不同刊 → "
                  + "akashic add-venue 另建。判不出來就不建——literal 留在誠實狀態是合法終點。")
        }

        /// 產不出 key 的**必須被印出來**（同 `bootstrap-people` 的 #238 教訓）：
        /// model 端有欄位而沒有任何輸出讀它，與丟棄在效果上完全相同。
        let dropped = result.dropped.filter { $0.occurrences >= minOccurrences }
        if !dropped.isEmpty {
            print("")
            print("產不出 ASCII key、需人工指定（\(dropped.count)）：")
            for d in dropped.prefix(AmbiguityDisplayLimit.rows) {
                print("  ×\(d.occurrences)  \(displaySafe(d.name, max: 200))")
            }
            if dropped.count > AmbiguityDisplayLimit.rows {
                print("  …另 \(dropped.count - AmbiguityDisplayLimit.rows) 筆未顯示")
            }
        }

        /// 同名來自不同種類的來源欄位——**不建檔，交人裁**。
        ///
        /// 目前零實例，但取任一個 type 都可能讓整組欄位需求錯（#324：`VenueType`
        /// 決定哪些欄位存在），而那個錯不會有任何跡象。
        if !result.conflicts.isEmpty {
            print("")
            print("同名但來源欄位種類不同、**先裁決再建檔**（\(result.conflicts.count)）：")
            for c in result.conflicts {
                let types = c.types.map(\.rawValue).joined(separator: " / ")
                print("  ×\(c.occurrences)  \(displaySafe(c.name, max: 200))  ↔ \(types)")
            }
        }

        guard apply else {
            print("")
            print("（dry-run）加 --apply 實際寫入。**只建立、不歸戶**"
                  + "——entry 的 venues literal 原樣留著，歸戶是 resolve-venues 的第二步。")
            return
        }

        let venues = VenueBootstrap.makeVenues(cands)
        for v in venues { _ = try store.writeVenue(v) }
        print("")
        print("已建立 \(venues.count) 筆 venue 記錄。"
              + "下一步：akashic resolve-venues 看候選，確認後 --apply 歸戶。")
    }
}
