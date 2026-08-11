import Foundation
import AkashicCore

/// Classical 二值語意的具型別失敗。
///
/// Associated values 是完整 machine payload；人類可見 rendering 另行限制筆數、
/// 消毒 caller-controlled references，且截在固定 scalar budget 內。
public enum ClassicalSemanticsError:
    Error,
    Equatable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case valuationAtomLimitExceeded(actual: Int, maximum: Int)
    case duplicateValuationAtom(Proposition)
    case incompleteValuation(missing: [Proposition])
    case rowLimitExceeded(atomCount: Int, maximumRows: Int)
    case duplicateFunctionAtom(Proposition)
    case outputCountMismatch(expected: Int, actual: Int)

    public var errorDescription: String? { description }

    public var description: String {
        let message: String
        switch self {
        case let .valuationAtomLimitExceeded(actual, maximum):
            message = "古典賦值含有 \(actual) 個原子，超過固定上限 \(maximum)"
        case .duplicateValuationAtom(let atom):
            message = "古典賦值重複指定同一原子：\(classicalAtomDisplay(atom))"
        case .incompleteValuation(let missing):
            message = "古典賦值不完整，缺少原子：\(classicalAtomListDisplay(missing))"
        case let .rowLimitExceeded(atomCount, maximumRows):
            message = "\(atomCount) 個原子的完整真值表超過固定列數上限 \(maximumRows)"
        case .duplicateFunctionAtom(let atom):
            message = "有限 Boolean function 重複指定同一原子：\(classicalAtomDisplay(atom))"
        case let .outputCountMismatch(expected, actual):
            message = "Boolean function output 數量不符：預期 \(expected)，實際 \(actual)"
        }
        return boundedClassicalRendering(message)
    }

    public var debugDescription: String { description }
}

/// 對一組已驗證原子的完整、store-independent Bool assignment。
///
/// Public initializer 刻意只接受 entry list。它在任何 hashing 前先檢查 count、驗證
/// atom，再以 bounded comparison 排除 duplicates，最後才建立 library-owned index。
public struct ClassicalValuation: Equatable {
    private struct Entry: Equatable {
        let atom: Proposition
        let value: Bool
        let canonicalBytes: Data
    }

    private let entries: [Entry]
    private let index: [Proposition: Bool]

    public init(assignments: [(atom: Proposition, value: Bool)]) throws {
        guard assignments.count <= PropositionLogicLimits.maximumDistinctAtomCount else {
            throw ClassicalSemanticsError.valuationAtomLimitExceeded(
                actual: assignments.count,
                maximum: PropositionLogicLimits.maximumDistinctAtomCount
            )
        }

        var validated: [Entry] = []
        validated.reserveCapacity(assignments.count)
        for assignment in assignments {
            try assignment.atom.validate()
            let bytes = try assignment.atom.canonicalBytesV1()
            validated.append(Entry(
                atom: assignment.atom,
                value: assignment.value,
                canonicalBytes: bytes
            ))
        }

        for index in validated.indices {
            if validated[..<index].contains(where: { $0.atom == validated[index].atom }) {
                throw ClassicalSemanticsError.duplicateValuationAtom(validated[index].atom)
            }
        }

        validated.sort { canonicalBytesLess($0.canonicalBytes, $1.canonicalBytes) }
        self.entries = validated
        self.index = Dictionary(
            uniqueKeysWithValues: validated.map { ($0.atom, $0.value) }
        )
    }

    fileprivate init(validatedCanonicalAssignments: [(atom: Proposition, value: Bool)]) {
        let validated = validatedCanonicalAssignments.map {
            Entry(atom: $0.atom, value: $0.value, canonicalBytes: Data())
        }
        self.entries = validated
        self.index = Dictionary(
            uniqueKeysWithValues: validated.map { ($0.atom, $0.value) }
        )
    }

    fileprivate func value(of atom: Proposition) -> Bool? {
        index[atom]
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.entries.count == rhs.entries.count else { return false }
        return zip(lhs.entries, rhs.entries).allSatisfy { pair in
            pair.0.atom == pair.1.atom && pair.0.value == pair.1.value
        }
    }
}

/// 一張完整、canonical-order 的 classical truth table。
public struct ClassicalTruthTable: Equatable {
    public struct Row: Equatable {
        public let inputs: [Bool]
        public let output: Bool

        fileprivate init(inputs: [Bool], output: Bool) {
            self.inputs = inputs
            self.output = output
        }
    }

    public let atoms: [Proposition]
    public let rows: [Row]
    public let canonicalBytes: Data

    fileprivate init(atoms: [Proposition], rows: [Row], canonicalBytes: Data) {
        self.atoms = atoms
        self.rows = rows
        self.canonicalBytes = canonicalBytes
    }
}

/// Caller-supplied finite Boolean function，stored atoms／outputs 一律 canonicalized。
public struct BooleanFunctionTable: Equatable {
    public let atoms: [Proposition]
    public let outputs: [Bool]
    public let canonicalBytes: Data

    public init(
        atomsInInputBitOrder atoms: [Proposition],
        outputsInInputBitRowOrder outputs: [Bool]
    ) throws {
        try self.init(
            atomsInInputBitOrder: atoms,
            outputsInInputBitRowOrder: outputs,
            shift: productionCheckedPowerOfTwoShift,
            workspaceProbe: .noOp
        )
    }

    init(
        atomsInInputBitOrder callerAtoms: [Proposition],
        outputsInInputBitRowOrder callerOutputs: [Bool],
        shift: (_ exponent: Int) -> Int?,
        workspaceProbe: EnumerationWorkspaceProbe
    ) throws {
        let maximumRows = PropositionLogicLimits.maximumClassicalRows
        let maximumVariables = maximumPowerOfTwoVariableCount(maximum: maximumRows)

        // 這是本 initializer 的第一個 element-independent operation。
        guard callerAtoms.count <= maximumVariables else {
            throw ClassicalSemanticsError.rowLimitExceeded(
                atomCount: callerAtoms.count,
                maximumRows: maximumRows
            )
        }

        var validated: [CanonicalAtom] = []
        validated.reserveCapacity(callerAtoms.count)
        for atom in callerAtoms {
            try atom.validate()
            let bytes = try atom.canonicalBytesV1()
            validated.append(CanonicalAtom(atom: atom, bytes: bytes))
        }

        for index in validated.indices {
            if validated[..<index].contains(where: { $0.atom == validated[index].atom }) {
                throw ClassicalSemanticsError.duplicateFunctionAtom(validated[index].atom)
            }
        }

        guard let rowCount = checkedPowerOfTwoCount(
            variableCount: callerAtoms.count,
            maximum: maximumRows,
            shift: shift
        ) else {
            throw ClassicalSemanticsError.rowLimitExceeded(
                atomCount: callerAtoms.count,
                maximumRows: maximumRows
            )
        }
        guard callerOutputs.count == rowCount else {
            throw ClassicalSemanticsError.outputCountMismatch(
                expected: rowCount,
                actual: callerOutputs.count
            )
        }

        let canonical = validated.sorted {
            canonicalBytesLess($0.bytes, $1.bytes)
        }
        let canonicalAtoms = canonical.map(\.atom)
        workspaceProbe.recordAllocation(elementCount: rowCount)
        var canonicalOutputs: [Bool] = []
        canonicalOutputs.reserveCapacity(rowCount)

        for canonicalRowIndex in 0..<rowCount {
            var callerRowIndex = 0
            for callerAtom in callerAtoms {
                guard let canonicalIndex = canonicalAtoms.firstIndex(of: callerAtom) else {
                    preconditionFailure("validated caller atom 不可能從 canonical atom array 消失")
                }
                let bitOffset = canonicalAtoms.count - canonicalIndex - 1
                let bit = (canonicalRowIndex >> bitOffset) & 1
                callerRowIndex = (callerRowIndex << 1) | bit
            }
            canonicalOutputs.append(callerOutputs[callerRowIndex])
        }

        self.atoms = canonicalAtoms
        self.outputs = canonicalOutputs
        self.canonicalBytes = canonicalTableBytes(
            domain: "akashic-boolean-function-table-v1",
            atoms: canonical,
            outputs: canonicalOutputs
        )
    }
}

/// Per-call allocation observation；production path 固定使用 `.noOp`，沒有 global state。
struct EnumerationWorkspaceProbe {
    private let onAllocate: (_ elementCount: Int) -> Void

    init(onAllocate: @escaping (_ elementCount: Int) -> Void) {
        self.onAllocate = onAllocate
    }

    static let noOp = EnumerationWorkspaceProbe(onAllocate: { _ in })

    func recordAllocation(elementCount: Int) {
        onAllocate(elementCount)
    }
}

/// 所有 `2^n` cardinality path 共用的 guarded helper。
///
/// 它先用 bounded doubling 證明結果不超過 maximum，通過後才呼叫注入的 shift。
/// 因此 13／63-variable rejection 不可能執行 shift closure。
func checkedPowerOfTwoCount(
    variableCount: Int,
    maximum: Int,
    shift: (_ exponent: Int) -> Int?
) -> Int? {
    guard variableCount >= 0, maximum >= 1 else { return nil }

    var expected = 1
    if variableCount > 0 {
        for _ in 0..<variableCount {
            guard expected <= maximum / 2 else { return nil }
            expected *= 2
        }
    }

    guard let shifted = shift(variableCount), shifted == expected else { return nil }
    return shifted
}

extension PropositionExpression {
    /// 以完整 classical assignment compositional evaluation；不接觸 store 或 epistemic state。
    public func classicalValue(under valuation: ClassicalValuation) throws -> Bool {
        let missing = atoms.filter { valuation.value(of: $0) == nil }
        guard missing.isEmpty else {
            throw ClassicalSemanticsError.incompleteValuation(missing: missing)
        }
        return classicalValueWithCompleteValuation(valuation)
    }

    /// 依 canonical atom／row order 建立完整 truth table。
    public func truthTable() throws -> ClassicalTruthTable {
        try truthTable(
            shift: productionCheckedPowerOfTwoShift,
            workspaceProbe: .noOp
        )
    }

    func truthTable(
        shift: (_ exponent: Int) -> Int?,
        workspaceProbe: EnumerationWorkspaceProbe
    ) throws -> ClassicalTruthTable {
        let canonicalAtoms = atoms
        let maximumRows = PropositionLogicLimits.maximumClassicalRows
        guard let rowCount = checkedPowerOfTwoCount(
            variableCount: canonicalAtoms.count,
            maximum: maximumRows,
            shift: shift
        ) else {
            throw ClassicalSemanticsError.rowLimitExceeded(
                atomCount: canonicalAtoms.count,
                maximumRows: maximumRows
            )
        }

        workspaceProbe.recordAllocation(elementCount: rowCount)
        var rows: [ClassicalTruthTable.Row] = []
        rows.reserveCapacity(rowCount)
        for rowIndex in 0..<rowCount {
            let inputs = classicalInputs(
                rowIndex: rowIndex,
                atomCount: canonicalAtoms.count
            )
            let valuation = ClassicalValuation(
                validatedCanonicalAssignments: zip(canonicalAtoms, inputs).map {
                    (atom: $0.0, value: $0.1)
                }
            )
            rows.append(ClassicalTruthTable.Row(
                inputs: inputs,
                output: classicalValueWithCompleteValuation(valuation)
            ))
        }

        let canonical = try canonicalAtoms.map {
            CanonicalAtom(atom: $0, bytes: try $0.canonicalBytesV1())
        }
        return ClassicalTruthTable(
            atoms: canonicalAtoms,
            rows: rows,
            canonicalBytes: canonicalTableBytes(
                domain: "akashic-classical-truth-table-v1",
                atoms: canonical,
                outputs: rows.map(\.output)
            )
        )
    }

    /// 以兩式 canonical atom union 的每一列比較 truth conditions。
    public func isClassicallyEquivalent(to other: Self) throws -> Bool {
        let union = try canonicalAtomUnion(atoms, other.atoms)
        let maximumRows = PropositionLogicLimits.maximumClassicalRows
        guard let rowCount = checkedPowerOfTwoCount(
            variableCount: union.count,
            maximum: maximumRows,
            shift: productionCheckedPowerOfTwoShift
        ) else {
            throw ClassicalSemanticsError.rowLimitExceeded(
                atomCount: union.count,
                maximumRows: maximumRows
            )
        }

        for rowIndex in 0..<rowCount {
            let inputs = classicalInputs(rowIndex: rowIndex, atomCount: union.count)
            let valuation = ClassicalValuation(
                validatedCanonicalAssignments: zip(union, inputs).map {
                    (atom: $0.0, value: $0.1)
                }
            )
            if classicalValueWithCompleteValuation(valuation)
                != other.classicalValueWithCompleteValuation(valuation)
            {
                return false
            }
        }
        return true
    }

    public func isClassicalTautology() throws -> Bool {
        try truthTable().rows.allSatisfy(\.output)
    }

    public func isClassicalContradiction() throws -> Bool {
        try truthTable().rows.allSatisfy { !$0.output }
    }

    private func classicalValueWithCompleteValuation(
        _ valuation: ClassicalValuation
    ) -> Bool {
        struct Frame {
            let expression: PropositionExpression
            let expanded: Bool
        }

        var stack = [Frame(expression: self, expanded: false)]
        var values: [Bool] = []
        values.reserveCapacity(nodeCount)

        while let frame = stack.popLast() {
            if !frame.expanded {
                stack.append(Frame(expression: frame.expression, expanded: true))
                for child in frame.expression.children.reversed() {
                    stack.append(Frame(expression: child, expanded: false))
                }
                continue
            }

            switch frame.expression.kind {
            case .atom:
                guard let atom = frame.expression.proposition,
                      let value = valuation.value(of: atom) else {
                    preconditionFailure("opaque expression 與 complete valuation invariant 失效")
                }
                values.append(value)
            case .not:
                guard let operand = values.popLast() else {
                    preconditionFailure("not node 缺少 operand value")
                }
                values.append(!operand)
            case .and, .or, .implies, .nor:
                guard let rhs = values.popLast(), let lhs = values.popLast() else {
                    preconditionFailure("binary node 缺少 child values")
                }
                switch frame.expression.kind {
                case .and:
                    values.append(lhs && rhs)
                case .or:
                    values.append(lhs || rhs)
                case .implies:
                    values.append(!lhs || rhs)
                case .nor:
                    values.append(!(lhs || rhs))
                case .atom, .not:
                    preconditionFailure("unreachable kind")
                }
            }
        }

        guard values.count == 1, let result = values.first else {
            preconditionFailure("classical evaluator 沒有產生唯一 root value")
        }
        return result
    }
}

// MARK: - Canonical helpers

private struct CanonicalAtom {
    let atom: Proposition
    let bytes: Data
}

private func canonicalAtomUnion(
    _ lhs: [Proposition],
    _ rhs: [Proposition]
) throws -> [Proposition] {
    var union: [CanonicalAtom] = []
    union.reserveCapacity(lhs.count + rhs.count)

    for atom in lhs + rhs {
        if union.contains(where: { $0.atom == atom }) { continue }
        union.append(CanonicalAtom(atom: atom, bytes: try atom.canonicalBytesV1()))
    }
    union.sort { canonicalBytesLess($0.bytes, $1.bytes) }
    return union.map(\.atom)
}

private func canonicalBytesLess(_ lhs: Data, _ rhs: Data) -> Bool {
    lhs.lexicographicallyPrecedes(rhs)
}

private func canonicalTableBytes(
    domain: String,
    atoms: [CanonicalAtom],
    outputs: [Bool]
) -> Data {
    var data = Data()
    data.appendLengthFramed(Data(domain.utf8))
    data.appendUInt64(atoms.count)
    for atom in atoms {
        data.appendLengthFramed(atom.bytes)
    }
    data.appendUInt64(outputs.count)
    for (index, output) in outputs.enumerated() {
        data.appendUInt64(index)
        data.append(output ? 0x01 : 0x00)
    }
    return data
}

private func classicalInputs(rowIndex: Int, atomCount: Int) -> [Bool] {
    (0..<atomCount).map { atomIndex in
        let bitOffset = atomCount - atomIndex - 1
        return ((rowIndex >> bitOffset) & 1) == 1
    }
}

private func maximumPowerOfTwoVariableCount(maximum: Int) -> Int {
    guard maximum >= 1 else { return -1 }
    var variables = 0
    var cardinality = 1
    while cardinality <= maximum / 2 {
        cardinality *= 2
        variables += 1
    }
    return variables
}

func productionCheckedPowerOfTwoShift(_ exponent: Int) -> Int? {
    guard exponent >= 0, exponent < Int.bitWidth - 1 else { return nil }
    return 1 << exponent
}

private extension Data {
    mutating func appendUInt64(_ value: Int) {
        precondition(value >= 0)
        var encoded = UInt64(value).bigEndian
        Swift.withUnsafeBytes(of: &encoded) {
            append(contentsOf: $0)
        }
    }

    mutating func appendLengthFramed(_ bytes: Data) {
        appendUInt64(bytes.count)
        append(bytes)
    }
}

// MARK: - Bounded diagnostics

private func classicalAtomDisplay(_ atom: Proposition) -> String {
    switch atom {
    case let .authored(person, work):
        return "authored(\(classicalReferenceDisplay(person)), \(classicalReferenceDisplay(work)))" // display-safe-exempt: helper 已逐一以 displaySafe 限制 reference
    case let .affiliated(person, organization):
        return "affiliated(\(classicalReferenceDisplay(person)), \(classicalReferenceDisplay(organization)))" // display-safe-exempt: helper 已逐一以 displaySafe 限制 reference
    }
}

private func classicalReferenceDisplay(_ reference: EntityRef) -> String {
    switch reference {
    case .key(let value):
        return "key(\(displaySafe(value, max: 120)))"
    case .literal(let value):
        return "literal(\(displaySafe(value, max: 120)))"
    }
}

private func classicalAtomListDisplay(_ atoms: [Proposition]) -> String {
    let displayed = atoms.prefix(5).map(classicalAtomDisplay).joined(separator: "、")
    guard atoms.count > 5 else { return displayed }
    return displayed + "，另有 \(atoms.count - 5) 個"
}

private func boundedClassicalRendering(_ value: String) -> String {
    let sanitized = displaySafe(value, max: 2_048)
    let scalars = sanitized.unicodeScalars
    guard scalars.count > 2_048 else { return sanitized }
    var bounded = String.UnicodeScalarView()
    bounded.append(contentsOf: scalars.prefix(2_048))
    return String(bounded)
}
