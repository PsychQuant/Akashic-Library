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
    // #204：真值函數式組合。古典二值語意在 `TruthFunction.swift`，
    // 認識面的三值組合在本檔下方——**兩層各自完整，互不冒充**。
    case and(Formula, Formula)
    case or(Formula, Formula)
    case implies(Formula, Formula)
    /// 共同否定（joint denial／NOR）。TLP 5.5 的完備基底。
    case nor(Formula, Formula)

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
            return Formula.kleeneNot(try inner.evaluate(in: model))
        case let .and(a, b):
            return Formula.kleeneAnd(try a.evaluate(in: model), try b.evaluate(in: model))
        case let .or(a, b):
            return Formula.kleeneOr(try a.evaluate(in: model), try b.evaluate(in: model))
        case let .implies(a, b):
            // p → q ≡ ¬p ∨ q，三值同樣照這個定義（Kleene）
            return Formula.kleeneOr(Formula.kleeneNot(try a.evaluate(in: model)),
                                    try b.evaluate(in: model))
        case let .nor(a, b):
            return Formula.kleeneNot(Formula.kleeneOr(try a.evaluate(in: model),
                                                      try b.evaluate(in: model)))
        }
    }

    // MARK: - Kleene 強三值運算子（認識面）
    //
    // **這不是命題 5 的二值真值函數**——它回答的是「以我們現在知道的，這個複合
    // 主張的知識狀態是什麼」。古典二值那一層在 `TruthFunction.swift`。
    //
    // 「強」的意思是：只要**已知的部分足以決定結果**，就給出結果而不因為有未定
    // 就一律未定。`false ∧ unknown` 是 false（不論那個 unknown 是什麼，合取都
    // 為假）；`true ∨ unknown` 是 true。這比「有未定就未定」（弱三值）保守得少，
    // 而且每一步都還是**只在證據足夠時**才宣稱真值——與本模組的立場一致。

    static func kleeneNot(_ t: TruthValue) -> TruthValue {
        switch t {
        case .holds: return .fails
        case .fails: return .holds
        case .undetermined(let why): return .undetermined(why)
        }
    }

    /// **兩邊都未定時，回傳左邊的 reason**（#204 verify F9）。
    ///
    /// 真值分量是可交換的（`∧`／`∨` 的三值表本身對稱），但 `TruthValue` 帶著
    /// `UndeterminedReason`，所以 `kleeneAnd(u1, u2) != kleeneAnd(u2, u1)`
    /// 在 `Equatable` 下成立——**只有 reason 不同**。
    ///
    /// 這是刻意的：reason 是給人看的線索（「為什麼不知道」），左偏讓它決定性、
    /// 不隨雜湊或求值順序漂移。要它可交換就得把 reason 合併成集合，那會讓最常見
    /// 的單一原因情形變得囉嗦。**真值分量的可交換性由
    /// `testTruthComponentIsCommutative` 釘住**，reason 的左偏是已記錄的行為。
    static func kleeneAnd(_ a: TruthValue, _ b: TruthValue) -> TruthValue {
        // 任一為假 → 假（不論另一個知不知道）
        if case .fails = a { return .fails }
        if case .fails = b { return .fails }
        if case .holds = a, case .holds = b { return .holds }
        if case .undetermined(let w) = a { return .undetermined(w) }
        if case .undetermined(let w) = b { return .undetermined(w) }
        return .holds
    }

    static func kleeneOr(_ a: TruthValue, _ b: TruthValue) -> TruthValue {
        // 任一為真 → 真
        if case .holds = a { return .holds }
        if case .holds = b { return .holds }
        if case .fails = a, case .fails = b { return .fails }
        if case .undetermined(let w) = a { return .undetermined(w) }
        if case .undetermined(let w) = b { return .undetermined(w) }
        return .fails
    }

    /// 公式裡出現的所有原子命題。
    public var atoms: [Proposition] {
        switch self {
        case .atom(let p): return [p]
        case .not(let f): return f.atoms
        case let .and(a, b), let .or(a, b), let .implies(a, b), let .nor(a, b):
            return a.atoms + b.atoms
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
    /// 看得見：拿 `PropositionModel` 對一個 **`authored` 原子**求值的呼叫端
    /// **永遠不會**得到 `.fails`，而那正是它該知道的事。
    ///
    /// **限定詞不能省**（#203 verify F3）：`Formula.not(.atom(p))` 在 plain model
    /// 上當然可以是 `.fails`——那是 `p` 成立時 `¬p` 為假，與「原子的反證」是兩件
    /// 不同的事。本檔自己的 `testNegationIsAPropositionNotAStance` 就斷言了它。
    /// 前一版把這句寫成無限定的「永遠不會」，被自己的測試駁倒。
    public func attesting(_ attestations: [AuthorListAttestation]) throws -> AttestedModel {
        try AttestedModel(base: self, attestations: attestations)
    }
}

/// 帶完備性證言的模型。**只有這個型別能讓 `authored` 原子產生 `.fails`。**
/// （複合式的 `.fails` 不需要證言——`¬p` 在 `p` 成立時就是假的。）
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

extension AttestedModel {

    /// **含證言的 revision**（#203 verify F2）。
    ///
    /// `AttestedModel` 原本沒有 revision，而證言**會改變真值**（那是它的全部作用）。
    /// 於是 #203 的 `.fails` 路徑整個落在 #202 的保證之外：`AttestedModel.base`
    /// 是 public，呼叫端最自然的動作就是拿 `base.contentRevision` 來標，而那個值
    /// 對「有沒有證言」完全無感——同一個 revision 對應 `.fails` 與 `.undetermined`
    /// 兩個世界。
    ///
    /// 更難堪的是 `testRevisionCoversEverythingEvaluationReads` 被 doc 稱作
    /// 「機械提醒」，卻只檢查作者槽與 names，所以 #203 靜默廢掉了 #202 的核心
    /// 不變式而沒有任何東西變紅。
    public var contentRevision: String {
        var parts = [base.contentRevision]
        for key in attestationsByWork.keys.sorted() {
            let a = attestationsByWork[key]!
            parts.append(CanonicalEncoding.record(
                ["att", a.workCitekey, a.attestedBy, a.attestedAt, a.basis]))
        }
        return CanonicalEncoding.digest(parts)
    }
}

extension Proposition {

    /// 帶 context 的求值，**證言版**（#203 verify F2）。
    ///
    /// 沒有這一支，`.fails` 就是一個產生得出來、卻無法被標記與重播的真值。
    public func evaluate(in model: AttestedModel,
                         context: ValuationContext) throws -> Valuation {
        if context.validTime != nil, !supportsValidTime {
            throw ValuationError.timeNotSupported(predicate: predicateName)
        }
        guard context.storeRevision == model.contentRevision else {
            throw ValuationError.revisionMismatch(expected: model.contentRevision,
                                                  got: context.storeRevision)
        }
        return Valuation(truth: try Formula.atom(self).evaluate(in: model),
                         context: context, proposition: self)
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
                // **空名單不得成為反證**（#203 verify F4）。`allSatisfy` 對空陣列
                // 是**空真**，所以前一版對「作者被壞掉的 re-import 清空」或「根本
                // 沒匯入作者」的 work，會對**每一個人**回 `.fails`——那是**從缺席
                // 製造反證**，正是本模組存在要擋的那個推論。
                //
                // 證言說的是「我核對過這份名單」；一份空名單沒有可核對的內容，
                // 它證成不了任何人不在其中。
                guard !entry.authors.isEmpty else { return plain }
                // **完備 ≠ 已歸戶**：還有 literal 槽就仍然不知道那是不是他
                let allResolved = entry.authors.allSatisfy {
                    if case .key = $0 { return true } else { return false }
                }
                return allResolved ? .fails : plain
            }
        case .not(let inner):
            return Formula.kleeneNot(try inner.evaluate(in: model))
        case let .and(a, b):
            return Formula.kleeneAnd(try a.evaluate(in: model), try b.evaluate(in: model))
        case let .or(a, b):
            return Formula.kleeneOr(try a.evaluate(in: model), try b.evaluate(in: model))
        case let .implies(a, b):
            return Formula.kleeneOr(Formula.kleeneNot(try a.evaluate(in: model)),
                                    try b.evaluate(in: model))
        case let .nor(a, b):
            return Formula.kleeneNot(Formula.kleeneOr(try a.evaluate(in: model),
                                                      try b.evaluate(in: model)))
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
