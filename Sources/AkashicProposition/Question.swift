import Foundation
import AkashicCore

/// 在開放世界模型中，yes/no 問句仍有三個窮盡的可能延續。
public struct YesNoQuestion: Equatable {
    public let subject: PropositionExpression

    /// 同時保留一個可表示的 no-answer node，因此 subject 最多使用 63 層 operator。
    public init(_ subject: PropositionExpression) throws {
        try subject.validate()
        try PropositionExpression.not(subject).validate()
        self.subject = subject
    }

    public var answerSpace: [Answer] { [.yes, .no, .undetermined] }

    public enum Answer: Equatable, CaseIterable {
        case yes
        case no
        case undetermined

        /// 單一三值映射供 public answer path 與 module tests 共用；canonical
        /// completeness witness 產生的 `.fails` 會在此映成可證成的 no。
        static func mapped(from truth: TruthValue) -> Self {
            switch truth {
            case .holds: return .yes
            case .fails: return .no
            case .undetermined: return .undetermined
            }
        }
    }

    /// 映射單一 context-bound valuation，不攤平也不重建它的稽核紀錄。
    public func answer(in context: ValuationContext) throws -> AnswerResult {
        let subjectValuation = try subject.evaluate(in: context)
        let answer = Answer.mapped(from: subjectValuation.truth)
        let establishedAnswer: EstablishedAnswer?
        switch answer {
        case .yes:
            establishedAnswer = EstablishedAnswer(valuation: subjectValuation)
        case .no:
            establishedAnswer = EstablishedAnswer(
                valuation: subjectValuation.negated(as: .not(subject))
            )
        case .undetermined:
            establishedAnswer = nil
        }
        return AnswerResult(
            answer: answer,
            subjectValuation: subjectValuation,
            establishedAnswer: establishedAnswer
        )
    }
}

/// Determinate answer 可主張的 expression，以及與它完全一致的 holds valuation。
public struct EstablishedAnswer: Equatable {
    public let valuation: Valuation
    public var expression: PropositionExpression { valuation.expression }

    fileprivate init(valuation: Valuation) {
        precondition(valuation.truth == .holds, "established answer 必須是 holds valuation")
        self.valuation = valuation
    }
}

public struct AnswerResult: Equatable {
    public let answer: YesNoQuestion.Answer
    public let subjectValuation: Valuation
    public let establishedAnswer: EstablishedAnswer?

    init(
        answer: YesNoQuestion.Answer,
        subjectValuation: Valuation,
        establishedAnswer: EstablishedAnswer?
    ) {
        self.answer = answer
        self.subjectValuation = subjectValuation
        self.establishedAnswer = establishedAnswer
    }
}

// MARK: - 名目時間角色

public enum PropositionTimeRole: String, Equatable, Hashable, Sendable {
    case recorded
    case accepted
}

/// 時間 wrapper 的驗證保留具型別、有界的原因，不反射未受信任輸入。
public struct PropositionTimeValidationError:
    Error, Equatable, Hashable, Sendable, LocalizedError, CustomStringConvertible
{
    public let role: PropositionTimeRole
    public let reason: ValidDayError

    public var errorDescription: String? {
        "\(role.rawValue) time 無效：\(reason.localizedDescription)" // display-safe-exempt: 兩個值都是封閉 enum
    }

    public var description: String {
        errorDescription ?? "命題時間無效"
    }
}

public struct RecordedTime: Equatable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        do {
            _ = try ValidDay(rawValue)
        } catch let reason as ValidDayError {
            throw PropositionTimeValidationError(role: .recorded, reason: reason)
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: RecordedTime, rhs: RecordedTime) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AcceptedTime: Equatable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        do {
            _ = try ValidDay(rawValue)
        } catch let reason as ValidDayError {
            throw PropositionTimeValidationError(role: .accepted, reason: reason)
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: AcceptedTime, rhs: AcceptedTime) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - 已記錄主張與已接受事實

public enum Stance: String, Equatable {
    case asserted
    case denied
    case questioned
}

/// 保存來源的立場與接受它成為事實，是兩個不同操作。
public struct Assertion: Equatable {
    public let expression: PropositionExpression
    public let stance: Stance
    public let source: String
    public let recorded: RecordedTime

    public init(
        expression: PropositionExpression,
        stance: Stance,
        source: String,
        recorded: RecordedTime
    ) {
        self.expression = expression
        self.stance = stance
        self.source = source
        self.recorded = recorded
    }
}

public struct AcceptedFact: Equatable {
    public let expression: PropositionExpression
    public let basis: Assertion
    public let valuation: Valuation
    public let acceptedBy: String
    public let acceptedAt: AcceptedTime

    fileprivate init(
        expression: PropositionExpression,
        basis: Assertion,
        valuation: Valuation,
        acceptedBy: String,
        acceptedAt: AcceptedTime
    ) {
        self.expression = expression
        self.basis = basis
        self.valuation = valuation
        self.acceptedBy = acceptedBy
        self.acceptedAt = acceptedAt
    }
}

public enum AdjudicationRefusal:
    Error, Equatable, LocalizedError, CustomStringConvertible
{
    /// 先於 stance 與 truth 檢查，避免否認立場掩蓋「用了另一個命題的證據」。
    case expressionMismatch(
        assertion: PropositionExpression,
        valuation: PropositionExpression
    )
    case stanceIsNotAssertion(Stance)
    /// 保存原封不動的 valuation，不只保存裸 truth value。
    case notEstablished(Valuation)

    public var errorDescription: String? {
        switch self {
        case .expressionMismatch:
            return "裁決使用了另一個命題的 valuation，拒絕接受"
        case .stanceIsNotAssertion(let stance):
            return "立場是 \(stance.rawValue)，不是 asserted——只有主張能被裁決為事實" // display-safe-exempt: Stance 是封閉 enum
        case .notEstablished:
            return "命題在指定 snapshot 與 valid day 下未成立——不得接受為事實"
        }
    }

    /// 不讓一般 Error 插值反射 proposition literal、key 或 trace value。
    public var description: String {
        errorDescription ?? "裁決拒絕"
    }
}

/// 只接受已算好的 valuation。裁決絕不重載 mutable store，也不重算可能與 caller 已見
/// 答案分叉的 evidence。
public func adjudicate(
    _ assertion: Assertion,
    valuation: Valuation,
    acceptedBy: String,
    acceptedAt: AcceptedTime
) throws -> AcceptedFact {
    // Public expression enum case 可直接構造；即使 malformed expression 正常情況下無法
    // 產生 public valuation，語意邊界仍須 fail closed。
    try assertion.expression.validate()
    try valuation.expression.validate()

    guard assertion.expression == valuation.expression else {
        throw AdjudicationRefusal.expressionMismatch(
            assertion: assertion.expression,
            valuation: valuation.expression
        )
    }
    guard assertion.stance == .asserted else {
        throw AdjudicationRefusal.stanceIsNotAssertion(assertion.stance)
    }
    guard valuation.truth == .holds else {
        throw AdjudicationRefusal.notEstablished(valuation)
    }
    return AcceptedFact(
        expression: assertion.expression,
        basis: assertion,
        valuation: valuation,
        acceptedBy: acceptedBy,
        acceptedAt: acceptedAt
    )
}
