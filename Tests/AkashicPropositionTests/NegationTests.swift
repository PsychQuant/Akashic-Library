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
            type: .periodicalArticle,
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
    ) throws -> PropositionExpression {
        var result = expression
        for _ in 0..<count {
            result = try PropositionExpression.not(result)
        }
        return result
    }

    private func negationLayerCount(_ trace: EvidenceTrace) -> Int {
        var current = trace
        var count = 0
        while current.kind == .not {
            guard current.children.count == 1 else {
                XCTFail("not kind 必須提供一個 ordered child")
                return count
            }
            count += 1
            current = current.children[0]
        }
        return count
    }

    private func atomLayerCount(_ trace: EvidenceTrace) -> Int {
        var count = 0
        var stack = [trace]
        while let current = stack.popLast() {
            if current.atomicEvidence != nil { count += 1 }
            stack.append(contentsOf: current.children.reversed())
        }
        return count
    }

    private func boundaryExpression(
        _ atom: PropositionExpression
    ) throws -> PropositionExpression {
        var expression = atom
        for _ in 0..<11 {
            expression = try PropositionExpression.and(expression, expression)
        }
        return try PropositionExpression.not(expression)
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
        SwiftcProbe.configure(process, arguments: [
            "-typecheck",
            "-warnings-as-errors",
            "-I", modules.path,
            "-Xcc", "-fmodule-map-file=\(cyamlModuleMap.path)",
            "-Xcc", "-I",
            "-Xcc", cyamlInclude.path,
            sourceURL.path,
        ])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        SwiftcProbe.assertToolchainMatched(text, process)
        return (process.terminationStatus, text)
    }

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 SwiftPM products directory")
    }

    // Production mutation caught: Equatable simplifies double negation or Hashable omits node tags.
    func testAtomNegationAndDoubleNegationHaveDistinctStructuralIdentity() throws {
        let p = try PropositionExpression.atom(atom)
        let notP = try PropositionExpression.not(p)
        let notNotP = try PropositionExpression.not(notP)

        XCTAssertNotEqual(p, notP)
        XCTAssertNotEqual(p, notNotP)
        XCTAssertNotEqual(notP, notNotP)
        XCTAssertEqual(Set([p, notP, notNotP]).count, 3)
        XCTAssertEqual(try atom.asExpression(), p)
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

    // Production mutation caught: trace equality 遞迴爆 stack，或 operator conclusion
    // 沒有從 bounded expression tree 機械導出。
    func testTraceEqualityTraverses4096NodesAndDerivesEveryConclusion() throws {
        let source = try context()
        let expression = try boundaryExpression(atom.asExpression())
        let left = try expression.evaluate(in: source)
        let right = try expression.evaluate(in: source)

        XCTAssertEqual(expression.nodeCount, 4_096)
        XCTAssertEqual(left.trace.kind, .not)
        XCTAssertEqual(left.trace.conclusion, .fails)
        XCTAssertEqual(left.trace.children.count, 1)
        XCTAssertEqual(left.trace, right.trace)
    }

    // Production mutation caught: equality/hash 重走 recursive storage 而不是 bounded iterative feed。
    func testEqualityAndHashTraverseValidated4096NodeTreesIteratively() throws {
        let left = try boundaryExpression(atom.asExpression())
        let right = try boundaryExpression(atom.asExpression())
        let different = try boundaryExpression(Proposition.authored(
            person: .key("someone-else"),
            work: .key(workKey)
        ).asExpression())

        XCTAssertEqual(left, right)
        XCTAssertEqual(left.hashValue, right.hashValue)
        XCTAssertNotEqual(left, different)
    }

    // Production mutation caught: factory depth check uses >= instead of >。
    func testFactoryAccepts64OperatorsAndRejects65() throws {
        let p = try PropositionExpression.atom(atom)
        let depth64 = try wrapping(p, count: 64)

        XCTAssertEqual(depth64.operatorDepth, 64)
        XCTAssertThrowsError(try PropositionExpression.not(depth64)) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .operatorDepthExceeded(actual: 65, maximum: 64)
            )
        }
    }

    // Production mutation caught: nested factory wraps或改寫 malformed atom 的原始 typed error。
    func testNestedMalformedAtomPreservesOriginalTypedError() throws {
        let malformedKey = Proposition.authored(
            person: .key("Not A Key"),
            work: .key(workKey)
        )
        let emptyLiteral = Proposition.affiliated(
            person: .literal("  "),
            organization: .key("org-a")
        )

        XCTAssertThrowsError(try PropositionExpression.not(malformedKey.asExpression())) {
            XCTAssertEqual($0 as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try YesNoQuestion(malformedKey.asExpression())) {
            XCTAssertEqual($0 as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try PropositionExpression.not(emptyLiteral.asExpression())) {
            XCTAssertEqual($0 as? PropositionError, .emptyLiteral)
        }
    }

    // Production mutation caught: question accepts depth 64 although a no answer needs one more node.
    func testQuestionReservesOneNegationNode() throws {
        let p = try PropositionExpression.atom(atom)

        XCTAssertNoThrow(try YesNoQuestion(wrapping(p, count: 63)))
        let depthBoundary = try wrapping(p, count: 64)
        XCTAssertThrowsError(try YesNoQuestion(depthBoundary)) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .operatorDepthExceeded(actual: 65, maximum: 64)
            )
        }
    }

    // Production mutation caught: double negation is normalized or atom evaluation is duplicated.
    func testDoubleNegationKeepsTwoTraceNodesButRestoresTruth() throws {
        let source = try context()
        let p = try PropositionExpression.atom(atom)
        let notNotP = try PropositionExpression.not(PropositionExpression.not(p))

        let atomic = try p.evaluate(in: source)
        let doubled = try notNotP.evaluate(in: source)

        XCTAssertEqual(atomic.truth, .holds)
        XCTAssertEqual(doubled.truth, atomic.truth)
        XCTAssertNotEqual(doubled.expression, atomic.expression)
        XCTAssertEqual(negationLayerCount(doubled.trace), 2)
        XCTAssertEqual(atomLayerCount(doubled.trace), 1)
        XCTAssertEqual(doubled.trace.kind, .not)
        XCTAssertEqual(doubled.trace.conclusion, .holds)
        let inner = try XCTUnwrap(doubled.trace.children.first)
        XCTAssertEqual(inner.kind, .not)
        XCTAssertEqual(inner.conclusion, .fails)
        let operand = try XCTUnwrap(inner.children.first)
        XCTAssertEqual(operand, atomic.trace)
    }

    // Production mutation caught: negation changes only truth and flattens/drops operand evidence.
    func testNegationPreservesContextQuarantineAndCompleteAtomicEvidence() throws {
        let quarantine = [
            QuarantinedFile(file: "entities/broken.yaml", reason: "malformed")
        ]
        let source = try context(quarantine: quarantine)
        let p = try PropositionExpression.atom(atom)
        let atomic = try p.evaluate(in: source)
        let notP = try PropositionExpression.not(p)
        let negated = try notP.evaluate(in: source)
        let atomicEvidence = try XCTUnwrap(atomic.trace.atomicEvidence)
        let negatedLeaf = try XCTUnwrap(negated.trace.children.first?.atomicEvidence)

        XCTAssertEqual(negated.expression, notP)
        XCTAssertEqual(negated.truth, .fails)
        XCTAssertEqual(negated.context, atomic.context)
        XCTAssertEqual(negatedLeaf.scope, atomicEvidence.scope)
        XCTAssertEqual(negatedLeaf.projection, atomicEvidence.projection)
        XCTAssertEqual(negatedLeaf.evidence, atomicEvidence.evidence)
        XCTAssertEqual(negatedLeaf.snapshotQuarantine, quarantine)
        XCTAssertEqual(negated.trace.conclusion, negated.truth)
        XCTAssertEqual(negated.trace.kind, .not)
        let operand = try XCTUnwrap(negated.trace.children.first)
        XCTAssertEqual(operand, atomic.trace)
        XCTAssertEqual(negated.trace.conclusion, .fails)
    }

    // Production mutation caught: an undetermined reason is collapsed or negated into determinate truth.
    func testNegationPreservesEveryUndeterminedReasonExactly() throws {
        let source = try context()
        let expression = try PropositionExpression.atom(atom)
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
            let evidence = AtomicEvidenceTrace(
                scope: .snapshotScopedTimeInvariant,
                projection: projection,
                evidence: [],
                snapshotQuarantine: [],
                conclusion: truth
            )
            let trace = EvidenceTrace.atom(
                expression: expression,
                context: source,
                evidence: evidence
            )
            let valuation = Valuation(
                expression: expression,
                truth: truth,
                context: source,
                trace: trace
            )

            let negatedExpression = try PropositionExpression.not(expression)
            let negated = valuation.negated(as: negatedExpression)
            XCTAssertEqual(negated.truth, truth, "reason=\(reason)")
            XCTAssertEqual(negated.context, source, "reason=\(reason)")
            XCTAssertEqual(negated.trace.conclusion, truth, "reason=\(reason)")
            XCTAssertEqual(negated.trace.kind, .not, "reason=\(reason)")
            let operand = try XCTUnwrap(negated.trace.children.first, "reason=\(reason)")
            XCTAssertEqual(operand, trace, "reason=\(reason)")
            XCTAssertEqual(negated.trace.conclusion, truth, "reason=\(reason)")
        }
    }

    // Production mutation caught: answer flattens subject or recomputes a second context/trace.
    func testYesAnswerRetainsItsCompleteEstablishedValuation() throws {
        let source = try context()
        let expression = try atom.asExpression()
        let question = try YesNoQuestion(expression)
        let result = try question.answer(in: source)

        XCTAssertEqual(result.answer, .yes)
        XCTAssertEqual(result.subjectValuation.expression, expression)
        XCTAssertEqual(result.subjectValuation.truth, .holds)
        XCTAssertEqual(result.establishedAnswer?.valuation, result.subjectValuation)
        XCTAssertEqual(result.establishedAnswer?.expression, expression)
    }

    // Production mutation caught: no reuses subject/fails valuation or normalizes ¬¬p to p.
    func testNegativeSubjectNoAnswerEstablishesStructuralDoubleNegation() throws {
        let source = try context()
        let p = try atom.asExpression()
        let negativeSubject = try PropositionExpression.not(p)
        let doubleNegation = try PropositionExpression.not(negativeSubject)
        let result = try YesNoQuestion(negativeSubject).answer(in: source)

        XCTAssertEqual(result.answer, .no)
        XCTAssertEqual(result.subjectValuation.expression, negativeSubject)
        XCTAssertEqual(result.subjectValuation.truth, .fails)
        guard let established = result.establishedAnswer else {
            return XCTFail("determinate no 必須有自己的 established valuation")
        }
        XCTAssertEqual(established.expression, doubleNegation)
        XCTAssertEqual(established.valuation.truth, .holds)
        XCTAssertEqual(established.valuation.context, result.subjectValuation.context)
        XCTAssertEqual(established.valuation.trace.kind, .not)
        XCTAssertEqual(established.valuation.trace.conclusion, .holds)
        let operand = try XCTUnwrap(established.valuation.trace.children.first)
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
        XCTAssertEqual(fact.expression, doubleNegation)
        XCTAssertEqual(fact.valuation, established.valuation)
    }

    // Production mutation caught: unknown is given a fabricated expression that callers can assert.
    func testUndeterminedAnswerHasNoEstablishedExpression() throws {
        let source = try context(authors: [])
        let result = try YesNoQuestion(atom.asExpression()).answer(in: source)

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
        let expression = try atom.asExpression()
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

    // Production mutation caught: malformed atom 繞過 opaque factory，或 adjudication 只比較 atoms。
    func testFactoryRejectsMalformedNestedExpressionAndAdjudicationUsesStructuralIdentity() throws {
        let source = try context()
        let p = try atom.asExpression()
        let holds = try p.evaluate(in: source)
        let malformed = Proposition.authored(
            person: .key("Not A Key"),
            work: .key(workKey)
        )

        XCTAssertThrowsError(try PropositionExpression.not(malformed.asExpression())) {
            XCTAssertEqual($0 as? PropositionError, .malformedKey("Not A Key"))
        }

        let notP = try PropositionExpression.not(p)
        let negatedAssertion = Assertion(
            expression: notP,
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
                .expressionMismatch(assertion: notP, valuation: p),
                "expression mismatch 必須先於 denied stance"
            )
        }
    }
}
