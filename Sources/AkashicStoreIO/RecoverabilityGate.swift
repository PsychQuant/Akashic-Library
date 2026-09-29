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

    /// 一句理由／說明的位元組上限（#683 從 `AkashicService` 搬到這一層）。
    ///
    /// 移除面一族（#573／#588／#572／#586／#609）的理由、未決腿與逐篇判定的說明、判斷型 reference 的 `statement` 都用這一個值——
    /// 它們是同一種東西：一段人寫的理由，進報告或進 store，超過即整批拒絕、不截斷（`lossless-intake` 的有界拒絕）。
    /// 先前定義在 `AkashicService`（MCPKit），而 App（AppKit）與 MCPKit 互不能 import，於是 #609 的 App 移除面自己寫了一個 `4_096`；
    /// 兩份各寫一次，改一邊另一邊不會跟著變（`no-compat-fallback` §同一件事只能有一份描述）。
    /// 數字的來源：`displaySafe` 對資料面的 800 字之數倍，讓一段完整的查證敘述放得下；2026-09-29 live store 最長的判定理由 687 位元組。
    public static let maxStatementBytes = 4_096

    /// `recordRecoverability` 的結果：`refusal` 為 nil ＝ 全部可回溯；`paths` 是驗過的記錄 id → 相對 store root 的路徑
    /// （同一次列舉的結果——要刪檔的呼叫端用它，不再列舉一次，#586 R1 verify）。
    public struct RecordRecoverability {
        public let refusal: String?
        public let paths: [UUID: String]
    }

    /// **可回溯閘的外層**（#683：`AkashicService.assertRecordsRecoverable` 的解析半邊搬到這一層，App 與 service 都呼叫它）。
    ///
    /// 把（記錄 id, 標籤）解析成磁碟上的實際檔案，再交給 `recoverabilityRefusal`。**路徑取自磁碟上的實際檔名，不由 id 拼**
    /// （#573 R1 verify Codex HIGH、DA 第 32 列）：load 接受小寫 UUID 檔名，git 的 pathspec 分大小寫，拼成大寫會對一個已 commit 的檔
    /// 永遠回「未被追蹤」。而共用的檢查對不存在的路徑是略過（刪檔的語意），在這裡等於沒檢查：找不到檔就拒絕，不放行。
    ///
    /// - items：（記錄 id, 人讀的標籤——已消毒）。
    /// - libraries：registry 檔（`libraries/<key>.yaml`，沒有 UUID）——#642 R1 verify。
    /// - legacyPaths：**format < 2 佈局**下某筆記錄的檔（`entries/<citekey>.yaml`）。entities 佈局的呼叫端不給；App 在 legacy 佈局的 store
    ///   開得起來，它的移除面先前就認得那個檔（與 `writeEntry` 選目的地的同一個判準），service 只認 `entities/`。這裡保留那個能力而不是
    ///   悄悄拿掉——只有給了才走，磁碟上找不到那個檔仍是「找不到」。
    /// - action：這次會改寫／刪掉什麼的一句（已消毒）；issue：字面常量。
    public static func recordRecoverability(root: URL,
                                            items: [(id: UUID, label: String)],
                                            libraries: [(key: String, label: String)] = [],
                                            legacyPaths: [UUID: String] = [:],
                                            action: String, issue: String) -> RecordRecoverability {
        guard !items.isEmpty || !libraries.isEmpty else { return RecordRecoverability(refusal: nil, paths: [:]) }
        let actual = items.isEmpty ? [:] : entityRelativePaths(root: root)
        var resolved: [UUID: String] = [:]
        var present: [(path: String, label: String)] = []
        var missing: [String] = []
        for item in items {
            if let path = actual[item.id] {
                resolved[item.id] = path
                present.append((path, item.label))
            } else if let legacy = legacyPaths[item.id],
                      FileManager.default.fileExists(atPath: root.appendingPathComponent(legacy).path) {
                resolved[item.id] = legacy
                present.append((legacy, item.label))
            } else {
                missing.append(item.label)
            }
        }
        for lib in libraries {
            let rel = libraryRelativePath(key: lib.key)
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(rel).path) {
                present.append((rel, lib.label))
            } else {
                missing.append(lib.label)
            }
        }
        let refusal = recoverabilityRefusal(root: root, present: present, missing: missing, action: action, issue: issue)
        return RecordRecoverability(refusal: refusal, paths: resolved)
    }

    /// 進拒絕訊息的清單上限：列 10 項、其餘只說數量（與 `AkashicService.listCapped` 同一個上限；那邊在 MCPKit，這裡不能引用）。
    private static func capped(_ items: [String]) -> String {
        let cap = 10
        let shown = items.prefix(cap).joined(separator: "、")
        return items.count > cap ? shown + "…（共 \(items.count) 項）" : shown   // display-safe-exempt: Int；shown 的每一項由呼叫端消毒
    }
}
