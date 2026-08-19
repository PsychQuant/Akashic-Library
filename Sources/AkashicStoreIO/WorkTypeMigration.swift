import Foundation
import AkashicCore

/// `migrate-work-types`（#325 階段一）：把 `Entry.type` 的自由字串遷到 APA7 ch10 的
/// 封閉值域。
///
/// ## 為什麼是兩階段
///
/// `Entry.type` 現在是 `String` 且 decode 不驗。**新 binary 上線的那一刻**，937 筆
/// 現有記錄的 type 全是舊自由字串——若 decode 直接改嚴格，整個 store 會瞬間看不見
/// （quarantine，而 `query` 回 rc=0、無訊息）。#323 的實測已經示範過那個確切的失敗。
///
/// 所以使用者裁定（2026-08-19）**遷移先行、decode 嚴格**：
///
/// 1. **本階段**：只有遷移命令，`Entry.type` 仍是 `String`。跑完 937 筆都是新值。
/// 2. 下一階段：`type` 收為封閉列舉，decode 對未知值嚴格。
///
/// 中間**沒有視窗期**——階段一的 binary 讀得懂新舊兩種值（因為它還是字串）。
///
/// ## 契約（沿用 `VenueMigration` 家族紀律，一條不減）
///
/// - **dry-run 預設**：不帶 `--apply` 只回報計畫，零寫入。
/// - **只改 `type` 一個鍵**：其餘欄位一個位元組都不動。
/// - **idempotent**：第二輪全數落 `alreadyMigrated`，applied = 0。
/// - **per-file trackedness**：`--apply` 只改寫 git 追蹤中的檔——未追蹤的檔改壞了
///   沒有回復路徑，進 `failed` 點名交人，不寫。
///
/// ## 對映表（封閉；實測 937/937 零殘留）
///
/// 三個舊值合流到 `conference-session`——那正是 APA7 10.5 的範圍，而舊值域把同一類
/// 拆成三個名字（`presentation`／`inproceedings`／部分 `unpublished`）。這本身就是
/// #325 的論據：舊的 10 個值不是分類，是各 importer 碰巧寫的字串。
public enum WorkTypeMigration {

    public struct Failed: Equatable {
        public var citekey: String
        public var reason: String
        public init(citekey: String, reason: String) {
            self.citekey = citekey
            self.reason = reason
        }
    }

    public struct Report: Equatable {
        /// 將遷移（dry-run）或已遷移（apply）的 citekey → 新值。
        public var planned: [(citekey: String, from: String, to: String)] = []
        /// type 已是新值域、本輪不動。
        public var alreadyMigrated: [String] = []
        /// 對映不到——**點名交人，絕不猜**。
        public var unmapped: [Failed] = []
        /// 拒寫（未追蹤等）。
        public var failed: [Failed] = []
        public var applied: Int = 0
        public init() {}

        public static func == (a: Report, b: Report) -> Bool {
            a.planned.map(\.citekey) == b.planned.map(\.citekey)
                && a.alreadyMigrated == b.alreadyMigrated
                && a.unmapped == b.unmapped && a.failed == b.failed
                && a.applied == b.applied
        }
    }

    /// 舊自由字串 → APA7 ch10 值域。**封閉列舉，不得依性質相似類推**。
    ///
    /// 每一列的 APA7 節號是它的依據；新增一列要寫出節號，否則那個值沒有判準。
    public static let mapping: [String: String] = [
        "article":       "journal-article",     // 10.1 Periodicals
        "book":          "book",                // 10.2 Books and Reference Works
        "incollection":  "book-chapter",        // 10.3 Edited Book Chapters
        "report":        "report",              // 10.4 Reports and Gray Literature
        "inproceedings": "conference-session",  // 10.5 Conference Sessions
        "presentation":  "conference-session",  // 10.5（同上——APA7 不分這兩者）
        "thesis":        "thesis",              // 10.6 Dissertations and Theses
        "online":        "webpage",             // 10.16 Webpages and Websites
    ]

    /// 已是新值域的值（idempotency 判定用）。
    public static let migratedValues: Set<String> = Set(mapping.values)
        .union(["wikipedia-entry"])

    /// 條件對映：值域相同但需要看 `fields` 才知道落哪一格。
    ///
    /// - `misc` → `wikipedia-entry`（10.3 例 49）：實測 14/14 只帶 `url`，全是維基
    ///   百科／線上百科條目。
    /// - `unpublished` → `conference-session`（10.5）：實測 21/21 帶 `fields.location`
    ///   ＝ APA7 §9.31「works with specific locations」的 source 要素；10.8
    ///   Unpublished Works **不需要地點**。
    static func conditionalTarget(_ entry: Entry) -> String? {
        switch entry.type {
        case "misc":
            return entry.fields["url"] != nil ? "wikipedia-entry" : nil
        case "unpublished":
            return entry.fields["location"] != nil ? "conference-session" : nil
        default:
            return nil
        }
    }

    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        var report = Report()
        let load = try store.load()

        let trackedRelPaths: Set<Data>
        if apply {
            guard let out = LibraryStore.git(["ls-files", "-z", "--", "entities"],
                                             in: store.root), out.status == 0 else {
                throw VenueMigration.MigrationError.noRecoveryPath(
                    detail: "git ls-files 無法執行——無從確認追蹤狀態")
            }
            trackedRelPaths = Set(out.out.split(separator: "\0").map { Data($0.utf8) })
        } else {
            trackedRelPaths = []
        }

        for entry in load.entries.sorted(by: { $0.citekey < $1.citekey }) {
            if migratedValues.contains(entry.type) {
                report.alreadyMigrated.append(entry.citekey)
                continue
            }
            guard let target = mapping[entry.type] ?? conditionalTarget(entry) else {
                report.unmapped.append(Failed(
                    citekey: entry.citekey,
                    reason: "type「\(displaySafe(entry.type, max: 80))」不在對映表，"
                          + "且條件判準也不成立——**不猜**，請人工裁決後補進 mapping"))
                continue
            }
            if apply {
                let relFile = "entities/\(entry.id.uuidString).yaml"
                guard trackedRelPaths.contains(Data(relFile.utf8)) else {
                    report.failed.append(Failed(
                        citekey: entry.citekey,
                        reason: "\(relFile) 未被 git 追蹤——改寫無回復路徑，先 commit 再跑"))
                    continue
                }
                var updated = entry
                updated.type = target
                let yaml = try EntryYAML.encode(updated)
                try Data(yaml.utf8).write(to: store.entityURL(id: entry.id),
                                          options: .atomic)
                report.applied += 1
            }
            report.planned.append((citekey: entry.citekey, from: entry.type, to: target))
        }
        return report
    }

    public static func nextStep(report: Report, apply: Bool) -> String? {
        if !apply {
            return report.planned.isEmpty
                ? nil
                : "\(report.planned.count) 筆待遷移——加 --apply 執行"
        }
        if !report.unmapped.isEmpty {
            return "\(report.unmapped.count) 筆對映不到，**未遷移**：補進 mapping 後重跑"
        }
        if !report.failed.isEmpty {
            return "\(report.failed.count) 筆因未被 git 追蹤而跳過：先 commit 再重跑"
        }
        return report.applied > 0
            ? "已遷移 \(report.applied) 筆。下一階段（type 收為封閉列舉）才會拒收舊值"
            : nil
    }
}
