import Foundation
import AkashicCore

/// `names` 的異寫法搬進 `variant` 分割（#422，format 13 → 14）。
///
/// > **#554 之後不得再跑（2026-09-12，退場見 #567）**：本遷移的前提「多筆且不帶時間 ＝
/// > 異寫法」在 #554 之後**為假**——`update-venue --authorize X` 把被換下來的舊指定刻意
/// > 留在 names、未標（D1 裁決：程式不替呼叫端多說「它是異寫」），而那筆記錄恰好滿足
/// > 本遷移的四個條件（variant 空、names 多筆、無時間、authorized 非空）。#554 R2 verify 的
/// > DA 席實測：同一筆 venue `--authorize` 前「沒有可分類的 venue」、後「將分類 1 筆」。
/// > live store 的遷移工作 2026-09-12 已歸零（dry-run 0 筆可分類），依 `no-compat-fallback`
/// > 退場即刪——刪一條 CLI 命令動 13 檔，是自己的生命週期事件（#567），本輪只在這裡與
/// > parity 列寫明。
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
        /// 多筆但**全部已在 `authorized`**——沒有異寫法可搬。與 `singleName` 分開
        /// （#422 verify R1）：乾跑報表是這個遷移唯一的攔截點，桶的標籤說錯話會讓
        /// 過目的人看到「單一名字」而實際是「多名字、無待分類項」。
        public var allAuthorized: [String] = []
        /// 多筆但 **`authorized` 為空——不分類，交人**（#422 verify R1 B3）。補集規則對
        /// 空的 `authorized` 回傳全部名字，會把一筆記錄的每個名字都標成它自己的異寫
        /// （實測三筆：wikipedia／stanford-encyclopedia-of-philosophy／bulletin-…-academia-sinica，
        /// 其中 bulletin 的 note 自述是新舊系列沿革）。「哪一個是權威形」是判定
        /// （`identity-is-judged-not-matched`），本遷移只重新分類**既有**判定——沒有既有判定
        /// 就沒有可分類的東西。`add-venue --names A B` 建檔時 `authorized` 留空，所以這不是
        /// 三筆歷史資料的問題，是建檔的預設產物：先指定 `authorized` 再跑。
        public var noAuthorized: [String] = []
        /// 已有 `variant`——本輪不動（冪等）。
        public var alreadyPartitioned: [String] = []
        /// **帶時間欄位**——那是沿革，不是異寫法，不動。
        public var hasTemporal: [String] = []
        public var failed: [Failed] = []
        public var applied: Int = 0
        public init() {}
    }

    public enum MigrationError: Error, CustomStringConvertible, SanitizedErrorDescription {
        case noRecoveryPath(detail: String)
        public var description: String {
            switch self {
            case .noRecoveryPath(let d): return "無回復路徑：\(displaySafeInvisible(d, max: 300))"
            }
        }
    }

    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        var report = Report()
        let load = try store.load()

        // per-file trackedness：**乾跑與實跑都查**（#422 verify R2 L1——先前只在 apply 查，
        // 於是一筆未追蹤的 venue 在乾跑印成「將分類」、apply 時才進 failed；乾跑的價值是
        // 誠實預告，兩種模式必須看到同一組拒絕）。沿用 `VenueMigration` 的既有形狀。
        guard let out = LibraryStore.git(["ls-files", "-z", "--", "entities"],
                                         in: store.root), out.status == 0 else {
            throw MigrationError.noRecoveryPath(
                detail: "git ls-files 無法執行——無從確認追蹤狀態")
        }
        let trackedRelPaths = Set(out.out.split(separator: "\0").map { Data($0.utf8) })

        // 乾跑與實跑走**同一組**寫入閘（#422 verify R1，security F4）：注定會 throw 的記錄
        // 不該被印成「將分類」；實跑則逐筆 do/catch 收進 `failed`，而不是讓例外穿出
        // `run()` 把整份報告連同已落盤的寫入一起丟掉（`LibraryStore.assertVenueWritable`
        // 的 doc 記著 #394 踩過的正是這個形狀）。
        let format = try StoreVersion.read(root: store.root)

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
            // 而那個前提在帶時間的記錄上不成立。判準與 `Venue.validate()` 的
            // 「variant 不得帶時間」共用同一個 `DateRange.makesTemporalClaim`——兩份會分岔。
            let temporal = items.contains { $0.range.makesTemporalClaim }
            guard !temporal else {
                report.hasTemporal.append(venue.key)
                continue
            }
            // **`authorized` 為空 → 不分類**（理由見 `Report.noAuthorized` 的 doc）。
            guard !venue.authorized.isEmpty else {
                report.noAuthorized.append(venue.key)
                continue
            }
            let authorized = Set(venue.authorized)
            let variants = items.map(\.value).filter { !authorized.contains($0) }
            guard !variants.isEmpty else {
                report.allAuthorized.append(venue.key)
                continue
            }
            report.planned.append(Planned(key: venue.key, variants: variants))

            var updated = venue
            updated.variant = variants
            let relFile = "entities/\(venue.id.uuidString).yaml"
            guard trackedRelPaths.contains(Data(relFile.utf8)) else {
                report.failed.append(Failed(
                    key: venue.key,
                    reason: "\(relFile) 未被 git 追蹤——改寫無回復路徑，先 commit 再跑"))
                report.planned.removeLast()
                continue
            }
            if apply {
                do {
                    _ = try store.writeVenue(updated)
                    report.applied += 1
                } catch {
                    report.failed.append(Failed(key: venue.key, reason: "寫入失敗：\(error)"))
                    report.planned.removeLast()
                }
            } else {
                do {
                    try LibraryStore.assertVenueWritable(updated, format: format)
                } catch {
                    report.failed.append(Failed(key: venue.key, reason: "寫入閘會拒絕：\(error)"))
                    report.planned.removeLast()
                }
            }
        }
        return report
    }

    /// 下一步的提示——與 `VenueMigration.nextStep` 同形。
    /// #472：`current` 是 store 現在的 marker（讀不到給 nil）——先前無條件印「改成 14」，
    /// 而那在今天的 store 上是降級指示。目標與提示分開：目標是本遷移這一代的常數，
    /// 提示由 `StoreVersion.bumpHint` 依現況決定。
    public static let targetFormat = 14

    public static func nextStep(report: Report, apply: Bool, current: Int?) -> String? {
        if !apply && !report.planned.isEmpty {
            return "這是乾跑，store 沒有被改動。確認以上分類無誤後加 --apply。\n"
                 + "**--apply 不會改 store.yaml 的 format**——"
                 + StoreVersion.bumpHint(target: targetFormat, current: current)
        }
        if apply && report.applied > 0 {
            return "接下來：`akashic validate` 確認零新 diagnostic。"
                 + StoreVersion.bumpHint(target: targetFormat, current: current)
        }
        return nil
    }
}
