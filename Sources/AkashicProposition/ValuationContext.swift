import CryptoKit
import Foundation
import AkashicCore

/// 求值的 context：**對哪個世界、在哪個時間**（#202）。
///
/// PR #201 的求值只收 `PropositionModel`，結果沒有指出它是對哪個 store revision、
/// 哪個有效時間成立。那讓 `.holds` 這件事**不可重播**：同一個命題明天再問可能得到
/// 不同答案，而系統無從說明為什麼，也無從比較兩次的答案是否真的矛盾。
///
/// ## 三個時間不可混用
///
/// | 欄位 | 是什麼 | 住在哪 |
/// |---|---|---|
/// | **valid time** | 命題**成立**的時間 | 本型別 |
/// | recorded | 來源**被記錄**的時間 | `Assertion.recorded` |
/// | accepted | **裁決**發生的時間 | `AcceptedFact.acceptedAt` |
///
/// 三者都是真的、都不一樣，而且**互相不能代替**。一篇 2019 年的論文可能 2026 年
/// 才被匯入（recorded）、2026 年才被裁決（accepted），但它成立的時間是 2019
/// （valid）。用 recorded 冒充 valid 會讓「什麼時候發生」變成「什麼時候被記錄」。
///
/// ## Git branch 不是 possible world
///
/// 誘人的想法是拿 git branch 當「另一個可能世界」。**不成立**：branch 是開發歷史，
/// 它記錄的是「誰在什麼時候改了檔案」，不是「世界處於什麼狀態」。同一個 branch 上
/// 的兩個 commit 也可能對應同一個世界狀態（改的是註解），不同 branch 也可能對應
/// 同一個世界狀態。`storeRevision` 記的是**內容的身分**，不是版本控制的身分。
public struct ValuationContext: Equatable {

    /// 對哪個 store。與 registry key 同一個命名空間（nil ＝ 未註冊的 ad-hoc store）。
    public let storeKey: String?

    /// **內容的身分**——同樣的內容必得同樣的 revision，不同內容必得不同的。
    ///
    /// 不用 git commit、不用 mtime、不用「載入的時刻」：前者記的是開發歷史，
    /// 後兩者會讓「同一份內容」在兩次載入得到兩個 revision，於是可重播性變成
    /// 假的——你能記下 revision，但記下來的東西對不回同一個世界。
    public let storeRevision: String

    /// 命題**成立**的時間點（ISO 8601 前綴，`YYYY[-MM[-DD]]`）。
    ///
    /// `nil` ＝ **未指定，不是「現在」**。這個區別是刻意的：預設成「現在」會讓
    /// 系統隱式讀取 wall clock，於是同一次求值在不同時刻得到不同答案而不留痕。
    /// 需要「現在」的呼叫端要**自己**把它寫進來——那樣它就出現在 context 裡，
    /// 可被記錄、比較、重播。
    public let validTime: String?

    public init(storeKey: String?, storeRevision: String, validTime: String? = nil) {
        self.storeKey = storeKey
        self.storeRevision = storeRevision
        self.validTime = validTime
    }
}

/// 帶 context 的求值結果——**結果與它成立的世界綁在一起**。
///
/// 分開回傳 `TruthValue` 與 context 會讓兩者可以被拆散、再配對錯。綁成一個值，
/// 「這個 `.holds` 是對哪個世界說的」就無法遺失。
public struct Valuation: Equatable {
    public let truth: TruthValue
    public let context: ValuationContext
    /// 被求值的那個命題。重播時不必另外記。
    public let proposition: Proposition
}

extension PropositionModel {

    /// 由內容算出的 revision（SHA-256 前 16 hex）。
    ///
    /// **只涵蓋求值讀得到的東西**：entry 的 citekey／作者槽、person 的 key／names。
    /// 涵蓋更多（例如 title）會讓無關的編輯造成 revision 變動，於是「revision 不同」
    /// 不再蘊含「求值可能不同」——那會讓這個欄位變成雜訊。
    ///
    /// 涵蓋更少則相反：漏掉某個求值讀的欄位，會讓兩個**求值行為不同**的世界共用
    /// 同一個 revision，可重播性就是假的。目前 `authored` 只讀作者槽與 person key／
    /// names，所以這個集合是**精確**的——新增 predicate 時必須同步擴充，
    /// `testRevisionCoversEverythingEvaluationReads` 是機械提醒。
    public var contentRevision: String {
        var parts: [String] = []
        for key in entriesByKey.keys.sorted() {
            let e = entriesByKey[key]!
            let slots = e.authors.map { a -> String in
                switch a {
                // display-safe-exempt: 這是 **hash 的輸入**不是訊息——消毒會改變
                // revision，讓「同樣的內容得同樣的 revision」不再成立
                case .key(let k): return CanonicalEncoding.field("k", k)
                case .literal(let s): return CanonicalEncoding.field("l", s)
                }
            }
            parts.append(CanonicalEncoding.record(["e", key] + slots))
        }
        for key in peopleByKey.keys.sorted() {
            parts.append(CanonicalEncoding.record(["p", key] + peopleByKey[key]!.names.sorted()))
        }
        return CanonicalEncoding.digest(parts)
    }
}

/// **長度前綴編碼**——把任意字串序列變成無歧義的一條位元組串（#202 verify F1）。
///
/// 第一版用 `joined(separator: ",")`／`"\n"` 而**不逃脫分隔符**。那讓兩個不同的
/// 世界得到同一個 revision，而本 repo 的資料**routinely** 觸發它：person 的 names
/// 幾乎都是 `Family, Given` 形式（實測 `~/.akashic` 有 893 個 person 檔含逗號）。
///
/// 席位實測的碰撞用的是本 repo 自己的 fixture 名字：
///
///     A: names = ["Chen, H.-Y."]          → 求值 .undetermined(.supportingEvidenceUnresolved)
///     B: names = ["Chen", "H.-Y."]        → 求值 .undetermined(.noSupportingEvidence)
///     兩者 revision 相同 → 拿 A 的 revision 標 B 的求值，`revisionMismatch` 守衛放行
///
/// 也就是說「可重播」在**最常見**的資料形狀上是假的。而 doc 當時還寫著涵蓋範圍
/// 「精確」——那句話是本 change 自己駁倒的。
///
/// 長度前綴（`<utf8 byte count>:<content>`）是**單射**的：不同的欄位序列不可能
/// 編出同一條串，因為長度本身把邊界寫進了編碼，不依賴任何字元不出現在內容裡。
enum CanonicalEncoding {
    /// 一個帶標籤的欄位。
    static func field(_ tag: String, _ value: String) -> String {
        "\(tag)\(unit(value))"
    }
    /// 一個長度前綴的單元。
    static func unit(_ s: String) -> String { "\(s.utf8.count):\(s)" }
    /// 一筆記錄＝若干單元串接（每個都長度前綴，所以不需要分隔符）。
    static func record(_ fields: [String]) -> String {
        fields.map(unit).joined()
    }
    /// 記錄序列 → SHA-256 前 16 hex。
    static func digest(_ records: [String]) -> String {
        let joined = records.map(unit).joined()
        let d = SHA256.hash(data: Data(joined.utf8))
        return d.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

extension Proposition {

    /// 帶 context 的求值。**這是 #202 之後的主要入口**。
    ///
    /// `evaluate(in:)`（無 context）仍然存在，因為多數呼叫端只想知道真值；但任何
    /// 要**保存**結果的路徑都該走這一支，否則保存下來的 `.holds` 說不出它是對哪個
    /// 世界成立的。
    ///
    /// ## 時間語意目前是「拒絕」不是「忽略」
    ///
    /// `authored` **沒有時間維度**——一篇論文的作者身分不隨時間改變。所以指定
    /// `validTime` 時本 predicate 不會因此改變答案。
    ///
    /// **但那不代表可以忽略它。** 忽略會讓呼叫端以為時間被納入考慮了。所以：
    /// 帶 `validTime` 求一個不支援時間的 predicate 會**明確拒絕**
    /// （`ValuationError.timeNotSupported`），而不是靜默回答一個沒考慮時間的答案。
    /// 這與 #205 的立場一致——不能表達的事要說出來，不要折成一個看起來正常的回答。
    public func evaluate(in model: PropositionModel,
                         context: ValuationContext) throws -> Valuation {
        if context.validTime != nil, !supportsValidTime {
            throw ValuationError.timeNotSupported(predicate: predicateName)
        }
        // revision 必須與 model 相符——拿 A 的 revision 標 B 的求值結果，
        // 那個標籤是假的，而假的可重播性比沒有更糟
        guard context.storeRevision == model.contentRevision else {
            throw ValuationError.revisionMismatch(expected: model.contentRevision,
                                                  got: context.storeRevision)
        }
        return Valuation(truth: try evaluate(in: model), context: context, proposition: self)
    }

    /// 這個 predicate 的真值會不會隨有效時間改變。
    ///
    /// `authored` 不會（作者身分不隨時間變）。像 `affiliatedWith` 那種**會**——
    /// 一個人 2019 在 A 校、2026 在 B 校。加那種 predicate 時這裡要回 true，
    /// 並在 `evaluate` 裡真的用到 `validTime`。
    public var supportsValidTime: Bool {
        switch self {
        case .authored: return false
        }
    }
}

public enum ValuationError: Error, Equatable, LocalizedError {
    case timeNotSupported(predicate: String)
    case revisionMismatch(expected: String, got: String)

    public var errorDescription: String? {
        switch self {
        case .timeNotSupported(let p):
            return "predicate「\(p)」沒有時間維度，指定 validTime 會得到一個沒考慮時間的答案"   // display-safe-exempt: predicateName 來自封閉 enum，是程式字面量
                + "——明確拒絕而非靜默忽略"
        case let .revisionMismatch(expected, got):
            return "context 的 storeRevision（\(got)）與 model 實際內容（\(expected)）不符"   // display-safe-exempt: 兩者都是本模組算出的 hex digest（SHA-256 前 16 hex），非 store 內容
                + "——標錯 revision 的結果不可重播"
        }
    }
}
