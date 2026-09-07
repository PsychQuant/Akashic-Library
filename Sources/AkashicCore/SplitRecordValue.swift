import Foundation

/// 拆分記錄的 statement 文法——**單一解析器**（#450）。
///
/// `splitAuthors`（#443）把一個黏著的作者 literal 拆成 N 段。它是作者位變更家族裡唯一**不可逆且沒有
/// store 記錄**的一腿，直到 #450 把判定持久化到 work 側：`Entry.references` 收一筆
/// `{field: authors, value: <原 literal 逐字>, judgement: "拆為 ⟦a⟧ ⟦b⟧：<理由>", rests-on: []}`。
///
/// `ProvenanceReference` 只有 field／value／kind 三槽，各段沒有結構化位置，只能寫在 statement——
/// 那是 #232 D3 自認過的 grammar-in-string；補救方式與 `VerdictPairingValue` 相同：**寫入端與讀取端
/// 都只經本型別的 `encoded`／`parse`**，不留第二份文法。
///
/// 文法：`拆為 ⟦a⟧ ⟦b⟧…：理由`——段以 `⟦…⟧` 包（段內可含空白與冒號）、段數 ≥ 2、全形 `：` 之後為理由、
/// 理由非空。`⟦`／`⟧` 是保留字元：段不得含它（`init?` 與 `parse` 同一條規則，所以 `encoded` 的輸出
/// **必然**解析回相等的值）；`splitAuthors` 對含它的段拒絕（與 `=` 在分隔符文法的既有處置同形）。
public struct SplitRecordValue: Equatable, Sendable {
    public static let prefix = "拆為 "
    public static let openBracket: Character = "⟦"
    public static let closeBracket: Character = "⟧"
    /// 全形冒號——段內的 ASCII `:` 與全形 `：` 都合法（括號內不解讀），只有括號外的第一個全形冒號是分隔。
    public static let reasonSeparator: Character = "："

    public let parts: [String]
    public let reason: String

    /// 回 nil＝這組值寫不成合法的 statement：段 <2、任一段空或含保留字元、理由（trim 後）空。
    public init?(parts: [String], reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts.count >= 2, !trimmed.isEmpty else { return nil }
        for p in parts {
            guard !p.isEmpty, !p.contains(Self.openBracket), !p.contains(Self.closeBracket) else { return nil }
        }
        self.parts = parts
        self.reason = trimmed
    }

    public var encoded: String {
        Self.prefix
            + parts.map { "\(Self.openBracket)\($0)\(Self.closeBracket)" }.joined(separator: " ")
            + String(Self.reasonSeparator) + reason
    }

    /// 回 nil＝malformed——呼叫端必須 loud（store 閘在 decode 期拒收）。
    public static func parse(_ statement: String) -> SplitRecordValue? {
        guard statement.hasPrefix(prefix) else { return nil }
        var i = statement.index(statement.startIndex, offsetBy: prefix.count)
        var parts: [String] = []
        var current: String?          // 非 nil ＝ 正在括號內
        while i < statement.endIndex {
            let c = statement[i]
            if var cur = current {
                if c == openBracket { return nil }               // 巢狀＝不平衡
                if c == closeBracket {
                    guard !cur.isEmpty else { return nil }       // 空段
                    parts.append(cur); current = nil
                } else {
                    cur.append(c); current = cur
                }
            } else if c == openBracket {
                current = ""
            } else if c == reasonSeparator {
                return SplitRecordValue(parts: parts, reason: String(statement[statement.index(after: i)...]))
            } else if c != " " {
                return nil                                       // 括號外只允許空白與分隔
            }
            i = statement.index(after: i)
        }
        return nil                                               // 沒有理由分隔、或括號未關
    }
}

/// 一筆拆分記錄：被退役的原 literal ＋ 解析後的 statement。
public struct SplitRecord: Equatable, Sendable {
    public let retired: String
    public let record: SplitRecordValue
    public init(retired: String, record: SplitRecordValue) { self.retired = retired; self.record = record }
}

extension Entry {
    /// 本 work 的拆分記錄（`field: authors` 的 reference，經唯一解析器）。decode 閘已保證每筆都解析得出，
    /// 這裡的 `compactMap` 是對手改檔的縱深防禦，不是第二條讀法。
    public var splitRecords: [SplitRecord] {
        references.compactMap { r in
            guard r.field == "authors", let v = r.value,
                  case .judgement(let statement, _) = r.kind,
                  let parsed = SplitRecordValue.parse(statement) else { return nil }
            return SplitRecord(retired: v, record: parsed)
        }
    }
}
