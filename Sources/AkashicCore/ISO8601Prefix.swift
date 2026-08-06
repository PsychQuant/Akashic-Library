import Foundation

/// ISO 8601 前綴的值域判定（#85）。
///
/// **裁決 (c)：不驗證但報告。** 三種精度（`2003`／`2003-01`／`2003-01-15`）是
/// 文件契約；解碼照常收下（fail-closed 的內容驗證會讓一筆可疑的**歷史資料**變成
/// 整個 store 載入不了）；`doctor` 用本判定把不合值域的列出來——回報而非拒絕，
/// 判斷屬使用端。四個日期樣欄位（`DateRange.start/end`、`organization.founded/
/// dissolved`、`person.died`）一致適用。
public enum ISO8601Prefix {

    /// 月 01–12、日 01–31 的值域檢查；**不驗日曆**（`2004-02-30` 通過）——
    /// 日曆級驗證需要曆法假設（格里曆起點、閏年），對歷史資料那是另一個裁決。
    public static func isValid(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return false }
        func number(_ sub: Substring, digits: Int) -> Int? {
            // `isNumber` 對全形數字（２００４）也 true——值域是 ASCII digit
            guard sub.count == digits, sub.allSatisfy({ $0.isASCII && $0.isNumber })
            else { return nil }
            return Int(sub)
        }
        guard number(parts[0], digits: 4) != nil else { return false }
        if parts.count >= 2 {
            guard let m = number(parts[1], digits: 2), (1...12).contains(m) else { return false }
        }
        if parts.count == 3 {
            guard let d = number(parts[2], digits: 2), (1...31).contains(d) else { return false }
        }
        return true
    }
}
