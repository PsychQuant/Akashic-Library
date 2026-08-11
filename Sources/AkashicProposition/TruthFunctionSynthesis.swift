import Foundation

/// Bounded NOR transformation／synthesis 的具型別失敗。
public enum PropositionTransformationError:
    Error,
    Equatable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case rewriteDepthLimitExceeded(minimumRequired: Int, maximum: Int)
    case rewriteNodeLimitExceeded(minimumRequired: Int, maximum: Int)
    case synthesisDepthLimitExceeded(minimumRequired: Int, maximum: Int)
    case synthesisNodeLimitExceeded(minimumRequired: Int, maximum: Int)
    case zeroArityFunctionUnsupported
    case rewriteVerificationFailed
    case synthesisVerificationFailed

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case let .rewriteDepthLimitExceeded(minimumRequired, maximum):
            return "NOR rewrite 至少需要 depth \(minimumRequired)，超過固定上限 \(maximum)" // display-safe-exempt: 兩項皆為 bounded 整數
        case let .rewriteNodeLimitExceeded(minimumRequired, maximum):
            return "NOR rewrite 至少需要 \(minimumRequired) nodes，超過固定上限 \(maximum)" // display-safe-exempt: 兩項皆為 bounded 整數
        case let .synthesisDepthLimitExceeded(minimumRequired, maximum):
            return "NOR synthesis 至少需要 depth \(minimumRequired)，超過固定上限 \(maximum)" // display-safe-exempt: 兩項皆為 bounded 整數
        case let .synthesisNodeLimitExceeded(minimumRequired, maximum):
            return "NOR synthesis 至少需要 \(minimumRequired) nodes，超過固定上限 \(maximum)" // display-safe-exempt: 兩項皆為 bounded 整數
        case .zeroArityFunctionUnsupported:
            return "零元 Boolean function 沒有可用現有 atom syntax 表示的 expression"
        case .rewriteVerificationFailed:
            return "NOR rewrite 的結構自我驗證失敗"
        case .synthesisVerificationFailed:
            return "NOR synthesis 的 truth-condition 自我驗證失敗"
        }
    }

    public var debugDescription: String { description }
}

/// Module-internal、per-call 的 rewrite verifier fault seam。
struct RewriteVerificationFaultInjector {
    private let mutation: (_ nodeIndex: Int, _ tag: UInt8) -> UInt8

    init(mutateNodeTag: @escaping (_ nodeIndex: Int, _ tag: UInt8) -> UInt8) {
        self.mutation = mutateNodeTag
    }

    static let noOp = RewriteVerificationFaultInjector { _, tag in tag }

    func nodeTag(at index: Int, original: UInt8) -> UInt8 {
        mutation(index, original)
    }
}

/// Module-internal、per-call 的 synthesis result-vector fault seam。
struct SynthesisVerificationFaultInjector {
    private let mutation: (_ rowIndex: Int, _ output: Bool) -> Bool

    init(mutateOutput: @escaping (_ rowIndex: Int, _ output: Bool) -> Bool) {
        self.mutation = mutateOutput
    }

    static let noOp = SynthesisVerificationFaultInjector { _, output in output }

    func output(at rowIndex: Int, original: Bool) -> Bool {
        mutation(rowIndex, original)
    }
}

/// Internal estimator seam；depth 一律先於 node count 回報。
func preflightRewriteEstimate(depth: Int, nodeCount: Int) throws {
    let maximumDepth = PropositionLogicLimits.maximumOperatorDepth
    guard depth <= maximumDepth else {
        throw PropositionTransformationError.rewriteDepthLimitExceeded(
            minimumRequired: depth,
            maximum: maximumDepth
        )
    }

    let maximumNodes = PropositionLogicLimits.maximumRewriteNodeCount
    guard nodeCount <= maximumNodes else {
        throw PropositionTransformationError.rewriteNodeLimitExceeded(
            minimumRequired: nodeCount,
            maximum: maximumNodes
        )
    }
}

/// Internal defensive synthesis estimator seam；depth 一律先於 node count 回報。
func preflightSynthesisEstimate(depth: Int, nodeCount: Int) throws {
    let maximumDepth = PropositionLogicLimits.maximumOperatorDepth
    guard depth <= maximumDepth else {
        throw PropositionTransformationError.synthesisDepthLimitExceeded(
            minimumRequired: depth,
            maximum: maximumDepth
        )
    }

    let maximumNodes = PropositionLogicLimits.maximumSynthesisNodeCount
    guard nodeCount <= maximumNodes else {
        throw PropositionTransformationError.synthesisNodeLimitExceeded(
            minimumRequired: nodeCount,
            maximum: maximumNodes
        )
    }
}

extension PropositionExpression {
    /// 此 expression 是否只含 atom／NOR nodes。
    public var isNorOnly: Bool {
        var work = [self]
        while let expression = work.popLast() {
            switch expression.kind {
            case .atom:
                continue
            case .nor:
                work.append(contentsOf: expression.children)
            case .not, .and, .or, .implies:
                return false
            }
        }
        return true
    }

    /// 依 v1 fixed identities 建立 bounded、deterministic NOR-only expression。
    public func rewrittenUsingNor() throws -> Self {
        try rewrittenUsingNor(verificationFaultInjector: .noOp)
    }

    func rewrittenUsingNor(
        verificationFaultInjector: RewriteVerificationFaultInjector
    ) throws -> Self {
        // 只計算 scalar metrics；在兩項 preflight 通過前不建立任何 output subtree。
        let estimate = estimateNorRewrite(of: self)
        try preflightRewriteEstimate(
            depth: reportableMetric(
                estimate.depth,
                maximum: PropositionLogicLimits.maximumOperatorDepth
            ),
            nodeCount: reportableMetric(
                estimate.nodeCount,
                maximum: PropositionLogicLimits.maximumRewriteNodeCount
            )
        )

        let plan = makeNorPlan(from: self)
        let rewritten = try materializeNorPlan(plan)
        guard verifyRewrite(
            source: self,
            plan: plan,
            output: rewritten,
            expected: estimate,
            faultInjector: verificationFaultInjector
        ) else {
            throw PropositionTransformationError.rewriteVerificationFailed
        }
        return rewritten
    }

    /// 唯一 public truth-function synthesis surface。
    public static func synthesizeUsingNor(
        _ table: BooleanFunctionTable
    ) throws -> PropositionExpression {
        try synthesizeUsingNor(table, verificationFaultInjector: .noOp)
    }

    static func synthesizeUsingNor(
        _ table: BooleanFunctionTable,
        verificationFaultInjector: SynthesisVerificationFaultInjector
    ) throws -> PropositionExpression {
        let plan = try synthesisPlan(table)
        let candidate = try plan.rewrittenUsingNor()

        guard try verifySynthesis(
            plan: plan,
            candidate: candidate,
            table: table,
            faultInjector: verificationFaultInjector
        ) else {
            throw PropositionTransformationError.synthesisVerificationFailed
        }
        return candidate
    }

    /// `@testable` structural golden seam；public module interface 不公開 pre-rewrite DNF。
    static func synthesisPlan(
        _ table: BooleanFunctionTable
    ) throws -> PropositionExpression {
        guard !table.atoms.isEmpty else {
            throw PropositionTransformationError.zeroArityFunctionUnsupported
        }

        // DNF 與其 fixed NOR expansion 都先以 scalar estimates 完成 preflight。
        let estimate = estimateSynthesisPlan(table)
        try preflightSynthesisEstimate(
            depth: reportableMetric(
                estimate.source.depth,
                maximum: PropositionLogicLimits.maximumOperatorDepth
            ),
            nodeCount: reportableMetric(
                estimate.source.nodeCount,
                maximum: PropositionLogicLimits.maximumSynthesisNodeCount
            )
        )
        try preflightSynthesisEstimate(
            depth: reportableMetric(
                estimate.rewritten.depth,
                maximum: PropositionLogicLimits.maximumOperatorDepth
            ),
            nodeCount: reportableMetric(
                estimate.rewritten.nodeCount,
                maximum: PropositionLogicLimits.maximumSynthesisNodeCount
            )
        )

        return try materializeSynthesisPlan(table)
    }
}

// MARK: - Rewrite plan and estimator

private struct TransformationEstimate: Equatable {
    let depth: Int
    let nodeCount: Int
}

private indirect enum NorPlan {
    case atom(Proposition)
    case nor(NorPlan, NorPlan)
}

private func estimateNorRewrite(
    of source: PropositionExpression
) -> TransformationEstimate {
    struct Frame {
        let expression: PropositionExpression
        let expanded: Bool
    }

    var work = [Frame(expression: source, expanded: false)]
    var estimates: [TransformationEstimate] = []
    estimates.reserveCapacity(source.nodeCount)

    while let frame = work.popLast() {
        if !frame.expanded {
            work.append(Frame(expression: frame.expression, expanded: true))
            for child in frame.expression.children.reversed() {
                work.append(Frame(expression: child, expanded: false))
            }
            continue
        }

        switch frame.expression.kind {
        case .atom:
            estimates.append(.atom)
        case .not:
            let child = popEstimate(&estimates)
            estimates.append(rewriteUnaryNot(child))
        case .and, .or, .implies, .nor:
            let rhs = popEstimate(&estimates)
            let lhs = popEstimate(&estimates)
            estimates.append(rewriteBinary(frame.expression.kind, lhs, rhs))
        }
    }

    guard estimates.count == 1, let result = estimates.first else {
        preconditionFailure("rewrite estimator 沒有產生唯一 root metric")
    }
    return result
}

private func makeNorPlan(from source: PropositionExpression) -> NorPlan {
    switch source.kind {
    case .atom:
        guard let proposition = source.proposition else {
            preconditionFailure("atom node 缺少 proposition")
        }
        return .atom(proposition)
    case .not:
        let child = makeNorPlan(from: source.children[0])
        return .nor(child, child)
    case .and:
        let lhs = makeNorPlan(from: source.children[0])
        let rhs = makeNorPlan(from: source.children[1])
        return .nor(.nor(lhs, lhs), .nor(rhs, rhs))
    case .or:
        let lhs = makeNorPlan(from: source.children[0])
        let rhs = makeNorPlan(from: source.children[1])
        let core = NorPlan.nor(lhs, rhs)
        return .nor(core, core)
    case .implies:
        let lhs = makeNorPlan(from: source.children[0])
        let rhs = makeNorPlan(from: source.children[1])
        let notLHS = NorPlan.nor(lhs, lhs)
        let core = NorPlan.nor(notLHS, rhs)
        return .nor(core, core)
    case .nor:
        return .nor(
            makeNorPlan(from: source.children[0]),
            makeNorPlan(from: source.children[1])
        )
    }
}

private func materializeNorPlan(_ plan: NorPlan) throws -> PropositionExpression {
    switch plan {
    case .atom(let proposition):
        return try .atom(proposition)
    case let .nor(lhs, rhs):
        return try .nor(
            materializeNorPlan(lhs),
            materializeNorPlan(rhs)
        )
    }
}

// MARK: - Independent rewrite verifier

private func verifyRewrite(
    source: PropositionExpression,
    plan: NorPlan,
    output: PropositionExpression,
    expected: TransformationEstimate,
    faultInjector: RewriteVerificationFaultInjector
) -> Bool {
    guard output.isNorOnly,
          output.operatorDepth == expected.depth,
          output.nodeCount == expected.nodeCount,
          rewritePlan(plan, exactlyRepresents: source) else {
        return false
    }

    var nodeIndex = 0
    var work: [(plan: NorPlan, output: PropositionExpression)] = [(plan, output)]
    while let item = work.popLast() {
        let actualTag = faultInjector.nodeTag(
            at: nodeIndex,
            original: transformationNodeTag(item.output.kind)
        )
        nodeIndex += 1

        switch item.plan {
        case .atom(let expectedAtom):
            guard actualTag == 0x00,
                  item.output.kind == .atom,
                  item.output.proposition == expectedAtom,
                  item.output.children.isEmpty else {
                return false
            }
        case let .nor(expectedLHS, expectedRHS):
            let children = item.output.children
            guard actualTag == 0x05,
                  item.output.kind == .nor,
                  children.count == 2 else {
                return false
            }
            work.append((expectedRHS, children[1]))
            work.append((expectedLHS, children[0]))
        }
    }
    return nodeIndex == expected.nodeCount
}

private func rewritePlan(
    _ plan: NorPlan,
    exactlyRepresents source: PropositionExpression
) -> Bool {
    var work: [(source: PropositionExpression, plan: NorPlan)] = [(source, plan)]
    while let item = work.popLast() {
        let children = item.source.children
        switch item.source.kind {
        case .atom:
            guard case .atom(let atom) = item.plan,
                  atom == item.source.proposition else {
                return false
            }
        case .not:
            guard children.count == 1,
                  case let .nor(lhs, rhs) = item.plan,
                  norPlansEqual(lhs, rhs) else {
                return false
            }
            work.append((children[0], lhs))
        case .nor:
            guard children.count == 2,
                  case let .nor(lhs, rhs) = item.plan else {
                return false
            }
            work.append((children[1], rhs))
            work.append((children[0], lhs))
        case .and:
            guard children.count == 2,
                  case let .nor(negatedLHS, negatedRHS) = item.plan,
                  case let .nor(lhsA, lhsB) = negatedLHS,
                  case let .nor(rhsA, rhsB) = negatedRHS,
                  norPlansEqual(lhsA, lhsB),
                  norPlansEqual(rhsA, rhsB) else {
                return false
            }
            work.append((children[1], rhsA))
            work.append((children[0], lhsA))
        case .or:
            guard children.count == 2,
                  case let .nor(coreA, coreB) = item.plan,
                  norPlansEqual(coreA, coreB),
                  case let .nor(lhs, rhs) = coreA else {
                return false
            }
            work.append((children[1], rhs))
            work.append((children[0], lhs))
        case .implies:
            guard children.count == 2,
                  case let .nor(coreA, coreB) = item.plan,
                  norPlansEqual(coreA, coreB),
                  case let .nor(negatedLHS, rhs) = coreA,
                  case let .nor(lhsA, lhsB) = negatedLHS,
                  norPlansEqual(lhsA, lhsB) else {
                return false
            }
            work.append((children[1], rhs))
            work.append((children[0], lhsA))
        }
    }
    return true
}

/// Duplicated rewrite operands are compared by an explicit bounded stack. A successful
/// preflight limits each expanded plan to 4,096 nodes, so no synthesized recursive
/// `Equatable` walk carries the verifier's stack-safety contract.
private func norPlansEqual(_ lhs: NorPlan, _ rhs: NorPlan) -> Bool {
    var work: [(NorPlan, NorPlan)] = [(lhs, rhs)]
    while let pair = work.popLast() {
        switch pair {
        case let (.atom(lhsAtom), .atom(rhsAtom)):
            guard lhsAtom == rhsAtom else { return false }
        case let (.nor(lhsA, lhsB), .nor(rhsA, rhsB)):
            work.append((lhsB, rhsB))
            work.append((lhsA, rhsA))
        case (.atom, .nor), (.nor, .atom):
            return false
        }
    }
    return true
}

private func transformationNodeTag(_ kind: PropositionExpression.Kind) -> UInt8 {
    switch kind {
    case .atom: 0x00
    case .not: 0x01
    case .and: 0x02
    case .or: 0x03
    case .implies: 0x04
    case .nor: 0x05
    }
}

// MARK: - Balanced-DNF synthesis

private struct SynthesisEstimate {
    let source: TransformationEstimate
    let rewritten: TransformationEstimate
}

private func estimateSynthesisPlan(_ table: BooleanFunctionTable) -> SynthesisEstimate {
    let atoms = table.atoms
    let atomEstimate = SynthesisEstimate(source: .atom, rewritten: .atom)

    if table.outputs.allSatisfy({ !$0 }) {
        let contradictions = atoms.map { _ in
            synthesisBinary(
                .and,
                atomEstimate,
                synthesisNot(atomEstimate)
            )
        }
        return balancedEstimate(contradictions, kind: .or)
    }

    if table.outputs.allSatisfy({ $0 }) {
        let tautologies = atoms.map { _ in
            synthesisBinary(
                .or,
                atomEstimate,
                synthesisNot(atomEstimate)
            )
        }
        return balancedEstimate(tautologies, kind: .and)
    }

    var minterms: [SynthesisEstimate] = []
    minterms.reserveCapacity(table.outputs.filter { $0 }.count)
    for (rowIndex, output) in table.outputs.enumerated() where output {
        let literals = atoms.indices.map { atomIndex -> SynthesisEstimate in
            let bitOffset = atoms.count - atomIndex - 1
            let input = ((rowIndex >> bitOffset) & 1) == 1
            return input ? atomEstimate : synthesisNot(atomEstimate)
        }
        minterms.append(balancedEstimate(literals, kind: .and))
    }
    return balancedEstimate(minterms, kind: .or)
}

private func materializeSynthesisPlan(
    _ table: BooleanFunctionTable
) throws -> PropositionExpression {
    let atoms = try table.atoms.map { try PropositionExpression.atom($0) }

    if table.outputs.allSatisfy({ !$0 }) {
        let contradictions = try atoms.map { atom in
            try PropositionExpression.and(atom, .not(atom))
        }
        return try balancedExpression(contradictions, kind: .or)
    }

    if table.outputs.allSatisfy({ $0 }) {
        let tautologies = try atoms.map { atom in
            try PropositionExpression.or(atom, .not(atom))
        }
        return try balancedExpression(tautologies, kind: .and)
    }

    var minterms: [PropositionExpression] = []
    minterms.reserveCapacity(table.outputs.filter { $0 }.count)
    for (rowIndex, output) in table.outputs.enumerated() where output {
        let literals = try atoms.indices.map { atomIndex -> PropositionExpression in
            let bitOffset = atoms.count - atomIndex - 1
            let input = ((rowIndex >> bitOffset) & 1) == 1
            return input ? atoms[atomIndex] : try .not(atoms[atomIndex])
        }
        minterms.append(try balancedExpression(literals, kind: .and))
    }
    return try balancedExpression(minterms, kind: .or)
}

private func balancedEstimate(
    _ elements: [SynthesisEstimate],
    kind: PropositionExpression.Kind
) -> SynthesisEstimate {
    precondition(!elements.isEmpty)
    var level = elements
    while level.count > 1 {
        var next: [SynthesisEstimate] = []
        next.reserveCapacity((level.count + 1) / 2)
        var index = 0
        while index < level.count {
            if index + 1 < level.count {
                next.append(synthesisBinary(kind, level[index], level[index + 1]))
            } else {
                next.append(level[index])
            }
            index += 2
        }
        level = next
    }
    return level[0]
}

private func balancedExpression(
    _ elements: [PropositionExpression],
    kind: PropositionExpression.Kind
) throws -> PropositionExpression {
    precondition(!elements.isEmpty)
    var level = elements
    while level.count > 1 {
        var next: [PropositionExpression] = []
        next.reserveCapacity((level.count + 1) / 2)
        var index = 0
        while index < level.count {
            if index + 1 < level.count {
                switch kind {
                case .and:
                    next.append(try .and(level[index], level[index + 1]))
                case .or:
                    next.append(try .or(level[index], level[index + 1]))
                case .atom, .not, .implies, .nor:
                    preconditionFailure("balanced synthesis fold 只接受 and／or")
                }
            } else {
                next.append(level[index])
            }
            index += 2
        }
        level = next
    }
    return level[0]
}

private func synthesisNot(_ child: SynthesisEstimate) -> SynthesisEstimate {
    SynthesisEstimate(
        source: sourceUnaryNot(child.source),
        rewritten: rewriteUnaryNot(child.rewritten)
    )
}

private func synthesisBinary(
    _ kind: PropositionExpression.Kind,
    _ lhs: SynthesisEstimate,
    _ rhs: SynthesisEstimate
) -> SynthesisEstimate {
    SynthesisEstimate(
        source: sourceBinary(lhs.source, rhs.source),
        rewritten: rewriteBinary(kind, lhs.rewritten, rhs.rewritten)
    )
}

private func verifySynthesis(
    plan: PropositionExpression,
    candidate: PropositionExpression,
    table: BooleanFunctionTable,
    faultInjector: SynthesisVerificationFaultInjector
) throws -> Bool {
    guard candidate.isNorOnly,
          candidate.atoms == table.atoms,
          candidate.nodeCount <= PropositionLogicLimits.maximumSynthesisNodeCount else {
        return false
    }

    // Replay pins deterministic structure／bytes independently of cross-table domains。
    let replay: PropositionExpression
    do {
        replay = try plan.rewrittenUsingNor()
    } catch {
        return false
    }
    guard replay == candidate,
          replay.canonicalBytes == candidate.canonicalBytes else {
        return false
    }

    let resultTable: ClassicalTruthTable
    do {
        resultTable = try candidate.truthTable()
    } catch {
        return false
    }
    guard resultTable.atoms == table.atoms else { return false }

    let observed = resultTable.rows.enumerated().map { rowIndex, row in
        faultInjector.output(at: rowIndex, original: row.output)
    }
    return observed == table.outputs
}

// MARK: - Checked metric arithmetic

private extension TransformationEstimate {
    static let atom = TransformationEstimate(depth: 0, nodeCount: 1)
}

private func sourceUnaryNot(
    _ child: TransformationEstimate
) -> TransformationEstimate {
    TransformationEstimate(
        depth: checkedMetricAdd(child.depth, 1, overflowFallback: Int.max),
        nodeCount: checkedMetricAdd(child.nodeCount, 1, overflowFallback: Int.max)
    )
}

private func sourceBinary(
    _ lhs: TransformationEstimate,
    _ rhs: TransformationEstimate
) -> TransformationEstimate {
    TransformationEstimate(
        depth: checkedMetricAdd(max(lhs.depth, rhs.depth), 1, overflowFallback: Int.max),
        nodeCount: checkedMetricSum(
            [1, lhs.nodeCount, rhs.nodeCount],
            overflowFallback: Int.max
        )
    )
}

private func rewriteUnaryNot(
    _ child: TransformationEstimate
) -> TransformationEstimate {
    TransformationEstimate(
        depth: checkedMetricAdd(child.depth, 1, overflowFallback: Int.max),
        nodeCount: checkedMetricSum(
            [1, checkedMetricMultiply(child.nodeCount, 2, overflowFallback: Int.max)],
            overflowFallback: Int.max
        )
    )
}

private func rewriteBinary(
    _ kind: PropositionExpression.Kind,
    _ lhs: TransformationEstimate,
    _ rhs: TransformationEstimate
) -> TransformationEstimate {
    switch kind {
    case .nor:
        return TransformationEstimate(
            depth: checkedMetricAdd(
                max(lhs.depth, rhs.depth),
                1,
                overflowFallback: Int.max
            ),
            nodeCount: checkedMetricSum(
                [1, lhs.nodeCount, rhs.nodeCount],
                overflowFallback: Int.max
            )
        )
    case .and, .or:
        return TransformationEstimate(
            depth: checkedMetricAdd(
                max(lhs.depth, rhs.depth),
                2,
                overflowFallback: Int.max
            ),
            nodeCount: checkedMetricSum(
                [
                    3,
                    checkedMetricMultiply(lhs.nodeCount, 2, overflowFallback: Int.max),
                    checkedMetricMultiply(rhs.nodeCount, 2, overflowFallback: Int.max),
                ],
                overflowFallback: Int.max
            )
        )
    case .implies:
        return TransformationEstimate(
            depth: checkedMetricAdd(
                max(
                    checkedMetricAdd(lhs.depth, 1, overflowFallback: Int.max),
                    rhs.depth
                ),
                2,
                overflowFallback: Int.max
            ),
            nodeCount: checkedMetricSum(
                [
                    5,
                    checkedMetricMultiply(lhs.nodeCount, 4, overflowFallback: Int.max),
                    checkedMetricMultiply(rhs.nodeCount, 2, overflowFallback: Int.max),
                ],
                overflowFallback: Int.max
            )
        )
    case .atom, .not:
        preconditionFailure("binary rewrite estimator 收到非 binary kind")
    }
}

private func popEstimate(
    _ estimates: inout [TransformationEstimate]
) -> TransformationEstimate {
    guard let estimate = estimates.popLast() else {
        preconditionFailure("postorder estimator 缺少 child metric")
    }
    return estimate
}

private func checkedMetricAdd(
    _ lhs: Int,
    _ rhs: Int,
    overflowFallback: Int
) -> Int {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? overflowFallback : value
}

private func checkedMetricMultiply(
    _ lhs: Int,
    _ rhs: Int,
    overflowFallback: Int
) -> Int {
    let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    return overflow ? overflowFallback : value
}

private func checkedMetricSum(
    _ values: [Int],
    overflowFallback: Int
) -> Int {
    var total = 0
    for value in values {
        let (next, overflow) = total.addingReportingOverflow(value)
        if overflow { return overflowFallback }
        total = next
    }
    return total
}

/// 精確計算可安全表示時保留完整 `minimumRequired`（例如 4,103）；只有
/// machine-`Int` overflow sentinel 才依 contract 收斂為固定上限加一。
private func reportableMetric(_ value: Int, maximum: Int) -> Int {
    value == Int.max ? maximum + 1 : value
}
