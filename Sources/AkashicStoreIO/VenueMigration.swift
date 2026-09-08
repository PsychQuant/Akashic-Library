import Foundation
import AkashicCore

/// `migrate-venues`（#304 / format 11）：從書目字串欄位回填 entry 的 `venues`
/// 二態 ref——**只產生 `.literal`**（`literal-first-then-key` 規則：進庫不猜 key）。
///
/// ## 契約（同 `PersonIdentityMigration` 的家族紀律）
///
/// - **dry-run 預設**：不帶 `--apply` 只回報計畫，零寫入。
/// - **只加不改**（lossless-intake 回填判準）：已有 `venues` 的 entry 一律跳過；
///   `fields` 的字串照舊保留（ref 是升格不是取代）；除 `venues` 鍵外一個位元組
///   都不動其它欄位。
/// - **idempotent**：第二輪全數落 `skippedExisting`／`noVenueSource`，applied = 0。
/// - **per-file trackedness**（R2 C4 同款）：`--apply` 只改寫 git 追蹤中的檔——
///   未追蹤的檔改壞了沒有回復路徑，進 `failed` 點名交人，不寫。
///
/// ## 為什麼繞過 `writeEntry` 的 format gate
///
/// 部署順序是「binary 先升 → migrate → 手動 bump marker」（同 format 10 程序），
/// 所以本 migration 在 format 10 的 store 上執行是**預期狀態**——它就是 gate 訊息
/// 指路的那條唯一入口。直接寫檔（atomic）而不走 `writeEntry`，是刻意的。
public enum VenueMigration {

    public struct Failed: Equatable {
        public var citekey: String
        public var reason: String
    }

    public struct Report: Equatable {
        /// 將回填（dry-run）或已回填（apply）的 citekey。
        public var planned: [String] = []
        /// 已有 `venues`、本輪不動的 citekey。
        public var skippedExisting: [String] = []
        /// 無任何載體來源欄位（journaltitle／booktitle／publisher）的 citekey。
        public var noVenueSource: [String] = []
        /// 拒寫（未追蹤等）——點名交人。
        public var failed: [Failed] = []
        /// 實際寫入筆數（dry-run 恆 0）。
        public var applied: Int = 0
        public init() {}
    }

    public enum MigrationError: Error, CustomStringConvertible {
        case noRecoveryPath(detail: String)
        public var description: String {
            switch self {
            case .noRecoveryPath(let d): return "無回復路徑：\(displaySafe(d, max: 300))"
            }
        }
    }


    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        var report = Report()
        let load = try store.load()

        // per-file trackedness：apply 時查一次（byte-exact，同 PersonIdentityMigration）。
        let trackedRelPaths: Set<Data>
        if apply {
            guard let out = LibraryStore.git(["ls-files", "-z", "--", "entities"],
                                             in: store.root), out.status == 0 else {
                throw MigrationError.noRecoveryPath(
                    detail: "git ls-files 無法執行——無從確認追蹤狀態")
            }
            trackedRelPaths = Set(out.out.split(separator: "\0").map { Data($0.utf8) })
        } else {
            trackedRelPaths = []
        }

        for entry in load.entries.sorted(by: { $0.citekey < $1.citekey }) {
            guard entry.venues.isEmpty else {
                report.skippedExisting.append(entry.citekey)
                continue
            }
            let derived = deriveLiterals(entry)
            guard !derived.isEmpty else {
                report.noVenueSource.append(entry.citekey)
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
                updated.venues = derived
                let yaml = try EntryYAML.encode(updated)
                // atomic（temp+rename）——與 store 寫入同保證。
                try Data(yaml.utf8).write(to: store.entityURL(id: entry.id),
                                          options: .atomic)
                report.applied += 1
            }
            report.planned.append(entry.citekey)
        }
        return report
    }

    /// 對映的唯一來源是 `VenueDerivation.literals(for:)`（AkashicCore）——
    /// migration 與 importer 共用，不留第二份會分岔的清單。
    static func deriveLiterals(_ entry: Entry) -> [VenueRef] {
        VenueDerivation.literals(for: entry)
    }

    /// 報告後的下一步提示（CLI 消費；同 PersonIdentityMigration.nextStep 形）。
    /// #472：目標是常數，提示由 `StoreVersion.bumpHint` 依現況決定——先前無條件印
    /// 「改成 11」，而那在今天的 store（16）上是降級指示。
    public static let targetFormat = 11

    public static func nextStep(report: Report, apply: Bool, current: Int?) -> String? {
        if !apply {
            return report.planned.isEmpty
                ? nil
                : "下一步：確認計畫無誤後加 --apply 執行；寫入後 akashic validate 驗證。"
                  + StoreVersion.bumpHint(target: targetFormat, current: current)
        }
        guard report.failed.isEmpty else {
            return "有 \(report.failed.count) 筆拒寫（未追蹤）——commit 後重跑；已寫入的不受影響"
        }
        return report.applied == 0 ? nil :
            "下一步：akashic validate 驗證。"
            + StoreVersion.bumpHint(target: targetFormat, current: current)
    }
}
