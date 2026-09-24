import Foundation

extension Sequence where Element == Entry {
    /// 出現兩次以上的 citekey（#627）。
    ///
    /// citekey 重複是 store「被支援的損壞態」：載入不拒、`validate` 另行報告。但寫入路徑
    /// 多半以 citekey 當 entry 的唯一鍵，用 `Dictionary(…, uniquingKeysWith:)` 靜默選一筆——
    /// 於是判定可能寫到**另一筆 work 的另一個作者**上，而且不出聲。凡是以 citekey 定位
    /// entry 的寫入面，都先問這個集合：命中就拒絕或具名略過，不猜是哪一筆。
    ///
    /// **只有這一個定義**——各路徑各算一次會長出兩種「重複」的意思。
    public var duplicatedCitekeys: Set<String> {
        var seen = Set<String>(), dup = Set<String>()
        for e in self where !seen.insert(e.citekey).inserted { dup.insert(e.citekey) }
        return dup
    }
}
