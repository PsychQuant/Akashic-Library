import Foundation

/// 識別碼——由註冊機構指派、用來**終結「這是哪一個」**的東西（#394）。
///
/// ## 為什麼是 value type 而不是 `String?`
///
/// 這個型別存在的判準是**介面深度**：若欄位型別是 `String?`，這個抽象什麼行為都沒藏，
/// 刪掉它今天不會壞任何東西——那樣的 seam 不該存在，而「識別碼是模型的一等公民」
/// 也就退化成「把字串從一個容器搬到另一個」。
///
/// 實測的兩個「有值而無型別」的產物（`Entry.fields` 這個自由字典驗不出它們）：
///
/// - `0003-066x`——ISSN 標準規定 check digit 的 `X` **大寫**，小寫是錯的
/// - `1467-8624(Electronic),0009-3920(Print)`——一個欄位塞兩個號
///
/// ## 正規化只發生在寫入面
///
/// 建構器做正規化；**讀取面對非正規值寬容**（載入並保留，不 quarantine）。
/// 理由是實測的：provenance reference 的 `value` 必須落在該欄位的現值清單內，
/// 讀取時改寫值會讓既有 reference 變成孤兒，於是整筆記錄拒讀（Task 1.1 探針：
/// `people: 1` → `people: 0`、`quarantined: 1`）。用整檔 quarantine 去修一個大小寫，
/// 代價不成比例。
///
/// **所以型別同時持有兩個字串**：`raw`（磁碟上的那個）與 `normalized`（算出來的）。
/// 語意分工逐字取自 task 4.1 的驗證目標——**讀取→`raw`、寫入→`normalized`**。
/// 少了 `raw`，「讀取面原樣保留」在結構上就做不到：decode 當下值已被改寫。
/// 實測 store 內有 43 個非正規值（issn 10、isbn 18、doi 15）落在這一格。
///
/// **相等由 `normalized` 決定**（見下方 protocol extension）：`0003-066x` 與
/// `0003-066X` 是同一個識別碼，否則遷移的去重永遠去不掉異寫法。
///
/// ## 它終結什麼、不終結什麼
///
/// 終結**指涉**（是哪一個），不終結**描述**（附帶欄位是否正確）。註冊機構收的是
/// 出版商送的資料，錯的照收。判準與封閉列舉見
/// `.claude/rules/identity-is-judged-not-matched.md` 的識別碼例外節。
public protocol Identifier: Equatable, CustomStringConvertible {
    /// 從原始字串建構；形狀不合法回 `nil`。**建構即算出正規形，但不丟掉原樣字串。**
    init?(_ raw: String)
    /// 原樣字串——**磁碟上的那個**。讀取面原樣保留靠它。
    var raw: String { get }
    /// 正規形——寫入面寫的就是這個。
    var normalized: String { get }
    /// 這種識別碼的預期形狀，供錯誤訊息具名。
    static var shapeDescription: String { get }
}

public extension Identifier {
    /// 顯示用正規形（`raw` 是儲存細節，不是給人看的）。
    var description: String { normalized }

    /// **相等由正規形決定，不由 `raw`。**
    ///
    /// 寫在這裡而不是靠 Swift 合成：加了 `raw` 之後，合成的逐欄位 `==` 會把
    /// `0003-066x` 與 `0003-066X` 判成兩個不同的識別碼，而遷移的去重
    /// （task 8.2：「先正規化再去重，去重後仍 >1 者才是真多號」）就永遠去不掉異寫法。
    static func == (a: Self, b: Self) -> Bool { a.normalized == b.normalized }
}

// MARK: - 共用的字元工具

private extension String {
    /// 去掉所有非英數字元（連字號、空白、括號…），並轉大寫。
    var idCompact: String {
        uppercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }
}

/// mod-11 check digit（ISSN 與 ISBN-10 共用的算法，權重方向不同故傳入）。
private func mod11(_ digits: [Int], weights: [Int]) -> Int? {
    guard digits.count == weights.count else { return nil }
    let sum = zip(digits, weights).reduce(0) { $0 + $1.0 * $1.1 }
    return (11 - (sum % 11)) % 11
}

// MARK: - ISSN

/// 期刊（serial）的識別碼。形狀 `NNNN-NNNN`，末位是 mod-11 check digit，
/// **10 以 大寫 `X` 表示**。
///
/// 一個期刊可以有**兩個** ISSN（print 與 electronic），所以 venue 側是清單而非純量
/// ——實測 Behavior Research Methods 的 `1554-351X`（print）與 `1554-3528`（electronic）。
public struct ISSN: Identifier {
    public let raw: String
    public let normalized: String
    public static let shapeDescription = "NNNN-NNNN（末位可為大寫 X）"

    public init?(_ raw: String) {
        self.raw = raw
        let c = raw.idCompact
        guard c.count == 8 else { return nil }
        let chars = Array(c)
        // 前 7 位必須是數字；末位是數字或 X
        var digits: [Int] = []
        for ch in chars.prefix(7) {
            guard let d = ch.wholeNumberValue, (0...9).contains(d) else { return nil }
            digits.append(d)
        }
        let last = chars[7]
        let lastValue: Int
        if last == "X" { lastValue = 10 } else if let d = last.wholeNumberValue, (0...9).contains(d) {
            lastValue = d
        } else { return nil }
        // check digit：權重 8..2
        guard let expected = mod11(digits, weights: [8, 7, 6, 5, 4, 3, 2]),
              expected == lastValue else { return nil }
        normalized = String(chars.prefix(4)) + "-" + String(chars.suffix(4))
    }
}

// MARK: - DOI

/// 作品的識別碼。形狀 `10.<registrant>/<suffix>`。
///
/// **不驗證它解析得到**——本型別只管形狀。是否指向存在的記錄是外部查證的事
/// （見 #393 的候選 DOI 判定流程）。
///
/// 正規化：剝掉 `https://doi.org/` 之類的前綴、轉小寫（DOI 的比對規則是
/// 大小寫不敏感，store 內存一種形式才不會出現「同一個 DOI 的兩種寫法」）。
public struct DOI: Identifier {
    public let raw: String
    public let normalized: String
    public static let shapeDescription = "10.<註冊者>/<後綴>"

    public init?(_ raw: String) {
        self.raw = raw
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/",
                       "http://dx.doi.org/", "doi:", "DOI:"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        s = s.lowercased()
        guard s.hasPrefix("10."), let slash = s.firstIndex(of: "/") else { return nil }
        let registrant = s[s.index(s.startIndex, offsetBy: 3)..<slash]
        let suffix = s[s.index(after: slash)...]
        // 註冊者至少 4 碼數字（實務下限），後綴非空且不含空白
        guard registrant.count >= 4, registrant.allSatisfy({ $0.isNumber || $0 == "." }),
              !suffix.isEmpty, !suffix.contains(where: { $0.isWhitespace }) else { return nil }
        normalized = s
    }
}

// MARK: - PMID

/// PubMed 的記錄編號。純數字，無 check digit。
public struct PMID: Identifier {
    public let raw: String
    public let normalized: String
    public static let shapeDescription = "純數字"

    public init?(_ raw: String) {
        self.raw = raw
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("pmid:") { s = String(s.dropFirst(5)) }
        s = s.trimmingCharacters(in: .whitespaces)
        // 前導零不是有意義的——正規化掉，否則同一筆會有兩種寫法
        guard !s.isEmpty, s.allSatisfy(\.isNumber), let n = UInt64(s), n > 0 else { return nil }
        normalized = String(n)
    }
}

// MARK: - ISBN

/// 書的識別碼。接受 ISBN-10 與 ISBN-13 兩形，**各自驗自己的 check digit**。
///
/// **刻意不把 10 碼換算成 13 碼。** 兩者是同一本書的兩種編碼，但「要不要視為同一個
/// 識別碼」是尚未裁決的問題（#394 的 Open Questions 之一）——在裁決之前，原樣保存
/// 來源給的那一種，不自作主張換算。
public struct ISBN: Identifier {
    public let raw: String
    public let normalized: String
    public static let shapeDescription = "10 碼（末位可為大寫 X）或 13 碼"

    public init?(_ raw: String) {
        self.raw = raw
        let c = raw.idCompact
        if c.count == 10 {
            var digits: [Int] = []
            for ch in c.prefix(9) {
                guard let d = ch.wholeNumberValue, (0...9).contains(d) else { return nil }
                digits.append(d)
            }
            let last = Array(c)[9]
            let lastValue: Int
            if last == "X" { lastValue = 10 } else if let d = last.wholeNumberValue,
                                                     (0...9).contains(d) { lastValue = d
            } else { return nil }
            guard let expected = mod11(digits, weights: [10, 9, 8, 7, 6, 5, 4, 3, 2]),
                  expected == lastValue else { return nil }
            normalized = c
        } else if c.count == 13 {
            var digits: [Int] = []
            for ch in c {
                guard let d = ch.wholeNumberValue, (0...9).contains(d) else { return nil }
                digits.append(d)
            }
            // EAN-13：權重 1,3 交替，總和 mod 10 == 0
            let sum = digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
            guard sum % 10 == 0 else { return nil }
            normalized = c
        } else {
            return nil
        }
    }
}

// MARK: - ORCID

/// 人的識別碼。形狀 `NNNN-NNNN-NNNN-NNNC`，末位是 ISO 7064 MOD 11-2 的
/// check digit（10 以大寫 `X` 表示）。
///
/// **每人恰一個**——這是 ORCID 的定義，故 person 側是純量而非清單。
public struct ORCID: Identifier {
    public let raw: String
    public let normalized: String
    public static let shapeDescription = "NNNN-NNNN-NNNN-NNNC（末位可為大寫 X）"

    public init?(_ raw: String) {
        self.raw = raw
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://orcid.org/", "http://orcid.org/"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        let c = s.idCompact
        guard c.count == 16 else { return nil }
        let chars = Array(c)
        var total = 0
        for ch in chars.prefix(15) {
            guard let d = ch.wholeNumberValue, (0...9).contains(d) else { return nil }
            total = (total + d) * 2
        }
        let remainder = total % 11
        let expected = (12 - remainder) % 11
        let last = chars[15]
        let lastValue: Int
        if last == "X" { lastValue = 10 } else if let d = last.wholeNumberValue,
                                                 (0...9).contains(d) { lastValue = d
        } else { return nil }
        guard expected == lastValue else { return nil }
        normalized = stride(from: 0, to: 16, by: 4)
            .map { String(chars[$0..<($0 + 4)]) }.joined(separator: "-")
    }
}

// MARK: - ROR

/// 研究機構的識別碼。形狀：`0` ＋ 6 碼 base32（Crockford，不含 `i l o u`）
/// ＋ 2 碼十進位 check digit（ISO 7064 MOD 97-10）。
///
/// **每個機構恰一個**——ROR 的定義，故 organization 側是純量。
public struct ROR: Identifier {
    public let raw: String
    public let normalized: String
    public static let shapeDescription = "0 ＋ 6 碼 base32 ＋ 2 碼 check digit"

    /// Crockford base32 的字母表（刻意排除 i／l／o／u 以免與 1／0 混淆）。
    private static let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")

    public init?(_ raw: String) {
        self.raw = raw
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://ror.org/", "http://ror.org/", "ror.org/"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        guard s.count == 9, s.hasPrefix("0") else { return nil }
        let body = String(s.prefix(7))          // 含前導 0 的 base32 部分
        let checkPart = String(s.suffix(2))
        guard checkPart.allSatisfy(\.isNumber), let check = Int(checkPart) else { return nil }
        // base32 解碼成整數
        var value = 0
        for ch in body {
            guard let idx = Self.alphabet.firstIndex(of: ch) else { return nil }
            value = value * 32 + idx
        }
        // MOD 97-10：把「數值 ×100」對 97 取餘，補數即 check digit
        let expected = 98 - ((value * 100) % 97)
        guard expected == check else { return nil }
        normalized = s
    }
}


// MARK: - 非正規形的 diagnostic（#394 task 4.3）

/// 讀取面寬容保留非正規形，**但不得靜默**——`lossless-intake` 的「靜默是最糟的形式」在
/// 這裡的落地：值留著，同時 `akashic validate` 具名它。遷移（`migrate-identifiers`）
/// 修好之後這些 diagnostic 自然歸零，所以它同時是遷移進度的量測。
///
/// **severity 是 warning 不是 error**：值指涉正確、只是寫法不是正規形。依 #416 的判準
/// `hasFindings` 只計 error——記成 error 會讓一份正常的 store 常態顯示不健康，那個布林
/// 就失去訊號。
///
/// 四個帶識別碼的記錄型別共用這一份（同 `IdentifierYAML` 的理由：一份規格的兩份副本
/// 必然分岔）。
public enum IdentifierDiagnostics {
    public static func nonNormal<T: Identifier>(_ ids: [T], field: String) -> [ValidationIssue] {
        ids.filter { $0.raw != $0.normalized }.map { issue($0, field: field) }
    }

    public static func nonNormal<T: Identifier>(_ id: T?, field: String) -> [ValidationIssue] {
        guard let id, id.raw != id.normalized else { return [] }
        return [issue(id, field: field)]
    }

    /// 訊息同時給**原樣值**與**正規形**——只給前者的話讀的人不知道要改成什麼。
    private static func issue<T: Identifier>(_ id: T, field: String) -> ValidationIssue {
        ValidationIssue(
            severity: .warning,
            message: "\(field)「\(displaySafe(id.raw, max: 120))」不是正規形"
                + "（正規形是「\(displaySafe(id.normalized, max: 120))」；"
                + "`migrate-identifiers` 會修正）")
    }
}
