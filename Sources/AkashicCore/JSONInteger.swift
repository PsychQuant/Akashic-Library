import Foundation

/// `JSONSerialization` 解出的數字轉成 `Int` 時不截斷、不繞回（#742 verify）。
///
/// 實測（macOS，2026-10-25）：`Int.max` 之後到 `UInt64.max` 的整數解成無號的 `NSNumber`，`intValue` 繞回成負數；超過 `UInt64` 的整數
/// 解成 `NSDecimalNumber`（float 型），`intValue` 截斷——`18446744073709551617` 變成 `1`，悄悄成為一個合法的頁序或作者位。
/// `1.0`、`1e3` 是 double，不是整數。布林（`true`）在 `JSONSerialization` 裡也是 `NSNumber`，要另外擋。
public enum JSONInteger {
    public enum Outcome: Equatable {
        case integer(Int)
        /// 不是整數：字串、布林、小數或指數寫法。
        case notAnInteger
        /// 是整數，但超出 `Int` 的範圍。
        case outOfRange
    }

    /// 判讀本身在 `JSONScalar`（#794：macOS 與 Linux 同一個答案）；這裡只把它的五種結果收成三種。
    public static func classify(_ value: Any) -> Outcome {
        switch JSONScalar.classify(value) {
        case .integer(let i): return .integer(i)
        case .integerOutOfRange: return .outOfRange
        case .boolean, .nonInteger, .other: return .notAnInteger
        }
    }
}
