import Foundation

/// verdict 記錄的三把鍵（change `resolution-verdict-states`，#619／#636）。
///
/// 在此之前「兩筆 verdict 算同一筆」只有一個定義——`verdictEqualityKey`（field ＋ 配對，不含 rule）——而它被約 40 個
/// 使用點共用，問的其實是三個不同的問題：
///
/// | 鍵 | 問什麼 | 用在哪 |
/// |---|---|---|
/// | `verdictPairingKey` | 這兩筆講的是不是**同一個配對** | 矛盾判斷、狀態推導 |
/// | `verdictRecordKey` | 這兩筆是不是**同一筆記錄**（可以只留一筆） | 寫入去重、合併收攏、D64 重複掃描 |
/// | `verdictEqualityKey` | 同一個 field、同一個配對，不分判定層級 | D20 退役相反判定、D23 confirmed literal 唯一性 |
///
/// 單一定義擋住兩件事：#636 的逐篇判定與既有 apply verdict 同鍵、被 `appendIfAbsent` 丟掉；#619 的「查過、判不出來」
/// 沒有欄位可寫。直接讓 `verdictEqualityKey` 帶層級會一刀切換全部使用點，而恰好需要「不分層級」的 D20／D23／#486 會安靜
/// 錯在最需要對的地方——所以拆成三把具名的鍵，由每個使用點顯式挑。
extension ProvenanceReference {

    /// confirmed／rejected 的**判定層級**（封閉二值）。
    ///
    /// 判準是**封閉列舉的 rule**，不是「看起來像人判的」這種性質：只有 `judgedRules` 裡的兩個 rule 是 `judged`，
    /// 其餘全部——四個 tier 的 rule、`venue-name-exact`、`org-name-exact`、缺尾註的 legacy、無法辨識的 rule——是 `nominated`。
    /// 讓整個 rule 字串參與相等會讓同一配對經不同 tier 重複 apply 累積多筆 confirmed；二值只開放使用者裁決的那一格
    /// （apply 與逐篇判定並存，#636）。
    public enum VerdictClass: String, Sendable {
        case judged
        case nominated
    }

    /// 屬於 `judged` 層級的 rule——**封閉列舉，兩個，不得依性質相似類推第三個**。
    ///
    /// - `author-judged-per-work`：person 的逐篇判定（`--judge`／`--refute`）
    /// - `author-organization-judged`：`attribute-org` 的團體作者判定。實作前探勘時補進來——它同樣附理由、同樣有
    ///   「先 apply、後判定會被去重吃掉」的 #636 形狀
    public static let judgedRules: Set<String> = [RuleName.judgedPerWork, RuleName.orgJudged]

    /// rule（可能缺席）→ 判定層級。
    public static func verdictClass(rule: String?) -> VerdictClass {
        guard let rule else { return .nominated }
        return judgedRules.contains(rule) ? .judged : .nominated
    }

    /// 本筆 verdict 的判定層級。非 judgement 型或非 confirmed／rejected 欄位回 nil。
    public var verdictClass: VerdictClass? {
        guard field == Self.resolutionConfirmedField || field == Self.resolutionRejectedField,
              case .judgement(let statement, _) = kind else { return nil }
        return Self.verdictClass(rule: Self.ruleTail(ofStatement: statement))
    }

    /// **配對鍵**：holderKind ＋ holder ＋ 正規化 literal。不含 field、不含層級。value 解析不了回 nil。
    ///
    /// 矛盾判斷（confirmed 與 rejected 配對鍵相同）與狀態推導都用它。`matchingKey` 與 `verdictEqualityKey` 同一把正規化
    /// （#470），所以「只差空白的兩個拼法是同一個配對」在三把鍵上答案一致。
    public static func verdictPairingKey(value: String?) -> String? {
        guard let v = value, let p = VerdictPairingValue.parse(v) else { return nil }
        return "\(p.holderKind.rawValue):\(p.holder)\u{0}" + NameNormalization.matchingKey(p.literal)
    }

    /// **記錄鍵**：寫入去重、合併收攏、D64 重複掃描的單一定義。
    ///
    /// - confirmed／rejected：`verdictEqualityKey`（field ＋ 配對）＋ 判定層級。同一配對的 `nominated` 與 `judged` 是兩筆記錄
    ///   （#636 並存）；同層級而只差空白的拼法仍是同一筆（#470 不變）。
    /// - undecided：整筆位元組相等（`byteExactKey`）。同一配對的多次查證是設計上要保留的，只有完全相同的重送才算重複。
    /// - 其餘欄位：`verdictEqualityKey` 的回退鍵（非 verdict 欄位本來就不在這條不變式的轄下）。
    ///
    /// 開頭的 tag 讓三支永遠不會撞鍵：沒有任何內容能從一支偽造出另一支的形狀。
    public var verdictRecordKey: [[UInt8]] {
        if field == Self.resolutionUndecidedField {
            return [[2]] + byteExactKey
        }
        let base = Array(Self.verdictEqualityKey(field: field, value: value).utf8)
        guard let cls = verdictClass else { return [[0], base] }
        return [[1], base, Array(cls.rawValue.utf8)]
    }
}
