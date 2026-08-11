import Foundation
import XCTest
import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicProposition

/// #213 canonical author-list completeness witness 到命題語意的承重整合測試。
///
/// Core／StoreIO 單元測試已固定 fingerprint、closed provenance 與 YAML；本檔只測
/// PropositionModel 邊界、open-world precedence、trace 與負向 fact 的端到端連接。
final class AuthorshipCompletenessPropositionTests: XCTestCase {
    private let personKey = "target-person"
    private let workKey = "target2026work"
    private let workID = UUID(uuidString: "8B5C44D1-74B8-48F2-AAD9-000000000213")!
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    private var snapshotID: StoreSnapshotID {
        StoreSnapshotID(
            store: StoreIdentity(
                uuid: UUID(uuidString: "A329BF70-0A32-47B3-A15F-000000000213")!
            ),
            revision: StoreRevision(
                digest: "sha256:0000000000000000000000000000000000000000000000000000000000000213"
            )
        )
    }

    private var references: [ProvenanceReference] {
        [
            ProvenanceReference(
                field: "authors",
                kind: .retrieval(
                    url: "https://example.test/complete-author-list",
                    retrieved: "2026-08-10",
                    status: 200,
                    mediaType: "text/html",
                    content: digest
                )
            ),
            ProvenanceReference(
                field: "authors",
                kind: .judgement(
                    statement: "The source enumerates the complete author list.",
                    restsOn: [digest]
                )
            ),
        ]
    }

    private var atom: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    private func witness(
        workID: UUID,
        authors: [AkashicCore.Author]
    ) throws -> AuthorListCompletenessWitness {
        try AuthorListCompletenessWitness(
            workID: workID,
            fingerprint: AuthorListFingerprint(authors: authors),
            attestedAuthors: authors,
            references: references
        )
    }

    private func entry(
        citekey: String = "target2026work",
        id: UUID? = nil,
        authors: [AkashicCore.Author],
        witnessWorkID: UUID? = nil,
        witnessAuthors: [AkashicCore.Author]? = nil,
        witnessed: Bool = false
    ) throws -> Entry {
        let resolvedID = id ?? workID
        let completeness: AuthorListCompletenessWitness?
        if witnessed || witnessWorkID != nil || witnessAuthors != nil {
            completeness = try witness(
                workID: witnessWorkID ?? resolvedID,
                authors: witnessAuthors ?? authors
            )
        } else {
            completeness = nil
        }
        return Entry(
            id: resolvedID,
            citekey: citekey,
            type: "article",
            title: "T",
            authors: authors,
            date: "2026",
            akashic: AkashicMeta(authorListCompleteness: completeness)
        )
    }

    private func rawModel(
        entries: [Entry],
        people: [Person]? = nil,
        organizations: [Organization] = []
    ) throws -> PropositionModel {
        try PropositionModel(
            snapshotID: snapshotID,
            entries: entries,
            people: people ?? [
                Person(key: personKey, names: ["Target Person", "目標人物"]),
            ],
            organizations: organizations
        )
    }

    private func context(
        authors: [AkashicCore.Author],
        witnessed: Bool
    ) throws -> ValuationContext {
        try rawModel(entries: [
            entry(authors: authors, witnessed: witnessed),
        ]).context(validAt: ValidDay("2026-08-10"))
    }

    private func modelError(
        entries: [Entry],
        people: [Person]? = nil
    ) -> PropositionModelValidationError? {
        do {
            _ = try rawModel(entries: entries, people: people)
            return nil
        } catch {
            return error as? PropositionModelValidationError
        }
    }

    /// 會抓到的回歸：programmatic Entry 繞過 YAML binding，或只回報第一筆 stale
    /// witness，讓 input order 改變 machine-readable refusal。
    func testModelRejectsAndAggregatesStaleWitnessBindingsDeterministically() throws {
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let wrongID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let first = try entry(
            citekey: "a2026work",
            id: firstID,
            authors: [.key("other-a")],
            witnessWorkID: wrongID
        )
        let second = try entry(
            citekey: "b2026work",
            id: secondID,
            authors: [.key("other-b")],
            witnessAuthors: [.key("different-author")]
        )

        let forward = modelError(entries: [first, second])
        let reverse = modelError(entries: [second, first])

        XCTAssertNotNil(forward, "兩筆 stale witness 必須在 model 邊界 fail closed")
        XCTAssertEqual(forward, reverse, "聚合 payload 不得依賴輸入排列")
        XCTAssertEqual(
            forward?.authorListCompletenessBindingIssues,
            [
                PropositionModelAuthorListCompletenessIssue(
                    entryCitekey: "a2026work",
                    entryID: firstID,
                    issue: .workID(witness: wrongID, current: firstID)
                ),
                PropositionModelAuthorListCompletenessIssue(
                    entryCitekey: "b2026work",
                    entryID: secondID,
                    issue: .authorSnapshot(
                        attested: AuthorListFingerprint(
                            authors: [.key("different-author")]
                        ),
                        current: AuthorListFingerprint(authors: [.key("other-b")])
                    )
                ),
            ],
            "typed payload 必須完整定位每筆 Entry 與每個 Core binding issue"
        )
    }

    /// 會抓到的回歸：duplicate guard 先 throw，導致同一批輸入的 stale witness 從
    /// aggregate payload 消失。
    func testDuplicateAndStaleWitnessProblemsAreReportedTogether() throws {
        let currentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let wrongID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let stale = try entry(
            citekey: "c2026work",
            id: currentID,
            authors: [.key("other-c")],
            witnessWorkID: wrongID
        )
        let duplicatePeople = [
            Person(key: personKey, names: ["First"]),
            Person(key: personKey, names: ["Second"]),
        ]

        let error = modelError(entries: [stale], people: duplicatePeople)

        XCTAssertEqual(error?.duplicatePersonKeys, [personKey])
        XCTAssertEqual(error?.authorListCompletenessBindingIssues.count, 1)
    }

    /// 會抓到的回歸：absence 被當成 false、literal 被字面差異當成反證、或 valid
    /// witness 壓過直接正面 key／matching literal。
    func testAuthoredUsesFixedOpenWorldPrecedence() throws {
        struct Example {
            let authors: [AkashicCore.Author]
            let witnessed: Bool
            let expected: TruthValue
        }
        let examples: [Example] = [
            Example(
                authors: [.literal("Unknown"), .key(personKey)],
                witnessed: true,
                expected: .holds
            ),
            Example(
                authors: [.literal("Someone Else"), .literal("Target Person")],
                witnessed: true,
                expected: .undetermined(
                    .supportingEvidenceUnresolved(literal: "Target Person")
                )
            ),
            Example(
                authors: [.literal("Someone Else")],
                witnessed: true,
                expected: .undetermined(
                    .authorIdentityUnresolved(literal: "Someone Else")
                )
            ),
            Example(
                authors: [.key("other-person")],
                witnessed: false,
                expected: .undetermined(.noSupportingEvidence)
            ),
            Example(
                authors: [.key("other-person")],
                witnessed: true,
                expected: .fails
            ),
            Example(
                authors: [],
                witnessed: false,
                expected: .undetermined(.noSupportingEvidence)
            ),
            Example(authors: [], witnessed: true, expected: .fails),
        ]

        for example in examples {
            let valuation = try atom.asExpression().evaluate(
                in: context(authors: example.authors, witnessed: example.witnessed)
            )
            XCTAssertEqual(
                valuation.truth,
                example.expected,
                "authors=\(example.authors), witnessed=\(example.witnessed)"
            )
        }
    }

    /// 會抓到的回歸：把 authored 的 completeness gate 誤套到沒有完備性證言的
    /// affiliated predicate，讓 affiliation absence 變成 false。
    func testAffiliatedAbsenceRemainsUndeterminedWithoutItsOwnCompletenessWitness() throws {
        let organizationKey = "example-institute"
        let model = try rawModel(
            entries: [],
            organizations: [Organization(key: organizationKey)]
        )
        let expression = try Proposition.affiliated(
            person: .key(personKey),
            organization: .key(organizationKey)
        ).asExpression()

        let valuation = try expression.evaluate(
            in: model.context(validAt: ValidDay("2026-08-10"))
        )

        XCTAssertEqual(valuation.truth, .undetermined(.noSupportingEvidence))
        XCTAssertNotEqual(valuation.truth, .fails)
    }

    /// 會抓到的回歸：evaluator 只保留逐槽 `.doesNotSupport`，卻沒有把真正授權
    /// closed-world 排除的 exact witness 帶入 atomic trace。
    func testWitnessBackedFailureTraceRetainsAllSlotsAndWitness() throws {
        let authors: [AkashicCore.Author] = [
            .key("other-a"),
            .key("other-b"),
        ]
        let valuation = try atom.asExpression().evaluate(
            in: context(authors: authors, witnessed: true)
        )

        XCTAssertEqual(valuation.truth, .fails)
        XCTAssertEqual(valuation.trace.conclusion, .fails)
        XCTAssertEqual(
            try XCTUnwrap(valuation.trace.atomicEvidence).evidence,
            [
                .authorSlot(slot: .key("other-a"), assessment: .doesNotSupport),
                .authorSlot(slot: .key("other-b"), assessment: .doesNotSupport),
                .authorListCompleteness(
                    witness: try witness(workID: workID, authors: authors)
                ),
            ],
            "trace 必須保留全部 slots 與真正授權排除的 exact witness"
        )
    }

    /// 會抓到的回歸：positive support 或 unresolved literal 分支提早 return，因而把
    /// snapshot 中存在的 completeness witness 從 trace 丟掉。
    func testPositiveAndLiteralPrecedenceStillRetainWitnessEvidence() throws {
        let supportedAuthors: [AkashicCore.Author] = [
            .literal("Unknown"),
            .key(personKey),
        ]
        let supported = try atom.asExpression().evaluate(
            in: context(authors: supportedAuthors, witnessed: true)
        )
        XCTAssertEqual(supported.truth, .holds)
        XCTAssertEqual(
            try XCTUnwrap(supported.trace.atomicEvidence).evidence.last,
            .authorListCompleteness(
                witness: try witness(workID: workID, authors: supportedAuthors)
            )
        )

        let literalAuthors: [AkashicCore.Author] = [.literal("Someone Else")]
        let unresolved = try atom.asExpression().evaluate(
            in: context(authors: literalAuthors, witnessed: true)
        )
        XCTAssertEqual(
            try XCTUnwrap(unresolved.trace.atomicEvidence).evidence,
            [
                .authorSlot(
                    slot: .literal("Someone Else"),
                    assessment: .identityUnresolved
                ),
                .authorListCompleteness(
                    witness: try witness(workID: workID, authors: literalAuthors)
                ),
            ]
        )
    }

    /// 會抓到的回歸：為限制人讀訊息而截斷 machine payload，或 default reflection
    /// 洩漏 witness 的 URL／judgement。
    func testBindingDiagnosticsAreCompleteDeterministicAndBounded() throws {
        let wrongID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let entries = try (0..<12).map { index in
            try entry(
                citekey: "work-\(index)",
                id: UUID(),
                authors: [.key("other-\(index)")],
                witnessWorkID: wrongID
            )
        }
        let forward = try XCTUnwrap(modelError(entries: entries))
        let reverse = try XCTUnwrap(modelError(entries: Array(entries.reversed())))

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.authorListCompletenessBindingIssues.count, 12)
        let generic: any Error = forward
        let renderings = [
            forward.localizedDescription,
            String(describing: generic),
            String(reflecting: generic),
        ]
        for rendered in renderings {
            XCTAssertLessThanOrEqual(rendered.unicodeScalars.count, 2_000)
            XCTAssertFalse(rendered.contains("https://example.test"))
            XCTAssertFalse(rendered.contains("enumerates the complete author list"))
        }
        XCTAssertEqual(renderings[0], renderings[1])
        XCTAssertEqual(renderings[1], renderings[2])
    }

    /// 會抓到的回歸：no 只帶 label、沿用 subject/fails valuation，或裁決時重新求值
    /// 而遺失 witness-backed operand trace。
    func testCanonicalWitnessProducesNoAndExactNegativeFact() throws {
        let entry = try entry(
            authors: [.key("other-person")],
            witnessed: true
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-proposition-witness-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(entry)
        try store.writePerson(Person(key: personKey, names: ["Target Person"]))

        let snapshot = try store.loadSnapshot()
        let model = try PropositionModel(snapshot: snapshot)
        let atomExpression = try atom.asExpression()
        let negativeExpression = try PropositionExpression.not(atomExpression)
        let question = try YesNoQuestion(atomExpression)
        let result = try question.answer(
            in: model.context(validAt: ValidDay("2026-08-10"))
        )

        XCTAssertEqual(result.answer, .no)
        XCTAssertEqual(result.subjectValuation.truth, .fails)
        let established = try XCTUnwrap(result.establishedAnswer)
        XCTAssertEqual(established.expression, negativeExpression)
        XCTAssertEqual(established.valuation.truth, .holds)
        XCTAssertEqual(established.valuation.trace.conclusion, .holds)
        XCTAssertEqual(established.valuation.context, result.subjectValuation.context)
        XCTAssertEqual(established.valuation.trace.kind, .not)
        XCTAssertEqual(established.valuation.trace.children, [result.subjectValuation.trace])

        let failedPositiveAssertion = Assertion(
            expression: atomExpression,
            stance: .asserted,
            source: "reviewer",
            recorded: try RecordedTime("2026-08-10")
        )
        XCTAssertThrowsError(
            try adjudicate(
                failedPositiveAssertion,
                valuation: result.subjectValuation,
                acceptedBy: "curator",
                acceptedAt: try AcceptedTime("2026-08-10")
            )
        ) { error in
            XCTAssertEqual(
                error as? AdjudicationRefusal,
                .notEstablished(result.subjectValuation)
            )
        }

        let assertion = Assertion(
            expression: established.expression,
            stance: .asserted,
            source: "reviewer",
            recorded: try RecordedTime("2026-08-10")
        )
        let fact = try adjudicate(
            assertion,
            valuation: established.valuation,
            acceptedBy: "curator",
            acceptedAt: try AcceptedTime("2026-08-10")
        )
        XCTAssertEqual(fact.expression, negativeExpression)
        XCTAssertEqual(fact.valuation, established.valuation)
        XCTAssertEqual(fact.valuation.trace.children, [result.subjectValuation.trace])
    }
}
