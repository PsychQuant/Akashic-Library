import Foundation
import AkashicCore

/// 錯誤描述的消毒邊界（#554 R28，Claude 代裁 D80；R27 verify 第 1／2／5／12／14／27 列——`invalidInput` 對已消毒的 what／why 再逃一次、
/// quarantine 的 decode-error 支把 `StoreYAMLError` 內部已逃脫的片段再逃一次、`fmt` 疊到第三層）。
///
/// 規則只有一句：**store 字串在最靠近它的地方逃脫一次，之後每一層只截**。落到 `Error` 上是兩類：
///
/// - **自帶消毒的錯誤**（`isSelfSanitizing`）：`errorDescription` 在擲出端／描述端已逐項 `displaySafeInvisible`——`StoreYAMLError`
///   （每個 throw 站點，`SanitizationBoundaryTests` 掃全樹）、`StoreIOError`（`invalidInput` 的 what／why 由擲出端消毒、描述只截）、
///   `DivergenceResolveError`、兩個 `MigrationError`、`StoreIncarnationError`、`ConfigError`。對它們**只截**。
/// - **其餘**（Yams 的 parse error 帶逐字檔案內容、Foundation 的 I/O 錯誤、`StoreVersionError`……）：在這裡逃脫一次。
///
/// 封閉列舉由 `SanitizationBoundaryTests.testSelfSanitizingErrorTypesAreAClosedList` 釘住：AkashicCore／AkashicStoreIO 內 `errorDescription`
/// 含 `displaySafe` 的型別集合必須等於這裡的 `is` 鏈——新增一個自帶消毒的錯誤型別而沒加進來，守衛紅；加進來而它其實沒消毒，同樣紅。
public enum ErrorDisplay {
    public static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    public static func isSelfSanitizing(_ error: Error) -> Bool {
        error is StoreYAMLError
            || error is StoreIOError
            || error is DivergenceResolveError
            || error is StoreMigration.MigrationError
            || error is PersonIdentityMigration.MigrationError
            || error is StoreIncarnationError
            || error is ConfigError
    }
}

/// 一個 `Error` 的可顯示描述：自帶消毒的只截（上限放大到八倍——逃脫序列一個 scalar 佔 8 字元，`max` 對這一類數的是輸入側的量級），
/// 其餘逃脫一次。所有把 `Error` 變成字串送進 quarantine reason／fmt failure／MCP payload／CLI 的地方都走這裡，不得各自 `displaySafe(String(describing:))`。
public func displaySafeError(_ error: Error, max: Int) -> String {
    let text = ErrorDisplay.describe(error)
    return ErrorDisplay.isSelfSanitizing(error)
        ? displaySafeClipOnly(text, max: max * 8)   // display-safe-exempt: 已消毒（自帶消毒的錯誤型別，封閉列舉見 ErrorDisplay），只截
        : displaySafeInvisible(text, max: max)
}
