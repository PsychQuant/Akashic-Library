import XCTest
import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicProposition

/// #198／#199／#200 的 vertical slice。
///
/// 這一層要守的不是「查得對」，是**「查不到不等於為假」**——所有測試都繞著
/// 那條線。
final class PropositionTests: XCTestCase {

    // MARK: - Fixture

    private let personKey = "cheng-che"
    private let workKey = "cheng2025identifiability"

    private var testSnapshotID: StoreSnapshotID {
        StoreSnapshotID(
            store: StoreIdentity(
                uuid: UUID(uuidString: "2F56038A-425D-40D8-8833-000000000202")!
            ),
            revision: StoreRevision(
                digest: "sha256:0000000000000000000000000000000000000000000000000000000000000202"
            )
        )
    }

    private func rawModel(
        entries: [Entry],
        people: [Person],
        organizations: [Organization] = []
    ) throws -> PropositionModel {
        try PropositionModel(
            snapshotID: testSnapshotID,
            entries: entries,
            people: people,
            organizations: organizations
        )
    }

    private func model(authorSlots: [AkashicCore.Author],
                       personNames: [String] = ["Che Cheng", "鄭澈"]) throws -> ValuationContext {
        var e = Entry(id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-0000000002A1")!,
                      citekey: workKey, type: "article", title: "T",
                      authors: authorSlots, date: "2025")
        e.fields = [:]
        return try rawModel(
            entries: [e],
            people: [Person(key: personKey, names: personNames)]
        ).context(validAt: ValidDay("2026-08-09"))
    }

    private var authored: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    private func entry(citekey: String, authors: [AkashicCore.Author] = []) -> Entry {
        Entry(id: UUID(), citekey: citekey, type: "article", title: "T",
              authors: authors, date: "2026")
    }

    private func person(key: String) -> Person {
        Person(key: key, names: [key])
    }

    private func capturedModelError(
        entries: [Entry],
        people: [Person],
        organizations: [Organization] = []
    ) -> PropositionModelValidationError? {
        do {
            _ = try rawModel(
                entries: entries,
                people: people,
                organizations: organizations
            )
            return nil
        } catch {
            return error as? PropositionModelValidationError
        }
    }

    private func assertPropositionError<T>(
        _ expected: PropositionError,
        _ operation: () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? PropositionError, expected, file: file, line: line)
        }
    }

    // MARK: - #198 構造驗證

    func testMalformedKeyIsRejectedAtConstruction() {
        XCTAssertThrowsError(try Proposition.makeAuthored(
            person: .key("Not A Key"), work: .key(workKey))) { e in
            XCTAssertEqual(e as? PropositionError, .malformedKey("Not A Key"))
        }
    }

    func testMalformedKeyErrorRenderingIsBoundedAndSanitized() {
        let rawKey = "Not-A-Key\u{202E}" + String(repeating: "x", count: 2_000)

        XCTAssertThrowsError(try Proposition.makeAuthored(
            person: .key(rawKey), work: .key(workKey))) { error in
            guard let propositionError = error as? PropositionError else {
                return XCTFail("必須保留 PropositionError typed payload")
            }
            let genericError: any Error = propositionError
            for message in [String(describing: genericError), String(reflecting: genericError)] {
                XCTAssertEqual(message, propositionError.localizedDescription,
                               "一般與 debug 錯誤顯示都必須走有界、已消毒的摘要")
                XCTAssertFalse(message.contains("\u{202E}"),
                               "預設錯誤顯示不得洩漏 bidi override")
                XCTAssertLessThan(message.count, 500,
                                  "預設錯誤顯示不得反射完整 malformed key")
            }
        }
    }

    /// **空 literal 不是「未知」，是構造錯誤。** 未知有它自己的表示（非空 literal
    /// 就是「還不知道指誰」），把空字串也算進去會讓兩個狀態混成一個。
    func testEmptyLiteralIsRejected() {
        XCTAssertThrowsError(try Proposition.makeAuthored(
            person: .literal("   "), work: .key(workKey))) { e in
            XCTAssertEqual(e as? PropositionError, .emptyLiteral)
        }
    }

    func testWellFormedPropositionIsAccepted() throws {
        let p = try Proposition.makeAuthored(person: .key(personKey), work: .literal("some title"))
        XCTAssertEqual(p.arguments.count, 2, "arity 由型別固定")
        XCTAssertEqual(p.predicateName, "authored")
    }

    /// 方向不可交換——兩者是**不同的命題**。
    func testDirectionIsPartOfIdentity() {
        let a = Proposition.authored(person: .key("a"), work: .key("b"))
        let b = Proposition.authored(person: .key("b"), work: .key("a"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - #205 canonical model boundary

    func testDuplicateEntryAndPersonKeysAreRejectedTogether() {
        let error = capturedModelError(
            entries: [
                entry(citekey: "work-b"), entry(citekey: "work-a"),
                entry(citekey: "work-b"), entry(citekey: "work-a"),
            ],
            people: [person(key: "person-b"), person(key: "person-b")]
        )

        guard let error else {
            return XCTFail("重複 entry citekey 與 person key 必須拒絕 model 構造")
        }
        XCTAssertEqual(error.duplicateEntryCitekeys, ["work-a", "work-b"])
        XCTAssertEqual(error.duplicatePersonKeys, ["person-b"])
    }

    func testDuplicateEntryRejectionIsIndependentOfInputOrder() {
        let supporting = entry(citekey: "work-a", authors: [.key("person-a")])
        let nonSupporting = entry(citekey: "work-a")
        let people = [person(key: "person-a")]

        let forward = capturedModelError(entries: [supporting, nonSupporting], people: people)
        let reverse = capturedModelError(entries: [nonSupporting, supporting], people: people)

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward?.duplicateEntryCitekeys, ["work-a"])
    }

    func testDuplicatePersonRejectionIsIndependentOfInputOrder() {
        let first = Person(key: "person-a", names: ["A"])
        let second = Person(key: "person-a", names: ["B"])

        let forward = capturedModelError(entries: [], people: [first, second])
        let reverse = capturedModelError(entries: [], people: [second, first])

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward?.duplicatePersonKeys, ["person-a"])
    }

    func testDuplicateOrganizationRejectionIsIndependentOfInputOrder() {
        let first = Organization(key: "org-a", note: "A")
        let second = Organization(key: "org-a", note: "B")

        let forward = capturedModelError(
            entries: [], people: [], organizations: [first, second]
        )
        let reverse = capturedModelError(
            entries: [], people: [], organizations: [second, first]
        )

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward?.duplicateOrganizationKeys, ["org-a"])
    }

    func testUniqueIdentityKeysRemainAccepted() {
        XCTAssertNoThrow(try rawModel(
            entries: [entry(citekey: "work-a")],
            people: [person(key: "person-a")]
        ))
    }

    func testDuplicateErrorDescriptionSanitizesCallerControlledKeys() {
        let injectedEntry = "work-a\u{001B}[31m"
        let injectedPerson = "person-a\u{202E}txt"
        let error = capturedModelError(
            entries: [entry(citekey: injectedEntry), entry(citekey: injectedEntry)],
            people: [person(key: injectedPerson), person(key: injectedPerson)]
        )

        guard let error else { return XCTFail("重複 citekey 與 person key 必須拒絕") }
        XCTAssertEqual(error.duplicateEntryCitekeys, [injectedEntry],
                       "machine payload 必須保留原值")
        XCTAssertEqual(error.duplicatePersonKeys, [injectedPerson],
                       "machine payload 必須保留原值")
        XCTAssertFalse(error.localizedDescription.contains("\u{001B}"),
                       "顯示訊息不得保留原始 ESC 控制字元")
        XCTAssertFalse(error.localizedDescription.contains("\u{202E}"),
                       "person key 顯示訊息不得保留 bidi override")
        XCTAssertTrue(error.localizedDescription.contains("共 1 筆"))
        XCTAssertTrue(error.localizedDescription.contains("另 0 筆未顯示"))
    }

    func testDuplicateErrorDescriptionBoundsLargeConflictSetsWithoutLosingPayload() {
        let entryBoundarySentinel = "\u{2603}"
        let personBoundarySentinel = "\u{2602}"
        let entryVisiblePrefix = "work-000-" + String(repeating: "e", count: 111)
        let personVisiblePrefix = "person-000-" + String(repeating: "p", count: 109)
        XCTAssertEqual(entryVisiblePrefix.unicodeScalars.count, 120,
                       "entry 哨兵必須恰好從第 121 個 scalar 開始")
        XCTAssertEqual(personVisiblePrefix.unicodeScalars.count, 120,
                       "person 哨兵必須恰好從第 121 個 scalar 開始")

        let longEntryKey = entryVisiblePrefix + entryBoundarySentinel + "-entry-tail-must-not-display"
        let longPersonKey = personVisiblePrefix + personBoundarySentinel + "-person-tail-must-not-display"
        let entryKeys = ([longEntryKey] + (100..<119).map { "work-\($0)" }).sorted()
        let personKeys = ([longPersonKey] + (200..<216).map { "person-\($0)" }).sorted()
        let organizationKeys = (["org-300-\u{202E}txt"]
            + (301..<308).map { "org-\($0)" }).sorted()
        let error = capturedModelError(
            entries: entryKeys.reversed().flatMap { [entry(citekey: $0), entry(citekey: $0)] },
            people: personKeys.reversed().flatMap { [person(key: $0), person(key: $0)] },
            organizations: organizationKeys.reversed().flatMap {
                [Organization(key: $0), Organization(key: $0)]
            }
        )

        guard let error else { return XCTFail("大量重複鍵仍必須拒絕") }
        XCTAssertEqual(error.duplicateEntryCitekeys, entryKeys,
                       "顯示面截斷不得截斷 machine payload")
        XCTAssertEqual(error.duplicatePersonKeys, personKeys,
                       "顯示面截斷不得截斷 machine payload")
        XCTAssertEqual(error.duplicateOrganizationKeys, organizationKeys,
                       "organization 顯示面截斷不得截斷 machine payload")

        let message = error.localizedDescription
        XCTAssertTrue(message.contains("共 20 筆，僅列前 5 筆"))
        XCTAssertTrue(message.contains("共 17 筆，僅列前 5 筆"))
        XCTAssertTrue(message.contains("共 8 筆，僅列前 5 筆"))
        XCTAssertTrue(message.contains("另 15 筆未顯示"))
        XCTAssertTrue(message.contains("另 12 筆未顯示"))
        XCTAssertTrue(message.contains("另 3 筆未顯示"))
        XCTAssertTrue(message.contains(entryKeys[4]), "entry 第 5 筆必須顯示")
        XCTAssertFalse(message.contains(entryKeys[5]), "entry 第 6 筆不得顯示")
        XCTAssertTrue(message.contains(personKeys[4]), "person 第 5 筆必須顯示")
        XCTAssertFalse(message.contains(personKeys[5]), "person 第 6 筆不得顯示")
        XCTAssertTrue(message.contains(organizationKeys[4]), "organization 第 5 筆必須顯示")
        XCTAssertFalse(message.contains(organizationKeys[5]), "organization 第 6 筆不得顯示")
        XCTAssertFalse(message.contains("entry-tail-must-not-display"),
                       "entry 可見鍵必須套用 120 字元上限")
        XCTAssertFalse(message.contains("person-tail-must-not-display"),
                       "person 可見鍵必須套用 120 字元上限")
        XCTAssertFalse(message.contains(entryBoundarySentinel),
                       "entry 的第 121 個 scalar 不得顯示")
        XCTAssertFalse(message.contains(personBoundarySentinel),
                       "person 的第 121 個 scalar 不得顯示")
        XCTAssertFalse(message.contains("\u{202E}"), "organization key 必須消毒 bidi override")
        XCTAssertLessThan(message.count, 3_000, "聚合錯誤的顯示總量必須有固定上限")
    }

    func testDuplicateErrorGenericInterpolationUsesBoundedSanitizedDescription() {
        let injected = "person-a\u{202E}" + String(repeating: "x", count: 2_000)
        let keys = (0..<40).map { "\(injected)-\($0)" }
        let error = capturedModelError(
            entries: [],
            people: keys.flatMap { [person(key: $0), person(key: $0)] }
        )

        guard let error else { return XCTFail("重複 person key 必須拒絕") }
        let genericError: any Error = error
        for message in [String(describing: genericError), String(reflecting: genericError)] {
            XCTAssertEqual(message, error.localizedDescription,
                           "一般與 debug 錯誤顯示都必須走有界、已消毒的摘要")
            XCTAssertFalse(message.contains("\u{202E}"),
                           "預設錯誤顯示不得洩漏 bidi override")
            XCTAssertLessThan(message.count, 1_500,
                              "預設錯誤顯示不得反射完整 machine payload")
        }
    }

    func testThreeClassBackslashHeavyDuplicateDescriptionHasFixedPostEscapeBound() {
        let injected = String(repeating: "\n\t\u{001B}\u{202E}", count: 100)
        let entryKeys = (0..<8).map { "entry-\($0)-\(injected)" }
        let personKeys = (0..<8).map { "person-\($0)-\(injected)" }
        let organizationKeys = (0..<8).map { "org-\($0)-\(injected)" }
        let error = capturedModelError(
            entries: entryKeys.flatMap { [entry(citekey: $0), entry(citekey: $0)] },
            people: personKeys.flatMap { [person(key: $0), person(key: $0)] },
            organizations: organizationKeys.flatMap {
                [Organization(key: $0), Organization(key: $0)]
            }
        )

        guard let error else { return XCTFail("三類重複鍵必須聚合拒絕") }
        XCTAssertEqual(error.duplicateEntryCitekeys.count, 8)
        XCTAssertEqual(error.duplicatePersonKeys.count, 8)
        XCTAssertEqual(error.duplicateOrganizationKeys.count, 8)
        let message = error.localizedDescription
        XCTAssertFalse(message.contains("\u{001B}"))
        XCTAssertFalse(message.contains("\u{202E}"))
        XCTAssertLessThan(message.count, 3_000,
                          "displaySafe 後的跳脫膨脹仍必須有固定總量上限")
    }

    func testCanonicalEquivalentDuplicateKeyRepresentationIsOrderIndependent() {
        let nfd = "e\u{301}"
        let nfc = "\u{00E9}"
        XCTAssertEqual(nfd, nfc, "fixture 必須是 Swift 視為相等的 canonical equivalents")
        XCTAssertNotEqual(Array(nfd.utf8), Array(nfc.utf8), "fixture 的原始 bytes 必須不同")

        let forward = capturedModelError(
            entries: [entry(citekey: nfd), entry(citekey: nfc)],
            people: []
        )
        let reverse = capturedModelError(
            entries: [entry(citekey: nfc), entry(citekey: nfd)],
            people: []
        )

        guard let forwardKeys = forward?.duplicateEntryCitekeys,
              let reverseKeys = reverse?.duplicateEntryCitekeys,
              forwardKeys.count == 1,
              reverseKeys.count == 1 else {
            return XCTFail("canonical-equivalent 重複鍵必須各自聚合成一筆")
        }
        let forwardKey = forwardKeys[0]
        let reverseKey = reverseKeys[0]
        XCTAssertEqual(Array(forwardKey.utf8), Array(reverseKey.utf8),
                       "相同衝突集合反轉輸入後，machine payload bytes 必須穩定")
    }

    // MARK: - #205 malformed proposition boundary

    func testDirectEmptyLiteralIsRejectedAcrossSemanticOperations() throws {
        let model = try rawModel(
            entries: [entry(citekey: "work-a")],
            people: [person(key: "person-a")]
        ).context(validAt: ValidDay("2026-08-09"))
        let valid = try Proposition.authored(person: .key("person-a"), work: .key("work-a"))
            .evaluate(in: model)
        let malformedCases = [
            Proposition.authored(person: .literal("   "), work: .key("work-a")),
            Proposition.authored(person: .key("person-a"), work: .literal("   ")),
        ]

        for malformed in malformedCases {
            let assertion = Assertion(expression: malformed.expression, stance: .asserted,
                                      source: "conversation",
                                      recorded: try RecordedTime("2026-08-09"))

            assertPropositionError(.emptyLiteral) { try malformed.project(in: model) }
            assertPropositionError(.emptyLiteral) { try malformed.evaluate(in: model) }
            assertPropositionError(.emptyLiteral) {
                try YesNoQuestion(malformed.expression)
            }
            assertPropositionError(.emptyLiteral) {
                try adjudicate(
                    assertion,
                    valuation: valid,
                    acceptedBy: "che",
                    acceptedAt: AcceptedTime("2026-08-09")
                )
            }
        }
    }

    func testMalformedKeyCannotBeMadeTrueByMatchingMalformedModel() throws {
        let malformedKey = "Not A Key"
        let cases = [
            (
                Proposition.authored(person: .key(malformedKey), work: .key("work-a")),
                try rawModel(
                    entries: [entry(citekey: "work-a", authors: [.key(malformedKey)])],
                    people: [person(key: malformedKey)]
                ).context(validAt: ValidDay("2026-08-09"))
            ),
            (
                Proposition.authored(person: .key("person-a"), work: .key(malformedKey)),
                try rawModel(
                    entries: [entry(citekey: malformedKey, authors: [.key("person-a")])],
                    people: [person(key: "person-a")]
                ).context(validAt: ValidDay("2026-08-09"))
            ),
        ]

        let validContext = try rawModel(
            entries: [entry(citekey: "valid-work", authors: [.key("valid-person")])],
            people: [person(key: "valid-person")]
        ).context(validAt: ValidDay("2026-08-09"))
        let validValuation = try Proposition.authored(
            person: .key("valid-person"), work: .key("valid-work")
        ).evaluate(in: validContext)

        for (malformed, model) in cases {
            let assertion = Assertion(expression: malformed.expression, stance: .asserted,
                                      source: "conversation",
                                      recorded: try RecordedTime("2026-08-09"))

            assertPropositionError(.malformedKey(malformedKey)) {
                try malformed.project(in: model)
            }
            assertPropositionError(.malformedKey(malformedKey)) {
                try malformed.evaluate(in: model)
            }
            assertPropositionError(.malformedKey(malformedKey)) {
                try YesNoQuestion(malformed.expression)
            }
            assertPropositionError(.malformedKey(malformedKey)) {
                try adjudicate(
                    assertion,
                    valuation: validValuation,
                    acceptedBy: "che",
                    acceptedAt: AcceptedTime("2026-08-09")
                )
            }
        }
    }

    func testAffiliatedMalformedArgumentsAreRejectedAcrossSemanticOperations() throws {
        let validPerson = person(key: "person-a")
        let validWork = entry(citekey: "work-a", authors: [.key("person-a")])
        let context = try rawModel(
            entries: [validWork],
            people: [validPerson],
            organizations: [Organization(key: "org-a")]
        ).context(validAt: ValidDay("2026-08-09"))
        let fallback = try Proposition.authored(
            person: .key("person-a"), work: .key("work-a")
        ).evaluate(in: context)
        let cases: [(Proposition, PropositionError)] = [
            (
                .affiliated(person: .key("Bad Person"), organization: .key("org-a")),
                .malformedKey("Bad Person")
            ),
            (
                .affiliated(person: .key("person-a"), organization: .key("Bad Org")),
                .malformedKey("Bad Org")
            ),
            (
                .affiliated(person: .key("person-a"), organization: .literal("   ")),
                .emptyLiteral
            ),
        ]

        for (malformed, expected) in cases {
            let assertion = Assertion(
                expression: malformed.expression,
                stance: .asserted,
                source: "conversation",
                recorded: try RecordedTime("2026-08-09")
            )
            assertPropositionError(expected) { try malformed.project(in: context) }
            assertPropositionError(expected) { try malformed.evaluate(in: context) }
            assertPropositionError(expected) { try YesNoQuestion(malformed.expression) }
            assertPropositionError(expected) {
                try adjudicate(
                    assertion,
                    valuation: fallback,
                    acceptedBy: "che",
                    acceptedAt: AcceptedTime("2026-08-09")
                )
            }
        }
    }

    // MARK: - #199 投射

    func testUnresolvedSymbolIsNotProjectable() throws {
        let p = Proposition.authored(person: .literal("Che Cheng"), work: .key(workKey))
        XCTAssertEqual(try p.project(in: model(authorSlots: [.key(personKey)])),
                       .unprojectable(.unresolvedSymbol(role: "person", literal: "Che Cheng")))
    }

    func testUnknownIdentityIsNotProjectable() throws {
        let p = Proposition.authored(person: .key("nobody"), work: .key(workKey))
        XCTAssertEqual(try p.project(in: model(authorSlots: [])),
                       .unprojectable(.unknownIdentity(role: "person", key: "nobody")))
    }

    /// 把 work 放進 person 的位置——**這條證明方向是有意義的**，而且錯誤訊息要
    /// 指出真正的問題（型別不對），不是語意較弱的「找不到」。
    func testReversedArgumentsReportWrongEntityKind() throws {
        let reversed = Proposition.authored(person: .key(workKey), work: .key(personKey))
        XCTAssertEqual(try reversed.project(in: model(authorSlots: [])),
                       .unprojectable(.wrongEntityKind(role: "person", key: workKey, expected: "person")))
    }

    func testFullyResolvedProjects() throws {
        guard case .authored = try authored.project(in: model(authorSlots: [.key(personKey)])) else {
            return XCTFail("兩個符號都有 identity，應該投射得出來")
        }
    }

    // MARK: - 核心不變式：投射不足 → 不宣稱真值

    func testUnprojectableNeverClaimsTruth() throws {
        for p in [Proposition.authored(person: .literal("X"), work: .key(workKey)),
                  Proposition.authored(person: .key("nobody"), work: .key(workKey)),
                  Proposition.authored(person: .key(personKey), work: .key("no-such-work"))] {
            let t = try p.evaluate(in: model(authorSlots: [.key(personKey)]))
            guard case .undetermined(.notProjectable) = t.truth else {
                return XCTFail("投射不足卻宣稱了真值：\(t)")
            }
        }
    }

    func testSupportingEvidenceHolds() throws {
        XCTAssertEqual(
            try authored.evaluate(in: model(authorSlots: [.key(personKey)])).truth,
            .holds
        )
    }

    /// 作者槽是 literal 且字面對得上——**「像」不是「是」**。這要回未定，而且
    /// 原因要帶得出那個 literal，否則使用者無從判斷該不該去歸戶。
    func testLookalikeLiteralIsUndeterminedNotTrue() throws {
        let t = try authored.evaluate(in: model(authorSlots: [.literal("Che Cheng")]))
        XCTAssertEqual(
            t.truth,
            .undetermined(.supportingEvidenceUnresolved(literal: "Che Cheng"))
        )
    }

    /// **本模組的中心主張。** 名單裡沒有他 → 未定，**不是為假**。
    ///
    /// store 不是封閉世界：作者槽可能還沒歸戶、可能匯入來源只給了前三位、可能
    /// 別名沒對上。「找不到」只支持未定。
    func testAbsenceIsUndeterminedNotFalse() throws {
        let t = try authored.evaluate(in: model(authorSlots: [.key("someone-else")]))
        XCTAssertEqual(t.truth, .undetermined(.noSupportingEvidence))
        XCTAssertNotEqual(t.truth, .fails, "查不到不等於為假")
    }

    /// **誠實邊界，用測試釘住**：沒有 completeness witness 時，任何 author-list
    /// absence 都保持 open-world；只有另一組整合測試的 exact witness 才能產生 `.fails`。
    func testAuthoredWithoutCompletenessWitnessNeverReturnsFails() throws {
        let cases: [[AkashicCore.Author]] = [
            [], [.key(personKey)], [.key("other")], [.literal("Che Cheng")], [.literal("Someone")],
        ]
        for slots in cases {
            XCTAssertNotEqual(try authored.evaluate(in: model(authorSlots: slots)).truth, .fails,
                              "slots=\(slots) 產生了 .fails——若這是刻意的，doc 與本測試要一起改")
        }
    }

    // MARK: - #200 答案空間

    /// yes/no 問句有**三個**答案。少掉未定，問句就退化成「有沒有查到」。
    func testAnswerSpaceIncludesUndetermined() throws {
        let q = try YesNoQuestion(authored.expression)
        XCTAssertEqual(q.answerSpace, [.yes, .no, .undetermined])
        XCTAssertEqual(Set(q.answerSpace).count, 3, "互斥")
        XCTAssertEqual(Set(YesNoQuestion.Answer.allCases), Set(q.answerSpace), "窮盡")
    }

    func testAnswerMapsTruthWithoutFlattening() throws {
        XCTAssertEqual(YesNoQuestion.Answer.mapped(from: .holds), .yes)
        XCTAssertEqual(YesNoQuestion.Answer.mapped(from: .fails), .no)
        XCTAssertEqual(
            YesNoQuestion.Answer.mapped(from: .undetermined(.noSupportingEvidence)),
            .undetermined
        )
        XCTAssertEqual(try YesNoQuestion(authored.expression)
            .answer(in: model(authorSlots: [.key(personKey)])).answer, .yes)
        XCTAssertEqual(try YesNoQuestion(authored.expression)
            .answer(in: model(authorSlots: [])).answer, .undetermined)
    }

    // MARK: - 保存 ≠ 接受

    private func assertion(_ stance: Stance) throws -> Assertion {
        Assertion(
            expression: authored.expression,
            stance: stance,
            source: "conversation",
            recorded: try RecordedTime("2026-08-09")
        )
    }

    func testAdjudicationRefusesUndetermined() {
        XCTAssertThrowsError(try adjudicate(
            assertion(.asserted),
            valuation: authored.evaluate(in: model(authorSlots: [])),
            acceptedBy: "che",
            acceptedAt: AcceptedTime("2026-08-09")
        )) { e in
            guard case .notEstablished(let refused) = e as? AdjudicationRefusal,
                  case .undetermined = refused.truth else {
                return XCTFail("未定必須被拒絕，實際：\(e)")
            }
        }
    }

    /// **提問不得升格為主張。** 把一個問句記進系統，不能讓它的主題命題變成被接受。
    func testQuestionedStanceCannotBecomeFact() {
        for s in [Stance.questioned, .denied] {
            XCTAssertThrowsError(try adjudicate(
                assertion(s),
                valuation: authored.evaluate(in: model(authorSlots: [.key(personKey)])),
                acceptedBy: "che",
                acceptedAt: AcceptedTime("2026-08-09")
            )) { e in
                XCTAssertEqual(e as? AdjudicationRefusal, .stanceIsNotAssertion(s))
            }
        }
    }

    func testAdjudicationAcceptsEstablishedAssertion() throws {
        let context = try model(authorSlots: [.key(personKey)])
        let valuation = try authored.evaluate(in: context)
        let f = try adjudicate(
            assertion(.asserted),
            valuation: valuation,
            acceptedBy: "che",
            acceptedAt: AcceptedTime("2026-08-09")
        )
        XCTAssertEqual(f.expression, authored.expression)
        XCTAssertEqual(f.basis.stance, .asserted)
        XCTAssertEqual(f.acceptedBy, "che")
        XCTAssertEqual(f.valuation, valuation)
    }
}
