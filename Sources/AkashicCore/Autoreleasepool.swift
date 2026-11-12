#if os(Linux)
/// Linux 沒有 Objective-C runtime，也就沒有 autorelease pool（#794）：`SourceChunks.pump` 與 `AbstractProposals` 在 macOS 以
/// `autoreleasepool` 逐塊排掉 Foundation 的 autoreleased 物件，Linux 上同一段程式直接執行閉包，結果與錯誤原樣傳出。
/// 只在 Linux 宣告——macOS 用 Foundation 自己的那一個。
@inlinable
public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}
#endif
