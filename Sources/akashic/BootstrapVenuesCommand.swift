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
        abstract: "從 literal 刊名建 venue 記錄（type 由來源欄位判定，寧可分割絕不合併）",
        discussion: "建出來的 venue 不指定對外形（authorized 留空，#563；顯示名暫取 names 的第一段）。指定是判定："
            + "akashic update-venue <key> --authorize \"<名字>\" --judgement \"<理由>\"（理由必填、寫一筆判定記錄，需要 store format ≥ 22，#564）。")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只列出；計畫讀到 legacy 拷貝或無法唯一定位的記錄時整批拒絕、零寫入，#709）")
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
        // 同 bootstrap-people（使用者 2026-10-05 裁決、2026-10-09 裁決 2，#709）：寫入候選面看完整的 load；計畫讀到 work 拷貝或無法唯一定位的
        // work 時 --apply 整批拒絕、零寫入，乾跑照常列出、開頭的附註說明（拷貝裡的刊名也是候選，一對相同的算兩次出現）
        if apply { try load.refuseApplyWithPlanBlockers(.venues) }

        let result = VenueBootstrap.result(entries: load.entries, existing: load.venues)
        var cands = result.candidates.filter { $0.occurrences >= minOccurrences }
        let total = cands.count
        if let limit { cands = Array(cands.prefix(limit)) }
        if let note = load.planBlockersNote(.venues) { print(note) }   // display-safe-exempt: 已消毒（常數字面、Int、逐項 displaySafeInvisible 的檔名）

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
                  + "akashic update-venue <既有 key> --add-variant \"<這個寫法>\" --judgement \"<理由>\"（key 是位置參數；理由必填，#564），"
                  + "下一輪它就是精確命中、由 resolve-venues 歸戶；是不同刊 → "
                  + "akashic add-venue 另建。判不出來就不建——literal 留在誠實狀態是合法終點。")
        }

        /// 不建檔的 literal **必須被印出來、附理由**（同 `bootstrap-people` 的 #238 教訓）：
        /// model 端有欄位而沒有任何輸出讀它，與丟棄在效果上完全相同。兩類——產不出 key 的
        /// （出口：`add-venue` 手動指定 key）、不能作為名字的（#554 R5 verify 第 5 列；出口：
        /// 修 work 的來源欄位）——理由分得開，人才知道往哪邊走。
        let dropped = result.dropped.filter { $0.occurrences >= minOccurrences }
        if !dropped.isEmpty {
            print("")
            print("不建檔的 literal（\(dropped.count)），各附理由：")
            for d in dropped.prefix(AmbiguityDisplayLimit.rows) {
                // `rejected` 那一類的 `d.name` 就是被 `wellFormednessIssue` 拒掉的原字串——結構上帶著那個不可見字元，而 venue
                // 沒被建出來、沒有 sibling 訊息可對照（R13 verify security 第 12 列）：以性質逃脫
                print("  ×\(d.occurrences)  \(displaySafeInvisible(d.name, max: 200))——\(d.reason)")   // display-safe-exempt: d.reason：reason 是 VenueBootstrap／NameIdentity 的固定訊息（含 U+ 十六進位，非 store 字串）
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
            // 沒有候選時不說「建出來的 venue」（#563 R2 verify 第 17／23／28 列：那句說的是不存在的記錄）
            print("（dry-run）加 --apply 實際寫入。**只建立、不歸戶**"
                  + "——entry 的 venues literal 原樣留著，歸戶是 resolve-venues 的第二步。"
                  + (cands.isEmpty ? "" : "建出來的 venue 不指定對外形（authorized 留空，#563）。"))
            return
        }

        let venues = VenueBootstrap.makeVenues(cands)
        for v in venues { _ = try store.writeVenue(v) }
        print("")
        print("已建立 \(venues.count) 筆 venue 記錄。"
              + (venues.isEmpty ? "" : "下一步：akashic resolve-venues 看候選，確認後 --apply 歸戶。"))
        guard !venues.isEmpty else { return }
        // 指令照抄要跑得通：#564 起 --authorize 必附 --judgement（R2 verify 第 0／4 列：這一行寫在 #564 整合之前，照抄得 exit 64）
        print("新建的 venue 沒有指定對外形（authorized 留空，#563；顯示名暫取 names 的第一段）："
              + "指定走 akashic update-venue <key> --authorize \"<名字>\" --judgement \"<理由>\"（理由必填、寫一筆判定記錄，#564），"
              + "doctor 不會替空的 venue authorized 報缺口（它只數 person 與 organization）。")
    }
}
