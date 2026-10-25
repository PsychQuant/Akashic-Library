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

    /// 替換腿新寫入的名字（literal、group、團體成員）的碼位閘：回 nil＝可以寫；否則回一句說得出是哪個碼位的話（#742 verify 第一、二輪）。
    ///
    /// 拒絕的集合是 repo 的單一定義 `UnsafeToEmitScalar`（#569：default-ignorable、Cc、Cf、Zl、Zp、非 U+0020 的空白、渲染成空白的碼位），
    /// 扣掉私用區，ZWJ／ZWNJ 照 `NameIdentity.joinerIsLegal` 的脈絡規則放行——與名字輸入閘 `NameIdentity.wellFormednessIssue` 同一份
    /// 碼位判準。**不沿用它的 NFC 要求**：那是 venue 名稱的規則，作者名從 PDF 抽出時常是 NFD，而 store 存逐字的值。另外拒絕以組合記號
    /// 開頭的名字：它會和段括號 `⟦` 黏成同一個字元，替換記錄解析不回來。只管新寫入的值——以 `from` 沿用的舊值原樣保留。
    public static func nameScalarIssue(_ s: String) -> String? {
        let scalars = Array(s.unicodeScalars)
        if let first = scalars.first, first.properties.isGraphemeExtend {
            return "以組合記號 U+\(hex(first)) 開頭——它會和前一個字元黏在一起，請刪掉它或補上它所屬的字母"   // display-safe-exempt: 十六進位碼位
        }
        for (i, u) in scalars.enumerated() {
            if u.value == 0x200C || u.value == 0x200D {
                if NameIdentity.joinerIsLegal(in: scalars, at: i) { continue }
                return "含不在使用它的文字裡的接合字元 U+\(hex(u))（ZWJ／ZWNJ）——不是名字的一部分，請刪掉它"   // display-safe-exempt: 十六進位碼位
            }
            guard UnsafeToEmitScalar.contains(u), u.properties.generalCategory != .privateUse else { continue }
            return "含控制字元或不可見字元 U+\(hex(u))（換行、tab、零寬、方向控制等）——PDF 抽出的名字常帶進這類字元，刪掉它再寫"   // display-safe-exempt: 十六進位碼位
        }
        return nil
    }

    private static func hex(_ u: Unicode.Scalar) -> String {
        let h = String(u.value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - h.count)) + h
    }

    /// 回 nil＝這組值寫不成合法的 statement：零段、任一段空或含保留字元、頁序 < 1、理由（trim 後）空。
    public init?(segments: [String], page: Int, reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segments.isEmpty, page >= 1, !trimmed.isEmpty else { return nil }
        for s in segments {
            guard !s.isEmpty, !s.contains(Self.openBracket), !s.contains(Self.closeBracket) else { return nil }
            // 以組合記號開頭的段會和 `⟦` 黏成同一個 Character，`parse` 切不出它（#742 verify 第二輪）
            guard s.unicodeScalars.first?.properties.isGraphemeExtend != true else { return nil }
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
