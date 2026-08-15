import Foundation
import XCTest
import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicProposition

/// #202 的 snapshot-bound context／trace vertical slice。
///
/// 每一個 snapshot 都走真實的 `LibraryStore.loadSnapshot()`；如此測到的是
/// StoreIO → Proposition 的公開邊界，不是測試自行拼裝出來的替身。
final class ContextValuationTests: XCTestCase {

    private let personKey = "cheng-che"
    private let workKey = "cheng2025identifiability"
    private let organizationKey = "academia-sinica"

    private func entry(
        citekey: String = "cheng2025identifiability",
        authors: [AkashicCore.Author] = [],
        id: UUID = UUID()
    ) -> Entry {
        Entry(id: id, citekey: citekey, type: "article", title: "T",
              authors: authors, date: "2026")
    }

    private func person(
        key: String = "cheng-che",
        names: [String] = ["Che Cheng", "鄭澈"],
        affiliations: [TemporalValue<OrgRef>] = [],
        id: UUID = UUID()
    ) -> Person {
        Person(key: key, names: PersonNames(variant: names), id: id,
               profile: PersonProfile(affiliations: TimelineOf(affiliations)))
    }

    private func organization(
        key: String = "academia-sinica",
        parents: [TemporalValue<OrgRef>] = [],
        id: UUID = UUID()
    ) -> Organization {
        Organization(
            key: key,
            names: TimelineOf([TemporalValue(value: "中央研究院")]),
            parents: TimelineOf(parents),
            id: id
        )
    }

    private func snapshot(
        entries: [Entry],
        people: [Person],
        organizations: [Organization] = [],
        addQuarantinedYAML: Bool = false
    ) throws -> LibrarySnapshot {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-proposition-context-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(root: root)
        try store.ensureLayout()
        for value in entries { try store.writeEntry(value) }
        for value in people { try store.writePerson(value) }
        for value in organizations { try store.writeOrganization(value) }
        if addQuarantinedYAML {
            let malformedFixtures = [
                ("A03D48F4-4EF5-4D5B-A892-2B1B3048B4F0.yaml", "person: [unterminated\n"),
                ("F03D48F4-4EF5-4D5B-A892-2B1B3048B4F0.yaml", "entry: {unterminated\n"),
            ]
            for (name, contents) in malformedFixtures {
                try contents.write(
                    to: store.entitiesDir.appendingPathComponent(name),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
        return try store.loadSnapshot()
    }

    /// 只用於測 in-memory 公開 Core shape 可表達、但 canonical YAML 邊界會拒絕的
    /// temporal 矛盾；snapshot identity 仍是 StoreIO internal factory 所建立。
    private func assembledSnapshot(
        entries: [Entry],
        people: [Person],
        organizations: [Organization] = []
    ) -> LibrarySnapshot {
        LibrarySnapshot(
            id: StoreSnapshotID(
                store: StoreIdentity(
                    uuid: UUID(uuidString: "F8CC727B-94F1-4F37-9C1C-000000000202")!
                ),
                revision: StoreRevision(
                    digest: "sha256:0000000000000000000000000000000000000000000000000000000000000202"
                )
            ),
            load: LibraryLoad(
                entries: entries,
                people: people,
                organizations: organizations
            )
        )
    }

    private func authoredSnapshot(
        authorSlots: [AkashicCore.Author],
        addQuarantinedYAML: Bool = false
    ) throws -> LibrarySnapshot {
        try snapshot(
            entries: [entry(citekey: workKey, authors: authorSlots)],
            people: [person(key: personKey)],
            addQuarantinedYAML: addQuarantinedYAML
        )
    }

    private func authoredSnapshotsBeforeAndAfterCanonicalMutation() throws
        -> (before: LibrarySnapshot, after: LibrarySnapshot)
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-proposition-revision-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let id = UUID(uuidString: "89FDE318-E4DE-46B6-8CA8-5539171991AA")!
        try store.writePerson(person(key: personKey))
        try store.writeEntry(entry(citekey: workKey, authors: [.key(personKey)], id: id))
        let before = try store.loadSnapshot()

        var changed = entry(citekey: workKey, authors: [.key(personKey)], id: id)
        changed.title = "同一命題之外的 canonical 內容變更"
        try store.writeEntry(changed)
        let after = try store.loadSnapshot()
        return (before, after)
    }

    private var authored: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    private var affiliated: Proposition {
        .affiliated(person: .key(personKey), organization: .key(organizationKey))
    }

    private func day(_ raw: String) throws -> ValidDay { try ValidDay(raw) }

    // 可攔截的 production mutation：接受前綴日期或不存在的格里曆日。
    func testRecordedAndAcceptedTimesRequireRealASCIIGregorianDays() throws {
        XCTAssertEqual(try RecordedTime("2024-02-29").rawValue, "2024-02-29")
        XCTAssertEqual(try AcceptedTime("2024-02-29").rawValue, "2024-02-29")

        for invalid in ["2023-02-29", "2026-08", "2026", "２０２６-０８-０９"] {
            XCTAssertThrowsError(try RecordedTime(invalid), "recorded=\(invalid)")
            XCTAssertThrowsError(try AcceptedTime(invalid), "accepted=\(invalid)")
        }
    }

    // 可攔截的 production mutation：typed time error 反射被拒的 caller-controlled value。
    func testTimeErrorInterpolationIsBoundedAndDoesNotReflectRejectedInput() {
        let injected = "2026-08-09\u{202E}" + String(repeating: "x", count: 2_000)
        XCTAssertThrowsError(try RecordedTime(injected)) { error in
            guard let typed = error as? PropositionTimeValidationError else {
                return XCTFail("必須保留 typed time error")
            }
            let generic: any Error = typed
            for message in [String(describing: generic), String(reflecting: generic)] {
                XCTAssertEqual(message, typed.localizedDescription)
                XCTAssertFalse(message.contains("\u{202E}"))
                XCTAssertLessThan(message.count, 300)
            }
        }
    }

    // 可攔截的 production mutation：context 丟失 snapshot ID／day，或 evaluate 重建輸出。
    func testContextBindsSnapshotAndValidDayAndReplayIsExactlyEqual() throws {
        let source = try authoredSnapshot(
            authorSlots: [.key(personKey)],
            addQuarantinedYAML: true
        )
        let model = try PropositionModel(snapshot: source)
        let context = model.context(validAt: try day("2026-08-09"))
        let first = try authored.evaluate(in: context)
        let replay = try authored.evaluate(in: context)
        let firstAtomic = try XCTUnwrap(first.trace.atomicEvidence)

        XCTAssertEqual(context.snapshotID, source.id)
        XCTAssertEqual(context.validAt.rawValue, "2026-08-09")
        XCTAssertEqual(first, replay)
        XCTAssertEqual(
            firstAtomic.projection,
            .authored(personKey: personKey, workKey: workKey)
        )
        XCTAssertTrue(firstAtomic.evidence.contains(
            .authorSlot(slot: .key(personKey), assessment: .supports)
        ))
        XCTAssertEqual(source.load.quarantined.count, 2)
        XCTAssertEqual(firstAtomic.snapshotQuarantine, source.load.quarantined)
        XCTAssertEqual(first.trace.conclusion, first.truth)
    }

    // 可攔截的 production mutation：revision 固定不變，或 valuation equality 忽略 snapshot 內容。
    func testCanonicalMutationInOneStoreCreatesDistinctContextAndValuation() throws {
        let snapshots = try authoredSnapshotsBeforeAndAfterCanonicalMutation()
        XCTAssertEqual(snapshots.before.id.store, snapshots.after.id.store)
        XCTAssertNotEqual(snapshots.before.id.revision, snapshots.after.id.revision)

        let validAt = try day("2026-08-09")
        let before = try authored.evaluate(
            in: PropositionModel(snapshot: snapshots.before).context(validAt: validAt)
        )
        let after = try authored.evaluate(
            in: PropositionModel(snapshot: snapshots.after).context(validAt: validAt)
        )
        XCTAssertEqual(before.truth, .holds)
        XCTAssertEqual(after.truth, .holds)
        XCTAssertNotEqual(before.context, after.context)
        XCTAssertNotEqual(before, after)
    }

    // 可攔截的 production mutation：authored 誤解讀 validAt timeline，或丟失 caller 指定日。
    func testAuthoredChangingValidDayOnlyChangesContext() throws {
        let model = try PropositionModel(
            snapshot: authoredSnapshot(authorSlots: [.key(personKey)])
        )
        let early = try authored.evaluate(in: model.context(validAt: day("2001-01-01")))
        let late = try authored.evaluate(in: model.context(validAt: day("2026-08-09")))

        XCTAssertEqual(early.truth, .holds)
        XCTAssertEqual(late.truth, .holds)
        XCTAssertNotEqual(early.context, late.context)
        XCTAssertNotEqual(early.trace, late.trace)
        XCTAssertEqual(early.trace.context, early.context)
        XCTAssertEqual(late.trace.context, late.context)
        XCTAssertEqual(early.trace.atomicEvidence, late.trace.atomicEvidence)
        XCTAssertEqual(
            try XCTUnwrap(early.trace.atomicEvidence).scope,
            .snapshotScopedTimeInvariant
        )
    }

    // 可攔截的 production mutation：affiliation 忽略 validAt、丟失 segment payload 或回 false。
    func testAffiliationUsesValidDayAndRetainsCompleteSupportingSegment() throws {
        let segment = TemporalValue(
            value: OrgRef.key(organizationKey),
            range: DateRange(start: "2020-01-01", end: "2020-12-31"),
            source: "source-digest",
            note: "研究任職"
        )
        let source = try snapshot(
            entries: [],
            people: [person(affiliations: [segment])],
            organizations: [organization()]
        )
        let model = try PropositionModel(snapshot: source)
        let active = try affiliated.evaluate(in: model.context(validAt: day("2020-06-15")))
        let after = try affiliated.evaluate(in: model.context(validAt: day("2021-01-01")))
        let activeAtomic = try XCTUnwrap(active.trace.atomicEvidence)

        XCTAssertEqual(active.truth, .holds)
        XCTAssertEqual(after.truth, .undetermined(.noSupportingEvidence))
        XCTAssertEqual(after.trace.conclusion, after.truth)
        XCTAssertEqual(activeAtomic.scope, .validTimeScoped)
        XCTAssertTrue(activeAtomic.evidence.contains(
            .affiliationSegment(
                segment: segment,
                identity: .resolvedMatch,
                temporal: .definitelyContains
            )
        ))
    }

    // 可攔截的 production mutation：正規化後的機構文字被靜默升格為 identity。
    func testLiteralAffiliationIsAVisibleCandidateButNeverAnIdentityMatch() throws {
        let segment = TemporalValue(
            value: OrgRef.literal("中央研究院"),
            range: DateRange(start: "2020-01-01", end: "2020-12-31"),
            source: "source-digest",
            note: "仍待歸戶"
        )
        let source = try snapshot(
            entries: [],
            people: [person(affiliations: [segment])],
            organizations: [organization()]
        )
        let model = try PropositionModel(snapshot: source)
        let valuation = try affiliated.evaluate(
            in: model.context(validAt: day("2020-06-15"))
        )

        XCTAssertEqual(
            valuation.truth,
            .undetermined(.supportingEvidenceUnresolved(literal: "中央研究院"))
        )
        XCTAssertTrue(try XCTUnwrap(valuation.trace.atomicEvidence).evidence.contains(
            .affiliationSegment(
                segment: segment,
                identity: .unresolvedCandidate,
                temporal: .definitelyContains
            )
        ))
    }

    // 可攔截的 production mutation：未解析 identity 繞過 temporal assessment。
    func testLiteralAffiliationContributesOnlyWhenItsTemporalEvidenceCanSupportTheDay() throws {
        let excluded = TemporalValue(
            value: OrgRef.literal("中央研究院"),
            range: DateRange(start: "2020-01-01", end: "2020-12-31")
        )
        let coarse = TemporalValue(
            value: OrgRef.literal("中央研究院"),
            range: DateRange(start: "2021-06")
        )
        let invalid = TemporalValue(
            value: OrgRef.literal("中央研究院"),
            range: DateRange(start: "2021-01-01", attested: ["2021-06-15"])
        )

        func valuation(
            segment: TemporalValue<OrgRef>,
            validAt: String
        ) throws -> Valuation {
            let source = assembledSnapshot(
                entries: [],
                people: [person(affiliations: [segment])],
                organizations: [organization()]
            )
            return try affiliated.evaluate(
                in: PropositionModel(snapshot: source).context(validAt: day(validAt))
            )
        }

        XCTAssertEqual(
            try valuation(segment: excluded, validAt: "2021-01-01").truth,
            .undetermined(.noSupportingEvidence)
        )
        XCTAssertEqual(
            try valuation(segment: coarse, validAt: "2021-06-15").truth,
            .undetermined(.temporalEvidenceIndeterminate)
        )
        XCTAssertEqual(
            try valuation(segment: invalid, validAt: "2021-06-15").truth,
            .undetermined(.invalidTemporalEvidence)
        )
    }

    // 可攔截的 production mutation：temporal invalidity 被壓成 no-evidence 或 containment。
    func testInvalidAffiliationEvidenceRemainsTypedAndVisible() throws {
        let segment = TemporalValue(
            value: OrgRef.key(organizationKey),
            range: DateRange(start: "2020-01-01", attested: ["2020-06-15"]),
            source: "source-digest",
            note: "矛盾 shape"
        )
        let source = assembledSnapshot(
            entries: [],
            people: [person(affiliations: [segment])],
            organizations: [organization()]
        )
        let model = try PropositionModel(snapshot: source)
        let valuation = try affiliated.evaluate(
            in: model.context(validAt: day("2020-06-15"))
        )

        XCTAssertEqual(valuation.truth, .undetermined(.invalidTemporalEvidence))
        XCTAssertEqual(
            try XCTUnwrap(valuation.trace.atomicEvidence).evidence,
            [
                .affiliationSegment(
                    segment: segment,
                    identity: .resolvedMatch,
                    temporal: .invalidEvidence(.mixedAttestationAndRange)
                )
            ]
        )
    }

    // 可攔截的 production mutation：一筆 invalid segment 蓋掉另一筆確定成立的正面證據。
    func testPositiveAffiliationOverridesOtherInvalidSegmentWithoutDroppingItFromTrace() throws {
        let invalid = TemporalValue(
            value: OrgRef.key(organizationKey),
            range: DateRange(start: "2020-01-01", attested: ["2020-06-15"]),
            source: "invalid-source"
        )
        let supporting = TemporalValue(
            value: OrgRef.key(organizationKey),
            range: DateRange(start: "2020-01-01", end: "2020-12-31"),
            source: "supporting-source"
        )
        let source = assembledSnapshot(
            entries: [],
            people: [person(affiliations: [invalid, supporting])],
            organizations: [organization()]
        )
        let valuation = try affiliated.evaluate(
            in: PropositionModel(snapshot: source)
                .context(validAt: day("2020-06-15"))
        )

        XCTAssertEqual(valuation.truth, .holds)
        let atomicEvidence = try XCTUnwrap(valuation.trace.atomicEvidence)
        XCTAssertEqual(atomicEvidence.evidence.count, 2)
        XCTAssertTrue(atomicEvidence.evidence.contains(
            .affiliationSegment(
                segment: invalid,
                identity: .resolvedMatch,
                temporal: .invalidEvidence(.mixedAttestationAndRange)
            )
        ))
        XCTAssertTrue(atomicEvidence.evidence.contains(
            .affiliationSegment(
                segment: supporting,
                identity: .resolvedMatch,
                temporal: .definitelyContains
            )
        ))
    }

    // 可攔截的 production mutation：粗精度／未知時間原因被攤平或猜成成立。
    func testCoarseAndUnknownTemporalReasonsRemainInTrace() throws {
        let coarse = TemporalValue(
            value: OrgRef.key(organizationKey),
            range: DateRange(start: "2020-06"),
            source: "coarse-source"
        )
        let unknownEnd = TemporalValue(
            value: OrgRef.key(organizationKey),
            range: DateRange(start: "2019-01-01", endedUnknown: true),
            source: "unknown-end-source"
        )
        let source = try snapshot(
            entries: [],
            people: [person(affiliations: [coarse, unknownEnd])],
            organizations: [organization()]
        )
        let valuation = try affiliated.evaluate(
            in: PropositionModel(snapshot: source)
                .context(validAt: day("2020-06-15"))
        )

        XCTAssertEqual(valuation.truth, .undetermined(.temporalEvidenceIndeterminate))
        let atomicEvidence = try XCTUnwrap(valuation.trace.atomicEvidence)
        XCTAssertTrue(atomicEvidence.evidence.contains(
            .affiliationSegment(
                segment: coarse,
                identity: .resolvedMatch,
                temporal: .indeterminate(.impreciseStart)
            )
        ))
        XCTAssertTrue(atomicEvidence.evidence.contains(
            .affiliationSegment(
                segment: unknownEnd,
                identity: .resolvedMatch,
                temporal: .indeterminate(.unknownEnd)
            )
        ))
    }

    // 可攔截的 production mutation：機構上級關係被當成人的 affiliation。
    func testOrganizationContainmentCannotEstablishPersonAffiliation() throws {
        let child = organization(
            key: "statistics-institute",
            parents: [TemporalValue(value: .key(organizationKey))]
        )
        let source = try snapshot(
            entries: [],
            people: [person(affiliations: [
                TemporalValue(value: .key("statistics-institute"),
                              range: DateRange(start: "2020-01-01"))
            ])],
            organizations: [organization(), child]
        )
        let model = try PropositionModel(snapshot: source)

        XCTAssertEqual(
            try affiliated.evaluate(
                in: model.context(validAt: day("2026-08-09"))
            ).truth,
            .undetermined(.noSupportingEvidence)
        )
    }

    // 可攔截的 production mutation：role-direction 檢查漏掉第三種 entity kind。
    func testAffiliationProjectionDiagnosesWrongEntityKinds() throws {
        let source = try snapshot(
            entries: [entry(citekey: workKey)],
            people: [person(key: personKey)],
            organizations: [organization()]
        )
        let context = try PropositionModel(snapshot: source)
            .context(validAt: day("2026-08-09"))

        XCTAssertEqual(
            try Proposition.affiliated(person: .key(workKey),
                                       organization: .key(organizationKey))
                .project(in: context),
            .unprojectable(.wrongEntityKind(role: "person", key: workKey,
                                            expected: "person"))
        )
        XCTAssertEqual(
            try Proposition.affiliated(person: .key(personKey),
                                       organization: .key(workKey))
                .project(in: context),
            .unprojectable(.wrongEntityKind(role: "organization", key: workKey,
                                            expected: "organization"))
        )
    }

    // 可攔截的 production mutation：任一 role 靜默強轉 literal／unknown／wrong kind。
    func testEveryProjectionRolePreservesLiteralUnknownAndWrongKindReasons() throws {
        let source = try snapshot(
            entries: [entry(citekey: workKey)],
            people: [person(key: personKey)],
            organizations: [organization()]
        )
        let context = try PropositionModel(snapshot: source)
            .context(validAt: day("2026-08-09"))

        let literalCases: [(Proposition, UnprojectableReason)] = [
            (
                .authored(person: .literal("P"), work: .key(workKey)),
                .unresolvedSymbol(role: "person", literal: "P")
            ),
            (
                .authored(person: .key(personKey), work: .literal("W")),
                .unresolvedSymbol(role: "work", literal: "W")
            ),
            (
                .affiliated(person: .key(personKey), organization: .literal("O")),
                .unresolvedSymbol(role: "organization", literal: "O")
            ),
        ]
        let unknownCases: [(Proposition, UnprojectableReason)] = [
            (
                .authored(person: .key("unknown-person"), work: .key(workKey)),
                .unknownIdentity(role: "person", key: "unknown-person")
            ),
            (
                .authored(person: .key(personKey), work: .key("unknown-work")),
                .unknownIdentity(role: "work", key: "unknown-work")
            ),
            (
                .affiliated(person: .key(personKey), organization: .key("unknown-org")),
                .unknownIdentity(role: "organization", key: "unknown-org")
            ),
        ]
        let wrongKindCases: [(Proposition, UnprojectableReason)] = [
            (
                .authored(person: .key(workKey), work: .key(workKey)),
                .wrongEntityKind(role: "person", key: workKey, expected: "person")
            ),
            (
                .authored(person: .key(personKey), work: .key(organizationKey)),
                .wrongEntityKind(role: "work", key: organizationKey, expected: "work")
            ),
            (
                .affiliated(person: .key(personKey), organization: .key(workKey)),
                .wrongEntityKind(role: "organization", key: workKey,
                                 expected: "organization")
            ),
        ]

        for (proposition, expected) in literalCases + unknownCases + wrongKindCases {
            XCTAssertEqual(try proposition.project(in: context), .unprojectable(expected))
        }
    }

    // 可攔截的 production mutation：answer／fact 新建 valuation 或丟失 audit context。
    func testAnswerAndFactPreserveTheExactOriginatingValuationAndThreeTimeRoles() throws {
        let context = try PropositionModel(
            snapshot: authoredSnapshot(authorSlots: [.key(personKey)],
                                        addQuarantinedYAML: true)
        ).context(validAt: day("2020-01-01"))
        let authoredExpression = try authored.asExpression()
        let result = try YesNoQuestion(authoredExpression).answer(in: context)
        let assertion = Assertion(
            expression: authoredExpression,
            stance: .asserted,
            source: "conversation",
            recorded: try RecordedTime("2026-08-08")
        )
        let fact = try adjudicate(
            assertion,
            valuation: result.subjectValuation,
            acceptedBy: "che",
            acceptedAt: try AcceptedTime("2026-08-09")
        )

        XCTAssertEqual(result.answer, .yes)
        XCTAssertEqual(result.subjectValuation, try authored.evaluate(in: context))
        XCTAssertEqual(fact.valuation, result.subjectValuation)
        XCTAssertEqual(fact.basis.recorded.rawValue, "2026-08-08")
        XCTAssertEqual(fact.valuation.context.validAt.rawValue, "2020-01-01")
        XCTAssertEqual(fact.acceptedAt.rawValue, "2026-08-09")
        XCTAssertFalse(
            try XCTUnwrap(fact.valuation.trace.atomicEvidence).snapshotQuarantine.isEmpty
        )
    }

    // 可攔截的 production mutation：先檢 stance／truth，後檢 proposition identity。
    func testAdjudicationMismatchPrecedesStanceAndTruth() throws {
        let context = try PropositionModel(
            snapshot: authoredSnapshot(authorSlots: [])
        ).context(validAt: day("2026-08-09"))
        let valuation = try authored.evaluate(in: context)
        let other = Proposition.authored(person: .key("somebody-else"),
                                         work: .key(workKey))
        let otherExpression = try other.asExpression()
        let authoredExpression = try authored.asExpression()
        let assertion = Assertion(
            expression: otherExpression,
            stance: .denied,
            source: "conversation",
            recorded: try RecordedTime("2026-08-08")
        )

        XCTAssertThrowsError(try adjudicate(
            assertion,
            valuation: valuation,
            acceptedBy: "che",
            acceptedAt: AcceptedTime("2026-08-09")
        )) { error in
            XCTAssertEqual(
                error as? AdjudicationRefusal,
                .expressionMismatch(
                    assertion: otherExpression,
                    valuation: authoredExpression
                )
            )
        }
    }

    // 可攔截的 production mutation：Error 插值反射 proposition／trace associated value。
    func testAdjudicationErrorInterpolationDoesNotReflectTypedPayloads() throws {
        let context = try PropositionModel(
            snapshot: authoredSnapshot(authorSlots: [.literal("Eve\u{202E}payload")])
        ).context(validAt: day("2026-08-09"))
        let valuation = try authored.evaluate(in: context)
        let injected = Proposition.authored(
            person: .literal("caller\u{001B}[31m"),
            work: .key(workKey)
        )
        let assertion = Assertion(
            expression: try injected.asExpression(),
            stance: .asserted,
            source: "conversation",
            recorded: try RecordedTime("2026-08-08")
        )

        XCTAssertThrowsError(try adjudicate(
            assertion,
            valuation: valuation,
            acceptedBy: "che",
            acceptedAt: AcceptedTime("2026-08-09")
        )) { error in
            guard let refusal = error as? AdjudicationRefusal else {
                return XCTFail("必須保留 typed adjudication refusal")
            }
            let generic: any Error = refusal
            for message in [String(describing: generic), String(reflecting: generic)] {
                XCTAssertEqual(message, refusal.localizedDescription)
                XCTAssertFalse(message.contains("\u{001B}"))
                XCTAssertFalse(message.contains("\u{202E}"))
                XCTAssertLessThan(message.count, 300)
            }
        }

        let matchingAssertion = Assertion(
            expression: try authored.asExpression(),
            stance: .asserted,
            source: "conversation",
            recorded: try RecordedTime("2026-08-08")
        )
        XCTAssertThrowsError(try adjudicate(
            matchingAssertion,
            valuation: valuation,
            acceptedBy: "che",
            acceptedAt: AcceptedTime("2026-08-09")
        )) { error in
            guard let refusal = error as? AdjudicationRefusal else {
                return XCTFail("必須保留 typed notEstablished refusal")
            }
            let generic: any Error = refusal
            for message in [String(describing: generic), String(reflecting: generic)] {
                XCTAssertEqual(message, refusal.localizedDescription)
                XCTAssertFalse(message.contains("\u{202E}"))
                XCTAssertLessThan(message.count, 300)
            }
        }
    }

    // 可攔截的 production mutation：refusal 只保存裸 TruthValue。
    func testNotEstablishedRefusalCarriesTheCompleteValuation() throws {
        let context = try PropositionModel(
            snapshot: authoredSnapshot(authorSlots: [])
        ).context(validAt: day("2026-08-09"))
        let valuation = try authored.evaluate(in: context)
        let assertion = Assertion(
            expression: try authored.asExpression(),
            stance: .asserted,
            source: "conversation",
            recorded: try RecordedTime("2026-08-08")
        )

        XCTAssertThrowsError(try adjudicate(
            assertion,
            valuation: valuation,
            acceptedBy: "che",
            acceptedAt: AcceptedTime("2026-08-09")
        )) { error in
            XCTAssertEqual(error as? AdjudicationRefusal, .notEstablished(valuation))
        }
    }

    // 可攔截的 production mutation：organization key 繞過聚合 duplicate guard。
    func testSnapshotModelRejectsEntryPersonAndOrganizationDuplicatesTogether() throws {
        let source = try snapshot(
            entries: [
                entry(citekey: "work-a", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
                entry(citekey: "work-a", id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
            ],
            people: [
                person(key: "person-a", id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
                person(key: "person-a", id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!),
            ],
            organizations: [
                organization(key: "org-a", id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!),
                organization(key: "org-a", id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!),
            ]
        )

        XCTAssertThrowsError(try PropositionModel(snapshot: source)) { error in
            guard let validation = error as? PropositionModelValidationError else {
                return XCTFail("三類重複鍵必須聚合為 typed model error：\(error)")
            }
            XCTAssertEqual(validation.duplicateEntryCitekeys, ["work-a"])
            XCTAssertEqual(validation.duplicatePersonKeys, ["person-a"])
            XCTAssertEqual(validation.duplicateOrganizationKeys, ["org-a"])
        }
    }
}
