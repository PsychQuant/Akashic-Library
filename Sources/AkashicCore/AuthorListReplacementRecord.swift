import Foundation

/// 作者列**替換記錄**的 statement 文法——**單一解析器**（#742，design D3）。
///
/// ## 為什麼需要它
///
/// 拆分（#450）與移除（#457）都是對**一格**作者位的局部改動；#742 要的是依作品本身的 byline 把整份
/// 作者列換掉（觸發實例 `claw2018framework`：Crossref 給 20 位，PDF 第 1 頁是 7 位）。替換之後 store
/// 要說得出依據——哪一份全文、第幾頁、理由——而那句話住在 `Entry.references` 的 `field: authors`。
///
/// ## 與另外兩種記錄怎麼分開
///
/// 拆分與移除的 value 是**已退役**的原 literal，必填；替換記錄**不帶 value**（被換掉的是整份列，不是一格）。
/// 所以 value 缺席就足以在形狀上把三者分開，statement 前綴（`拆為 `／`移除：`／`替換為 `）再確認一次——
/// 兩道都在附著驗證（`Entry.validateReferenceAttachment`），讓錯放的記錄在 decode 期就被擋下。
///
/// ## 文法
///
/// `替換為 ⟦s1⟧ ⟦s2⟧ … ⟦sn⟧；依據第 N 頁：理由`
///
/// - 每段是替換後那一位寫進 store 的值，逐字：個人 literal、帶 corporate 大括號的團體名，或
///   `key:<person key>`／`organization:<org key>`（`from` 沿用的已歸戶位）。段數 ≥ 1，段不得為空、
///   不得含 `⟦`／`⟧`（`init?` 與 `parse` 同一條規則，所以 `encoded` 必然解析回相等的值）。
/// - `N` 是 PDF 的實體頁序，從 1 起算，只收 ASCII 數字、不收前導零——同一個頁序只有一種寫法
///   （store 的不變式是「同一份資料只有一種位元組形式」）。
/// - 理由（trim 後）非空。
///
/// 寫入端（替換腿）與讀取端（附著驗證、`StoreHealth` 的失效 warning）都只經本型別，不留第二份文法。
public struct AuthorListReplacementRecordValue: Equatable, Sendable {
    public static let prefix = "替換為 "
    public static let openBracket: Character = "⟦"
    public static let closeBracket: Character = "⟧"
    /// 全形分號——段列與頁序的分隔。段內的分號不解讀（括號內）。
    public static let pageSeparator: Character = "；"
    public static let pageHead = "依據第 "
    public static let pageTail = " 頁"
    /// 全形冒號——頁序與理由的分隔，與 `SplitRecordValue`／`AuthorRemovalRecordValue` 同一個字元。
    public static let reasonSeparator: Character = "："

    public let segments: [String]
    public let page: Int
    public let reason: String

    /// 替換腿新寫入的名字（literal、group、團體成員）不得含控制字元（Unicode general category Cc）：PDF 抽出的 byline 常把一個名字
    /// 折成兩行，逐字抄進來的換行會進 store、替換記錄與匯出（#742 verify）。只管新寫入的值——以 `from` 沿用的舊值原樣保留，
    /// 所以這條不放進 `init?`（那會讓既有的記錄解析不回來）。
    public static func containsControlCharacter(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// 回 nil＝這組值寫不成合法的 statement：零段、任一段空或含保留字元、頁序 < 1、理由（trim 後）空。
    public init?(segments: [String], page: Int, reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segments.isEmpty, page >= 1, !trimmed.isEmpty else { return nil }
        for s in segments {
            guard !s.isEmpty, !s.contains(Self.openBracket), !s.contains(Self.closeBracket) else { return nil }
        }
        self.segments = segments
        self.page = page
        self.reason = trimmed
    }

    public var encoded: String {
        Self.prefix
            + segments.map { "\(Self.openBracket)\($0)\(Self.closeBracket)" }.joined(separator: " ")
            + String(Self.pageSeparator) + Self.pageHead + String(page) + Self.pageTail
            + String(Self.reasonSeparator) + reason
    }

    /// 回 nil＝不是替換記錄，或 malformed——呼叫端合起來判斷（附著驗證對 `field: authors` 三種文法都不中時拒收）。
    public static func parse(_ statement: String) -> AuthorListReplacementRecordValue? {
        guard statement.hasPrefix(prefix) else { return nil }
        var i = statement.index(statement.startIndex, offsetBy: prefix.count)
        var segments: [String] = []
        var current: String?          // 非 nil ＝ 正在括號內
        while i < statement.endIndex {
            let c = statement[i]
            if var cur = current {
                if c == openBracket { return nil }               // 巢狀＝不平衡
                if c == closeBracket {
                    guard !cur.isEmpty else { return nil }       // 空段
                    segments.append(cur); current = nil
                } else {
                    cur.append(c); current = cur
                }
            } else if c == openBracket {
                current = ""
            } else if c == pageSeparator {
                return parseTail(segments: segments, tail: statement[statement.index(after: i)...])
            } else if c != " " {
                return nil                                       // 括號外只允許空白與分隔
            }
            i = statement.index(after: i)
        }
        return nil                                               // 沒有頁序分隔、或括號未關
    }

    /// `依據第 N 頁：理由`。
    private static func parseTail(segments: [String], tail: Substring) -> AuthorListReplacementRecordValue? {
        guard tail.hasPrefix(pageHead) else { return nil }
        let afterHead = tail.dropFirst(pageHead.count)
        let digits = afterHead.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.first != "0", let page = Int(digits) else { return nil }
        let rest = afterHead.dropFirst(digits.count)
        let head = pageTail + String(reasonSeparator)
        guard rest.hasPrefix(head) else { return nil }
        return AuthorListReplacementRecordValue(
            segments: segments, page: page, reason: String(rest.dropFirst(head.count)))
    }
}

/// 一筆替換記錄：解析後的 statement ＋ 它依據的那一份全文（rests-on 恰一個 digest，附著驗證保證）。
public struct AuthorListReplacementRecord: Equatable, Sendable {
    public let record: AuthorListReplacementRecordValue
    public let source: String
    public init(record: AuthorListReplacementRecordValue, source: String) {
        self.record = record; self.source = source
    }
}

extension Entry {
    /// 本 work 的作者列替換記錄（至多一筆——附著驗證拒收兩筆）。decode 閘已保證形狀，
    /// 這裡取第一筆是對手改檔的縱深防禦，不是第二條讀法。
    public var authorListReplacementRecord: AuthorListReplacementRecord? {
        for r in references where r.field == "authors" && r.value == nil {
            guard case .judgement(let statement, let restsOn) = r.kind, restsOn.count == 1,
                  let parsed = AuthorListReplacementRecordValue.parse(statement) else { continue }
            return AuthorListReplacementRecord(record: parsed, source: restsOn[0])
        }
        return nil
    }
}
