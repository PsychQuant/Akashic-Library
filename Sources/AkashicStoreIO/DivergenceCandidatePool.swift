import Foundation
import AkashicCore

/// 歧異記錄的「候選存在」檢查用的 key 集合——依形狀一份，建一次、每一筆共用（#611 R1 verify 第 5 列）。
///
/// 先前 `recordDivergence` 每記一筆就把四個形狀的 key 集合整個重建一遍（約 7.6k 個鍵）——只省了磁碟讀取，省不了這一段。
/// Zotero 匯入一趟可能記下很多筆，所以集合由呼叫端建一次交進來（`recordDivergence(…against:)`）。
/// 歧異記錄本身沒有 key，寫入它不改變任何形狀的 key 集合，所以一趟之內這份集合不必隨寫隨更新。
public struct DivergenceCandidatePool {
    let keys: [EntityKind: Set<String>]

    public init(_ load: LibraryLoad) {
        // **per-shape 存在檢查**（#133 verify F2）：曾用 people ∪ organizations 的
        // 合集只驗 key 不驗 shape——person 被記成 work 照樣寫入，validate 警告
        // 「無法被消歧」而 MCP 面完全看不見；真正的 work（citekey）反而不在集合裡、
        // 結構上不可用。shape 說是什麼，就到那個形狀的集合裡驗。
        // 窮舉 switch 而不是字典字面值（#699 R1 verify）：`crossRecordIssues` 的查找表同一個形狀，字面值漏了 `.venue` 而編譯器看不出來；
        // switch 讓下一個新形狀在這裡也編不過，要當場決定它收不收。
        var byShape: [EntityKind: Set<String>] = [:]
        for kind in EntityKind.allCases {
            switch kind {
            case .person: byShape[kind] = Set(load.people.map(\.key))
            case .organization: byShape[kind] = Set(load.organizations.map(\.key))
            case .work: byShape[kind] = Set(load.entries.map(\.citekey))
            // #553：venue 加入。**與 `resolveDivergence` 的 switch 必須同一個 change**
            // ——`.organization` 今天正是那個半吊子狀態（記得起來、解不掉），
            // venue 不重蹈。**org 維持這個狀態是 #555 的顯式裁決**（使用者 2026-09-11：暫不做，既不實作也不拿掉），
            // 理由、代價與觸發條件在 `zero-instance-guards` 第 24 列；`StoreHealth.unmergeableDivergences` 讓第一筆
            // org 歧異記錄出聲（#555 R2 D90）。不要把這一格當成待修的殘留（#555 R1 verify 第 15 列）。
            case .venue: byShape[kind] = Set(load.venues.map(\.key))
            // 歧異記錄沒有 key（身分是 UUID），不收——`checkDivergenceArguments` 在讀 store 之前就拒絕它；
            // 沒有集合的形狀走 `recordDivergence` 的「合併管線尚未實作」那一則。
            case .divergence: break
            }
        }
        keys = byShape
    }
}

extension LibraryStore {
    /// 寫入當下磁碟上 `entities/<id>.yaml` 的那一筆歧異記錄（#611 R1 verify 第 25／31 列）。
    ///
    /// 沒有檔、讀不出來、或解出來不是同一個 id 的歧異記錄，都回 nil：前兩者交給 `writeDivergence` 的 `assertEntitiesDestination`
    /// 具名拒絕（被 quarantine 的記錄、另一種記錄），這裡不重複那一條。只讀一個檔。
    func divergenceOnDisk(id: UUID) -> Divergence? {
        let dest = entityURL(id: id)
        guard FileManager.default.fileExists(atPath: dest.path),
              let text = try? String(contentsOf: dest, encoding: .utf8),
              let d = try? DivergenceYAML.decode(text), d.id == id else { return nil }
        return d
    }
}
