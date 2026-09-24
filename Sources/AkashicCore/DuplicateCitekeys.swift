import Foundation

extension Sequence where Element == Entry {
    /// 出現兩次以上的 citekey（#627）。寫入路徑要問的是涵蓋更廣的 `unlocatableCitekeys`。
    ///
    /// citekey 重複是 store「被支援的損壞態」：載入不拒、`validate` 另行報告。但寫入路徑
    /// 多半以 citekey 當 entry 的唯一鍵，用 `Dictionary(…, uniquingKeysWith:)` 靜默選一筆——
    /// 於是判定可能寫到**另一筆 work 的另一個作者**上，而且不出聲。凡是以 citekey 定位
    /// entry 的寫入面，都先問 `unlocatableCitekeys`：命中就拒絕或具名略過，不猜是哪一筆。
    ///
    /// **只有這一個定義**——各路徑各算一次會長出兩種「重複」的意思。
    public var duplicatedCitekeys: Set<String> {
        var seen = Set<String>(), dup = Set<String>()
        for e in self where !seen.insert(e.citekey).inserted { dup.insert(e.citekey) }
        return dup
    }

    /// 無法唯一定位一筆 work 檔的 citekey（#627 R2）：citekey 重複，**或**該 entry 的 id 與另一筆
    /// 共用。後者的 citekey 本身唯一，但寫入以 id 定檔（`entities/<id>.yaml`），改它等於改兄弟
    /// 的檔——實測 drop-author 會把另一筆 work 整個蓋掉。resolve-people 各腿問的是這個集合。
    public var unlocatableCitekeys: Set<String> {
        var idCount: [UUID: Int] = [:]
        for e in self { idCount[e.id, default: 0] += 1 }
        var out = duplicatedCitekeys
        for e in self where idCount[e.id, default: 0] > 1 { out.insert(e.citekey) }
        return out
    }
}
