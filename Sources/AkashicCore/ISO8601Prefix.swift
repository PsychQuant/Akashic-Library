import Foundation

/// ISO 8601 前綴的值域判定（#85）。
///
/// **裁決 (c)：不驗證但報告。** 三種精度（`2003`／`2003-01`／`2003-01-15`）是
/// 文件契約；解碼照常收下（fail-closed 的內容驗證會讓一筆可疑的**歷史資料**變成
/// 整個 store 載入不了）；`doctor` 用本判定把不合值域的列出來——回報而非拒絕，
/// 判斷屬使用端。四個日期樣欄位（`DateRange.start/end`、`organization.founded/
/// dissolved`、`person.died`）一致適用。
///
/// **`Entry.date` 刻意排除**（#144 verify F6 的追問）：biblatex/EDTF 的 date 合法
/// 地包含區間（`2003/2004`）、季節、約略（`2003~`）與 `unknown`/`open`——拿去過
/// ISO 前綴檢查會把報告灌爆假陽性。它的值域屬 biblatex 契約，不屬本判定。
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

    /// 兩個日期是否**相容**——其一是另一個的前綴（#157 verify 157-8）。
    ///
    /// 這是「精度差異」與「值衝突」的分界。合併重複記錄時兩者的後果相反：
    ///
    /// - `2020` vs `2020-03-15`：同一件事的不同精度，是重複記錄的**正常形狀**。
    ///   要求相等會誤拒最常見的情況（#71 R2 DA 的同型教訓）。
    /// - `2019` vs `2021`：互斥。那不是排版差異，是對「這兩筆是不是同一篇」的
    ///   反證，或至少是一個必須有人裁決的來源衝突（同 person 側 `died` 的理由）。
    ///
    /// **前綴必須落在分隔點上**：`2020` 相容 `2020-03`，但 `202` 不相容 `2020`
    ///（否則 202 年與 2020 年會被當成同一件事）。非 ISO 前綴格式的值一律**當成
    /// 不相容**——本函式無法判斷兩個自由文字日期的關係，而不可逆合併前的預設
    /// 應該是讓人裁決。
    public static func compatible(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        guard isValid(short), isValid(long) else { return false }
        guard long.hasPrefix(short) else { return false }
        // 分隔點檢查：`2020` → `2020-03` 的下一個字元必須是 `-`。
        //
        // **這是 defence-in-depth，現行 `isValid` 下不可達**（#157 verify 157-14）：
        // `isValid` 只接受 `YYYY`(4)／`YYYY-MM`(7)／`YYYY-MM-DD`(10) 三種**定寬**形狀，
        // 所以任何「合法且是另一個合法值的前綴」的組合，下一個字元必然是 `-`。
        // 席位 mutation 實測：改成 `return true` 全套 966 綠——**寫不出能觸發它的
        // 測試，那本身就是不可達的證明**。
        //
        // 保留而非刪除，因為它釘的是 `isValid` 的定寬文法這個前提；日後若放寬
        // （例如支援 EDTF 的變寬形式）它就會活起來。但**測試不得宣稱在驗它**——
        // `testMutuallyExclusiveDatesAreReportedButPrecisionIsNot` 的「202 不是 2020
        // 的精度較低版本」實際上是被 `isValid` 的四位數年份規則擋下的。歸因寫錯會
        // 讓日後放寬 `isValid` 的人以為這條還罩得住。
        let next = long[long.index(long.startIndex, offsetBy: short.count)]
        return next == "-"
    }
}
