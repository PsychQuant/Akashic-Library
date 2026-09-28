import ArgumentParser
import AkashicCore

/// 服務層（與 store 層）做的 argv 檢查，在 CLI 的 `validate()` 跑（#654）。
///
/// 判準寫在 `RuntimeFailure` 的 doc：只看解析後的 argv 就判得出來 → 用法錯誤（exit 64、印子命令 usage）。這類檢查有些住在
/// `AkashicService`（MCP 也要同一道檢查），先前 CLI 呼叫服務時它們跟著 `ServiceError` 一起變成 exit 1。現在服務把它們暴露成
/// **不碰 store 的 static 函式**：服務方法開頭呼叫一次，CLI 的 `validate()` 呼叫同一個函式、把它的錯誤轉成 `ValidationError`
/// ——同一件事只有一份描述（`no-compat-fallback`），而 `validate()` 早於開 store，缺佈局也不會搶先報執行期失敗。
///
/// `body` 裡只放純函式：它丟的任何錯誤都被當成用法錯誤。錯誤的 payload 已在擲出端逃過一次（`ServiceError`／`StoreIOError` 都自帶消毒），
/// `displaySafeErrorText` 對它們原樣回傳，不再逃（`displaySafe` 不冪等）。
func argvCheck(_ body: () throws -> Void) throws {
    do {
        try body()
    } catch {
        throw ValidationError(displaySafeErrorText(error))
    }
}
