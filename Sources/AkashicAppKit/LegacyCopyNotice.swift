import Foundation
import AkashicCore
import AkashicStoreIO

/// App 的寫入留下 legacy 拷貝時的非阻斷提示（#708）。
///
/// 使用者 2026-09-30 裁決：App 的寫入遇到「寫進 `entities/`、搬移後的 legacy 拷貝刪不掉」時，動作照常算**成功**，另以一個非阻斷的提示
/// 列出要清的 legacy 檔——與 CLI、MCP、import-zotero 把它記在成功那一側的 `writtenWithLegacyCopy`（#705）同一個說法。
/// 先前 App 沒有收集範圍，同一件事擲 `legacyCopyNotRemoved`、畫面上是「操作失敗」。
///
/// 內容就是 `LegacyCopyLeft` 本身，文字取自同一個來源：說明是 `LegacyCopyLeft.reportLines` 的第一行（CLI 末尾與 MCP 錯誤回應印的那一行），
/// 每一列的完整說明是 `LegacyCopyLeft.message`——App 不另寫第三份描述。
///
/// 住在 View 之外（同 `RecordIssuesSummary`）：`AkashicApp/` 的 UI 不在 SwiftPM 測試範圍，能測的部分要最大化；View 只收這個值型別。
public struct LegacyCopyNotice: Equatable {
    /// 收到的每一筆，依收到的順序；同一筆（kind、id、legacy 檔）只留一次。
    public let items: [LegacyCopyLeft]

    /// 提示的一列：哪一筆記錄、要清的是哪個 legacy 檔。顯示字串都已消毒（`display*`）。
    public struct Row: Identifiable, Equatable {
        /// 以原始值組成（不顯示），同一筆記錄的同一個 legacy 檔只有一列。
        public let id: String
        /// `work「citekey」`／`person「key」`。
        public let displayRecord: String
        /// 要清的 legacy 檔，相對 store root（`entries/<citekey>.yaml`／`people/<key>.yaml`）。
        public let displayLegacyFile: String
        /// 寫進去的那一份（`entities/<id>.yaml`）。
        public let writtenFile: String
        /// 完整說明，與 CLI／MCP 的每一筆同一句（`LegacyCopyLeft.message`，已消毒）。
        public let displayDetail: String
    }

    init(items: [LegacyCopyLeft]) {
        self.items = items
    }

    /// 併入新收到的幾筆，回傳新的提示（不改自己）。
    func adding(_ new: [LegacyCopyLeft]) -> LegacyCopyNotice {
        var merged = items
        for item in new where !merged.contains(where: { Self.sameLeftover($0, item) }) {
            merged.append(item)
        }
        return LegacyCopyNotice(items: merged)
    }

    /// 只留 legacy 檔還在 `root` 底下的那幾筆；一筆都不剩就回 nil。使用者刪掉 legacy 那份之後，提示不再叫他去清一個已經不在的檔。
    func stillPresent(under root: URL) -> LegacyCopyNotice? {
        let left = items.filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0.legacyFile).path) }
        return left.isEmpty ? nil : LegacyCopyNotice(items: left)
    }

    public var rows: [Row] {
        items.map { item in
            Row(id: "\(item.kind.rawValue):\(item.id.uuidString):\(item.legacyFile)",   // display-safe-exempt: item.legacyFile：只當列的識別、不顯示
                displayRecord: "\(item.kind.rawValue)「\(displaySafeInvisible(item.key, max: 200))」",
                displayLegacyFile: displaySafeInvisible(item.legacyFile, max: 300),
                writtenFile: item.writtenFile,
                displayDetail: item.message)   // display-safe-exempt: item.message：LegacyCopyLeft.message 已消毒（key 逐項 displaySafeInvisible、detail 擲出端已消毒）
        }
    }

    /// 說明：CLI 與 MCP 的人可讀報告的第一行（鍵名＋筆數）。
    public var headline: String { LegacyCopyLeft.reportLines(items).first ?? "" }

    private static func sameLeftover(_ a: LegacyCopyLeft, _ b: LegacyCopyLeft) -> Bool {
        a.kind == b.kind && a.id == b.id && a.legacyFile == b.legacyFile
    }
}
