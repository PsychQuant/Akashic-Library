import Foundation

/// 命題的唯一結構式 expression。`Proposition` 仍只代表封閉的 atomic predicate；
/// operator 一律留在這一層，讓後續真值函數沿用同一個 AST。
public indirect enum PropositionExpression: Hashable {
    case atom(Proposition)
    case not(PropositionExpression)

    /// 語意邊界可接受的最大 operator nesting。Atom 本身不占 depth。
    public static let maximumOperatorDepth = 64

    /// 安全 atom factory；直接 enum case 仍可繞過，因此所有語意邊界也會重驗。
    public static func makeAtom(_ proposition: Proposition) throws -> Self {
        try proposition.validate()
        return .atom(proposition)
    }

    /// 安全 negation factory，同時驗證完整 operand 與新增後的 depth。
    public static func makeNot(_ operand: Self) throws -> Self {
        let expression = Self.not(operand)
        try expression.validate()
        return expression
    }

    /// 迭代檢查整條 unary chain，避免 public case 組出的未驗證深鏈遞迴耗盡 stack。
    public func validate() throws {
        _ = try validatedAtomAndDepth()
    }

    /// 結構 equality 不做 double-negation 化簡；迭代剝離 operator，直到比較 atom。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        var left = lhs
        var right = rhs
        while true {
            switch (left, right) {
            case let (.atom(leftAtom), .atom(rightAtom)):
                return leftAtom == rightAtom
            case let (.not(leftOperand), .not(rightOperand)):
                left = leftOperand
                right = rightOperand
            case (.atom, .not), (.not, .atom):
                return false
            }
        }
    }

    /// 每個 operator 都以獨立 tag 進入 hash；不遞迴，也不做語意化簡。
    public func hash(into hasher: inout Hasher) {
        var current = self
        while true {
            switch current {
            case .not(let operand):
                hasher.combine(UInt8(1))
                current = operand
            case .atom(let proposition):
                hasher.combine(UInt8(0))
                hasher.combine(proposition)
                return
            }
        }
    }

    /// 回傳已驗證的 atom 與 operator 數；expression evaluator 用同一次 traversal，
    /// 不需再以遞迴方式拆 AST。
    func validatedAtomAndDepth() throws -> (atom: Proposition, depth: Int) {
        var current = self
        var depth = 0
        while case .not(let operand) = current {
            depth += 1
            guard depth <= Self.maximumOperatorDepth else {
                throw PropositionExpressionError.operatorDepthExceeded(
                    maximum: Self.maximumOperatorDepth
                )
            }
            current = operand
        }

        guard case .atom(let proposition) = current else {
            preconditionFailure("PropositionExpression 目前只有 atom／not")
        }
        try proposition.validate()
        return (proposition, depth)
    }
}

/// Expression shape 的具型別錯誤。Nested atom 錯誤不包裝，仍原樣擲出 `PropositionError`。
public enum PropositionExpressionError:
    Error, Equatable, LocalizedError, CustomStringConvertible
{
    case operatorDepthExceeded(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .operatorDepthExceeded(let maximum):
            return "命題 expression 的 operator 深度超過上限 \(maximum)" // display-safe-exempt: maximum 是封閉 Int
        }
    }

    public var description: String {
        errorDescription ?? "命題 expression 不合法"
    }
}

extension Proposition {
    /// 將 atomic predicate 明示提升成 expression；語意操作仍會重驗 atom。
    public var expression: PropositionExpression { .atom(self) }
}
