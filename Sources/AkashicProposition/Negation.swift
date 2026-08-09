import Foundation
import AkashicCore

/// 顯式否定與可證成的否定答案（#203）。
///
/// PR #201 的答案空間只有 `.yes`／`.no`／`.undetermined` **三個標籤**，沒有可被
/// 求值、主張、裁決的否定命題 `¬p`。而 `Stance.denied` 與 `Answer.no` **都不是**
/// 否定命題：前者是「某人否認 p」（關於**立場**），後者是「對問句的回答」
/// （關於**問答**）。`¬p` 是一個**命題**——它自己可以被主張、被裁決、被組合。
///
/// 三者混用會讓「他否認這件事」與「這件事不成立」變成同一件事，而它們的證據
/// 要求完全不同。
public indirect enum Formula: Equatable {
    case atom(Proposition)
    case not(Formula)

    /// 這個公式在模型下的真值。**三值，不是二值**——`¬p` 的未定仍是未定。
    ///
    /// 否定的真值表（Kleene 強三值）：
    ///
    /// | p | ¬p |
    /// |---|---|
    /// | holds | fails |
    /// | fails | holds |
    /// | undetermined | **undetermined** |
    ///
    /// 最後一列是重點：**`p` 未定時 `¬p` 也未定**，不是 true。把「不知道 p」
    /// 讀成「¬p 成立」正是本模組從第一天就在擋的 closed-world 誤推。
    public func evaluate(in model: PropositionModel) throws -> TruthValue {
        switch self {
        case .atom(let p):
            return try p.evaluate(in: model)
        case .not(let inner):
            switch try inner.evaluate(in: model) {
            case .holds: return .fails
            case .fails: return .holds
            case .undetermined(let why): return .undetermined(why)
            }
        }
    }

    /// 公式裡出現的所有原子命題（去重後依 predicate 與引數排序，決定性）。
    public var atoms: [Proposition] {
        switch self {
        case .atom(let p): return [p]
        case .not(let f): return f.atoms
        }
    }
}

// MARK: - 讓 `.fails` 真的可達

/// **作者名單完備性的證言**——`authored` 能產生 `.fails` 的唯一途徑（#203）。
///
/// ## 為什麼需要一個型別而不是一個 bool 欄位
///
/// `.fails` 需要**正面的反證**。對 `authored` 而言那是「這篇的作者名單已完備」
/// ——只有在名單完備的前提下，「名單裡沒有他」才蘊含「他不是作者」。
///
/// store 本身**沒有任何欄位能表達完備**（作者槽可能還沒歸戶、匯入來源可能只給
/// 前三位、別名可能沒對上），所以完備性只能來自**外部證言**：某個來源在某個時間
/// 宣稱「我核對過，這篇的作者就是這些」。
///
/// 那是一項**有來源的主張**，不是資料的性質。所以它長得像 `Assertion` 而不像
/// 一個 `isComplete: Bool`——一個 bool 說不出「誰說的、什麼時候、憑什麼」，
/// 而那三件事正是它能承擔反證責任的全部理由。
public struct AuthorListAttestation: Equatable {
    /// 哪一篇的作者名單。
    public let workCitekey: String
    /// 誰做的核對。
    public let attestedBy: String
    /// 何時核對的（ISO 8601 前綴）。
    public let attestedAt: String
    /// 依據什麼（出版社頁面、PDF 首頁、作者本人確認…）。**必填**——
    /// 沒有依據的完備性證言只是一句斷言，撐不起反證。
    public let basis: String

    public init(workCitekey: String, attestedBy: String, attestedAt: String, basis: String) throws {
        guard !basis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttestationError.basisRequired(workCitekey: workCitekey)
        }
        guard StoreKey.isValid(workCitekey) else {
            throw AttestationError.malformedCitekey(workCitekey)
        }
        self.workCitekey = workCitekey
        self.attestedBy = attestedBy
        self.attestedAt = attestedAt
        self.basis = basis
    }
}

public enum AttestationError: Error, Equatable, LocalizedError {
    case basisRequired(workCitekey: String)
    case malformedCitekey(String)
    case duplicateAttestation(String)

    public var errorDescription: String? {
        switch self {
        case .basisRequired(let k):
            return "「\(displaySafe(k, max: 120))」的完備性證言缺 basis"
                + "——沒有依據的證言撐不起反證"
        case .malformedCitekey(let k):
            return "證言的 citekey 不合法：'\(displaySafe(k, max: 120))'"
        case .duplicateAttestation(let k):
            return "「\(displaySafe(k, max: 120))」有重複的完備性證言"
                + "——歧義的證言集合不得用於反證"
        }
    }
}

extension PropositionModel {

    /// 附上完備性證言後的模型。
    ///
    /// 分成獨立型別而非塞進 `PropositionModel`，是為了讓「有沒有證言」在型別上
    /// 看得見：拿 `PropositionModel` 求值的呼叫端**永遠不會**得到 `.fails`，
    /// 而那正是它該知道的事。
    public func attesting(_ attestations: [AuthorListAttestation]) throws -> AttestedModel {
        try AttestedModel(base: self, attestations: attestations)
    }
}

/// 帶完備性證言的模型。**只有這個型別能產生 `.fails`。**
public struct AttestedModel {
    public let base: PropositionModel
    public let attestationsByWork: [String: AuthorListAttestation]

    init(base: PropositionModel, attestations: [AuthorListAttestation]) throws {
        var byWork: [String: AuthorListAttestation] = [:]
        for a in attestations {
            // 同 #205 的立場：歧義輸入 fail closed，不 last-wins
            guard byWork[a.workCitekey] == nil else {
                throw AttestationError.duplicateAttestation(a.workCitekey)
            }
            byWork[a.workCitekey] = a
        }
        self.base = base
        self.attestationsByWork = byWork
    }
}

extension Formula {

    /// 對**帶證言**的模型求值——這是 `.fails` 唯一可達的路徑。
    ///
    /// 判定順序刻意是「先看正面支持，再看反證」：
    ///
    /// 1. 名單裡有他 → `.holds`（有證言與否都一樣）
    /// 2. 名單裡沒有他，**且**該篇有完備性證言，**且**所有作者槽都已歸戶
    ///    → `.fails`（這是真的反證）
    /// 3. 其餘 → `.undetermined`
    ///
    /// 第 2 步的第三個條件容易漏：**證言說「名單完備」，但如果槽位還是 `.literal`，
    /// 我們仍然不知道那個 literal 是不是他**。完備 ≠ 已歸戶。少了這個條件，
    /// 一篇「作者名單已核對、但都還沒歸戶」的 work 會對每個人回 `.fails`。
    public func evaluate(in model: AttestedModel) throws -> TruthValue {
        switch self {
        case .atom(let p):
            let plain = try p.evaluate(in: model.base)
            guard case .undetermined(.noSupportingEvidence) = plain else { return plain }
            // 只有「找不到支持」這一種未定，才可能被證言翻成 .fails
            switch p {
            case let .authored(person, work):
                guard case let .key(workKey) = work, case .key = person,
                      model.attestationsByWork[workKey] != nil,
                      let entry = model.base.entriesByKey[workKey] else { return plain }
                // **完備 ≠ 已歸戶**：還有 literal 槽就仍然不知道那是不是他
                let allResolved = entry.authors.allSatisfy {
                    if case .key = $0 { return true } else { return false }
                }
                return allResolved ? .fails : plain
            }
        case .not(let inner):
            switch try inner.evaluate(in: model) {
            case .holds: return .fails
            case .fails: return .holds
            case .undetermined(let why): return .undetermined(why)
            }
        }
    }
}

extension YesNoQuestion {

    /// 帶否定命題的答案——**`.no` 攜帶 `¬p` 的內容**，不只是一個標籤（#203）。
    public struct JustifiedAnswer: Equatable {
        public let answer: Answer
        public let truth: TruthValue
        /// 這個答案對應的命題內容：`.yes` → `p`，`.no` → `¬p`，未定 → `p`。
        public let content: Formula
    }

    public func answer(in model: AttestedModel) throws -> JustifiedAnswer {
        let t = try Formula.atom(subject).evaluate(in: model)
        switch t {
        case .holds: return JustifiedAnswer(answer: .yes, truth: t, content: .atom(subject))
        case .fails: return JustifiedAnswer(answer: .no, truth: t, content: .not(.atom(subject)))
        case .undetermined: return JustifiedAnswer(answer: .undetermined, truth: t,
                                                   content: .atom(subject))
        }
    }
}
