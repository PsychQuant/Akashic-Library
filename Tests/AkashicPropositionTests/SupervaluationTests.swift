import Foundation
import XCTest
import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicProposition

/// #214 bounded supervaluation 的承重測試。
///
/// 這些測試刻意以無 supporting evidence 的 canonical atoms 產生 unknown；若 production
/// 偷換成 strong Kleene，excluded middle、contradiction 與 self implication 會直接轉紅。
final class SupervaluationTests: XCTestCase {
    private var snapshotID: StoreSnapshotID {
        StoreSnapshotID(
            store: StoreIdentity(
                uuid: UUID(uuidString: "21400000-0000-4000-8000-000000000001")!
            ),
            revision: StoreRevision(
                digest: "sha256:" + String(repeating: "21", count: 32)
            )
        )
    }

    private func proposition(_ index: Int) -> Proposition {
        .authored(
            person: .key(String(format: "person-%02d", index)),
            work: .key(String(format: "work-%02d", index))
        )
    }

    private func context(atomCount: Int) throws -> ValuationContext {
        let people = (0..<atomCount).map {
            Person(key: String(format: "person-%02d", $0), names: ["P\($0)"])
        }
        let entries = (0..<atomCount).map {
            Entry(
                id: UUID(
                    uuidString: String(
                        format: "21400000-0000-4000-8001-%012d",
                        $0
                    )
                )!,
                citekey: String(format: "work-%02d", $0),
                type: "article",
                title: "W\($0)",
                authors: [],
                date: "2026"
            )
        }
        return try PropositionModel(
            snapshotID: snapshotID,
            entries: entries,
            people: people,
            organizations: []
        ).context(validAt: ValidDay("2026-08-11"))
    }

    private func auditedContext() throws -> (
        context: ValuationContext,
        quarantine: [QuarantinedFile]
    ) {
        let quarantine = [
            QuarantinedFile(
                file: "entities/broken-214.yaml",
                reason: "malformed fixture"
            )
        ]
        let entry = Entry(
            id: UUID(uuidString: "21400000-0000-4000-8002-000000000001")!,
            citekey: "work-00",
            type: "article",
            title: "Audited",
            authors: [.key("person-00")],
            date: "2026"
        )
        let person = Person(key: "person-00", names: ["P0"])
        let model = try PropositionModel(
            snapshotID: snapshotID,
            entries: [entry],
            people: [person],
            organizations: [],
            snapshotQuarantine: quarantine
        )
        return (
            model.context(validAt: try ValidDay("2026-07-31")),
            quarantine
        )
    }

    private func atom(_ index: Int) throws -> PropositionExpression {
        try PropositionExpression.atom(proposition(index))
    }

    private func balancedOr(
        _ expressions: ArraySlice<PropositionExpression>
    ) throws -> PropositionExpression {
        precondition(!expressions.isEmpty)
        if expressions.count == 1 { return expressions.first! }
        let midpoint = expressions.index(
            expressions.startIndex,
            offsetBy: expressions.count / 2
        )
        return try PropositionExpression.or(
            balancedOr(expressions[..<midpoint]),
            balancedOr(expressions[midpoint...])
        )
    }

    private func preorder(_ root: EvidenceTrace) -> [EvidenceTrace] {
        var result: [EvidenceTrace] = []
        var stack = [root]
        while let current = stack.popLast() {
            result.append(current)
            stack.append(contentsOf: current.children.reversed())
        }
        return result
    }

    // Production mutations caught: strong-Kleene operator tables, wrong implication, or NOR
    // implemented as ordinary OR.
    func testUnknownExcludedMiddleHoldsAndUnknownContradictionFails() throws {
        let context = try context(atomCount: 1)
        let p = try atom(0)
        let notP = try PropositionExpression.not(p)

        let excludedMiddle = try PropositionExpression.or(p, notP)
        let contradiction = try PropositionExpression.and(p, notP)
        let selfImplication = try PropositionExpression.implies(p, p)
        let jointDenial = try PropositionExpression.nor(p, notP)

        XCTAssertEqual(try excludedMiddle.evaluate(in: context).truth, .holds)
        XCTAssertEqual(try contradiction.evaluate(in: context).truth, .fails)
        XCTAssertEqual(try selfImplication.evaluate(in: context).truth, .holds)
        XCTAssertEqual(try jointDenial.evaluate(in: context).truth, .fails)
    }

    // Production mutations caught: implication copied from OR, absorbing known conclusions are
    // removed, or binary mixed reasons lose their canonical atom payload.
    func testImplicationAndMixedKnownUnknownFollowAllCompletions() throws {
        let context = try context(atomCount: 2)
        let p = try atom(0)
        let q = try atom(1)
        let notP = try PropositionExpression.not(p)
        let alwaysTrue = try PropositionExpression.or(p, notP)
        let alwaysFalse = try PropositionExpression.and(p, notP)

        XCTAssertEqual(
            try PropositionExpression.implies(alwaysFalse, q)
                .evaluate(in: context).truth,
            .holds
        )
        XCTAssertEqual(
            try PropositionExpression.and(alwaysFalse, q)
                .evaluate(in: context).truth,
            .fails
        )
        XCTAssertEqual(
            try PropositionExpression.or(alwaysTrue, q)
                .evaluate(in: context).truth,
            .holds
        )
        XCTAssertEqual(
            try PropositionExpression.nor(alwaysTrue, q)
                .evaluate(in: context).truth,
            .fails
        )
        XCTAssertEqual(
            try PropositionExpression.implies(alwaysTrue, q)
                .evaluate(in: context).truth,
            .undetermined(.supervaluationInconclusive(atoms: [proposition(1)]))
        )
        XCTAssertEqual(
            try PropositionExpression.implies(p, q).evaluate(in: context).truth,
            .undetermined(.supervaluationInconclusive(
                atoms: [proposition(0), proposition(1)]
            ))
        )
    }

    // Production mutations caught: duplicate syntax occurrences are projected repeatedly or a
    // trace short-circuits after the first determinate branch.
    func testDuplicateAtomsAreEvaluatedOnceButEveryOccurrenceIsTraced() throws {
        let context = try context(atomCount: 1)
        let p = try atom(0)
        let expression = try PropositionExpression.or(p, p)
        var evaluated: [Proposition] = []
        let valuation = try expression.evaluate(
            in: context,
            shift: { 1 << $0 },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in }),
            atomicObserver: { evaluated.append($0) }
        )
        XCTAssertEqual(evaluated, [proposition(0)])
        XCTAssertEqual(valuation.trace.children.count, 2)
        XCTAssertEqual(valuation.trace.children.map(\.expression), [p, p])
    }

    // Production mutations caught: completion guard happens after shift/allocation, or the cap is
    // widened beyond the fixed 4,096 compatible worlds.
    func testCompletionLimitFailsClosedBeforeEnumeration() throws {
        let acceptedContext = try context(atomCount: 12)
        let acceptedAtoms = try (0..<12).map(atom)
        let accepted = try balancedOr(acceptedAtoms[...])
        var acceptedAtomsEvaluated: [Proposition] = []
        let acceptedValuation = try accepted.evaluate(
            in: acceptedContext,
            shift: { 1 << $0 },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in }),
            atomicObserver: { acceptedAtomsEvaluated.append($0) }
        )
        XCTAssertEqual(acceptedAtomsEvaluated, (0..<12).map(proposition))
        XCTAssertEqual(acceptedValuation.trace.completionSummary?.completionCount, 4_096)

        let rejectedContext = try context(atomCount: 13)
        let rejectedAtoms = try (0..<13).map(atom)
        let rejected = try balancedOr(rejectedAtoms[...])
        var shiftCount = 0
        var workspaceAllocationCount = 0
        var rejectedAtomsEvaluated: [Proposition] = []
        let workspaceProbe = EnumerationWorkspaceProbe(
            onAllocate: { _ in workspaceAllocationCount += 1 }
        )

        XCTAssertThrowsError(try rejected.evaluate(
            in: rejectedContext,
            shift: { exponent in
                shiftCount += 1
                return 1 << exponent
            },
            workspaceProbe: workspaceProbe,
            atomicObserver: { rejectedAtomsEvaluated.append($0) }
        )) { error in
            XCTAssertEqual(
                error as? PropositionEvaluationError,
                .supervaluationCompletionLimitExceeded(
                    undeterminedAtomCount: 13,
                    maximumCompletions: 4_096
                )
            )
        }
        XCTAssertEqual(shiftCount, 0)
        XCTAssertEqual(workspaceAllocationCount, 0)
        XCTAssertEqual(rejectedAtomsEvaluated, (0..<13).map(proposition))
    }


    // Production mutations caught: stable node IDs or preorder are changed, repeated occurrences
    // are folded, a child is reordered, or a composite trace loses its exact context/expression.
    func testEverySubformulaProducesOrderedContextBoundTrace() throws {
        let context = try context(atomCount: 2)
        let p = try atom(0)
        let q = try atom(1)
        let andPP = try PropositionExpression.and(p, p)
        let notP = try PropositionExpression.not(p)
        let norQNotP = try PropositionExpression.nor(q, notP)
        let expression = try PropositionExpression.implies(andPP, norQNotP)
        var evaluated: [Proposition] = []

        let valuation = try expression.evaluate(
            in: context,
            shift: { 1 << $0 },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in }),
            atomicObserver: { evaluated.append($0) }
        )

        XCTAssertEqual(evaluated, [proposition(0), proposition(1)])
        XCTAssertEqual(valuation.expression, expression)
        XCTAssertEqual(valuation.context, context)
        XCTAssertEqual(valuation.trace.expression, expression)
        XCTAssertEqual(valuation.trace.kind, .implies)
        XCTAssertEqual(valuation.trace.conclusion, valuation.truth)
        XCTAssertEqual(valuation.trace.children.map(\.expression), [andPP, norQNotP])

        let nodes = preorder(valuation.trace)
        XCTAssertEqual(nodes.count, 8)
        XCTAssertTrue(nodes.allSatisfy { $0.context == context })
        XCTAssertEqual(nodes.map(\.expression), [
            expression,
            andPP,
            p,
            p,
            norQNotP,
            q,
            notP,
            p,
        ])
        let expectedKinds: [EvidenceTrace.Kind] = [
            .implies,
            .and,
            .atom,
            .atom,
            .nor,
            .atom,
            .not,
            .atom,
        ]
        XCTAssertEqual(nodes.map { $0.kind }, expectedKinds)
        XCTAssertEqual(nodes[1].children.map(\.expression), [p, p])
        XCTAssertEqual(nodes[4].children.map(\.expression), [q, notP])
        XCTAssertEqual(nodes[6].children.map(\.expression), [p])
        let atomNodes = nodes.filter { $0.kind == .atom }
        let operatorNodes = nodes.filter { $0.kind != .atom }
        XCTAssertEqual(atomNodes.count, 4)
        for node in atomNodes {
            XCTAssertNotNil(node.atomicEvidence)
            XCTAssertTrue(node.children.isEmpty)
        }
        for node in operatorNodes {
            XCTAssertNil(node.atomicEvidence)
            XCTAssertEqual(node.completionSummary?.completionCount, 4)
        }
    }

    // Production mutations caught: an absorbing false short-circuits its sibling, reverses child
    // order, or drops snapshot/day/quarantine/projection refusal from an atom leaf.
    func testAbsorbingTruthRetainsBothChildrenContextAndRefusal() throws {
        let audited = try auditedContext()
        let p = try atom(0)
        let q = try atom(1)
        let notP = try PropositionExpression.not(p)
        let expression = try PropositionExpression.and(notP, q)
        var evaluated: [Proposition] = []

        let valuation = try expression.evaluate(
            in: audited.context,
            shift: { 1 << $0 },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in }),
            atomicObserver: { evaluated.append($0) }
        )

        XCTAssertEqual(valuation.truth, .fails)
        XCTAssertEqual(evaluated, [proposition(0), proposition(1)])
        XCTAssertEqual(valuation.context.snapshotID, snapshotID)
        XCTAssertEqual(valuation.context.validAt.rawValue, "2026-07-31")
        XCTAssertEqual(valuation.trace.context, valuation.context)
        XCTAssertEqual(valuation.trace.children.map(\.expression), [notP, q])

        let left = valuation.trace.children[0]
        let right = valuation.trace.children[1]
        XCTAssertEqual(left.conclusion, .fails)
        XCTAssertEqual(right.conclusion, .undetermined(.notProjectable(
            .unknownIdentity(role: "person", key: "person-01")
        )))
        XCTAssertEqual(left.context, audited.context)
        XCTAssertEqual(right.context, audited.context)
        XCTAssertEqual(right.atomicEvidence?.refusal, .notProjectable(
            .unknownIdentity(role: "person", key: "person-01")
        ))
        XCTAssertEqual(right.atomicEvidence?.projection, .unprojectable(
            .unknownIdentity(role: "person", key: "person-01")
        ))
        XCTAssertEqual(right.atomicEvidence?.snapshotQuarantine, audited.quarantine)
    }

    // Production mutations caught: question construction defers its negation budget, a no answer
    // re-evaluates atoms, or the established answer flattens/normalizes the subject trace.
    func testQuestionReservesNegationAndNoAnswerDoesNotReevaluateAtoms() throws {
        let audited = try auditedContext()
        let p = try atom(0)
        let subject = try PropositionExpression.not(p)
        let question = try YesNoQuestion(subject)
        var evaluated: [Proposition] = []

        let result = try question.answer(
            in: audited.context,
            shift: { 1 << $0 },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in }),
            atomicObserver: { evaluated.append($0) }
        )

        XCTAssertEqual(YesNoQuestion.Answer.allCases, [.yes, .no, .undetermined])
        XCTAssertEqual(question.answerSpace, [.yes, .no, .undetermined])
        XCTAssertEqual(evaluated, [proposition(0)])
        XCTAssertEqual(result.answer, .no)
        XCTAssertEqual(result.subjectValuation.expression, subject)
        XCTAssertEqual(result.subjectValuation.truth, .fails)
        let established = try XCTUnwrap(result.establishedAnswer)
        let reservedNegation = try PropositionExpression.not(subject)
        XCTAssertEqual(established.expression, reservedNegation)
        XCTAssertNotEqual(established.expression, p)
        XCTAssertEqual(established.valuation.truth, .holds)
        XCTAssertEqual(established.valuation.context, audited.context)
        XCTAssertEqual(established.valuation.trace.kind, .not)
        XCTAssertEqual(established.valuation.trace.children, [result.subjectValuation.trace])
        let establishedLeaf = try XCTUnwrap(
            preorder(established.valuation.trace).last?.atomicEvidence
        )
        XCTAssertEqual(
            establishedLeaf.snapshotQuarantine,
            audited.quarantine
        )

        var depthBoundary = p
        for _ in 0..<64 {
            depthBoundary = try PropositionExpression.not(depthBoundary)
        }
        XCTAssertThrowsError(try YesNoQuestion(depthBoundary)) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .operatorDepthExceeded(actual: 65, maximum: 64)
            )
        }
    }

    // Production mutations caught: adjudication substitutes semantic equivalence for recorded
    // syntax, checks stance before identity, or fails to retain the exact successful valuation.
    func testAdjudicationUsesStructuralIdentityAndRetainsExactValuation() throws {
        let audited = try auditedContext()
        let p = try atom(0)
        let q = try atom(1)
        let recorded = try PropositionExpression.or(p, q)
        let evaluatedExpression = try PropositionExpression.or(q, p)
        let valuation = try evaluatedExpression.evaluate(
            in: audited.context,
            shift: { 1 << $0 },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in }),
            atomicObserver: { _ in }
        )
        XCTAssertTrue(try recorded.isClassicallyEquivalent(to: evaluatedExpression))
        XCTAssertNotEqual(recorded, evaluatedExpression)

        let mismatched = Assertion(
            expression: recorded,
            stance: .denied,
            source: "#214 structural gate",
            recorded: try RecordedTime("2026-08-10")
        )
        XCTAssertThrowsError(try adjudicate(
            mismatched,
            valuation: valuation,
            acceptedBy: "reviewer",
            acceptedAt: AcceptedTime("2026-08-11")
        )) { error in
            XCTAssertEqual(
                error as? AdjudicationRefusal,
                .expressionMismatch(
                    assertion: recorded,
                    valuation: evaluatedExpression
                )
            )
        }

        let exact = Assertion(
            expression: evaluatedExpression,
            stance: .asserted,
            source: "#214 exact gate",
            recorded: try RecordedTime("2026-08-10")
        )
        let fact = try adjudicate(
            exact,
            valuation: valuation,
            acceptedBy: "reviewer",
            acceptedAt: AcceptedTime("2026-08-11")
        )
        XCTAssertEqual(fact.expression, evaluatedExpression)
        XCTAssertEqual(fact.valuation, valuation)
        XCTAssertEqual(fact.valuation.context, audited.context)
        XCTAssertEqual(fact.valuation.trace, valuation.trace)
    }

    // Production mutation caught: Stance.denied is converted into an asserted structural not or
    // allowed to create an AcceptedFact.
    func testDeniedStanceNeverConvertsIntoAssertedNegation() throws {
        let audited = try auditedContext()
        let p = try atom(0)
        let valuation = try p.evaluate(
            in: audited.context,
            shift: { 1 << $0 },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in }),
            atomicObserver: { _ in }
        )
        let denied = Assertion(
            expression: p,
            stance: .denied,
            source: "source denial",
            recorded: try RecordedTime("2026-08-10")
        )
        let assertedNegation = Assertion(
            expression: try PropositionExpression.not(p),
            stance: .asserted,
            source: "explicit proposition negation",
            recorded: try RecordedTime("2026-08-10")
        )

        XCTAssertNotEqual(denied, assertedNegation)
        XCTAssertEqual(denied.expression, p)
        XCTAssertEqual(assertedNegation.expression, try PropositionExpression.not(p))
        XCTAssertThrowsError(try adjudicate(
            denied,
            valuation: valuation,
            acceptedBy: "reviewer",
            acceptedAt: AcceptedTime("2026-08-11")
        )) { error in
            XCTAssertEqual(
                error as? AdjudicationRefusal,
                .stanceIsNotAssertion(.denied)
            )
        }
    }
}
