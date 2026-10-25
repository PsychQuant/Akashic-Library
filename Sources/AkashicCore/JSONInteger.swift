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

    public static func classify(_ value: Any) -> Outcome {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return .notAnInteger }
        if n is NSDecimalNumber {
            let s = n.stringValue
            let digits = s.hasPrefix("-") ? s.dropFirst() : Substring(s)
            return !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? .outOfRange : .notAnInteger
        }
        guard !CFNumberIsFloatType(n) else { return .notAnInteger }
        let i = n.intValue
        return n.stringValue == String(i) ? .integer(i) : .outOfRange
    }
}
