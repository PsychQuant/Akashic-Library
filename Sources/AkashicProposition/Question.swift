import Foundation

/// 命題問句與答案空間（#200）。
///
/// 文件的限縮：**一個 query 以一組可表達的 answer-propositions 切分目前模型所
/// 容許的未來延續。** 三個詞不可混用：
///
/// | 詞 | 是什麼 |
/// |---|---|
/// | `Query` | 對紀錄／模型執行的**操作** |
/// | `Assertion` | **可真可假**的內容 |
/// | `Fact` | 經 reality comparison 與裁決而**接受**的 assertion |
///
/// 現有的 `QueryFilter` 是第一種，它篩選書目索引。本型別是第二種的問句形式，
/// 刻意**不重用** `Query` 這個名字——沿用會讓「執行查詢」「找到資料」「產生一
/// 項事實」在讀者腦中折成同一件事，而那正是 #200 要擋的。
public struct YesNoQuestion: Equatable {
    /// 被問的那個命題。
    public let subject: Proposition

    public init(_ subject: Proposition) { self.subject = subject }

    /// 答案空間：**互斥且窮盡**地切分模型容許的延續。
    ///
    /// yes/no 問句有**三個** answer——不是兩個。「未定」不是缺少答案，它是模型
    /// 目前容許的第三種延續，而且對非封閉世界是**最常見**的那一種。把它省掉，
    /// 問句就退化成「有沒有查到」。
    public var answerSpace: [Answer] { [.yes, .no, .undetermined] }

    public enum Answer: Equatable, CaseIterable {
        case yes
        case no
        case undetermined
    }

    /// 對模型求答。回傳落在答案空間裡的**哪一個**，以及未定時的原因。
    ///
    /// **回傳 `Answer` 不是 `Bool`**：型別層讓「未定」無法被靜默壓成 false。
    public func answer(in model: PropositionModel) -> (answer: Answer, truth: TruthValue) {
        let t = subject.evaluate(in: model)
        switch t {
        case .holds: return (.yes, t)
        case .fails: return (.no, t)
        case .undetermined: return (.undetermined, t)
        }
    }
}

// MARK: - Assertion 與 Fact 是不同的型別

/// 立場：同一個命題可以被主張、被否認、或只是被提問。
///
/// **提問也是一種立場**，而且是這裡最重要的一種：把一個問句記進系統**不得**讓
/// 它的主題命題變成被主張的內容。
public enum Stance: String, Equatable {
    case asserted
    case denied
    case questioned
}

/// 一項有來源的主張。
///
/// **保存 ≠ 接受。** `Assertion` 存在於系統裡，只表示「某個來源在某個時間對這個
/// 命題採取了某個立場」。它自己不帶真值——真值要對模型求（`evaluate`），而接受
/// 要經裁決（`adjudicate`）。
public struct Assertion: Equatable {
    public let proposition: Proposition
    public let stance: Stance
    /// 誰主張的。自由字串（來源可能是一個人、一份匯入、一段對話）。
    public let source: String
    /// 何時記錄的（ISO 8601 前綴）。**不是命題成立的時間**——那是命題內容的事。
    public let recorded: String

    public init(proposition: Proposition, stance: Stance, source: String, recorded: String) {
        self.proposition = proposition
        self.stance = stance
        self.source = source
        self.recorded = recorded
    }
}

/// 經裁決接受的事實。
///
/// **與 `Assertion` 是不同的型別**，這是刻意的：共用型別的話，任何來源文字都可能
/// 因為一個布林欄位被誤翻成真（#198 診斷明列的風險）。要拿到 `AcceptedFact`
/// 只有一條路——`adjudicate`——而它會拒絕投射不足的命題。
public struct AcceptedFact: Equatable {
    public let proposition: Proposition
    public let basis: Assertion
    public let acceptedBy: String
    public let acceptedAt: String

    /// `private init`：外部無法直接構造，只能經 `adjudicate`。
    fileprivate init(proposition: Proposition, basis: Assertion,
                     acceptedBy: String, acceptedAt: String) {
        self.proposition = proposition
        self.basis = basis
        self.acceptedBy = acceptedBy
        self.acceptedAt = acceptedAt
    }
}

public enum AdjudicationRefusal: Error, Equatable, LocalizedError {
    /// 立場不是主張——否認與提問都不能被接受成事實。
    case stanceIsNotAssertion(Stance)
    /// 投射不足，或模型未支持。**「未定」不得升格為事實。**
    case notEstablished(TruthValue)

    public var errorDescription: String? {
        switch self {
        case .stanceIsNotAssertion(let s):
            return "立場是 \(s.rawValue)，不是 asserted——只有主張能被裁決為事實"   // display-safe-exempt: Stance 是封閉 enum，rawValue 是三個程式字面量之一（asserted/denied/questioned），結構上帶不了 store 內容
        case .notEstablished:
            return "命題在目前模型下未成立（未定或為假）——不得接受為事實"
        }
    }
}

/// 裁決：把一項 assertion 升格為 fact。**唯一**產生 `AcceptedFact` 的路徑。
///
/// 兩道閘，缺一不可：
/// 1. 立場必須是 `asserted`——被提問或被否認的命題不能被接受。
/// 2. 對模型求值必須 `.holds`——**`.undetermined` 一律拒絕**。這是本模組的核心
///    不變式：投射不足時系統不宣稱真值，也就不可能把它接受成事實。
public func adjudicate(_ assertion: Assertion, in model: PropositionModel,
                       acceptedBy: String, acceptedAt: String) throws -> AcceptedFact {
    guard assertion.stance == .asserted else {
        throw AdjudicationRefusal.stanceIsNotAssertion(assertion.stance)
    }
    let t = assertion.proposition.evaluate(in: model)
    guard t == .holds else { throw AdjudicationRefusal.notEstablished(t) }
    return AcceptedFact(proposition: assertion.proposition, basis: assertion,
                        acceptedBy: acceptedBy, acceptedAt: acceptedAt)
}
