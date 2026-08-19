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

    // **對映表不住在這裡**——它是 `WorkType.init?(biblatexEntryType:fields:)`。
    //
    // 遷移的來源值域**就是** biblatex entry type：舊的自由字串 `Entry.type` 裝的
    // 正是 `article` / `incollection` / `inproceedings` 那些。所以「遷移表」與
    // 「讀 `.bib` 用的逆向表」不是兩張長得像的表，是**同一張表**。
    //
    // 第一版真的寫了兩份（這裡一份 `mapping` + `conditionalTarget`，`WorkType` 那邊
    // 一份逆向）。兩份會分岔，而且分岔是**安靜的**：階段二把 `journal-article` 更名為
    // `periodical-article` 時，這裡沒跟著改，於是遷移會產出一個階段二拒收的值——
    // 部署後才炸，而且炸在「已經改寫完 937 個檔」之後。
    //
    // 折成一份之後那個分岔**無處可寫**，不是被測試擋住。這與
    // `entity-backlink-completeness` 的「一個讀取面只有一條實作路徑」同一個立場，
    // 以及它引的 3.325：好的記法讓矛盾在文法上寫不出來。
    //
    // 條件式細分（`misc` 帶 `url` → wikipedia-entry；`unpublished` 帶 `location`
    // → conference-session）也一併住在那個 initializer 裡，同一個理由。

    /// 這個值是否已經是新值域（idempotency 判定）。
    ///
    /// 注意 `book` / `report` / `thesis` **同時**是合法 biblatex type 與合法
    /// `WorkType` rawValue。先判「已遷移」再判「可遷移」是對的：那三個值兩條路
    /// 的答案相同（都是它自己），所以順序在此不改變結果，但寫死順序讓它不依賴
    /// 這個巧合。
    public static func isAlreadyMigrated(_ type: String) -> Bool {
        WorkType(rawValue: type) != nil
    }

    /// 條件對映：值域相同但需要看 `fields` 才知道落哪一格。
    ///
    /// - `misc` → `wikipedia-entry`（10.3 例 49）：實測 14/14 只帶 `url`，全是維基
    ///   百科／線上百科條目。
    /// - `unpublished` → `conference-session`（10.5）：實測 21/21 帶 `fields.location`
    ///   ＝ APA7 §9.31「works with specific locations」的 source 要素；10.8
    ///   Unpublished Works **不需要地點**。


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
            if isAlreadyMigrated(entry.type) {
                report.alreadyMigrated.append(entry.citekey)
                continue
            }
            guard let target = WorkType(biblatexEntryType: entry.type,
                                        fields: entry.fields)?.rawValue else {
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
