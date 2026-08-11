import Foundation

/// 命題邏輯各階段共用且不可由呼叫端調整的資源上限。
public enum PropositionLogicLimits {
    public static let maximumReferenceUTF8ByteCount = 4_096
    public static let maximumOperatorDepth = 64
    public static let maximumNodeCount = 4_096
    public static let maximumDistinctAtomCount = 63
    public static let maximumClassicalRows = 4_096
    public static let maximumSupervaluationCompletions = 4_096
    public static let maximumRewriteNodeCount = 4_096
    public static let maximumSynthesisNodeCount = 4_096
}

/// Structural hashing 的封閉輸入。每個 component 都保留一項可稽核的結構事實。
enum PropositionStructuralHashFeedComponent: Hashable {
    case atomTableCount(Int)
    case atomPayload(length: Int, bytes: Data)
    case nodeTag(UInt8)
    case childBoundary(parentTag: UInt8, childIndex: UInt8)
    case atomIndex(Int)
}

/// 命題的唯一結構式 expression。
///
/// Storage 保持不透明；所有值都必須經 throwing factory 建立，因此 metrics、atom table
/// 與資源上限自建立後便是不可破壞的 invariant。
public struct PropositionExpression: Hashable {
    public enum Kind: Equatable {
        case atom
        case not
        case and
        case or
        case implies
        case nor
    }

    private struct CanonicalAtom {
        let proposition: Proposition
        let bytes: Data
    }

    private indirect enum Storage {
        case atom(Proposition)
        case not(PropositionExpression)
        case and(PropositionExpression, PropositionExpression)
        case or(PropositionExpression, PropositionExpression)
        case implies(PropositionExpression, PropositionExpression)
        case nor(PropositionExpression, PropositionExpression)
    }

    private let storage: Storage
    private let canonicalAtoms: [CanonicalAtom]

    /// Root operator；atomic expression 回傳 `.atom`。
    public var kind: Kind {
        switch storage {
        case .atom: .atom
        case .not: .not
        case .and: .and
        case .or: .or
        case .implies: .implies
        case .nor: .nor
        }
    }

    /// Atomic expression 的命題；operator expression 為 `nil`。
    public var proposition: Proposition? {
        guard case .atom(let proposition) = storage else { return nil }
        return proposition
    }

    /// Root 的直接 children，固定為 atom 0 個、not 1 個、binary operator 2 個。
    public var children: [Self] {
        switch storage {
        case .atom:
            []
        case .not(let operand):
            [operand]
        case .and(let lhs, let rhs),
             .or(let lhs, let rhs),
             .implies(let lhs, let rhs),
             .nor(let lhs, let rhs):
            [lhs, rhs]
        }
    }

    /// Root 至最深 atom 的 operator 數；atom 本身為 0。
    public let operatorDepth: Int

    /// 包含所有 operator 與 atom occurrence 的節點數。
    public let nodeCount: Int

    /// 依 canonical atom bytes 字典序排列且去重的 atom table。
    public var atoms: [Proposition] {
        canonicalAtoms.map(\.proposition)
    }

    /// `akashic-proposition-expression-v1` 的完整 canonical bytes。
    public var canonicalBytes: Data {
        var result = Data()
        let domain = Data("akashic-proposition-expression-v1".utf8)
        Self.appendUInt64(domain.count, to: &result)
        result.append(domain)

        Self.appendUInt64(canonicalAtoms.count, to: &result)
        for atom in canonicalAtoms {
            Self.appendUInt64(atom.bytes.count, to: &result)
            result.append(atom.bytes)
        }

        Self.appendUInt64(nodeCount, to: &result)
        var stack = [self]
        while let current = stack.popLast() {
            result.append(Self.nodeTag(for: current.kind))
            switch current.storage {
            case .atom(let proposition):
                // Atom occurrence 的 index 必須相對於 root canonical table；child 自己的
                // 單元素 table 永遠是 0，會錯把 `op(p,q)` 與 `op(q,p)` 編成同一結構。
                Self.appendUInt64(atomIndex(for: proposition), to: &result)
            case .not(let operand):
                stack.append(operand)
            case .and(let lhs, let rhs),
                 .or(let lhs, let rhs),
                 .implies(let lhs, let rhs),
                 .nor(let lhs, let rhs):
                stack.append(rhs)
                stack.append(lhs)
            }
        }
        return result
    }

    /// Hashing 與測試稽核共用的結構 feed；順序為 atom table 後接 preorder tree。
    var structuralHashFeed: [PropositionStructuralHashFeedComponent] {
        var feed: [PropositionStructuralHashFeedComponent] = [
            .atomTableCount(canonicalAtoms.count)
        ]
        feed.reserveCapacity(1 + canonicalAtoms.count + (nodeCount * 3))
        for atom in canonicalAtoms {
            feed.append(.atomPayload(length: atom.bytes.count, bytes: atom.bytes))
        }

        var stack: [(expression: Self, boundary: (parentTag: UInt8, childIndex: UInt8)?)] = [
            (self, nil)
        ]
        while let item = stack.popLast() {
            if let boundary = item.boundary {
                feed.append(
                    .childBoundary(
                        parentTag: boundary.parentTag,
                        childIndex: boundary.childIndex
                    )
                )
            }

            let tag = Self.nodeTag(for: item.expression.kind)
            feed.append(.nodeTag(tag))
            switch item.expression.storage {
            case .atom(let proposition):
                feed.append(.atomIndex(atomIndex(for: proposition)))
            case .not(let operand):
                stack.append((operand, (tag, 0)))
            case .and(let lhs, let rhs),
                 .or(let lhs, let rhs),
                 .implies(let lhs, let rhs),
                 .nor(let lhs, let rhs):
                stack.append((rhs, (tag, 1)))
                stack.append((lhs, (tag, 0)))
            }
        }
        return feed
    }

    private init(
        storage: Storage,
        operatorDepth: Int,
        nodeCount: Int,
        canonicalAtoms: [CanonicalAtom]
    ) {
        self.storage = storage
        self.operatorDepth = operatorDepth
        self.nodeCount = nodeCount
        self.canonicalAtoms = canonicalAtoms
    }

    /// 建立 atomic expression；命題驗證錯誤維持原本的 `PropositionError`。
    public static func atom(_ proposition: Proposition) throws -> Self {
        let bytes = try proposition.canonicalBytesV1()
        return Self(
            storage: .atom(proposition),
            operatorDepth: 0,
            nodeCount: 1,
            canonicalAtoms: [CanonicalAtom(proposition: proposition, bytes: bytes)]
        )
    }

    /// 建立 negation；不做 double-negation 化簡。
    public static func not(_ operand: Self) throws -> Self {
        try makeUnary(kind: .not, operand: operand)
    }

    /// 建立 conjunction；保留 lhs／rhs 的結構順序。
    public static func and(_ lhs: Self, _ rhs: Self) throws -> Self {
        try makeBinary(kind: .and, lhs: lhs, rhs: rhs)
    }

    /// 建立 disjunction；保留 lhs／rhs 的結構順序。
    public static func or(_ lhs: Self, _ rhs: Self) throws -> Self {
        try makeBinary(kind: .or, lhs: lhs, rhs: rhs)
    }

    /// 建立 material implication；保留 antecedent／consequent 的結構順序。
    public static func implies(_ lhs: Self, _ rhs: Self) throws -> Self {
        try makeBinary(kind: .implies, lhs: lhs, rhs: rhs)
    }

    /// 建立 NOR；保留 lhs／rhs 的結構順序。
    public static func nor(_ lhs: Self, _ rhs: Self) throws -> Self {
        try makeBinary(kind: .nor, lhs: lhs, rhs: rhs)
    }

    @available(*, deprecated, message: "改用 atom(_:)")
    public static func makeAtom(_ proposition: Proposition) throws -> Self {
        try atom(proposition)
    }

    @available(*, deprecated, message: "改用 not(_:)")
    public static func makeNot(_ operand: Self) throws -> Self {
        try not(operand)
    }

    @available(*, deprecated, message: "改用 PropositionLogicLimits.maximumOperatorDepth")
    public static var maximumOperatorDepth: Int {
        PropositionLogicLimits.maximumOperatorDepth
    }

    /// Equality 只比較完整結構 feed，不做交換、化簡或語意等價折疊。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.structuralHashFeed == rhs.structuralHashFeed
    }

    /// Hash 只消耗與 equality 相同的完整結構 feed。
    public func hash(into hasher: inout Hasher) {
        for component in structuralHashFeed {
            hasher.combine(component)
        }
    }

    private static func makeUnary(kind: Kind, operand: Self) throws -> Self {
        let depth = checkedMetric(
            adding: operand.operatorDepth,
            1,
            saturation: PropositionLogicLimits.maximumOperatorDepth + 1
        )
        guard depth <= PropositionLogicLimits.maximumOperatorDepth else {
            throw PropositionExpressionError.operatorDepthExceeded(
                actual: depth,
                maximum: PropositionLogicLimits.maximumOperatorDepth
            )
        }

        let nodes = checkedMetric(
            adding: operand.nodeCount,
            1,
            saturation: PropositionLogicLimits.maximumNodeCount + 1
        )
        guard nodes <= PropositionLogicLimits.maximumNodeCount else {
            throw PropositionExpressionError.nodeCountExceeded(
                actual: nodes,
                maximum: PropositionLogicLimits.maximumNodeCount
            )
        }

        guard operand.canonicalAtoms.count <= PropositionLogicLimits.maximumDistinctAtomCount else {
            throw PropositionExpressionError.distinctAtomCountExceeded(
                actual: operand.canonicalAtoms.count,
                maximum: PropositionLogicLimits.maximumDistinctAtomCount
            )
        }

        let storage: Storage
        switch kind {
        case .not:
            storage = .not(operand)
        case .atom, .and, .or, .implies, .nor:
            preconditionFailure("unsupported unary operator")
        }
        return Self(
            storage: storage,
            operatorDepth: depth,
            nodeCount: nodes,
            canonicalAtoms: operand.canonicalAtoms
        )
    }

    private static func makeBinary(kind: Kind, lhs: Self, rhs: Self) throws -> Self {
        let deepestChild = max(lhs.operatorDepth, rhs.operatorDepth)
        let depth = checkedMetric(
            adding: deepestChild,
            1,
            saturation: PropositionLogicLimits.maximumOperatorDepth + 1
        )
        guard depth <= PropositionLogicLimits.maximumOperatorDepth else {
            throw PropositionExpressionError.operatorDepthExceeded(
                actual: depth,
                maximum: PropositionLogicLimits.maximumOperatorDepth
            )
        }

        let childNodes = checkedMetric(
            adding: lhs.nodeCount,
            rhs.nodeCount,
            saturation: PropositionLogicLimits.maximumNodeCount + 1
        )
        let nodes = checkedMetric(
            adding: childNodes,
            1,
            saturation: PropositionLogicLimits.maximumNodeCount + 1
        )
        guard nodes <= PropositionLogicLimits.maximumNodeCount else {
            throw PropositionExpressionError.nodeCountExceeded(
                actual: nodes,
                maximum: PropositionLogicLimits.maximumNodeCount
            )
        }

        let atoms = mergedCanonicalAtoms(lhs.canonicalAtoms, rhs.canonicalAtoms)
        guard atoms.count <= PropositionLogicLimits.maximumDistinctAtomCount else {
            throw PropositionExpressionError.distinctAtomCountExceeded(
                actual: atoms.count,
                maximum: PropositionLogicLimits.maximumDistinctAtomCount
            )
        }

        let storage: Storage
        switch kind {
        case .and:
            storage = .and(lhs, rhs)
        case .or:
            storage = .or(lhs, rhs)
        case .implies:
            storage = .implies(lhs, rhs)
        case .nor:
            storage = .nor(lhs, rhs)
        case .atom, .not:
            preconditionFailure("unsupported binary operator")
        }
        return Self(
            storage: storage,
            operatorDepth: depth,
            nodeCount: nodes,
            canonicalAtoms: atoms
        )
    }

    private static func mergedCanonicalAtoms(
        _ lhs: [CanonicalAtom],
        _ rhs: [CanonicalAtom]
    ) -> [CanonicalAtom] {
        var result: [CanonicalAtom] = []
        result.reserveCapacity(lhs.count + rhs.count)
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < lhs.count, rightIndex < rhs.count {
            let left = lhs[leftIndex]
            let right = rhs[rightIndex]
            if left.bytes == right.bytes {
                precondition(
                    left.proposition == right.proposition,
                    "canonical atom bytes 必須對結構相異的 proposition 保持 injective"
                )
                result.append(left)
                leftIndex += 1
                rightIndex += 1
            } else if left.bytes.lexicographicallyPrecedes(right.bytes) {
                result.append(left)
                leftIndex += 1
            } else {
                result.append(right)
                rightIndex += 1
            }
        }
        result.append(contentsOf: lhs[leftIndex...])
        result.append(contentsOf: rhs[rightIndex...])
        return result
    }

    private static func checkedMetric(
        adding lhs: Int,
        _ rhs: Int,
        saturation: Int
    ) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { return saturation }
        return sum
    }

    private static func nodeTag(for kind: Kind) -> UInt8 {
        switch kind {
        case .atom: 0x00
        case .not: 0x01
        case .and: 0x02
        case .or: 0x03
        case .implies: 0x04
        case .nor: 0x05
        }
    }

    private func atomIndex(for proposition: Proposition) -> Int {
        guard let index = canonicalAtoms.firstIndex(where: { $0.proposition == proposition }) else {
            preconditionFailure("expression atom 必須存在於 canonical atom table")
        }
        return index
    }

    private static func appendUInt64(_ value: Int, to data: inout Data) {
        guard let converted = UInt64(exactly: value) else {
            preconditionFailure("canonical framing length 必須可表示為 UInt64")
        }
        var bigEndian = converted.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

/// Expression shape 的具型別錯誤。Nested atom 錯誤不包裝，仍原樣擲出 `PropositionError`。
public enum PropositionExpressionError:
    Error, Equatable, LocalizedError, CustomStringConvertible, CustomDebugStringConvertible
{
    case operatorDepthExceeded(actual: Int, maximum: Int)
    case nodeCountExceeded(actual: Int, maximum: Int)
    case distinctAtomCountExceeded(actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .operatorDepthExceeded(let actual, let maximum):
            "命題 expression 的 operator 深度 \(actual) 超過上限 \(maximum)"
        case .nodeCountExceeded(let actual, let maximum):
            "命題 expression 的節點數 \(actual) 超過上限 \(maximum)"
        case .distinctAtomCountExceeded(let actual, let maximum):
            "命題 expression 的相異 atom 數 \(actual) 超過上限 \(maximum)"
        }
    }

    public var description: String {
        errorDescription ?? "命題 expression 不合法"
    }

    public var debugDescription: String {
        description
    }
}

extension Proposition {
    /// 將 atomic predicate 明示提升成 expression，並保留原始驗證錯誤。
    public func asExpression() throws -> PropositionExpression {
        try PropositionExpression.atom(self)
    }
}
