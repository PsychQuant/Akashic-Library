import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// 歧異記錄的移除面（#586；Spectra change `divergence-dismissal`）：一筆問題不成立、候選記錯了、或撞上沒有合併管線的
/// shape（`zero-instance-guards` 第 24 列），帶理由把那筆記錄刪掉——只刪記錄，不碰任何候選實體與參照。
///
/// spec 的「Deleting a record without rewriting its references SHALL NOT be offered」指的是**被併的候選實體**：刪掉它們
/// 而不改寫參照會留下懸空引用。歧異記錄本身沒有任何記錄指向它（`entity-backlink-completeness` 第 9、10 條邊都是從它
/// 指出去），刪掉不留懸空引用——本面在 spec 裡是自己的一條 Requirement，不是那句禁令的例外。
///
/// 使用者 2026-09-27 對移除面一族的裁決（同 #588 的 `--remove-issn`、#572 的 `--drop-venue`）：理由必填、只進報告，
/// 不寫進 store、不改 store format；刪除前要求記錄檔已 commit、乾淨（`assertRecordsRecoverable`）。乾跑只回報。
extension AkashicService {

    public func dismissDivergence(id raw: String, reason: String, dryRun: Bool) throws -> String {
        guard let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespaces)) else {
            throw ServiceError.invalid("「\(displaySafeInvisible(raw, max: 200))」不是合法的 UUID——歧異記錄以 id 定位（先用 divergences 列出）")
        }
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServiceError.invalid("理由是空白——理由是「為什麼這個問題不成立或不再延後」的紀錄，報告與 commit 靠它；零寫入")
        }
        guard reason.utf8.count <= Self.maxStatementBytes else {
            throw ServiceError.invalid("理由超過 \(Self.maxStatementBytes) 位元組——精簡它；零寫入")   // display-safe-exempt: Self.maxStatementBytes 是 Int 常數
        }
        let load = try store.load()
        guard let d = load.divergences.first(where: { $0.id == id }) else {
            throw ServiceError.notFound("歧異記錄「\(id.uuidString)」")   // display-safe-exempt: UUID 由型別保證
        }
        // **讀不懂的記錄不刪**（#75 的同一條理由）：一個帶未知欄位的記錄可能由較新的 binary 寫入，那個欄位也許正是
        // 「不要放棄這一筆」。刪除前 git 有副本，但刪掉自己讀不懂的東西仍是不該由工具做的判斷——拒絕並指向升級。
        guard d.unknownFields.isEmpty else {
            throw ServiceError.invalid(
                "歧異記錄「\(id.uuidString)」帶 \(d.unknownFields.count) 個本 binary 不認得的欄位——可能由較新版本寫入；"   // display-safe-exempt: UUID 由型別保證；Int
                + "讀不懂的記錄不刪（同 resolve-divergence 的 #75），升級 binary 後再跑；零寫入")
        }
        var payload: [String: Any] = [
            "id": id.uuidString,   // display-safe-exempt: UUID 由型別保證
            "question": displaySafe(d.question, max: 300),
            "candidates": d.candidates.map { "\($0.shape.rawValue):\(displaySafe($0.key, max: 200))" },   // display-safe-exempt: EntityKind 的 rawValue 是封閉值域
            "reason": displaySafe(reason, max: Self.maxStatementBytes),   // display-safe-exempt: reason 是呼叫端原樣輸入、未消毒——這裡是第一次逃脫
        ]
        if dryRun {
            payload["dryRun"] = true   // display-safe-exempt: Bool
            payload["note"] = "乾跑：不動任何檔案——實跑只刪這筆歧異記錄，候選實體與參照都不動"
            return try jsonString(payload)
        }
        try assertRecordsRecoverable([(id, "歧異記錄「\(id.uuidString)」")],   // display-safe-exempt: UUID 由型別保證
                                     action: "這次會刪掉 1 筆歧異記錄",
                                     issue: "#586")
        // 路徑取自磁碟上的實際檔名（`assertRecordsRecoverable` 已確認它存在）——不由 id 拼，小寫 UUID 檔名也對得上（#573 R1）
        guard let rel = Self.entityRelativePaths(root: store.root)[id] else {
            throw ServiceError.notFound("歧異記錄「\(id.uuidString)」的檔案")   // display-safe-exempt: UUID 由型別保證
        }
        try FileManager.default.removeItem(at: store.root.appendingPathComponent(rel))
        try LibraryIndex(store: store).rebuild()
        payload["dismissed"] = true   // display-safe-exempt: Bool
        payload["reasonNote"] = "理由只在這份報告裡——要留在 git，寫進接下來的 commit message（#586，使用者 2026-09-27 裁決）"
        return try jsonString(payload)
    }
}
