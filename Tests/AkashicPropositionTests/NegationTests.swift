import Foundation
import XCTest
import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicProposition

/// #213 的 bounded expression／recursive trace vertical slice。
///
/// 每個測試都鎖定一個可觀察的破壞：語法 identity 被化簡、nested atom 漏驗、
/// depth budget off-by-one、未知被誤作 false，或 negation 只換 truth 而丟失 audit trail。
final class NegationTests: XCTestCase {
    private let personKey = "cheng-che"
    private let workKey = "cheng2025identifiability"

    private var atom: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    private var snapshotID: StoreSnapshotID {
        StoreSnapshotID(
            store: StoreIdentity(
                uuid: UUID(uuidString: "9E47152A-3D6D-4D71-8A67-000000000213")!
            ),
            revision: StoreRevision(
                digest: "sha256:0000000000000000000000000000000000000000000000000000000213"
            )
        )
    }

    private func context(
        authors: [AkashicCore.Author] = [.key("cheng-che")],
        quarantine: [QuarantinedFile] = []
    ) throws -> ValuationContext {
        let entry = Entry(
            id: UUID(uuidString: "2D0C1EA4-A457-4189-8B29-000000000213")!,
            citekey: workKey,
            type: "article",
            title: "T",
            authors: authors,
            date: "2026"
        )
        let person = Person(key: personKey, names: ["Che Cheng", "鄭澈"])
        return try PropositionModel(
            snapshotID: snapshotID,
            entries: [entry],
            people: [person],
            organizations: [],
            snapshotQuarantine: quarantine
        ).context(validAt: ValidDay("2026-08-10"))
    }

    private func wrapping(
        _ expression: PropositionExpression,
        count: Int
    ) -> PropositionExpression {
        (0..<count).reduce(expression) { partial, _ in .not(partial) }
    }

    private func negationLayerCount(_ trace: EvidenceTrace) -> Int {
        var current = trace
        var count = 0
        while current.kind == .negation {
            guard let operand = current.operand else {
                XCTFail("negation kind 必須提供 operand view")
                return count
            }
            count += 1
            current = operand
        }
        return count
    }

    private func atomLayerCount(_ trace: EvidenceTrace) -> Int {
        var current = trace
        while let operand = current.operand { current = operand }
        return current.kind == .atom ? 1 : 0
    }

    private func externalTypecheck(
        _ source: String
    ) throws -> (status: Int32, output: String) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("akashic-trace-typecheck-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Probe.swift")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let modules = productsDirectory.appendingPathComponent("Modules")
        let scratchRoot = productsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cyamlInclude = scratchRoot
            .appendingPathComponent("checkouts/Yams/Sources/CYaml/include")
        let cyamlModuleMap = cyamlInclude.appendingPathComponent("module.modulemap")
        XCTAssertTrue(
            fileManager.fileExists(atPath: modules.path),
            "external probe 找不到 SwiftPM Modules：\(modules.path)"
        )
        XCTAssertTrue(
            fileManager.fileExists(atPath: cyamlModuleMap.path),
            "external probe 找不到 CYaml module map：\(cyamlModuleMap.path)"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc",
            "-typecheck",
            "-warnings-as-errors",
            "-I", modules.path,
            "-Xcc", "-fmodule-map-file=\(cyamlModuleMap.path)",
            "-Xcc", "-I",
            "-Xcc", cyamlInclude.path,
            sourceURL.path,
        ]
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 SwiftPM products directory")
    }

    // Production mutation caught: Equatable simplifies double negation or Hashable omits node tags.
    func testAtomNegationAndDoubleNegationHaveDistinctStructuralIdentity() throws {
        let p = try PropositionExpression.makeAtom(atom)
        let notP = try PropositionExpression.makeNot(p)
        let notNotP = try PropositionExpression.makeNot(notP)

        XCTAssertNotEqual(p, notP)
        XCTAssertNotEqual(p, notNotP)
        XCTAssertNotEqual(notP, notNotP)
        XCTAssertEqual(Set([p, notP, notNotP]).count, 3)
        XCTAssertEqual(atom.expression, p)
    }

    // Production mutation caught: public enum cases expose raw trace construction to clients.
    func testExternalClientCannotConstructRawTraceNodes() throws {
        let allowed = try externalTypecheck("""
            import AkashicProposition

            func audit(_ trace: EvidenceTrace) -> TruthValue {
                trace.conclusion
            }
            """)
        XCTAssertEqual(allowed.status, 0, allowed.output)

        let rawAtom = try externalTypecheck("""
            import AkashicProposition

            func constructAtom(_ atomic: AtomicEvidenceTrace) -> EvidenceTrace {
                EvidenceTrace.atom(atomic)
            }
            """)
        XCTAssertNotEqual(
            rawAtom.status,
            0,
            "non-@testable client 不得取得 raw atom constructor"
        )
        XCTAssertTrue(rawAtom.output.contains("atom"), rawAtom.output)

        let rawNegation = try externalTypecheck("""
            import AkashicProposition

            func constructNegation(_ operand: EvidenceTrace) -> EvidenceTrace {
                EvidenceTrace.negation(operand: operand, conclusion: .holds)
            }
            """)
        XCTAssertNotEqual(
            rawNegation.status,
            0,
            "non-@testable client 不得自行配對 operand 與 conclusion"
        )
        XCTAssertTrue(rawNegation.output.contains("negation"), rawNegation.output)
    }

    // Production mutation caught: synthesized recursive equality overflows, or a caller supplies
    // a conclusion instead of deriving it mechanically from the operand.
    func testTraceEqualityTraverses32768NodesAndDerivesEveryConclusion() {
        let projection = EvidenceProjection.authored(
            personKey: personKey,
            workKey: workKey
        )
        let atomic = AtomicEvidenceTrace(
            scope: .snapshotScopedTimeInvariant,
            projection: projection,
            evidence: [],
            snapshotQuarantine: [],
            conclusion: .holds
        )
        let leftAtom = EvidenceTrace.atom(atomic)
        let rightAtom = EvidenceTrace.atom(atomic)

        let once = EvidenceTrace.negating(leftAtom)
        let twice = EvidenceTrace.negating(once)
        XCTAssertEqual(once.kind, .negation)
        XCTAssertEqual(once.operand, leftAtom)
        XCTAssertEqual(once.conclusion, .fails)
        XCTAssertEqual(twice.conclusion, .holds)
        XCTAssertEqual(twice.atomic, atomic)

        var left = leftAtom
        var right = rightAtom
        for _ in 0..<32_768 {
            left = EvidenceTrace.negating(left)
            right = EvidenceTrace.negating(right)
        }

        XCTAssertEqual(left.conclusion, .holds)
        XCTAssertEqual(left, right)
    }

    // Production mutation caught: synthesized recursive equality/hash walks an untrusted deep chain.
    func testEqualityAndHashTraverseUnvalidatedChainsIteratively() {
        let left = wrapping(.atom(atom), count: 4_096)
        let right = wrapping(.atom(atom), count: 4_096)
        let different = wrapping(
            .atom(.authored(person: .key("someone-else"), work: .key(workKey))),
            count: 4_096
        )

        XCTAssertEqual(left, right)
        XCTAssertEqual(left.hashValue, right.hashValue)
        XCTAssertNotEqual(left, different)
    }

    // Production mutation caught: depth check uses >= instead of >, or validates only the root.
    func testValidationAccepts64OperatorsAndRejects65() throws {
        let p = try PropositionExpression.makeAtom(atom)
        let depth64 = wrapping(p, count: 64)
        let depth65 = wrapping(p, count: 65)

        XCTAssertNoThrow(try depth64.validate())
        XCTAssertThrowsError(try depth65.validate()) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .operatorDepthExceeded(maximum: 64)
            )
        }
    }

    // Production mutation caught: validation stops at a not node and never reaches its atom.
    func testNestedMalformedAtomPreservesOriginalTypedError() throws {
        let malformedKey = wrapping(
            .atom(.authored(person: .key("Not A Key"), work: .key(workKey))),
            count: 2
        )
        let emptyLiteral = wrapping(
            .atom(.affiliated(person: .literal("  "), organization: .key("org-a"))),
            count: 1
        )
        let source = try context()

        XCTAssertThrowsError(try malformedKey.validate()) {
            XCTAssertEqual($0 as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try malformedKey.evaluate(in: source)) {
            XCTAssertEqual($0 as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try YesNoQuestion(malformedKey)) {
            XCTAssertEqual($0 as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try emptyLiteral.evaluate(in: source)) {
            XCTAssertEqual($0 as? PropositionError, .emptyLiteral)
        }
    }

    // Production mutation caught: question accepts depth 64 although a no answer needs one more node.
    func testQuestionReservesOneNegationNode() throws {
        let p = try PropositionExpression.makeAtom(atom)

        XCTAssertNoThrow(try YesNoQuestion(wrapping(p, count: 63)))
        XCTAssertThrowsError(try YesNoQuestion(wrapping(p, count: 64))) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .operatorDepthExceeded(maximum: 64)
            )
        }
    }

    // Production mutation caught: double negation is normalized or atom evaluation is duplicated.
    func testDoubleNegationKeepsTwoTraceNodesButRestoresTruth() throws {
        let source = try context()
        let p = try PropositionExpression.makeAtom(atom)
        let notNotP = try PropositionExpression.makeNot(.not(p))

        let atomic = try p.evaluate(in: source)
        let doubled = try notNotP.evaluate(in: source)

        XCTAssertEqual(atomic.truth, .holds)
        XCTAssertEqual(doubled.truth, atomic.truth)
        XCTAssertNotEqual(doubled.expression, atomic.expression)
        XCTAssertEqual(negationLayerCount(doubled.trace), 2)
        XCTAssertEqual(atomLayerCount(doubled.trace), 1)
        XCTAssertEqual(doubled.trace.kind, .negation)
        XCTAssertEqual(doubled.trace.conclusion, .holds)
        let inner = try XCTUnwrap(doubled.trace.operand)
        XCTAssertEqual(inner.kind, .negation)
        XCTAssertEqual(inner.conclusion, .fails)
        let operand = try XCTUnwrap(inner.operand)
        XCTAssertEqual(operand, atomic.trace)
    }

    // Production mutation caught: negation changes only truth and flattens/drops operand evidence.
    func testNegationPreservesContextQuarantineAndCompleteAtomicEvidence() throws {
        let quarantine = [
            QuarantinedFile(file: "entities/broken.yaml", reason: "malformed")
        ]
        let source = try context(quarantine: quarantine)
        let p = try PropositionExpression.makeAtom(atom)
        let atomic = try p.evaluate(in: source)
        let negated = try PropositionExpression.makeNot(p).evaluate(in: source)

        XCTAssertEqual(negated.expression, .not(p))
        XCTAssertEqual(negated.truth, .fails)
        XCTAssertEqual(negated.context, atomic.context)
        XCTAssertEqual(negated.trace.scope, atomic.trace.scope)
        XCTAssertEqual(negated.trace.projection, atomic.trace.projection)
        XCTAssertEqual(negated.trace.evidence, atomic.trace.evidence)
        XCTAssertEqual(negated.trace.snapshotQuarantine, quarantine)
        XCTAssertEqual(negated.trace.conclusion, negated.truth)
        XCTAssertEqual(negated.trace.kind, .negation)
        let operand = try XCTUnwrap(negated.trace.operand)
        XCTAssertEqual(operand, atomic.trace)
        XCTAssertEqual(negated.trace.conclusion, .fails)
    }

    // Production mutation caught: an undetermined reason is collapsed or negated into determinate truth.
    func testNegationPreservesEveryUndeterminedReasonExactly() throws {
        let source = try context()
        let expression = try PropositionExpression.makeAtom(atom)
        let projection = EvidenceProjection.authored(personKey: personKey, workKey: workKey)
        let reasons: [UndeterminedReason] = [
            .notProjectable(.unknownIdentity(role: "person", key: "missing")),
            .noSupportingEvidence,
            .supportingEvidenceUnresolved(literal: "C. Cheng"),
            .authorIdentityUnresolved(literal: "Another Author"),
            .temporalEvidenceIndeterminate,
            .invalidTemporalEvidence,
        ]

        for reason in reasons {
            let truth = TruthValue.undetermined(reason)
            let trace = EvidenceTrace.atom(AtomicEvidenceTrace(
                scope: .snapshotScopedTimeInvariant,
                projection: projection,
                evidence: [],
                snapshotQuarantine: [],
                conclusion: truth
            ))
            let valuation = Valuation(
                expression: expression,
                truth: truth,
                context: source,
                trace: trace
            )

            let negated = valuation.negated(as: .not(expression))
            XCTAssertEqual(negated.truth, truth, "reason=\(reason)")
            XCTAssertEqual(negated.context, source, "reason=\(reason)")
            XCTAssertEqual(negated.trace.conclusion, truth, "reason=\(reason)")
            XCTAssertEqual(negated.trace.kind, .negation, "reason=\(reason)")
            let operand = try XCTUnwrap(negated.trace.operand, "reason=\(reason)")
            XCTAssertEqual(operand, trace, "reason=\(reason)")
            XCTAssertEqual(negated.trace.conclusion, truth, "reason=\(reason)")
        }
    }

    // Production mutation caught: answer flattens subject or recomputes a second context/trace.
    func testYesAnswerRetainsItsCompleteEstablishedValuation() throws {
        let source = try context()
        let question = try YesNoQuestion(atom.expression)
        let result = try question.answer(in: source)

        XCTAssertEqual(result.answer, .yes)
        XCTAssertEqual(result.subjectValuation.expression, atom.expression)
        XCTAssertEqual(result.subjectValuation.truth, .holds)
        XCTAssertEqual(result.establishedAnswer?.valuation, result.subjectValuation)
        XCTAssertEqual(result.establishedAnswer?.expression, atom.expression)
    }

    // Production mutation caught: no reuses subject/fails valuation or normalizes ¬¬p to p.
    func testNegativeSubjectNoAnswerEstablishesStructuralDoubleNegation() throws {
        let source = try context()
        let p = atom.expression
        let negativeSubject = try PropositionExpression.makeNot(p)
        let result = try YesNoQuestion(negativeSubject).answer(in: source)

        XCTAssertEqual(result.answer, .no)
        XCTAssertEqual(result.subjectValuation.expression, negativeSubject)
        XCTAssertEqual(result.subjectValuation.truth, .fails)
        guard let established = result.establishedAnswer else {
            return XCTFail("determinate no 必須有自己的 established valuation")
        }
        XCTAssertEqual(established.expression, .not(negativeSubject))
        XCTAssertEqual(established.valuation.truth, .holds)
        XCTAssertEqual(established.valuation.context, result.subjectValuation.context)
        XCTAssertEqual(established.valuation.trace.kind, .negation)
        XCTAssertEqual(established.valuation.trace.conclusion, .holds)
        let operand = try XCTUnwrap(established.valuation.trace.operand)
        XCTAssertEqual(operand, result.subjectValuation.trace)

        let assertion = Assertion(
            expression: established.expression,
            stance: .asserted,
            source: "answer",
            recorded: try RecordedTime("2026-08-09")
        )
        let fact = try adjudicate(
            assertion,
            valuation: established.valuation,
            acceptedBy: "reviewer",
            acceptedAt: try AcceptedTime("2026-08-10")
        )
        XCTAssertEqual(fact.expression, .not(negativeSubject))
        XCTAssertEqual(fact.valuation, established.valuation)
    }

    // Production mutation caught: unknown is given a fabricated expression that callers can assert.
    func testUndeterminedAnswerHasNoEstablishedExpression() throws {
        let source = try context(authors: [])
        let result = try YesNoQuestion(atom.expression).answer(in: source)

        XCTAssertEqual(result.answer, .undetermined)
        XCTAssertEqual(
            result.subjectValuation.truth,
            .undetermined(.noSupportingEvidence)
        )
        XCTAssertNil(result.establishedAnswer)
    }

    // Production mutation caught: denied(p) is silently converted into asserted(¬p).
    func testDeniedExpressionRemainsARefusedStanceEvenWhenThatExpressionHolds() throws {
        let source = try context()
        let expression = atom.expression
        let valuation = try expression.evaluate(in: source)
        let denied = Assertion(
            expression: expression,
            stance: .denied,
            source: "source",
            recorded: try RecordedTime("2026-08-09")
        )

        XCTAssertThrowsError(try adjudicate(
            denied,
            valuation: valuation,
            acceptedBy: "reviewer",
            acceptedAt: try AcceptedTime("2026-08-10")
        )) { error in
            XCTAssertEqual(error as? AdjudicationRefusal, .stanceIsNotAssertion(.denied))
        }
    }

    // Production mutation caught: adjudication validates only the outer node or compares atoms only.
    func testAdjudicationRevalidatesNestedExpressionAndUsesStructuralIdentity() throws {
        let source = try context()
        let p = atom.expression
        let holds = try p.evaluate(in: source)
        let malformed = PropositionExpression.not(.atom(
            .authored(person: .key("Not A Key"), work: .key(workKey))
        ))
        let malformedValuation = Valuation(
            expression: malformed,
            truth: .holds,
            context: source,
            trace: holds.trace
        )
        let malformedAssertion = Assertion(
            expression: malformed,
            stance: .asserted,
            source: "source",
            recorded: try RecordedTime("2026-08-09")
        )

        XCTAssertThrowsError(try adjudicate(
            malformedAssertion,
            valuation: malformedValuation,
            acceptedBy: "reviewer",
            acceptedAt: try AcceptedTime("2026-08-10")
        )) {
            XCTAssertEqual($0 as? PropositionError, .malformedKey("Not A Key"))
        }

        let negatedAssertion = Assertion(
            expression: .not(p),
            stance: .denied,
            source: "source",
            recorded: try RecordedTime("2026-08-09")
        )
        XCTAssertThrowsError(try adjudicate(
            negatedAssertion,
            valuation: holds,
            acceptedBy: "reviewer",
            acceptedAt: try AcceptedTime("2026-08-10")
        )) { error in
            XCTAssertEqual(
                error as? AdjudicationRefusal,
                .expressionMismatch(assertion: .not(p), valuation: p),
                "expression mismatch 必須先於 denied stance"
            )
        }
    }
}
