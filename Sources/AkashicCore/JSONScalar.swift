import Foundation

/// JSON 純量的型別判讀（#794）：布林、整數、超出 `Int` 的整數、非整數的數、其他。macOS 與 Linux 給同一個答案。
///
/// `JSONSerialization` 把 `true` 與 `1` 都解成 `NSNumber`，而 `0`、`1`、`1.0` 在兩個平台都 `is Bool`——`is Bool` 分不出 JSON 的布林與數字。
/// macOS 以 CoreFoundation 的型別身分分辨（`CFBooleanGetTypeID`、`CFNumberIsFloatType`，逐字沿用本函式出現之前各呼叫端的寫法）；
/// Linux 沒有公開的 CoreFoundation，改以 `NSNumber.objCType` 判。
///
/// **Linux 分支的前提**（2026-11-12 在 macOS、`swift:6.4.2-noble`、`swift:6.4.2-jammy` 量過）：布林的 `objCType` 是 `c`，整數是
/// `i`／`q`／`Q`，小數是 `d`，超過 `UInt64` 的整數是 `NSDecimalNumber`。這對 `JSONSerialization` 的輸出成立，也對 MCP 面的
/// `NSNumber(booleanLiteral:)` 與原生 `Bool`／`Int`／`Double` 橋接成的 `NSNumber` 成立（Linux 上 `NSNumber(value: Int8(1))` 是 `i`，
/// 不是 `c`）。其他方式造出的 `NSNumber`（例如 macOS 上 `NSNumber(value: Int8)` 是 `c`）不在這個前提裡，不要拿本函式判讀它們。
///
/// `PyJSONParser` 的輸出是原生 Swift 值，`is Bool` 只對 `true`／`false` 成立，不需要本函式（`WebRead` 的兩處 `is Bool` 因此不改）。
public enum JSONScalar {
    public enum Kind: Equatable {
        case boolean
        case integer(Int)
        /// 是整數，但超出 `Int` 的範圍（`Int.max` 之後到 `UInt64.max` 的無號 NSNumber，或超過 `UInt64` 而解成 `NSDecimalNumber` 的整數）。
        case integerOutOfRange
        /// 數字，但不是整數：小數或指數寫法（`1.0`、`1e3`）。
        case nonInteger
        /// 不是數字也不是布林：字串、`null`、陣列、物件。
        case other
    }

    public static func classify(_ value: Any) -> Kind {
        guard let n = value as? NSNumber else { return .other }
        if isBoolean(n) { return .boolean }
        if n is NSDecimalNumber {
            let s = n.stringValue
            let digits = s.hasPrefix("-") ? s.dropFirst() : Substring(s)
            return !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? .integerOutOfRange : .nonInteger
        }
        if isFloatingPoint(n) { return .nonInteger }
        let i = n.intValue
        return n.stringValue == String(i) ? .integer(i) : .integerOutOfRange
    }

    /// `CFNumberIsFloatType` 的對應：小數與 `NSDecimalNumber` 為 true（macOS 上 `NSDecimalNumber` 也是浮點型）。給要沿用原本
    /// 「浮點／整數」二分的 Python 相容轉寫用（`pyStr`、`PyJSONBridge`）；判斷「是不是整數」用 `classify`。
    public static func isFloatingPoint(_ n: NSNumber) -> Bool {
        #if os(Linux)
        if n is NSDecimalNumber { return true }
        let type = String(cString: n.objCType)
        return type == "d" || type == "f"
        #else
        return CFNumberIsFloatType(n)
        #endif
    }

    private static func isBoolean(_ n: NSNumber) -> Bool {
        #if os(Linux)
        return String(cString: n.objCType) == "c"
        #else
        return CFGetTypeID(n) == CFBooleanGetTypeID()
        #endif
    }
}
