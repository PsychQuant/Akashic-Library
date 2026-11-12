import Foundation
import XCTest
@testable import AkashicCore

/// #794：`JSONScalar.classify` 在 macOS 與 Linux 給同一個答案。
///
/// macOS 以 CoreFoundation 的型別身分分辨布林與數字；Linux 沒有公開的 CoreFoundation，而 `JSONSerialization` 的 `0`、`1`、`1.0`
/// 在兩個平台都 `is Bool`，所以 Linux 以 `NSNumber.objCType` 判（2026-11-12 在 macOS、noble、jammy 量過每個產生者的值）。
/// 同一組斷言在兩個平台都跑。
final class JSONScalarTests: XCTestCase {
    private func decoded(_ text: String) throws -> Any {
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data("[\(text)]".utf8)) as? [Any])
        return try XCTUnwrap(array.first)
    }

    // spec-example: linux-platform-support / JSON scalar table
    func testTheJSONScalarTable() throws {
        let table: [(String, JSONScalar.Kind)] = [
            ("true", .boolean),
            ("false", .boolean),
            ("0", .integer(0)),
            ("1", .integer(1)),
            ("-3", .integer(-3)),
            ("1.0", .nonInteger),
            ("1e3", .nonInteger),
            ("18446744073709551617", .integerOutOfRange),
            ("\"1\"", .other),
        ]
        for (text, expected) in table {
            XCTAssertEqual(JSONScalar.classify(try decoded(text)), expected, "JSON \(text)")
        }
    }

    /// 表外的邊界：`Int.max` 之後到 `UInt64.max` 解成無號 NSNumber（`intValue` 繞回），超過 `UInt64` 的負數解成 `NSDecimalNumber`，
    /// 小數不是整數，`null` 是其他。
    func testRangeEdgesAndOtherJSONValues() throws {
        XCTAssertEqual(JSONScalar.classify(try decoded("9223372036854775807")), .integer(Int.max))
        XCTAssertEqual(JSONScalar.classify(try decoded("9223372036854775808")), .integerOutOfRange)
        XCTAssertEqual(JSONScalar.classify(try decoded("18446744073709551615")), .integerOutOfRange)
        XCTAssertEqual(JSONScalar.classify(try decoded("-9223372036854775809")), .integerOutOfRange)
        XCTAssertEqual(JSONScalar.classify(try decoded("2.5")), .nonInteger)
        XCTAssertEqual(JSONScalar.classify(try decoded("null")), .other)
        XCTAssertEqual(JSONScalar.classify(try decoded("[1]")), .other)
    }

    /// MCP 面的值不是 `JSONSerialization` 產生的：`valueToAny` 把布林做成 `NSNumber(booleanLiteral:)`，整數與小數是原生的
    /// `Int`／`Double`。它們經同一批呼叫端，所以同一個函式也要分對（Linux 上 `Int8` 的 NSNumber 是 `i`，不會被當成布林）。
    func testValuesThatDoNotComeFromJSONSerialization() {
        XCTAssertEqual(JSONScalar.classify(NSNumber(booleanLiteral: true)), .boolean)
        XCTAssertEqual(JSONScalar.classify(NSNumber(booleanLiteral: false)), .boolean)
        XCTAssertEqual(JSONScalar.classify(true), .boolean)
        XCTAssertEqual(JSONScalar.classify(0), .integer(0))
        XCTAssertEqual(JSONScalar.classify(1), .integer(1))
        XCTAssertEqual(JSONScalar.classify(5.0), .nonInteger)
        XCTAssertEqual(JSONScalar.classify("x"), .other)
        XCTAssertEqual(JSONScalar.classify(NSNull()), .other)
    }

    /// `isFloatingPoint` 是 `CFNumberIsFloatType` 的對應：Python 相容的轉寫（`pyStr`、`PyJSONBridge`）沿用原本的「浮點／整數」二分，
    /// 而 `NSDecimalNumber` 在 macOS 是浮點型——兩個平台要一樣。
    func testFloatingPointMatchesTheCoreFoundationSplit() throws {
        XCTAssertFalse(JSONScalar.isFloatingPoint(try XCTUnwrap(try decoded("0") as? NSNumber)))
        XCTAssertFalse(JSONScalar.isFloatingPoint(try XCTUnwrap(try decoded("18446744073709551615") as? NSNumber)))
        XCTAssertTrue(JSONScalar.isFloatingPoint(try XCTUnwrap(try decoded("1.0") as? NSNumber)))
        XCTAssertTrue(JSONScalar.isFloatingPoint(try XCTUnwrap(try decoded("18446744073709551617") as? NSNumber)))
        XCTAssertFalse(JSONScalar.isFloatingPoint(try XCTUnwrap(try decoded("true") as? NSNumber)))
    }

    /// `JSONInteger` 建在 `JSONScalar` 上，對外的回傳值不變。
    func testJSONIntegerKeepsItsOutcomes() throws {
        XCTAssertEqual(JSONInteger.classify(try decoded("true")), .notAnInteger)
        XCTAssertEqual(JSONInteger.classify(try decoded("7")), .integer(7))
        XCTAssertEqual(JSONInteger.classify(try decoded("1.0")), .notAnInteger)
        XCTAssertEqual(JSONInteger.classify(try decoded("9223372036854775808")), .outOfRange)
        XCTAssertEqual(JSONInteger.classify(try decoded("18446744073709551617")), .outOfRange)
        XCTAssertEqual(JSONInteger.classify(try decoded("\"7\"")), .notAnInteger)
    }
}
