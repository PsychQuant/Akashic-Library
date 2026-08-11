import Foundation
import XCTest
import AkashicCore
@testable import AkashicProposition

/// #214 的 bounded NOR rewrite／finite-function synthesis 承重契約。
///
/// 測試同時釘住 truth conditions 與 exact syntax；只比等價或只比 `isNorOnly`
/// 都不足以保護 v1 deterministic rewrite／balanced-DNF contract。
final class TruthFunctionSynthesisTests: XCTestCase {
    private var p: Proposition { atom("p") }
    private var q: Proposition { atom("q") }
    private var r: Proposition { atom("r") }

    private func atom(_ label: String) -> Proposition {
        .authored(
            person: .key("person-\(label)"),
            work: .key("work-\(label)")
        )
    }

    private func numberedAtoms(_ count: Int) -> [Proposition] {
        (0..<count).map { atom(String(format: "%02d", $0)) }
    }

    private func expression(_ proposition: Proposition) throws -> PropositionExpression {
        try PropositionExpression.atom(proposition)
    }

    private func balancedNor(_ propositions: [Proposition]) throws -> PropositionExpression {
        precondition(!propositions.isEmpty)
        var level = try propositions.map { try expression($0) }

        while level.count > 1 {
            var next: [PropositionExpression] = []
            next.reserveCapacity((level.count + 1) / 2)
            var index = 0
            while index < level.count {
                if index + 1 < level.count {
                    next.append(try PropositionExpression.nor(level[index], level[index + 1]))
                } else {
                    next.append(level[index])
                }
                index += 2
            }
            level = next
        }

        return level[0]
    }

    private func outputs(atomCount: Int, trueRows: Set<Int>) -> [Bool] {
        (0..<(1 << atomCount)).map(trueRows.contains)
    }

    private func functionTable(
        atoms: [Proposition],
        trueRows: Set<Int>
    ) throws -> BooleanFunctionTable {
        try BooleanFunctionTable(
            atomsInInputBitOrder: atoms,
            outputsInInputBitRowOrder: outputs(
                atomCount: atoms.count,
                trueRows: trueRows
            )
        )
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func rewriteFixtures() throws -> [(
        name: String,
        source: PropositionExpression,
        expected: PropositionExpression
    )] {
        let pExpression = try expression(p)
        let qExpression = try expression(q)

        let notP = try PropositionExpression.not(pExpression)
        let expectedNot = try PropositionExpression.nor(pExpression, pExpression)

        let andPQ = try PropositionExpression.and(pExpression, qExpression)
        let expectedAnd = try PropositionExpression.nor(
            PropositionExpression.nor(pExpression, pExpression),
            PropositionExpression.nor(qExpression, qExpression)
        )

        let orPQ = try PropositionExpression.or(pExpression, qExpression)
        let pNorQ = try PropositionExpression.nor(pExpression, qExpression)
        let expectedOr = try PropositionExpression.nor(pNorQ, pNorQ)

        let impliesPQ = try PropositionExpression.implies(pExpression, qExpression)
        let notPUsingNor = try PropositionExpression.nor(pExpression, pExpression)
        let implicationCore = try PropositionExpression.nor(notPUsingNor, qExpression)
        let expectedImplies = try PropositionExpression.nor(
            implicationCore,
            implicationCore
        )

        let norPQ = try PropositionExpression.nor(pExpression, qExpression)
        let expectedNor = try PropositionExpression.nor(pExpression, qExpression)

        return [
            ("not", notP, expectedNot),
            ("and", andPQ, expectedAnd),
            ("or", orPQ, expectedOr),
            ("implies", impliesPQ, expectedImplies),
            ("nor", norPQ, expectedNor),
        ]
    }

    // Production mutation caught: a rewrite retains a non-NOR node or misstates one identity.
    func testNorRewritePreservesEveryOperatorAndUsesOnlyNor() throws {
        for fixture in try rewriteFixtures() {
            let rewritten = try fixture.source.rewrittenUsingNor()
            XCTAssertTrue(rewritten.isNorOnly, fixture.name)
            XCTAssertTrue(
                try fixture.source.isClassicallyEquivalent(to: rewritten),
                fixture.name
            )
            XCTAssertEqual(
                try fixture.source.truthTable().rows.map(\.output),
                try rewritten.truthTable().rows.map(\.output),
                fixture.name
            )
        }
    }

    // Production mutation caught: an equivalent but different NOR identity, child swap, or shared child.
    func testRewriteStructuralGoldensPinEveryOperator() throws {
        for fixture in try rewriteFixtures() {
            let rewritten = try fixture.source.rewrittenUsingNor()
            XCTAssertEqual(rewritten, fixture.expected, fixture.name)
            XCTAssertEqual(
                rewritten.canonicalBytes,
                fixture.expected.canonicalBytes,
                fixture.name
            )
            XCTAssertEqual(
                try fixture.source.rewrittenUsingNor(),
                rewritten,
                "重播不得依 iteration 或 process state 改變結構"
            )
        }

        let canonicalP = Proposition.authored(person: .key("p"), work: .key("w"))
        let rewrittenNot = try PropositionExpression.not(expression(canonicalP))
            .rewrittenUsingNor()
        XCTAssertEqual(
            hex(rewrittenNot.canonicalBytes),
            "0000000000000021616b61736869632d70726f706f736974696f6e2d65787072657373696f6e2d763100000000000000010000000000000038000000000000001b616b61736869632d70726f706f736974696f6e2d61746f6d2d7631000000000000000000017000000000000000000177000000000000000305000000000000000000000000000000000000"
        )
    }

    /// Rewrite verifier 不得以 truth-table enumeration 自我驗證，否則第 13 個 atom
    /// 就會誤撞 classical row limit，63-atom 合法 expression 更不可能 rewrite。
    func testRewriteStructuralVerifierSupportsEveryAtomCountFromThirteenThroughSixtyThree() throws {
        for count in 13...63 {
            let source = try balancedNor(numberedAtoms(count))
            let rewritten = try source.rewrittenUsingNor()
            XCTAssertEqual(rewritten, source, "\(count) atoms")
            XCTAssertEqual(rewritten.canonicalBytes, source.canonicalBytes, "\(count) atoms")
            XCTAssertTrue(rewritten.isNorOnly, "\(count) atoms")
            XCTAssertEqual(rewritten.atoms.count, count)
        }
    }

    // Production mutation caught: rewrite verifier or its per-call fault input is bypassed.
    func testRewriteSelfCheckRejectsCorruptedPlan() throws {
        let source = try PropositionExpression.implies(expression(p), expression(q))
        let fault = RewriteVerificationFaultInjector(mutateNodeTag: { index, tag in
            index == 0 ? tag ^ 0x7f : tag
        })

        XCTAssertThrowsError(
            try source.rewrittenUsingNor(verificationFaultInjector: fault)
        ) { error in
            XCTAssertEqual(
                error as? PropositionTransformationError,
                .rewriteVerificationFailed
            )
        }
        XCTAssertNoThrow(try source.rewrittenUsingNor())
    }

    // Production mutation caught: valid zero-arity representation is refused or synthesis invents constants.
    func testZeroArityFunctionTableIsRepresentableButSynthesisRejectsIt() throws {
        for output in [false, true] {
            let table = try BooleanFunctionTable(
                atomsInInputBitOrder: [],
                outputsInInputBitRowOrder: [output]
            )
            XCTAssertEqual(table.atoms, [])
            XCTAssertEqual(table.outputs, [output])

            XCTAssertThrowsError(
                try PropositionExpression.synthesizeUsingNor(table)
            ) { error in
                XCTAssertEqual(
                    error as? PropositionTransformationError,
                    .zeroArityFunctionUnsupported
                )
            }
        }
    }

    /// 三原子 non-symmetric permutation 同時釘住 caller bit order 與 synthesis 讀到的
    /// canonical vector；只排序 atoms 而未同步排 outputs 會在這裡失敗。
    func testCallerBitOrderPermutationFeedsSynthesis() throws {
        let a = atom("a")
        let b = atom("b")
        let c = atom("c")
        let table = try BooleanFunctionTable(
            atomsInInputBitOrder: [b, c, a],
            outputsInInputBitRowOrder: [
                false, true, false, true, false, true, false, true,
            ]
        )

        XCTAssertEqual(table.atoms, [a, b, c])
        XCTAssertEqual(
            table.outputs,
            [false, false, false, false, true, true, true, true]
        )

        let synthesized = try PropositionExpression.synthesizeUsingNor(table)
        XCTAssertEqual(synthesized.atoms, [a, b, c])
        XCTAssertEqual(try synthesized.truthTable().rows.map(\.output), table.outputs)
    }

    // Production mutation caught: a mask is skipped, row bits are reversed, or constants are special-cased wrong.
    func testAllSixteenBinaryBooleanFunctionsSynthesizeToNor() throws {
        for mask in 0..<16 {
            let requested = (0..<4).map { row in
                mask & (1 << (3 - row)) != 0
            }
            let table = try BooleanFunctionTable(
                atomsInInputBitOrder: [p, q],
                outputsInInputBitRowOrder: requested
            )
            let first = try PropositionExpression.synthesizeUsingNor(table)
            let second = try PropositionExpression.synthesizeUsingNor(table)

            XCTAssertTrue(first.isNorOnly, "mask \(mask)")
            XCTAssertEqual(first.atoms, [p, q], "mask \(mask)")
            XCTAssertEqual(
                try first.truthTable().rows.map(\.output),
                requested,
                "mask \(mask)"
            )
            XCTAssertEqual(first, second, "mask \(mask)")
            XCTAssertEqual(first.canonicalBytes, second.canonicalBytes, "mask \(mask)")
        }
    }

    // Production mutation caught: fold association, row order, literal polarity, or constant plan changes.
    func testSynthesisStructuralGoldensPinMintermMultirowAndConstants() throws {
        let pExpression = try expression(p)
        let qExpression = try expression(q)
        let rExpression = try expression(r)
        let notP = try PropositionExpression.not(pExpression)
        let notQ = try PropositionExpression.not(qExpression)
        let notR = try PropositionExpression.not(rExpression)

        let singleMinterm = try PropositionExpression.and(
            PropositionExpression.and(pExpression, qExpression),
            rExpression
        )

        let or0111 = try PropositionExpression.or(
            PropositionExpression.or(
                PropositionExpression.and(notP, qExpression),
                PropositionExpression.and(pExpression, notQ)
            ),
            PropositionExpression.and(pExpression, qExpression)
        )

        let rowOne = try PropositionExpression.and(
            PropositionExpression.and(notP, notQ),
            rExpression
        )
        let rowThree = try PropositionExpression.and(
            PropositionExpression.and(notP, qExpression),
            rExpression
        )
        let rowSix = try PropositionExpression.and(
            PropositionExpression.and(pExpression, qExpression),
            notR
        )
        let nonSymmetricMultirow = try PropositionExpression.or(
            PropositionExpression.or(rowOne, rowThree),
            rowSix
        )

        let constantFalse = try PropositionExpression.or(
            PropositionExpression.and(pExpression, notP),
            PropositionExpression.and(qExpression, notQ)
        )
        let constantTrue = try PropositionExpression.and(
            PropositionExpression.or(pExpression, notP),
            PropositionExpression.or(qExpression, notQ)
        )

        let fixtures: [(
            name: String,
            table: BooleanFunctionTable,
            expectedPlan: PropositionExpression
        )] = [
            ("single row 7", try functionTable(atoms: [p, q, r], trueRows: [7]), singleMinterm),
            ("0111", try functionTable(atoms: [p, q], trueRows: [1, 2, 3]), or0111),
            (
                "rows 1,3,6",
                try functionTable(atoms: [p, q, r], trueRows: [1, 3, 6]),
                nonSymmetricMultirow
            ),
            ("constant false", try functionTable(atoms: [p, q], trueRows: []), constantFalse),
            ("constant true", try functionTable(atoms: [p, q], trueRows: [0, 1, 2, 3]), constantTrue),
        ]

        for fixture in fixtures {
            let actualPlan = try PropositionExpression.synthesisPlan(fixture.table)
            XCTAssertEqual(actualPlan, fixture.expectedPlan, fixture.name)
            XCTAssertEqual(
                actualPlan.canonicalBytes,
                fixture.expectedPlan.canonicalBytes,
                fixture.name
            )

            let expectedFinal = try fixture.expectedPlan.rewrittenUsingNor()
            let actualFinal = try PropositionExpression.synthesizeUsingNor(fixture.table)
            XCTAssertEqual(actualFinal, expectedFinal, fixture.name)
            XCTAssertEqual(
                actualFinal.canonicalBytes,
                expectedFinal.canonicalBytes,
                fixture.name
            )
        }
    }

    // Production mutation caught: rewrite/synthesis node guards are removed or use an off-by-one comparison.
    func testRewriteAndSynthesisRespectFixedExpansionBudget() throws {
        var rewriteBoundary = try expression(p)
        for _ in 0..<11 {
            rewriteBoundary = try PropositionExpression.not(rewriteBoundary)
        }
        let acceptedRewrite = try rewriteBoundary.rewrittenUsingNor()
        XCTAssertEqual(acceptedRewrite.nodeCount, 4_095)

        let rejectedRewrite = try PropositionExpression.nor(
            rewriteBoundary,
            expression(q)
        )
        XCTAssertThrowsError(try rejectedRewrite.rewrittenUsingNor()) { error in
            XCTAssertEqual(
                error as? PropositionTransformationError,
                .rewriteNodeLimitExceeded(minimumRequired: 4_097, maximum: 4_096)
            )
        }

        let fiveAtoms = numberedAtoms(5)
        let acceptedTable = try functionTable(
            atoms: fiveAtoms,
            trueRows: [3, 6, 7, 11, 13, 15]
        )
        let acceptedSynthesis = try PropositionExpression.synthesizeUsingNor(acceptedTable)
        XCTAssertEqual(acceptedSynthesis.nodeCount, 4_095)

        let rejectedTable = try functionTable(
            atoms: fiveAtoms,
            trueRows: [1, 2, 3, 4, 7]
        )
        XCTAssertThrowsError(
            try PropositionExpression.synthesizeUsingNor(rejectedTable)
        ) { error in
            XCTAssertEqual(
                error as? PropositionTransformationError,
                .synthesisNodeLimitExceeded(minimumRequired: 4_103, maximum: 4_096)
            )
        }
    }

    // Production mutation caught: rewrite depth preflight is removed or happens after materialization.
    func testRewriteEstimatorRetainsDepthPreflight() throws {
        XCTAssertNoThrow(try preflightRewriteEstimate(depth: 64, nodeCount: 4_096))
        XCTAssertThrowsError(
            try preflightRewriteEstimate(depth: 65, nodeCount: 1)
        ) { error in
            XCTAssertEqual(
                error as? PropositionTransformationError,
                .rewriteDepthLimitExceeded(minimumRequired: 65, maximum: 64)
            )
        }
    }

    // Production mutation caught: defensive synthesis depth preflight is removed or deferred.
    func testSynthesisEstimatorRetainsDefensiveDepthPreflight() throws {
        XCTAssertNoThrow(try preflightSynthesisEstimate(depth: 64, nodeCount: 4_096))
        XCTAssertThrowsError(
            try preflightSynthesisEstimate(depth: 65, nodeCount: 1)
        ) { error in
            XCTAssertEqual(
                error as? PropositionTransformationError,
                .synthesisDepthLimitExceeded(minimumRequired: 65, maximum: 64)
            )
        }
    }

    // Production mutation caught: synthesis verifier or its per-call output fault is bypassed.
    func testSynthesisSelfCheckRejectsMismatchedCandidate() throws {
        let table = try functionTable(atoms: [p, q], trueRows: [3])
        let fault = SynthesisVerificationFaultInjector(mutateOutput: { row, output in
            row == 0 ? !output : output
        })

        XCTAssertThrowsError(
            try PropositionExpression.synthesizeUsingNor(
                table,
                verificationFaultInjector: fault
            )
        ) { error in
            XCTAssertEqual(
                error as? PropositionTransformationError,
                .synthesisVerificationFailed
            )
        }
        XCTAssertNoThrow(try PropositionExpression.synthesizeUsingNor(table))
    }

    // Production mutation caught: synthesis or table serialization depends on unstable iteration.
    func testSynthesisAndTruthTableCanonicalBytesReplayExactly() throws {
        let firstTable = try functionTable(atoms: [p, q, r], trueRows: [1, 3, 6])
        let secondTable = try functionTable(atoms: [p, q, r], trueRows: [1, 3, 6])
        XCTAssertEqual(firstTable.canonicalBytes, secondTable.canonicalBytes)

        let first = try PropositionExpression.synthesizeUsingNor(firstTable)
        let second = try PropositionExpression.synthesizeUsingNor(secondTable)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.canonicalBytes, second.canonicalBytes)

        let firstTruthTable = try first.truthTable()
        let secondTruthTable = try second.truthTable()
        XCTAssertEqual(firstTruthTable, secondTruthTable)
        XCTAssertEqual(firstTruthTable.canonicalBytes, secondTruthTable.canonicalBytes)
        XCTAssertEqual(firstTruthTable.rows.map(\.output), firstTable.outputs)
    }
}
