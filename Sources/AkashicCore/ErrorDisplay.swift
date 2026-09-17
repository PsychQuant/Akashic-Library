import Foundation

/// **自帶消毒的錯誤型別**（#554 R29，Claude 代裁 D81；R28 verify 第 1／5／7／10／13／14／15／17／19／32／37／40 列）：`errorDescription`
/// （或 `description`）裡的每一個 store／呼叫端字串都已在擲出端或描述端以 `displaySafeInvisible` 逃脫一次，所以任何把它變成文字的
/// 地方**只截不逃**。R28 把這個集合寫成 AkashicStoreIO 裡的一條 `is` 鏈——`ServiceError` 住在 AkashicMCPKit（相依方向相反）、
/// `IndexError`／`QueryError`／`GraphError`／App 的錯誤住在別的模組，鏈碰不到它們，於是「唯一入口」對一半的型別是假的，而守衛只掃兩個目錄。
/// 改成 protocol 之後每個模組自己宣告，`SanitizationBoundaryTests.testSelfSanitizingErrorTypesAreAClosedList` 掃**全樹**：描述裡有逃脫的
/// 型別必須 conform、conform 的型別描述裡不得再有列舉式 `displaySafe(`。
///
/// **conform 的義務**：描述裡的插值要嘛是性質式逃脫（`displaySafeInvisible`）、要嘛是程式構造值；**不得**在描述裡再對已消毒的參數逃脫
/// （`ServiceError` 的 what／why 由 140 個擲出站點消毒，描述原樣回傳——那是同一條義務的另一種分工，守衛掃擲出站點）。
public protocol SanitizedErrorDescription: Error {}

/// 錯誤描述的消毒邊界（#554 R28 D80 → R29 D81）。規則只有一句：**store 字串在最靠近它的地方逃脫一次，之後每一層只截**。
/// 落到 `Error` 上是兩類——自帶消毒的（`SanitizedErrorDescription`）只截；其餘（Yams 的 parse error 帶逐字檔案內容、Foundation 的 I/O
/// 錯誤、`StoreVersionError`……）在這裡逃一次。所有把 `Error` 變成字串送給人或 LLM 的地方（quarantine reason、fmt failure、MCP 的錯誤
/// 出口、App 的錯誤面、CLI 的 `ValidationError` 包裝）都走 `displaySafeError`／`displaySafeErrorMultiline`，不得各自
/// `displaySafe(String(describing:))`——R28 verify 第 1／7／15 列：MCP 與 App 的出口各自逃脫，把擲出端已逃的 `\u{0007}` 變成 `\u{005C}u{0007}`。
public enum ErrorDisplay {
    public static func describe(_ error: Error) -> String {
        if let d = (error as? LocalizedError)?.errorDescription { return d }   // display-safe-exempt: 這裡就是 Error → 文字的唯一入口（D81）
        // Foundation 的 `NSError` 不符合 `LocalizedError`，而它的 `String(describing:)` 是
        // `Error Domain=NSCocoaErrorDomain Code=513 …UserInfo={…NSFileNewItemLocationKey=….tmp-…}` 那種原始 dump——
        // 在 512 字被截斷、把 atomicWrite 的暫存檔名漏出去（#146 verify G3，ProvenanceMigration 曾為此單獨改用 `localizedDescription`）。
        // Swift 自己的 enum error 相反：`localizedDescription` 是「The operation couldn't be completed. (Module.Type error 1.)」，
        // `String(describing:)` 才有內容。以「真的是 NSError 子類」分流，兩邊各取有內容的那個。
        if type(of: error) is NSError.Type { return error.localizedDescription }   // display-safe-exempt: 同上
        return String(describing: error)   // display-safe-exempt: 同上
    }

    public static func isSelfSanitizing(_ error: Error) -> Bool { error is SanitizedErrorDescription }
}

/// 單行：自帶消毒的只截（上限放大到八倍——逃脫序列一個 scalar 佔 8 字元，`max` 對這一類數的是輸入側的量級），其餘逃脫一次。
public func displaySafeError(_ error: Error, max: Int) -> String {
    let text = ErrorDisplay.describe(error)
    return ErrorDisplay.isSelfSanitizing(error)
        ? displaySafeClipOnly(text, max: max * 8)   // display-safe-exempt: 已消毒（SanitizedErrorDescription），只截
        : displaySafeInvisible(text, max: max)
}

/// 多行（MCP 的錯誤出口、App／CLI 把整則描述給人看）：自帶消毒的走 `displaySafeAssembled`（逐行只截、合法反斜線原樣——與 CLI 的
/// 頂層 sink 同一條），其餘走 `displaySafeMultiline`（逐行逃脫一次）。
public func displaySafeErrorMultiline(_ error: Error, maxLineLength: Int = 400) -> String {
    let text = ErrorDisplay.describe(error)
    if ErrorDisplay.isSelfSanitizing(error) {
        return displaySafeAssembled(text, maxLineLength: maxLineLength)   // display-safe-exempt: 已消毒（SanitizedErrorDescription），只截
    }
    // 非自帶消毒的錯誤（Yams、Foundation）：逐行列舉式逃脫之後再以性質逃脫不可見 scalar——與 `displaySafeInvisible` 同一個組合，只是
    // 保留 LF 當行分隔（`escapingInvisibleScalars` 會把 LF 當 Cc 逃掉，所以先切行再套）。
    return displaySafeMultiline(text, maxLineLength: maxLineLength)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { escapingInvisibleScalars(String($0)) }
        .joined(separator: "\n")
}
