import Foundation

/// 嚴格的 valid-time 日值。
///
/// 只接受 ASCII `YYYY-MM-DD`，且日期必須真實存在於延伸格里曆中。這個型別不提供
/// `now` 或任何隱式 `String` 轉換：有效時間必須由呼叫端明確指定，答案才能重播。
public struct ValidDay: Equatable, Hashable, Comparable, Sendable {
    public let rawValue: String
    let point: GregorianDayPoint

    public init(_ rawValue: String) throws {
        self.point = try GregorianDayRules.fullDay(rawValue)
        self.rawValue = rawValue
    }

    public static func < (lhs: ValidDay, rhs: ValidDay) -> Bool {
        lhs.point < rhs.point
    }
}

/// `ValidDay` 的構造錯誤。錯誤不攜帶未受信任的原字串，避免未來顯示時繞過
/// `displaySafe`；呼叫端若需要來源位置，應在自己的 typed context 另行保存。
public enum ValidDayError: Error, Equatable, Hashable, Sendable, LocalizedError {
    /// 不是精確的 ASCII `YYYY-MM-DD` shape。
    case invalidFormat
    /// shape 正確，但年、月或日不是真實的格里曆日。
    case invalidGregorianDay

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "有效日期必須是完整的 ASCII YYYY-MM-DD"
        case .invalidGregorianDay:
            return "有效日期不是真實存在的格里曆日"
        }
    }
}

struct GregorianDayPoint: Equatable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    static func < (lhs: GregorianDayPoint, rhs: GregorianDayPoint) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

enum GregorianPrecision: Equatable, Hashable, Sendable {
    case year
    case month
    case day
}

struct GregorianDayInterval: Equatable, Hashable, Sendable {
    let earliest: GregorianDayPoint
    let latest: GregorianDayPoint
    let precision: GregorianPrecision
}

enum GregorianDayRules {
    static func fullDay(_ rawValue: String) throws -> GregorianDayPoint {
        let bytes = Array(rawValue.utf8)
        guard hasShape(bytes, count: 10, separators: [4, 7]) else {
            throw ValidDayError.invalidFormat
        }

        let year = decimal(bytes, 0..<4)
        let month = decimal(bytes, 5..<7)
        let day = decimal(bytes, 8..<10)
        guard isRealDay(year: year, month: month, day: day) else {
            throw ValidDayError.invalidGregorianDay
        }
        return GregorianDayPoint(year: year, month: month, day: day)
    }

    /// 解析來源保留的 `YYYY`／`YYYY-MM`／`YYYY-MM-DD` 精度，並回傳所有可能日的
    /// 閉區間。任何非 ASCII、非真實日或不支援的 shape 都回 `nil`，由 assessment
    /// 依欄位轉成具名 invalid evidence。
    static func interval(_ rawValue: String) -> GregorianDayInterval? {
        let bytes = Array(rawValue.utf8)
        switch bytes.count {
        case 4:
            guard hasShape(bytes, count: 4, separators: []) else { return nil }
            let year = decimal(bytes, 0..<4)
            guard year > 0 else { return nil }
            return GregorianDayInterval(
                earliest: GregorianDayPoint(year: year, month: 1, day: 1),
                latest: GregorianDayPoint(year: year, month: 12, day: 31),
                precision: .year)

        case 7:
            guard hasShape(bytes, count: 7, separators: [4]) else { return nil }
            let year = decimal(bytes, 0..<4)
            let month = decimal(bytes, 5..<7)
            guard year > 0, (1...12).contains(month) else { return nil }
            return GregorianDayInterval(
                earliest: GregorianDayPoint(year: year, month: month, day: 1),
                latest: GregorianDayPoint(
                    year: year,
                    month: month,
                    day: daysInMonth(year: year, month: month)),
                precision: .month)

        case 10:
            guard let point = try? fullDay(rawValue) else { return nil }
            return GregorianDayInterval(earliest: point, latest: point, precision: .day)

        default:
            return nil
        }
    }

    private static func hasShape(
        _ bytes: [UInt8],
        count: Int,
        separators: Set<Int>
    ) -> Bool {
        guard bytes.count == count else { return false }
        for (index, byte) in bytes.enumerated() {
            if separators.contains(index) {
                guard byte == 0x2D else { return false }
            } else {
                guard (0x30...0x39).contains(byte) else { return false }
            }
        }
        return true
    }

    private static func decimal(_ bytes: [UInt8], _ range: Range<Int>) -> Int {
        range.reduce(into: 0) { value, index in
            value = value * 10 + Int(bytes[index] - 0x30)
        }
    }

    private static func isRealDay(year: Int, month: Int, day: Int) -> Bool {
        guard year > 0, (1...12).contains(month) else { return false }
        return (1...daysInMonth(year: year, month: month)).contains(day)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = year.isMultiple(of: 400)
                || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}
