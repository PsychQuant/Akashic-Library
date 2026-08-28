import Foundation
import AkashicCore

/// `names` 的異寫法搬進 `variant` 分割（#422，format 13 → 14）。
///
/// ## 為什麼是搬而不是重新判定
///
/// 那些名字**已經在同一筆記錄裡**——它們是誰的別名，前一次判定已經做過了（那正是它們
/// 被寫進同一個 `names` 的原因）。本遷移不做新判定，只是把既有判定的結果**重新分類**：
/// `authorized` 清單裡有的留在 authorized，其餘進 variant。
///
/// 機械的、可逆的、零新斷言——所以它不受 `identity-is-judged-not-matched` 管
/// （那條管的是「這兩個字串是同一本刊的兩種寫法」，而那個判定已經做過了）。
///
/// ## 誤標的出口是乾跑
///
/// 若某一筆其實是**沿革**（不是異寫法），遷移會把它誤標成 variant。所以乾跑逐筆印出來
/// 給人看，而不是靜默套用。實測 35 筆，人工過目可行。
///
/// **帶時間欄位的 names item 一律不動**——那是沿革的既有標記，而本遷移的前提正是
/// 「多筆且不帶時間 ＝ 異寫法」。實測那樣的 venue 有 35 筆、帶時間的 0 筆。
public enum VenueVariantMigration {

    public struct Planned: Equatable {
        public var key: String
        /// 會被標成 variant 的名字（依序）。
        public var variants: [String]
    }

    public struct Failed: Equatable {
        public var key: String
        public var reason: String
    }

    public struct Report: Equatable {
        public var planned: [Planned] = []
        /// `names` 只有一筆——沒有可分類的東西。
        public var singleName: [String] = []
        /// 已有 `variant`——本輪不動（冪等）。
        public var alreadyPartitioned: [String] = []
        /// **帶時間欄位**——那是沿革，不是異寫法，不動。
        public var hasTemporal: [String] = []
        public var failed: [Failed] = []
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

        // per-file trackedness：apply 時查一次（沿用 `VenueMigration` 的既有形狀）。
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

        for venue in load.venues.sorted(by: { $0.key < $1.key }) {
            guard venue.variant.isEmpty else {
                report.alreadyPartitioned.append(venue.key)
                continue
            }
            let items = venue.names.entries
            guard items.count > 1 else {
                report.singleName.append(venue.key)
                continue
            }
            // **帶時間 ＝ 沿革，不動。** 本遷移的前提是「多筆且不帶時間 ＝ 異寫法」，
            // 而那個前提在帶時間的記錄上不成立。
            // 拆成具名函式——四個 optional 的 `||` 鏈會讓型別檢查器超時
            func hasTime(_ i: TemporalValue<String>) -> Bool {
                if i.range.start != nil { return true }
                if i.range.end != nil { return true }
                if i.range.endedUnknown { return true }
                if !i.range.attested.isEmpty { return true }
                return false
            }
            let temporal = items.contains(where: hasTime)
            guard !temporal else {
                report.hasTemporal.append(venue.key)
                continue
            }
            let authorized = Set(venue.authorized)
            let variants = items.map(\.value).filter { !authorized.contains($0) }
            guard !variants.isEmpty else {
                // 全部都在 authorized——沒有異寫法可搬
                report.singleName.append(venue.key)
                continue
            }
            report.planned.append(Planned(key: venue.key, variants: variants))

            if apply {
                let relFile = "entities/\(venue.id.uuidString).yaml"
                guard trackedRelPaths.contains(Data(relFile.utf8)) else {
                    report.failed.append(Failed(
                        key: venue.key,
                        reason: "\(relFile) 未被 git 追蹤——改寫無回復路徑，先 commit 再跑"))
                    report.planned.removeLast()
                    continue
                }
                var updated = venue
                updated.variant = variants
                try store.writeVenue(updated)
                report.applied += 1
            }
        }
        return report
    }

    /// 下一步的提示——與 `VenueMigration.nextStep` 同形。
    public static func nextStep(report: Report, apply: Bool) -> String? {
        if !apply && !report.planned.isEmpty {
            return "這是乾跑，store 沒有被改動。確認以上分類無誤後加 --apply。\n"
                 + "**--apply 不會改 store.yaml 的 format**——那是驗證之後的人工最後一步（13 → 14）。"
        }
        if apply && report.applied > 0 {
            return "接下來：`akashic validate` 確認零新 diagnostic，然後手動把 store.yaml 的 format 改成 14。"
        }
        return nil
    }
}
