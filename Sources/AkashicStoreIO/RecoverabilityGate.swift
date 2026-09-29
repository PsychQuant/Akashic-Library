import Foundation
import AkashicCore

/// **可回溯閘的共用核心**（#573 一族；#642 R1 verify 把它一般化到 registry 檔）。
///
/// 會改寫或刪掉資料的寫入，舊版要在 git 裡拿得回來——記錄檔要 tracked、clean、HEAD 可解析、沒有 index 位元
/// （檢查本身是 `filesNotSafelyRecoverable`）。先前這條只涵蓋 `entities/<uuid>.yaml`（`AkashicService.assertRecordsRecoverable`），
/// 而 library 的 registry 檔（`libraries/<key>.yaml`）在別處：`set-kind` 整值替換一條規則、改名把規則裡的 citekey 換掉，
/// 舊值同樣只剩 git 那一份。所以**訊息與判斷只有這一份**——實體記錄與 registry 檔都經它，呼叫端只負責把路徑交進來、
/// 把回傳的句子包成自己那一層的錯誤型別。
extension LibraryStore {
    /// registry 檔相對 store root 的路徑。
    public static func libraryRelativePath(key: String) -> String { "libraries/\(key).yaml" }

    /// - present：（相對 root 的路徑, 人讀的標籤——已消毒）——記錄檔在磁碟上。
    /// - missing：（人讀的標籤——已消毒）——找不到記錄檔，無從確認 git 裡有副本，一律拒絕。
    /// - action：這次會改寫／刪掉什麼的一句（已消毒）；issue：字面常量。
    ///
    /// 回傳 `nil`＝全部可回溯；否則是拒絕的整句。順序固定：先分辨「不在 git 裡」（否則下面那支檢查對非工作樹回的是
    /// 「無法執行 git」，指錯原因）→ 找不到的 → 不可回溯的。
    public static func recoverabilityRefusal(root: URL,
                                             present: [(path: String, label: String)],
                                             missing: [String],
                                             action: String, issue: String) -> String? {
        guard !present.isEmpty || !missing.isEmpty else { return nil }
        guard isInsideVersionedWorkTree(root) else {
            return "\(action)，而 store 不在 git 工作樹裡——被改寫或刪掉的舊版不會留下任何副本。"   // display-safe-exempt: action 由呼叫端組、已消毒
                 + "把 store 放進 git 並 commit 後再跑（\(issue)）；整批拒絕、零寫入"   // display-safe-exempt: issue 是字面常量
        }
        guard missing.isEmpty else {
            return "\(action)，但下列記錄找不到記錄檔、無從確認 git 裡有副本："   // display-safe-exempt: action 已消毒
                 + capped(missing) + "（\(issue)）；整批拒絕、零寫入"   // display-safe-exempt: missing 的每一項由呼叫端消毒；issue 是字面常量
        }
        let bad = filesNotSafelyRecoverable(root: root, relativePaths: present.map(\.path))
        guard !bad.isEmpty else { return nil }
        let labelByPath = Dictionary(present.map { ($0.path, $0.label) }, uniquingKeysWith: { a, _ in a })
        let lines = capped(bad.map { "\(labelByPath[$0.path] ?? displaySafeInvisible($0.path, max: 200))：\($0.why)" })   // display-safe-exempt: label 由呼叫端消毒；why 是 filesNotSafelyRecoverable 的固定句
        return "\(action)，而舊版的唯一副本會是 git——下列記錄檔不能確認可回溯："   // display-safe-exempt: action 已消毒
             + lines + "。先 commit 再跑（\(issue)）；整批拒絕、零寫入"   // display-safe-exempt: lines 的 label 已消毒、why 是本 package 的固定句；issue 是字面常量
    }

    /// 進拒絕訊息的清單上限：列 10 項、其餘只說數量（與 `AkashicService.listCapped` 同一個上限；那邊在 MCPKit，這裡不能引用）。
    private static func capped(_ items: [String]) -> String {
        let cap = 10
        let shown = items.prefix(cap).joined(separator: "、")
        return items.count > cap ? shown + "…（共 \(items.count) 項）" : shown   // display-safe-exempt: Int；shown 的每一項由呼叫端消毒
    }
}
