import Foundation
import AkashicCore

/// 一個**registry 解析過**的 store（#125 第三層）。
///
/// ## 它擋的是什麼
///
/// `LibraryStore(root:)` 建出來的是 keyless store——它的 index 回落 in-store
/// `.akashic/`。對一個**已註冊**的 store 這樣做，會在它裡面長出一個永遠用不到的
/// index，並且**重建錯的那個**（`~/.akashic/index/<key>.sqlite` 從來沒被更新）。
///
/// #101 修過兩個這樣的呼叫點，並在 `LibraryStore` 留下註解要人一律走
/// `AppState.store`。#125 的 issue body 就是那段事故程式碼——而它在 #160 之後
/// **仍然編得過，而且逐字重現同一個事故**（席位 R2 實測：keyless 重建長出
/// in-store index、query 開不了檔）。
///
/// **今天沒事靠的是註解，而那正是本型別要取代的擋法。**
///
/// ## 為什麼是型別而不是更多註解
///
/// 註解擋不住新的呼叫點，也擋不住重構。型別可以：`GraphModel` 只收
/// `ResolvedStore`，於是 `GraphModel(store: LibraryStore(root: x))` **編不過**。
/// 那是 #125 的收工判準——它是機械可檢查的，不需要人記得。
///
/// ## 「解析過」包含「確定沒有 key」
///
/// keyless 是**合法**的狀態（未註冊的 store、`--library` 指到任意目錄）。本型別
/// 要求的不是「一定有 key」，而是「**有沒有 key 這件事被查過**」——`resolved(_:)`
/// 由 registry 解析路徑呼叫，`unregistered(_:)` 是顯式的 opt-out 且必須說明理由。
///
/// 兩者都合法，差別在**它有沒有被決定過**。事故的形狀不是「keyless 很壞」，是
/// 「一個已註冊的 store 被當成 keyless」——那是**沒查**，不是查了之後沒有。
public struct ResolvedStore {

    public let store: LibraryStore

    private init(_ store: LibraryStore) { self.store = store }

    /// 由 registry 解析而來（`AkashicHome.resolveDetailed` 或等價路徑）。
    ///
    /// 傳入的 store **必須**是用解析結果的 `root` 與 `key` 建的。這一層不重新
    /// 解析——那會讓同一件事有兩個答案；它只把「已經解析過」這個事實變成型別。
    public static func resolved(_ store: LibraryStore) -> ResolvedStore {
        ResolvedStore(store)
    }

    /// 顯式的 keyless opt-out。**理由是必填的**，與 `display-safe-exempt` 同一個
    /// 哲學：例外要留下可稽核的字，不能靠沉默通過。
    ///
    /// - Parameter reason: 為什麼這裡確定不需要 registry key（例如「測試用的
    ///   臨時 store，從未註冊」、「使用者以 `--library` 指向任意目錄」）。
    public static func unregistered(_ store: LibraryStore, reason: String) -> ResolvedStore {
        _ = reason   // 只為了讓呼叫端寫下它——編譯器強制存在，讀者強制看見
        return ResolvedStore(store)
    }
}
