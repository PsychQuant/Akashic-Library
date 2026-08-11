import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

private func keyPathIsWritable<Root, Value>(_: KeyPath<Root, Value>) -> Bool { false }
private func keyPathIsWritable<Root, Value>(_: WritableKeyPath<Root, Value>) -> Bool { true }

final class AuthorshipCompletenessTests: XCTestCase {
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    private var validReferences: [ProvenanceReference] {
        [
            ProvenanceReference(
                field: "authors",
                kind: .retrieval(
                    url: "https://example.test/work",
                    retrieved: "2026-08-10",
                    status: 200,
                    mediaType: "text/html",
                    content: digest)),
            ProvenanceReference(
                field: "authors",
                kind: .judgement(
                    statement: "The cited source enumerates the complete author list.",
                    restsOn: [digest])),
        ]
    }

    /// 會抓到的回歸：domain、slot count、case tag 或 UTF-8 length framing 任一項
    /// 被移除、改序或改成平台 endian。期待值由獨立 Ruby Digest::SHA256 fixture
    /// 依規格逐 byte 推導，不呼叫 production helper。
    func testV1FingerprintMatchesGoldenVectorAndDigestShape() {
        let fingerprint = AuthorListFingerprint(
            authors: [.key("author-a"), .literal("Bé")])

        XCTAssertEqual(
            fingerprint.digest,
            "sha256:8ade206dc3439d220879052cdd1ac9bd47737cebcac6bc959e0062970394777d")
        XCTAssertNotNil(
            fingerprint.digest.range(
                of: #"^sha256:[0-9a-f]{64}$"#,
                options: .regularExpression))
    }

    /// 會抓到的回歸：fingerprint 天真串接 author 文字，因而讓不同 slot boundary、
    /// key/literal case、順序或 canonically-equivalent Unicode bytes 發生碰撞。
    func testV1FingerprintSeparatesEveryStructuralAuthorBoundary() {
        let pairs: [([Author], [Author])] = [
            ([.key("ab"), .key("c")], [.key("a"), .key("bc")]),
            ([.key("a"), .literal("b")], [.literal("a"), .key("b")]),
            ([.key("a"), .key("b")], [.key("b"), .key("a")]),
            ([.literal("é")], [.literal("e\u{0301}")]),
        ]

        for (left, right) in pairs {
            XCTAssertNotEqual(
                AuthorListFingerprint(authors: left),
                AuthorListFingerprint(authors: right),
                "不同的 ordered raw author snapshot 不得共用 fingerprint")
        }
    }

    /// 會抓到的回歸：witness 讓 caller 事後改 work、fingerprint、author snapshot 或
    /// provenance，繞過 throwing initializer 建立的封閉證據鏈。
    func testValidWitnessConstructionStoresReadOnlyValues() throws {
        let workID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let authors: [Author] = [.key("author-a"), .key("author-b")]
        let fingerprint = AuthorListFingerprint(authors: authors)

        let witness = try AuthorListCompletenessWitness(
            workID: workID,
            fingerprint: fingerprint,
            attestedAuthors: authors,
            references: validReferences)

        XCTAssertEqual(witness.workID, workID)
        XCTAssertEqual(witness.fingerprint, fingerprint)
        XCTAssertEqual(witness.attestedAuthors, authors)
        XCTAssertEqual(witness.references, validReferences)
        XCTAssertFalse(keyPathIsWritable(\AuthorListCompletenessWitness.workID))
        XCTAssertFalse(keyPathIsWritable(\AuthorListCompletenessWitness.fingerprint))
        XCTAssertFalse(keyPathIsWritable(\AuthorListCompletenessWitness.attestedAuthors))
        XCTAssertFalse(keyPathIsWritable(\AuthorListCompletenessWitness.references))
    }

    private func assertWitnessRejected(
        authors: [Author] = [.key("author-a")],
        fingerprint: AuthorListFingerprint? = nil,
        references: [ProvenanceReference],
        reason: AuthorshipCompletenessValidationError.Reason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolvedFingerprint = fingerprint ?? AuthorListFingerprint(authors: authors)
        XCTAssertThrowsError(
            try AuthorListCompletenessWitness(
                workID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                fingerprint: resolvedFingerprint,
                attestedAuthors: authors,
                references: references),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                (error as? AuthorshipCompletenessValidationError)?.reason,
                reason,
                "typed reason 必須穩定：\(error)",
                file: file,
                line: line)
        }
    }

    /// 會抓到的回歸：public non-throwing ProvenanceReference 被直接偽造後，witness
    /// initializer 信任其外觀而未重驗 authors field、nil value 與兩種 kind 的不變量。
    func testForgedPublicReferencesAreRevalidated() {
        let fullwidthDigest = "sha256:" + String(repeating: "ａ", count: 64)
        let cases: [(ProvenanceReference, AuthorshipCompletenessValidationError.Reason)] = [
            (
                ProvenanceReference(
                    field: "title",
                    kind: .retrieval(
                        url: "https://example.test/work", retrieved: "2026-08-10",
                        status: 200, mediaType: nil, content: digest)),
                .referenceField(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors", value: "author-a",
                    kind: .retrieval(
                        url: "https://example.test/work", retrieved: "2026-08-10",
                        status: 200, mediaType: nil, content: digest)),
                .referenceValue(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .retrieval(
                        url: "", retrieved: "2026-08-10", status: 200,
                        mediaType: nil, content: digest)),
                .retrievalURL(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .retrieval(
                        url: "https://example.test/work", retrieved: "",
                        status: 200, mediaType: nil, content: digest)),
                .retrievalDate(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .retrieval(
                        url: "https://example.test/work", retrieved: "2026-08-10",
                        status: 200, mediaType: nil, content: "sha256:not-a-digest")),
                .retrievalDigest(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .retrieval(
                        url: "https://example.test/work", retrieved: "2026-08-10",
                        status: 200, mediaType: nil, content: fullwidthDigest)),
                .retrievalDigest(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .judgement(statement: " \n ", restsOn: [digest])),
                .judgementStatement(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .judgement(statement: "complete", restsOn: [])),
                .judgementRestsOn(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .judgement(statement: "complete", restsOn: ["sha256:bad"])),
                .judgementDigest(index: 0)
            ),
            (
                ProvenanceReference(
                    field: "authors",
                    kind: .judgement(statement: "complete", restsOn: [fullwidthDigest])),
                .judgementDigest(index: 0)
            ),
        ]

        for (reference, reason) in cases {
            assertWitnessRejected(references: [reference], reason: reason)
        }
    }

    /// 會抓到的回歸：judgement 能引用 bundle 外部的合法 digest，或 bundle 只有
    /// retrieval／只有 judgement 仍被當成封閉證據鏈。
    func testEvidenceChainRequiresLocalRetrievalAndJudgement() {
        let external = "sha256:" + String(repeating: "cd", count: 32)
        assertWitnessRejected(
            references: [validReferences[0]],
            reason: .judgementRequired)
        assertWitnessRejected(
            references: [validReferences[1]],
            reason: .retrievalRequired)
        assertWitnessRejected(
            references: [
                validReferences[0],
                ProvenanceReference(
                    field: "authors",
                    kind: .judgement(statement: "complete", restsOn: [external])),
            ],
            reason: .judgementDigestNotRetrieved(index: 1))
    }

    /// 會抓到的回歸：persisted fingerprint 未驗 shape／未重算，或非法作者槽進入
    /// truth-bearing witness。
    func testFingerprintAndAuthorSnapshotAreValidated() throws {
        XCTAssertThrowsError(try AuthorListFingerprint(digest: "sha256:short")) { error in
            XCTAssertEqual(
                (error as? AuthorshipCompletenessValidationError)?.reason,
                .malformedFingerprint)
        }

        let authors: [Author] = [.key("author-a")]
        assertWitnessRejected(
            authors: authors,
            fingerprint: AuthorListFingerprint(authors: [.key("author-b")]),
            references: validReferences,
            reason: .fingerprintMismatch)
        assertWitnessRejected(
            authors: [.key("Not A Store Key")],
            references: validReferences,
            reason: .authorKey(index: 0))
        assertWitnessRejected(
            authors: [.literal(" \n ")],
            references: validReferences,
            reason: .authorLiteral(index: 0))
        assertWitnessRejected(references: [], reason: .referencesRequired)
    }

    /// 會抓到的回歸：exact snapshot 比對退回 Swift String canonical equality，
    /// 讓 NFC／NFD 或 key/literal case 在 fingerprint 之外失去獨立 raw-byte guard。
    func testRawAuthorSnapshotComparisonPreservesCaseOrderAndUTF8Bytes() {
        XCTAssertTrue(AuthorListCompletenessWitness.rawAuthorSnapshotsEqual(
            [.key("author-a"), .literal("Bé")],
            [.key("author-a"), .literal("Bé")]))
        XCTAssertFalse(AuthorListCompletenessWitness.rawAuthorSnapshotsEqual(
            [.literal("é")],
            [.literal("e\u{0301}")]))
        XCTAssertFalse(AuthorListCompletenessWitness.rawAuthorSnapshotsEqual(
            [.key("same")],
            [.literal("same")]))
        XCTAssertFalse(AuthorListCompletenessWitness.rawAuthorSnapshotsEqual(
            [.key("a"), .key("b")],
            [.key("b"), .key("a")]))
    }

    /// 會抓到的回歸：錯誤的 default reflection 洩漏控制字元／bidi 或讓 oversized
    /// caller input 無上限灌進 terminal、UI 與 LLM context。
    func testValidationDiagnosticsAreSanitizedAndPostEscapeBounded() {
        let hostile = "\u{001B}[2J\u{202E}\n" + String(repeating: "x", count: 10_000)
        let forged = ProvenanceReference(
            field: hostile,
            kind: .retrieval(
                url: "https://example.test/work", retrieved: "2026-08-10",
                status: 200, mediaType: nil, content: digest))

        XCTAssertThrowsError(
            try AuthorListCompletenessWitness(
                workID: UUID(),
                fingerprint: AuthorListFingerprint(authors: []),
                attestedAuthors: [],
                references: [forged])
        ) { error in
            let validation = error as? AuthorshipCompletenessValidationError
            XCTAssertEqual(validation?.reason, .referenceField(index: 0))
            let renderings = [
                String(describing: error),
                String(reflecting: error),
                (error as? LocalizedError)?.errorDescription ?? "",
            ]
            for rendered in renderings {
                XCTAssertFalse(rendered.contains("\u{001B}"), rendered)
                XCTAssertFalse(rendered.contains("\u{202E}"), rendered)
                XCTAssertFalse(rendered.contains("\n"), rendered)
                XCTAssertLessThanOrEqual(rendered.unicodeScalars.count, 320, rendered)
            }
        }
    }

    /// 會抓到的回歸：binding 只看 citekey、忽略 work UUID，或用 Swift String 的
    /// canonical-equivalent equality 而漏掉 ordered raw UTF-8 author mutation。
    func testBindingUsesWorkIDAndExactOrderedRawAuthorSnapshot() throws {
        let workID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let authors: [Author] = [.key("author-a"), .literal("é")]
        let witness = try AuthorListCompletenessWitness(
            workID: workID,
            fingerprint: AuthorListFingerprint(authors: authors),
            attestedAuthors: authors,
            references: validReferences)

        XCTAssertNoThrow(try witness.validateBinding(workID: workID, authors: authors))
        XCTAssertThrowsError(
            try witness.validateBinding(workID: UUID(), authors: authors)
        ) { error in
            XCTAssertEqual(
                (error as? AuthorListCompletenessBindingError)?.issues.map(\.kind),
                [.workID])
        }

        let mutations: [[Author]] = [
            [.key("author-a")],
            [.key("author-a"), .literal("é"), .key("author-b")],
            [.literal("é"), .key("author-a")],
            [.key("author-a"), .literal("e\u{0301}")],
            [.literal("author-a"), .literal("é")],
        ]
        for mutated in mutations {
            XCTAssertThrowsError(
                try witness.validateBinding(workID: workID, authors: mutated)
            ) { error in
                XCTAssertEqual(
                    (error as? AuthorListCompletenessBindingError)?.issues.map(\.kind),
                    [.authorSnapshot])
            }
        }
    }

    /// 會抓到的回歸：aggregate 的人類訊息無上限列出所有 issue，讓大量 machine
    /// payload 灌進 terminal/UI/LLM context；顯示截斷不得同時丟掉 typed payload。
    func testBindingDiagnosticsAreBoundedWithoutTruncatingMachinePayload() {
        let issues: [AuthorListCompletenessBindingIssue] = (0..<200).map { index in
            .workID(
                witness: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                current: UUID(uuidString: String(format: "11111111-1111-1111-1111-%012d", index))!)
        }
        let error = AuthorListCompletenessBindingError(issues: issues)

        XCTAssertEqual(error.issues.count, issues.count)
        for rendered in [
            String(describing: error),
            String(reflecting: error),
            error.errorDescription ?? "",
        ] {
            XCTAssertLessThanOrEqual(rendered.unicodeScalars.count, 512, rendered)
        }
    }
}

final class AuthorshipCompletenessStoreIOTests: XCTestCase {
    private let workID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let digest = "sha256:" + String(repeating: "ab", count: 32)
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func references() -> [ProvenanceReference] {
        [
            ProvenanceReference(
                field: "authors",
                kind: .retrieval(
                    url: "https://example.test/work", retrieved: "2026-08-10",
                    status: 200, mediaType: "text/html", content: digest)),
            ProvenanceReference(
                field: "authors",
                kind: .judgement(statement: "Complete author list.", restsOn: [digest])),
        ]
    }

    private func witness(authors: [Author]) throws -> AuthorListCompletenessWitness {
        try AuthorListCompletenessWitness(
            workID: workID,
            fingerprint: AuthorListFingerprint(authors: authors),
            attestedAuthors: authors,
            references: references())
    }

    private func entry(
        citekey: String = "witness2026entry",
        authors: [Author] = [.key("author-a"), .key("author-b")]
    ) throws -> Entry {
        var entry = Entry(
            id: workID,
            citekey: citekey,
            type: "article",
            title: "Witnessed",
            authors: authors)
        entry.akashic.authorListCompleteness = try witness(authors: authors)
        return entry
    }

    private func makeStore() throws -> LibraryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-authorship-witness-\(UUID().uuidString)")
        roots.append(root)
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        return store
    }

    private func replacingFirst(
        _ needle: String,
        with replacement: String,
        in source: String
    ) throws -> String {
        let range = try XCTUnwrap(
            source.range(of: needle),
            "fixture 找不到預期片段：\(needle)\n\(source)")
        var result = source
        result.replaceSubrange(range, with: replacement)
        return result
    }

    /// Regression baseline：optional schema 缺席時不得為既有 Entry 製造任何 byte diff。
    func testWitnessAbsencePreservesLegacyCanonicalBytes() throws {
        let entry = Entry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            citekey: "witness2026entry",
            type: "article",
            title: "Witness-free",
            authors: [.key("author-a")])

        XCTAssertEqual(
            try EntryYAML.encode(entry),
            """
            work:
            id: 11111111-1111-1111-1111-111111111111
            citekey: witness2026entry
            type: article
            title: Witness-free
            authors:
            - key: author-a

            """)
    }

    /// Regression baseline：akashic tolerant namespace 的 additive optional field 不升版。
    /// （現值來自 #232 的 verdict 欄位對＋#223 的 sources——都與 witness 無關；
    /// witness 落地時是 7、沒有推動任何 bump，本測試主張的就是這件事。）
    ///
    /// ⚠️ 這個斷言**耦合到與 witness 無關的 bump**：它想說的是「witness 沒有造成
    /// 升版」，但寫法是釘住當下的 `supported` 值，於是任何**別的**理由的 bump 都會
    /// 讓它變紅（#223 的 9 即是一次）。要真正表達原意，該斷言的是「帶 witness
    /// 的記錄能寫進沒有為它升版的 store」，而不是一個數字。留待後續處理。
    func testOptionalWitnessDoesNotBumpStoreVersion() {
        XCTAssertEqual(StoreVersion.supported, 9)
    }

    /// 會抓到的回歸：known keys 順序漂移、漏存 exact authors/provenance、加入自我參照
    /// revision 欄位，或 decode→encode 無法形成 canonical fixed point。
    func testWitnessRoundTripsByValueWithFixedKnownKeyOrder() throws {
        let original = try entry()
        let first = try EntryYAML.encode(original)
        let decoded = try EntryYAML.decode(first)
        let second = try EntryYAML.encode(decoded)

        XCTAssertEqual(decoded.akashic.authorListCompleteness,
                       original.akashic.authorListCompleteness)
        XCTAssertEqual(second, first)
        let keys = [
            "    work-id:",
            "    author-list-fingerprint:",
            "    attested-authors:",
            "    references:",
        ]
        let positions = keys.compactMap { first.range(of: $0)?.lowerBound }
        XCTAssertEqual(positions.count, keys.count, first)
        for (left, right) in zip(positions, positions.dropFirst()) {
            XCTAssertLessThan(left, right, first)
        }
        XCTAssertFalse(first.contains("store-revision"), first)
        XCTAssertFalse(first.contains("snapshot-id"), first)
    }

    /// 會抓到的回歸：empty authors 被省略，導致「完備的 exact 空清單」無法保存。
    func testEmptyAttestedAuthorListRoundTripsExactly() throws {
        let original = try entry(authors: [])
        let yaml = try EntryYAML.encode(original)
        let decoded = try EntryYAML.decode(yaml)

        XCTAssertTrue(yaml.contains("attested-authors: []"), yaml)
        XCTAssertEqual(decoded.akashic.authorListCompleteness,
                       original.akashic.authorListCompleteness)
        XCTAssertTrue(decoded.authors.isEmpty)
    }

    /// 會抓到的回歸：新增 known witness 時剝掉同一 Akashic namespace 裡較新 binary
    /// 的未知欄位，破壞 tolerant-preserve 的舊 binary 邊界。
    func testWitnessCoexistsWithUnknownAkashicFieldsWithoutLoss() throws {
        var original = try entry()
        original.akashic.unknownFields = [
            UnknownField(
                key: "future-witness-policy",
                raw: "  future-witness-policy:\n    mode: retained\n"),
        ]

        let first = try EntryYAML.encode(original)
        let decoded = try EntryYAML.decode(first)
        let second = try EntryYAML.encode(decoded)

        XCTAssertEqual(decoded.akashic.authorListCompleteness,
                       original.akashic.authorListCompleteness)
        XCTAssertEqual(decoded.akashic.unknownFields.map(\.key), ["future-witness-policy"])
        XCTAssertTrue(second.contains("future-witness-policy:"), second)
        XCTAssertEqual(second, first)
    }

    /// 會抓到的回歸：decode 信任 persisted fingerprint／work UUID，或只用 Swift String
    /// equality 比 authors 而漏掉 ordered snapshot mutation。
    func testDecodeRejectsMalformedFingerprintAndStaleBindings() throws {
        let canonical = try EntryYAML.encode(try entry())
        let otherID = "22222222-2222-2222-2222-222222222222"
        let staleWork = try replacingFirst(
            "    work-id: \(workID.uuidString)",
            with: "    work-id: \(otherID)",
            in: canonical)
        let currentFingerprint = AuthorListFingerprint(
            authors: [.key("author-a"), .key("author-b")]).digest
        let malformedFingerprint = try replacingFirst(
            "    author-list-fingerprint: \(currentFingerprint)",
            with: "    author-list-fingerprint: sha256:bad",
            in: canonical)
        let reorderedEntryAuthors = try replacingFirst(
            "authors:\n- key: author-a\n- key: author-b",
            with: "authors:\n- key: author-b\n- key: author-a",
            in: canonical)

        for invalid in [staleWork, malformedFingerprint, reorderedEntryAuthors] {
            XCTAssertThrowsError(try EntryYAML.decode(invalid), invalid)
        }
    }

    /// 會抓到的回歸：strict witness mapping 收下未知欄位，或 duplicate known key
    /// first/last-wins 而讓 stale witness 被另一筆遮掉。
    func testWitnessKnownShapeRejectsUnknownDuplicateAndWrongScalarTags() throws {
        let canonical = try EntryYAML.encode(try entry())
        let withUnknown = try replacingFirst(
            "    work-id:",
            with: "    unexpected: true\n    work-id:",
            in: canonical)
        let marker = "  author-list-completeness:"
        let witnessRange = try XCTUnwrap(canonical.range(of: marker))
        let witnessBlock = String(canonical[witnessRange.lowerBound...])
        let duplicate = canonical + witnessBlock

        let fingerprint = AuthorListFingerprint(
            authors: [.key("author-a"), .key("author-b")]).digest
        let taggedFingerprint = try replacingFirst(
            "    author-list-fingerprint: \(fingerprint)",
            with: "    author-list-fingerprint: !!timestamp \"\(fingerprint)\"",
            in: canonical)
        let taggedURL = try replacingFirst(
            "      url: https://example.test/work",
            with: "      url: !!int \"42\"",
            in: canonical)

        for invalid in [withUnknown, duplicate, taggedFingerprint, taggedURL] {
            XCTAssertThrowsError(try EntryYAML.decode(invalid), invalid)
        }
    }

    /// 會抓到的回歸：strict tag decoder 加入後，encoder 仍把看似 bool／int／null 的
    /// 合法字串寫成 plain scalar，造成 canonical witness 自己寫得出卻讀不回。
    func testAmbiguousWitnessStringsAreQuotedAndRoundTripAsStrings() throws {
        let authors: [Author] = [.literal("2026")]
        let references = [
            ProvenanceReference(
                field: "authors",
                kind: .retrieval(
                    url: "42", retrieved: "true", status: 200,
                    mediaType: "null", content: digest)),
            ProvenanceReference(
                field: "authors",
                kind: .judgement(statement: "false", restsOn: [digest])),
        ]
        var ambiguous = Entry(
            id: workID,
            citekey: "ambiguous2026entry",
            type: "article",
            title: "Ambiguous scalars",
            authors: authors)
        ambiguous.akashic.authorListCompleteness = try AuthorListCompletenessWitness(
            workID: workID,
            fingerprint: AuthorListFingerprint(authors: authors),
            attestedAuthors: authors,
            references: references)

        let encoded = try EntryYAML.encode(ambiguous)
        let decoded = try EntryYAML.decode(encoded)

        for quoted in ["\"2026\"", "\"42\"", "\"true\"", "\"null\"", "\"false\""] {
            XCTAssertTrue(encoded.contains(quoted), encoded)
        }
        XCTAssertEqual(decoded.akashic.authorListCompleteness,
                       ambiguous.akashic.authorListCompleteness)
    }

    /// 會抓到的回歸：binding 錯誤被當成 witness 缺席，檔案仍進 truth-bearing entries。
    func testMalformedWitnessFileIsQuarantinedInsteadOfSilentlyDropped() throws {
        let store = try makeStore()
        let canonical = try EntryYAML.encode(try entry())
        let malformed = try replacingFirst(
            "    author-list-fingerprint:",
            with: "    author-list-fingerprint: sha256:bad #",
            in: canonical)
        try malformed.write(
            to: store.entityURL(id: workID), atomically: true, encoding: .utf8)

        let load = try store.load()
        XCTAssertTrue(load.entries.isEmpty)
        XCTAssertEqual(load.quarantined.map(\.file),
                       ["entities/\(workID.uuidString).yaml"])
        XCTAssertTrue(load.quarantined[0].reason.contains("fingerprint"),
                      load.quarantined[0].reason)
    }

    /// 會抓到的回歸：Unicode Character 分類把全形 hex 當成合法 digest，使惡意
    /// witness 進入 snapshot 與 proposition truth boundary，而不是在 StoreIO quarantine。
    func testFullwidthDigestWitnessFileIsQuarantined() throws {
        let store = try makeStore()
        let canonical = try EntryYAML.encode(try entry())
        let fullwidthDigest = "sha256:" + String(repeating: "ａ", count: 64)
        let malformed = canonical.replacingOccurrences(of: digest, with: fullwidthDigest)
        try malformed.write(
            to: store.entityURL(id: workID), atomically: true, encoding: .utf8)

        let load = try store.load()
        XCTAssertTrue(load.entries.isEmpty)
        XCTAssertEqual(load.quarantined.map(\.file),
                       ["entities/\(workID.uuidString).yaml"])
        XCTAssertTrue(load.quarantined[0].reason.contains("digest"),
                      load.quarantined[0].reason)
    }

    /// 會抓到的回歸：witness 綁 citekey 而非 immutable work UUID。
    func testCitekeyRenamePreservesWitnessBinding() throws {
        let original = try entry(citekey: "old2026key")
        var renamed = original
        renamed.citekey = "new2026key"

        let decoded = try EntryYAML.decode(EntryYAML.encode(renamed))
        XCTAssertEqual(decoded.citekey, "new2026key")
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.akashic.authorListCompleteness,
                       original.akashic.authorListCompleteness)
    }

    /// 會抓到的回歸：revision 由 re-encode 或另一趟 filesystem read 計算，漏掉實際
    /// accepted capture 裡 truth-affecting witness bytes。
    func testWitnessOnlyChangeChangesRevisionAndDecodedSnapshotTogether() throws {
        let store = try makeStore()
        var original = try entry()
        original.akashic.authorListCompleteness = nil
        try store.writeEntry(original)
        let before = try store.loadSnapshot()

        let witnessed = try entry()
        try store.writeEntry(witnessed)
        let after = try store.loadSnapshot()

        XCTAssertEqual(before.id.store, after.id.store)
        XCTAssertNotEqual(before.id.revision, after.id.revision)
        XCTAssertNil(before.load.entries.first?.akashic.authorListCompleteness)
        XCTAssertEqual(after.load.entries.first?.akashic.authorListCompleteness,
                       witnessed.akashic.authorListCompleteness)
    }

    /// 會抓到的回歸：work 消歧刪除被併 Entry 時，canonical completeness witness
    /// 沒進欄位遺失閘；倖存者缺席或持有另一筆 witness 都會靜默丟失 truth-bearing data。
    func testWorkMergeRefusesDroppingOrReplacingCanonicalWitness() throws {
        let authors: [Author] = [.key("author-a"), .key("author-b")]
        let doomed = try entry(citekey: "doomed2026entry", authors: authors)
        let keeperID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        var keeper = Entry(
            id: keeperID,
            citekey: "keeper2026entry",
            type: doomed.type,
            title: doomed.title,
            authors: authors)

        let absentLosses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertTrue(
            absentLosses.contains { $0.contains("author-list-completeness") },
            "doomed 有 witness、keeper 缺席時必須拒絕：\(absentLosses)")

        keeper.akashic.authorListCompleteness = try AuthorListCompletenessWitness(
            workID: keeperID,
            fingerprint: AuthorListFingerprint(authors: authors),
            attestedAuthors: authors,
            references: references())
        let differentLosses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertTrue(
            differentLosses.contains { $0.contains("author-list-completeness") },
            "兩筆不同 work-bound witness 不得 first/keeper-wins：\(differentLosses)")

        var sameWitness = doomed
        sameWitness.citekey = "same2026entry"
        XCTAssertFalse(
            LibraryStore.fieldsLostByMerging(doomed, into: sameWitness)
                .contains { $0.contains("author-list-completeness") },
            "同值 witness 本身不構成資料遺失")
    }
}
