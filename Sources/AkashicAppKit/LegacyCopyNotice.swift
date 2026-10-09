import Foundation
import AkashicCore
import AkashicStoreIO

/// App 的寫入留下 legacy 拷貝時的非阻斷提示（#708）。
///
/// 使用者 2026-09-30 裁決：App 的寫入遇到「寫進 `entities/`、搬移後的 legacy 拷貝刪不掉」時，動作照常算**成功**，另以一個非阻斷的提示
/// 列出要清的 legacy 檔——與 CLI、MCP、import-zotero 把它記在成功那一側的 `writtenWithLegacyCopy`（#705）同一個說法。
/// 先前 App 沒有收集範圍，同一件事擲 `legacyCopyNotRemoved`、畫面上是「操作失敗」。
///
/// 內容就是 `LegacyCopyLeft` 本身，文字取自同一個來源：這件事是什麼的一句說明是 `LegacyCopyLeft.explanation`（CLI 末尾與 MCP 錯誤回應的標題
/// 也用它），每一列的完整說明是 `LegacyCopyLeft.message`——App 不另寫第三份描述。**標題是一般說明文字，不是 CLI／MCP 的 JSON 鍵名**
/// （R1 verify 第 12／32 列：先前直接取報告的第一行，GUI 使用者在側欄看到 `writtenWithLegacyCopy（…）: N`）。
///
/// 住在 View 之外（同 `RecordIssuesSummary`）：`AkashicApp/` 的 UI 不在 SwiftPM 測試範圍，能測的部分要最大化；View 只收這個值型別。
public struct LegacyCopyNotice: Equatable {
    /// 收到的每一筆，依收到的順序；同一筆（kind、id、legacy 檔）只留一次、留**最新**的那一筆（key 與說明可能隨再一次留下而更新）。
    public let items: [LegacyCopyLeft]
    /// 這份提示屬於哪個 store：每一列顯示 legacy 檔的**完整路徑**要它，`stillPresent` 檢查兩個檔還在不在也要它。
    public let root: URL

    /// 提示的一列：哪一筆記錄、要清的是哪個 legacy 檔。顯示字串都已消毒（`display*`）。
    public struct Row: Identifiable, Equatable {
        /// 以原始值組成（不顯示），同一筆記錄的同一個 legacy 檔只有一列。
        public let id: String
        /// `work「citekey」`／`person「key」`。
        public let displayRecord: String
        /// 要清的 legacy 檔，相對 store root（`entries/<citekey>.yaml`／`people/<key>.yaml`）。
        public let displayLegacyFile: String
        /// 要清的 legacy 檔的**完整路徑**（store root ＋ 相對路徑）：側欄顯示它，使用者不必自己知道 store 在哪裡才刪得掉（R1 verify 第 12／32 列）。
        public let displayLegacyPath: String
        /// 寫進去的那一份（`entities/<id>.yaml`）。
        public let writtenFile: String
        /// 完整說明，與 CLI／MCP 的每一筆同一句（`LegacyCopyLeft.message`，已消毒）。
        public let displayDetail: String
    }

    init(items: [LegacyCopyLeft], root: URL) {
        self.items = items
        self.root = root
    }

    /// 併入新收到的幾筆，回傳新的提示（不改自己）。同一個 legacy 檔再次留下時，換成最新的那一筆（原位置不動）。
    func adding(_ new: [LegacyCopyLeft]) -> LegacyCopyNotice {
        var merged = items
        for item in new {
            if let i = merged.firstIndex(where: { Self.sameLeftover($0, item) }) {
                merged[i] = item
            } else {
                merged.append(item)
            }
        }
        return LegacyCopyNotice(items: merged, root: root)
    }

    /// 只留**兩個檔都還在**的那幾筆：legacy 那份還在、而且寫進去的那份（`entities/<id>.yaml`）也還在；一筆都不剩就回 nil。
    /// 使用者刪掉 legacy 那份之後，提示不再叫他去清一個已經不在的檔；**寫進去的那份不見了**（git 還原、手動清理、別的工具）時，legacy 檔成了
    /// 唯一的一份，這一列的指示「刪掉 legacy 那份」會刪掉唯一的拷貝——所以那一列要拿掉（#708 R1 verify 第 11 列）。
    func stillPresent() -> LegacyCopyNotice? {
        let fm = FileManager.default
        let left = items.filter {
            fm.fileExists(atPath: root.appendingPathComponent($0.legacyFile).path)
                && fm.fileExists(atPath: root.appendingPathComponent($0.writtenFile).path)
        }
        return left.isEmpty ? nil : LegacyCopyNotice(items: left, root: root)
    }

    public var rows: [Row] {
        items.map { item in
            Row(id: "\(item.kind.rawValue):\(item.id.uuidString):\(item.legacyFile)",   // display-safe-exempt: item.legacyFile：只當列的識別、不顯示
                displayRecord: "\(item.kind.rawValue)「\(displaySafeInvisible(item.key, max: 200))」",
                displayLegacyFile: displaySafeInvisible(item.legacyFile, max: 300),
                displayLegacyPath: displaySafeInvisible(root.appendingPathComponent(item.legacyFile).path, max: 600),
                writtenFile: item.writtenFile,
                // 之後的寫入沒有套用的那一筆，附上與 CLI／MCP 同一句（`reportLines` 的附句、MCP 列的 `laterWriteNotApplied`）——
                // 先前 App 的提示讀不到這個旗標（#708 R2 verify 第 34 列）
                displayDetail: item.message + (item.laterWriteRefused ? "；" + LegacyCopyLeft.laterWriteRefusedNote : ""))   // display-safe-exempt: item.message：LegacyCopyLeft.message 已消毒（key 逐項 displaySafeInvisible、detail 擲出端已消毒）；laterWriteRefusedNote：常量字面
        }
    }

    /// 標題：一般說明文字（不是 CLI／MCP 的鍵名）。這件事是什麼的一句說明與 CLI／MCP 的報告標題是同一份（`LegacyCopyLeft.explanation`），
    /// 另加一句**只陳述可確定的事**：留下拷貝本身不算失敗；同一個動作若另有錯誤，請依那個錯誤的訊息處理，而後續的寫入**可能**因為
    /// 兩份並存而被拒絕（`LegacyCopyLeftBeforeFailure`：寫了、拷貝留下、之後的步驟才失敗）。
    ///
    /// **不得說「那是別的原因、與這份拷貝無關」**（#708 R2 verify 第 1 列）：`LegacyCopyLeft.laterWriteRefused` 標的正是相反的情形——同一個操作
    /// 之後對同一筆的寫入被 #631 拒絕，**原因就是這份拷貝**（兩份並存時 #631 拒絕同一筆的下一次寫入），那一步沒有套用。先前的標題把這個後續錯誤
    /// 一概歸給別的原因，使用者會同時看到拒寫的錯誤與否認其原因的提示，被引去找別的原因、而不是去清留下的拷貝。
    /// 有任何一筆標了 `laterWriteRefused` 時，標題另說這一件事（與 CLI／MCP 同一句 `laterWriteRefusedNote`）。
    ///
    /// 第二句不再重複「刪掉 legacy 那份」、不說「即可」（#705 第四次 verify INFO 29）：`explanation` 剛說完「確認 entities/ 那份是新的之後刪掉」，
    /// 先前緊接著再說一次「刪掉 legacy 那份之後重跑即可」，把上一輪拿掉的「即可」與無前提的刪除又放回同一個標題。
    ///
    /// 有 `laterWriteRefused` 時那一句也一樣（#709 b36 verify LOW 10、16、17）：先前接的是整句 `laterWriteRefusedNote`（「刪掉 legacy 那份之後重跑即可補上」），
    /// 那一支把無前提的刪除與「即可」又放回標題，而測試只驗了沒有被拒的那一支。標題接的是事實（`laterWriteRefusedFact`），處置直接寫「拷貝處理掉之後」——
    /// 不靠「照上一句」的位置指涉（標題被拆行或接在別處時「上一句」不一定是 explanation）。
    public var headline: String {
        let base = "\(LegacyCopyLeft.explanation)（\(items.count) 筆）。同一個動作若另有錯誤，請依那個錯誤的訊息處理；後續的寫入可能因為這份 legacy 拷貝還在（兩份並存）而被拒絕——拷貝處理掉之後重跑那些寫入。"   // display-safe-exempt: explanation：常量字面；count：Int
        let refused = items.filter(\.laterWriteRefused).count
        guard refused > 0 else { return base }
        return base + "其中 \(refused) 筆：\(LegacyCopyLeft.laterWriteRefusedFact)，拷貝處理掉之後要重跑才補得上。"   // display-safe-exempt: refused：Int；laterWriteRefusedFact：常量字面
    }

    private static func sameLeftover(_ a: LegacyCopyLeft, _ b: LegacyCopyLeft) -> Bool {
        a.kind == b.kind && a.id == b.id && a.legacyFile == b.legacyFile
    }
}
