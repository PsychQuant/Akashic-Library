import Foundation

/// **自帶消毒的錯誤型別**（#554 R29，Claude 代裁 D81；R28 verify 第 1／5／7／10／13／14／15／17／19／32／37／40 列）：`errorDescription`
/// （或 `description`）裡的每一個 store／呼叫端字串都已在擲出端或描述端以 `displaySafeInvisible` 逃脫一次，所以任何把它變成文字的
/// 地方**只截不逃**。R28 把這個集合寫成 AkashicStoreIO 裡的一條 `is` 鏈——`ServiceError` 住在 AkashicMCPKit（相依方向相反）、
/// `IndexError`／`QueryError`／`GraphError`／App 的錯誤住在別的模組，鏈碰不到它們，於是「唯一入口」對一半的型別是假的，而守衛只掃兩個目錄。
/// 改成 protocol 之後每個模組自己宣告，`SanitizationBoundaryTests.testSelfSanitizingErrorTypesAreAClosedList` 掃**全樹**：型別宣告內
/// 任一處消毒 payload 的、或擲出站點對 payload 消毒的（R30，D82；R29 verify 第 3／4／6／14 列：`AuthorshipCompletenessValidationError`
/// 在 `init` 消毒、`StoreVersionError` 在擲出端消毒，R29 的守衛只看描述 body、兩者都漏），都必須 conform；conform 的型別描述裡不得再有
/// 列舉式 `displaySafe(`。
///
/// **conform 的義務**：每一個 payload **恰逃一次**——要嘛擲出端逃（描述原樣或只截）、要嘛描述端逃（擲出端傳原值）。守衛以
/// **payload 粒度**比對描述端與擲出站點（R30；R29 verify 第 17／22 列：R29 是 case 粒度、只掃四條手寫 needle，19 個型別裡 15 個的
/// 擲出站點沒人看）。
public protocol SanitizedErrorDescription: Error {}

/// 錯誤描述的消毒邊界（#554 R28 D80 → R29 D81 → R30 D82 → R31 D83）。規則只有一句：**store 字串在最靠近它的地方逃脫一次，之後每一層只截**。
/// 落到 `Error` 上是三個函式、一個順序：`displaySafeErrorText` 把 `Error` 變成**逃過一次、每行輸入有界、沒截**的文字（自帶消毒的原樣回傳，
/// 其餘逐行逃一次）；`displaySafeError` 對它折掉 LF 再只截（`max` 是**輸出** scalar 上限——R29 把 ×8 藏在函式內部，MCP 的 `applyDict["error"]`
/// 那一格因此拿到 4,096 而 changelog 說 512，R29 verify 第 23／24 列；R30 保留真 LF 進 `displaySafeClipOnly`，而它把 LF 逃成八個字元，
/// 512 個 LF 變 4,096——R30 verify 第 12 列）；`displaySafeErrorMultiline` 把前綴接上之後才交給 `displaySafeAssembled` 逐行截（含半截逃脫序列
/// 的退讓與 96 KB 總量上限——R29 在 96 KB 之後才套 `escapingInvisibleScalars`，實測 720 KB 進 MCP context，第 10／12／15／18 列；R29 的 MCP
/// 出口先截再加 `Error: `、CLI 先加再截，同一個錯誤兩面差 7 個字元，第 9 列）。
///
/// **輸入側的界是承重的**（R31 D83；R30 verify 第 1／3／6／9／35 列，CRITICAL）：R30 為了讓 sink 量最終輸出，把每行的逃脫改成
/// `displaySafe(line, max: .max)`——整行先逃完、再由 sink 丟掉 99.9%。錯誤文字是未信任的 store 內容（Yams 把出錯那一行逐字展開、不截），
/// 而 `escapingInvisibleScalars` 對每個要逃的 scalar 走一次 `String(format:)`，實測**接近二次**：400,000 個 ZWSP 的單行讓 `akashic validate`
/// 跑 20 秒、1 MB 96 秒、5 MB 兩次 300 秒都沒跑完；純 ASCII 仍是線性（第 35 列）。`displaySafe` 自己的 doc 早就寫著「`max` 才是本函式真正
/// 會接觸的上界」，R30 在兩個呼叫端違反了它而沒改 doc。修法不是回到 R29（sink 的 `max` 當輸入上限、輸出 ×8），是**輸入上限與輸出上限分開**：
/// 每行只讀 `inputScalarCeiling` 個 scalar——每個輸入 scalar 至少產生一個輸出 scalar，所以任何輸出上限 ≤ ceiling 的 sink 不需要更多輸入，
/// 截出來的字串與無界版本逐字相同（`testInputCeilingDoesNotChangeClippedOutput`）；ceiling 取全樹最大的 sink 輸出上限（CLI 的 4,096），
/// 守衛釘住「每個 `displaySafeError(max:)`／`maxLineLength` 都 ≤ ceiling」。行數不設上限：分行是線性的、每行工作有界，總工作量與輸入長度
/// 同階（實測 2 MB 單行 ZWSP < 0.05 秒、200,000 行 < 1 秒，`testErrorTextWorkIsLinearInTheInput`）。
///
/// 所有把 `Error` 變成字串送給人或 LLM 的地方都走這三個入口之一，不得各自 `"\(error)"`／`String(describing:)`
/// （R29 verify 第 5 列：`"\(error)"` 是守衛的結構盲區，11 個站點）。CLI 頂層對**非 ArgumentParser** 的錯誤也走 `displaySafeErrorText`
/// 再交給 `fullMessage`（R31；R30 verify 第 2 列：直接傳到頂層的 Yams／Foundation 錯誤只經列舉式的 `displaySafeAssembled`，ZWSP 原樣落 stderr）。
public enum ErrorDisplay {
    /// 每行逃脫前最多讀取的輸入 scalar 數＝全樹最大的 sink 輸出上限（CLI／App 的 4,096）。改 sink 上限時若超過它，守衛
    /// `testEverySinkBoundIsWithinTheInputCeiling` 會紅——那時要一起抬這個數，不是靜默讓 sink 拿到被 ceiling 截短的行。
    public static let inputScalarCeiling = 4_096

    /// atomicWrite 的暫存檔名（`.<name>.tmp-<UUID>`，`LibraryStore.atomicWrite`）：`moveItem` 失敗時 `NSFilePathErrorKey` 帶的是**它**
    /// 不是目的檔（R30 verify 第 20 列實測 code 516）；#146 G3 就是為了不把它印出來——這裡不附，附了就把 R30 關掉的洞從另一把鑰匙打開。
    static func isAtomicWriteTemp(_ lastComponent: String) -> Bool {
        lastComponent.hasPrefix(".") && lastComponent.contains(".tmp-")
    }

    public static func describe(_ error: Error) -> String {
        if let d = (error as? LocalizedError)?.errorDescription { return d }   // display-safe-exempt: 這裡就是 Error → 文字的唯一入口（D81）
        // Foundation 的 `NSError` 不符合 `LocalizedError`，而它的 `String(describing:)` 是
        // `Error Domain=NSCocoaErrorDomain Code=513 …UserInfo={…NSFileNewItemLocationKey=….tmp-…}` 那種原始 dump——
        // 在 512 字被截斷、把 atomicWrite 的暫存檔名漏出去（#146 verify G3，ProvenanceMigration 曾為此單獨改用 `localizedDescription`）。
        // Swift 自己的 enum error 相反：`localizedDescription` 是「The operation couldn't be completed. (Module.Type error 1.)」，
        // `String(describing:)` 才有內容。以「動態型別是 NSError」分流（`CocoaError`／`URLError` 這類橋接 struct 在 catch 裡也是
        // NSError，R29 verify 第 40 列實測），兩邊各取有內容的那個。`localizedDescription` 對 `removeItem` 這類失敗會把路徑丟掉
        // （「"x" couldn't be removed.」，第 32／40 列）——`NSFilePathErrorKey` 在時補回**檔名**（R31；R30 verify 第 20 列：R30 附的是絕對路徑，
        // 使用者名稱與家目錄佈局隨 quarantine reason 進 MCP payload，而 `localizedDescription` 是本地化文字、通常只引檔名，`contains(path)`
        // 幾乎恆為假、幾乎每次都附）；atomicWrite 的暫存檔一律不附（`isAtomicWriteTemp`）。
        if type(of: error) is NSError.Type {   // display-safe-exempt: 同上
            let ns = error as NSError
            if let path = ns.userInfo[NSFilePathErrorKey] as? String {
                let name = (path as NSString).lastPathComponent
                if !name.isEmpty, !isAtomicWriteTemp(name), !ns.localizedDescription.contains(name) {
                    return "\(ns.localizedDescription)（檔案：\(name)）"   // display-safe-exempt: 未消毒——呼叫端（displaySafeErrorText）逃一次
                }
            }
            return ns.localizedDescription   // display-safe-exempt: 同上
        }
        return String(describing: error)   // display-safe-exempt: 同上
    }

    public static func isSelfSanitizing(_ error: Error) -> Bool { error is SanitizedErrorDescription }

    /// 頂層 sink 對**非自帶消毒**錯誤的分流結果：文字已逃一次、每行輸入有界，`CustomStringConvertible` 讓 ArgumentParser 的
    /// `describe()` 原樣取回（它不是 `LocalizedError`，所以 `fullMessage` 走 `.other`——與原始錯誤同一條路、同一個 exit code）。
    public struct EscapedOnce: Error, CustomStringConvertible, SanitizedErrorDescription {
        public let description: String   // display-safe-exempt: 已逃一次（displaySafeErrorText 產出），本型別只是載體
        public init(_ error: Error) { description = displaySafeErrorText(error) }
    }
}

/// **逃一次、輸入有界、不截**：自帶消毒的錯誤原樣回傳；其餘逐行（只認真 LF）先讀至多 `ErrorDisplay.inputScalarCeiling` 個 scalar、
/// 以列舉式＋性質式逃脫一次，LF 保留當行分隔。這是三個入口共用的第一步——總量與行長由同一個 sink 量（`displaySafeAssembled`／
/// `displaySafeClipOnly`），於是上限量的是**最終**輸出（R30 D82），而工作量由 ceiling 量（R31 D83）。
public func displaySafeErrorText(_ error: Error) -> String {
    let text = ErrorDisplay.describe(error)
    if ErrorDisplay.isSelfSanitizing(error) { return text }   // display-safe-exempt: 已消毒（SanitizedErrorDescription）
    return text.replacingOccurrences(of: "\r\n", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { escapingInvisibleScalars(displaySafe(String($0), max: ErrorDisplay.inputScalarCeiling)) }
        .joined(separator: "\n")
}

/// 單行：`max` 是**輸出** scalar 的上限（兩類錯誤都是），截點退讓到完整的逃脫序列。呼叫端自己決定它的消費端裝得下多少——
/// 人的終端 4,096、MCP payload 512（#236／#388 的 context 預算）；R29 的 `max * 8` 讓 MCP 的成功 payload（`applyDict["error"]`）
/// 悄悄拿到 4,096（R29 verify 第 23 列）。多行文字在這裡**折成一行**：真 LF 改寫成 `\u{000A}` 字面（八個字元）之後才截，
/// 於是 `displaySafeClipOnly` 不會再逃任何東西、`max` 才真的是輸出上限（R31；R30 verify 第 12 列：600 個 LF 的原始錯誤在 R30 出 4,096 個 scalar）。
public func displaySafeError(_ error: Error, max: Int) -> String {
    displaySafeClipOnly(displaySafeErrorText(error).replacingOccurrences(of: "\n", with: "\\u{000A}"), max: max)   // display-safe-exempt: 已逃一次（displaySafeErrorText），只截
}

/// 多行（MCP 的錯誤出口、App／CLI 把整則描述給人看）：**前綴接在截之前**，然後整段走 `displaySafeAssembled`——逐行只截、
/// 半截逃脫序列退讓、96 KB 總量（以 UTF-8 位元組計，R31；R30 以 `String.count` 計、CJK 內容可達 288 KB，R30 verify 第 13 列）——
/// 與 CLI 頂層 sink 同一條路，所以兩面對同一個錯誤（含被截斷的）印出同一個字串（R29 verify 第 9 列：R29 的 MCP 先截再加 `Error: `，
/// CLI 先加再截，406 vs 413）。
public func displaySafeErrorMultiline(_ error: Error, prefix: String = "", maxLineLength: Int = 400) -> String {
    displaySafeAssembled(prefix + displaySafeErrorText(error), maxLineLength: maxLineLength)   // display-safe-exempt: 已逃一次，只截
}
